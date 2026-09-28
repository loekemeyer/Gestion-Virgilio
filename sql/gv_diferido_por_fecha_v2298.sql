-- =============================================================================
-- gv_diferido_por_fecha_v2298.sql — Lo que espera importado se parte POR FECHA
-- de reingreso, y la NP que quedó programada antes de que llegue su mercadería
-- se reprograma sola. (Thomas, 2026-09-26, v22.98)
--
-- ✅ APLICADO el 26/09 ~19:55 ART con el "sí" de Thomas, en este orden:
--   1. backups: zz_backups."GV_Backup_WebDiferido_20260926" (13), "GV_Backup_WebProg_diferido_20260926" (15),
--      "GV_Backup_WebBase_diferido_20260926" (167) en Gestión; zz_backups."LK_Backup_defs_diferido_20260926"
--      (vista + función de Chef, con sus opciones) en LK.
--   2. LK: vista + parche de Chef + sync_diferido_virgilio(45), en una transacción que abortaba si
--      cambiaba algún pedido fuera de 1448/1474/1524/1540. GV_PPP_Web_Diferido: 4 actualizadas, 5 nuevas.
--   3. Gestión: borradas las 13 líneas duplicadas de PPP_Web_Base (lista de abajo).
--   4. Gestión: tabla de log, función, vista centinela, parche del armador y 3 centinelas.
--      gv_reglas_perdidas = 0; gv_ppp_diferido_antes_de_tiempo = sólo LK 0221 "se reprograma".
-- =============================================================================
-- Thomas, textual: "si son pedidos que son únicamente pedidos de artículos importados
-- que llegan en noviembre, sí, habría que reprogramarlo de manera automática. Si son
-- pedidos que tienen parte de una cosa y parte de la otra, habría que dejarlos ahí y
-- particionar los pedidos en dos."
--
-- LOS TRES CASOS DEL 26/09 (revisión del módulo de Importación, problema 574):
--   LK 0221 (1358 #2) · 566E x1 (llega 29/11)             · E49A 30/09 -> se reprograma
--   LK 0206 (1524 #2) · baches 29/09 + 566E x3 (29/11)    · E37A 29/09 -> se parte
--   LK 0227 (1540 #3) · 606E 29/09 + 323E x3 (03/11)      · E18C 01/10 -> se parte
--
-- DOS PIEZAS, en dos proyectos:
--
-- 1) EL CORTE LO HACE LK (kwkclwhmoygunqmlegrg), no Gestión. `v_pedidos_web_np` y
--    `gv_pedidos_web_np_chef` metían TODO lo diferido de un pedido en UNA NP, con
--    no_antes_de = la fecha más lejana. Ahora hay una NP por fecha de reingreso (la
--    congelada en `pedido_diferido` al entrar el pedido, que no se mueve después).
--    Con una sola fecha el resultado es IDÉNTICO al de antes (medido: 1.669 NP, sólo
--    cambian los 4 pedidos con fechas mezcladas: 1448, 1474, 1524, 1540; Chef idéntico).
--    El SQL está en la sección LK de abajo. Se corre en LK, junto con
--    `sync_diferido_virgilio(45)`, en la MISMA transacción: así GV_PPP_Web_Diferido
--    se entera del corte en el mismo instante en que el feed lo muestra.
--
-- 2) GESTIÓN: `gv_ppp_web_diferido_tarde`. Una NP diferida programada para un día
--    ANTERIOR a su reingreso (el de LK, sin los +7) se desprograma y el pase (b2) del
--    armador la vuelve a programar EN LA MISMA CORRIDA (reingreso + N días). Se llama
--    desde el armador, antes del filtro (a000).
--    ⚠ Compara contra el reingreso CRUDO, no contra el piso (+7): con el piso, los baches
--      que llegan el mismo día que sale la tanda también saldrían, y Thomas dijo
--      "dejarlos ahí".
--    ⚠ Sólo si la tanda NO empezó (ni picking ni armado ni carga), la NP no está
--      facturada ni armada. Si no, queda a la vista en gv_ppp_diferido_antes_de_tiempo y
--      decide Marianela (regla v21.10: un pedido en proceso no se mueve solo).
--    ⚠ Sólo toca las NP que vienen en el feed de esa corrida (p_filas), para que el
--      pase (b2) las vea y no queden colgadas en A Programar (regla v20.80).
--
-- ⚠ ORDEN OBLIGATORIO: primero LK (el corte) y DESPUÉS el parche del armador. Al revés,
--   el armador ve LK 0227 entera con 03/11 > 01/10 y la desprograma entera, 606E incluido.
--
-- ⚠ PPP_Web_Base NO borra artículos que dejaron la NP (el Edge Function hace upsert):
--   los artículos que el corte mueve de NP quedan duplicados en la foto de picking.
--   La limpieza de los pedidos afectados va en la sección DATOS (con backup).
-- =============================================================================

-- ─── GESTIÓN (hrxfctzncixxqmpfhskv) ─────────────────────────────────────────

create table if not exists public."GV_Diferido_Reprogramado" (
  id          bigserial primary key,
  empresa     text   not null,
  order_id    bigint not null,
  np_idx      int    not null,
  np_label    text,
  tanda_prev  text,
  fecha_prev  date,
  reingreso   date,
  por         text,
  creado_at   timestamptz not null default now()
);
alter table public."GV_Diferido_Reprogramado" enable row level security;
revoke insert, update, delete, truncate on public."GV_Diferido_Reprogramado" from anon, authenticated;
comment on table public."GV_Diferido_Reprogramado" is
  'v22.98 (Thomas 26/09): NP diferidas que el armador desprogramo porque su reingreso cae despues del dia de entrega. Las vuelve a programar el pase (b2) en la misma corrida.';

create or replace function public.gv_ppp_web_diferido_tarde(
  p_empresa text, p_filas jsonb default null, p_simular boolean default true, p_por text default null)
returns table(r_np text, r_order_id bigint, r_np_idx int, r_tanda text, r_fecha date,
              r_reingreso date, r_accion text)
language plpgsql
security definer
set search_path to 'public'
as $f$
-- v22.98 (Thomas, 26/09/2026): "si son pedidos que son unicamente pedidos de articulos
--   importados que llegan en noviembre, si, habria que reprogramarlo de manera automatica".
--   La NP diferida (GV_PPP_Web_Diferido) programada para un dia ANTERIOR a su reingreso
--   (el de LK, crudo: sin los +7 de gv_diferido_piso) sale de su tanda; el pase (b2) del
--   armador la vuelve a programar en la misma corrida. Solo si la tanda no empezo.
declare r record;
begin
  for r in
    with cand as (
      select w.empresa, w.order_id, w.np_idx,
             public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np,
             btrim(w.tanda) as tanda, w.fecha_entrega, d.no_antes_de
        from public."PPP_Web_Programacion" w
        join public."GV_PPP_Web_Diferido" d
          on d.empresa = w.empresa and d.order_id = w.order_id and d.np_idx = w.np_idx
       where w.empresa = p_empresa
         and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
         and w.fecha_entrega is not null
         and d.no_antes_de > w.fecha_entrega
         and (p_filas is null or exists (
               select 1 from jsonb_array_elements(p_filas) x
                where (x->>'order_id')::bigint = w.order_id and (x->>'np_idx')::int = w.np_idx))
    )
    select c.*,
           case
             when exists (select 1 from public."Facturacion_NP" f where f.np = c.np)
               then 'facturada: no se toca'
             when exists (select 1 from public."Entregas_Virgilio" e
                           where e.np = c.np and coalesce(e.tanda, '') !~ '-X$')
               then 'armada: no se toca'
             when exists (select 1 from public."Registros_Produccion_Virgilio" rp
                           where upper(split_part(rp.texto, '|', 1)) = upper(c.tanda)
                             and rp.opcion in ('EP','PK','PKC','TP','AP','TAP','CC','CCN','CR','CCR','CRN')
                             and not public.es_legajo_test(rp.legajo))
               then 'tanda empezada: decide Marianela'
             else 'se reprograma'
           end as accion
      from cand c
     order by c.fecha_entrega, c.np
  loop
    if not p_simular and r.accion = 'se reprograma' then
      update public."PPP_Web_Programacion" w
         set tanda = null, fecha_entrega = null, actualizado_at = now()
       where w.empresa = r.empresa and w.order_id = r.order_id and w.np_idx = r.np_idx;
      insert into public."GV_Diferido_Reprogramado"
        (empresa, order_id, np_idx, np_label, tanda_prev, fecha_prev, reingreso, por)
      values (r.empresa, r.order_id, r.np_idx, r.np, r.tanda, r.fecha_entrega, r.no_antes_de,
              coalesce(nullif(btrim(p_por), ''), 'manual'));
    end if;
    r_np := r.np; r_order_id := r.order_id; r_np_idx := r.np_idx; r_tanda := r.tanda;
    r_fecha := r.fecha_entrega; r_reingreso := r.no_antes_de; r_accion := r.accion;
    return next;
  end loop;
end
$f$;
revoke execute on function public.gv_ppp_web_diferido_tarde(text, jsonb, boolean, text) from public, anon;
grant execute on function public.gv_ppp_web_diferido_tarde(text, jsonb, boolean, text) to authenticated, service_role;

-- Centinela: vacía = ninguna NP va a salir sin la mercadería que espera.
-- 'se reprograma' la arregla sola el armador en la próxima corrida; lo demás es para Marianela.
create or replace view public.gv_ppp_diferido_antes_de_tiempo with (security_invoker = true) as
select 'lk'::text as empresa, t.* from public.gv_ppp_web_diferido_tarde('lk') t
union all
select 'chef'::text, t.* from public.gv_ppp_web_diferido_tarde('chef') t;
revoke all on public.gv_ppp_diferido_antes_de_tiempo from anon;
grant select on public.gv_ppp_diferido_antes_de_tiempo to authenticated, service_role;

-- Parche al armador (sobre la definición VIVA, idempotente, falla si el ancla no está una vez).
do $do$
declare d text; n text; anc text := '  -- (a000) v21.61 (Luis, 2026-09-23, problema 514) -- LO YA PROGRAMADO NO ENTRA.';
begin
  d := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
  if d ~ 'gv_ppp_web_diferido_tarde' then return; end if;
  if (length(d) - length(replace(d, anc, ''))) / length(anc) <> 1 then
    raise exception 'armador: el ancla (a000) no esta exactamente una vez';
  end if;
  insert into zz_backups."GV_Backup_Funciones" (motivo, nombre, def)
  values ('pre v22.98 diferido tarde', 'gv_ppp_web_armar_pendientes', d);
  n := replace(d, anc,
    '  -- (a-dif) v22.98 (Thomas, 26/09) -- LA NP DIFERIDA PROGRAMADA ANTES DE SU REINGRESO SE REPROGRAMA.' || chr(10) ||
    '  --   "si son pedidos que son unicamente pedidos de articulos importados que llegan en noviembre,' || chr(10) ||
    '  --   habria que reprogramarlo de manera automatica". gv_ppp_web_diferido_tarde la saca de su tanda' || chr(10) ||
    '  --   (solo si la tanda no empezo) y el pase (b2) la vuelve a programar en esta misma corrida.' || chr(10) ||
    '  --   Si falla, el armado sigue: lo que quedo se ve en gv_ppp_diferido_antes_de_tiempo.' || chr(10) ||
    '  begin' || chr(10) ||
    '    perform public.gv_ppp_web_diferido_tarde(p_empresa, p_filas, false, ''armador'');' || chr(10) ||
    '  exception when others then' || chr(10) ||
    '    raise warning ''gv_ppp_web_diferido_tarde: %'', sqlerrm;' || chr(10) ||
    '  end;' || chr(10) || anc);
  execute n;
end
$do$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
 ('gv_ppp_web_armar_pendientes', 'funcion', 'perform public\.gv_ppp_web_diferido_tarde\(p_empresa, p_filas, false',
  'La NP diferida programada antes de su reingreso se desprograma y (b2) la reprograma en la misma corrida', 'Thomas', 'v22.98'),
 ('gv_ppp_web_diferido_tarde', 'funcion', 'd\.no_antes_de > w\.fecha_entrega',
  'Compara contra el reingreso CRUDO (sin +7): lo que llega el mismo dia que sale la tanda se deja ahi', 'Thomas', 'v22.98'),
 ('gv_ppp_web_diferido_tarde', 'funcion', 'tanda empezada: decide Marianela',
  'Una NP diferida cuya tanda ya empezo (picking/armado/carga) no se desprograma sola', 'Thomas', 'v22.98');

-- ─── LK (kwkclwhmoygunqmlegrg) ──────────────────────────────────────────────
-- Se corrió EN LK, en UNA transacción (aplicado, ver cabecera). Va comentado para que no
-- se ejecute por error en Gestión. La definición viva manda: pg_get_viewdef('public.v_pedidos_web_np').
-- Rollback LK: las definiciones anteriores están en zz_backups."LK_Backup_defs_diferido_20260926"
-- (columna def; la vista con opciones security_invoker=true); recrearlas y correr sync_diferido_virgilio(45).
/*
create or replace view public.v_pedidos_web_np with (security_invoker = true) as
 SELECT g.empresa, g.order_id, g.np_idx, g.cod, g.razon_social, g.fecha_recep, g.hora_recep, g.direccion, g.v,
    g.condicion_pago_code, g.numero_oc, g.enviado_a_compras, g.lineas, g.cajas, g.items, g.arts, g.localidad,
    g.provincia, g.zona_expreso, g.nombre_expreso, g.direccion_expreso, g.m3, g.m3_parcial, g.isis_empresa,
    g.cod_isis, g.diferido, g.no_antes_de, fe.txt AS fecha_entrega_txt, gv_fe_pactada_fecha(fe.txt) AS fecha_entrega_pactada,
    gv_fe_pactada_hora(fe.txt) AS hora_entrega_pactada, fe.obs AS observaciones, fe.rfecha AS retiro_fecha, fe.rfranja AS retiro_franja
   FROM ( WITH vol AS MATERIALIZED (SELECT virgilio_volumen_map.codigo, virgilio_volumen_map.m3 FROM virgilio_volumen_map() virgilio_volumen_map(codigo, m3)),
          cap AS (SELECT 'lk'::text AS empresa, 18 AS cap_lineas UNION ALL SELECT 'chef'::text AS text, 15),
          lin AS (
           SELECT i.empresa, i.order_id, i.linea_rn, i.cod_cliente, i.razon_social, i.fecha_pedido, i.hora_pedido, i.created_at,
              i.sucursal_entrega, i.vend, i.condicion_pago_code, i.numero_oc, i.observaciones, i.art, i.cajas, i.uxb, i.uni,
              i.enviado_a_compras_at, i.localidad, i.provincia, i.zona_expreso, i.nombre_expreso, i.direccion_expreso,
              i.isis_empresa, i.cod_isis, c.cap_lineas, v.m3 AS m3_unit,
              COALESCE(i.cajas, 0::numeric) * COALESCE(v.m3, 0::numeric) AS linea_m3,
              d.order_id IS NOT NULL AS es_diferido,
              CASE WHEN d.order_id IS NULL THEN NULL::date ELSE reingreso_piso(i.art, d.fecha_reingreso) END AS linea_no_antes_de,
              COALESCE(d.fecha_reingreso, 'infinity'::date) AS dif_grupo          -- v22.98: grupo = fecha congelada
             FROM v_pedidos_web i
               JOIN cap c ON c.empresa = i.empresa
               LEFT JOIN vol v ON v.codigo = upper(btrim(i.art))
               LEFT JOIN pedido_diferido d ON d.empresa = i.empresa AND d.order_id = i.order_id AND d.art = i.art),
          orden AS (
           SELECT l.*,
              row_number() OVER (PARTITION BY l.empresa, l.order_id, l.es_diferido ORDER BY l.linea_rn) AS rk,
              count(*) FILTER (WHERE NOT l.es_diferido) OVER (PARTITION BY l.empresa, l.order_id) AS n_disp,
              row_number() OVER (PARTITION BY l.empresa, l.order_id, l.es_diferido, l.dif_grupo ORDER BY l.linea_rn) AS rk_g,
              dense_rank() OVER (PARTITION BY l.empresa, l.order_id, l.es_diferido ORDER BY l.dif_grupo) AS gr
             FROM lin l),
          grp AS (   -- cuántas NP ocupan los grupos de fecha anteriores (cada grupo respeta el tope de líneas)
           SELECT o.empresa, o.order_id, o.gr,
              COALESCE(sum(ceil(count(*)::numeric / min(o.cap_lineas)::numeric)) OVER (PARTITION BY o.empresa, o.order_id ORDER BY o.gr ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0::numeric)::integer AS slots_prev
             FROM orden o WHERE o.es_diferido GROUP BY o.empresa, o.order_id, o.gr),
          part AS (
           SELECT o.*,
              CASE WHEN o.es_diferido
                   THEN ceil(o.n_disp::numeric / o.cap_lineas::numeric)::integer + COALESCE(g2.slots_prev, 0) + ceil(o.rk_g::numeric / o.cap_lineas::numeric)::integer
                   ELSE ceil(o.rk::numeric / o.cap_lineas::numeric)::integer END AS np_idx
             FROM orden o
             LEFT JOIN grp g2 ON o.es_diferido AND g2.empresa = o.empresa AND g2.order_id = o.order_id AND g2.gr = o.gr)
         SELECT p.empresa, p.order_id, p.np_idx, min(p.cod_cliente) AS cod, min(p.razon_social) AS razon_social,
            min(p.fecha_pedido) AS fecha_recep, min(p.hora_pedido) AS hora_recep, min(p.sucursal_entrega) AS direccion,
            min(p.vend) AS v, min(p.condicion_pago_code) AS condicion_pago_code, min(p.numero_oc) AS numero_oc,
            bool_and(p.enviado_a_compras_at IS NOT NULL) AS enviado_a_compras, count(*) AS lineas, sum(p.cajas) AS cajas,
            jsonb_agg(jsonb_build_object('art', p.art, 'cajas', p.cajas, 'uxb', p.uxb, 'uni', p.uni) ORDER BY p.linea_rn) AS items,
            string_agg(p.art, ','::text ORDER BY p.linea_rn) AS arts, min(p.localidad) AS localidad, min(p.provincia) AS provincia,
            min(p.zona_expreso) AS zona_expreso, min(p.nombre_expreso) AS nombre_expreso, min(p.direccion_expreso) AS direccion_expreso,
            round(sum(p.linea_m3), 3) AS m3, bool_or(p.m3_unit IS NULL) AS m3_parcial, min(p.isis_empresa) AS isis_empresa,
            min(p.cod_isis) AS cod_isis, bool_or(p.es_diferido) AS diferido, max(p.linea_no_antes_de) AS no_antes_de
           FROM part p
          GROUP BY p.empresa, p.order_id, p.np_idx) g
     LEFT JOIN LATERAL ( SELECT NULLIF(COALESCE(o.sheets_payload ->> 'fecha_entrega'::text, o.sheets_payload ->> 'fechaEntrega'::text), ''::text) AS txt,
            NULLIF(btrim(o.sheets_payload ->> 'observaciones'::text), ''::text) AS obs,
            CASE WHEN (o.sheets_payload ->> 'retiro_fecha'::text) ~ '^\d{4}-\d{2}-\d{2}$'::text THEN (o.sheets_payload ->> 'retiro_fecha'::text)::date ELSE NULL::date END AS rfecha,
            NULLIF(btrim(o.sheets_payload ->> 'retiro_franja'::text), ''::text) AS rfranja
           FROM orders o WHERE o.id = g.order_id) fe ON true;

-- gv_pedidos_web_np_chef(integer): el mismo corte, parcheado por replace() sobre la definición viva
-- (tres anclas: dif_grupo en con_m3, rk_g/gr en orden, CTE grp + join en part). Mismo resultado: una NP por fecha.

select public.sync_diferido_virgilio(45);
*/

-- ─── DATOS (Gestión) — con el "sí" de Thomas ─────────────────────────────────
-- Backup (clave: empresa, order_id, np_idx, articulo):
--   create table zz_backups."GV_Backup_WebBase_diferido_20260926" as
--     select * from public."PPP_Web_Base" where empresa = 'lk' and order_id in (1448,1474,1524,1540);
--   alter table zz_backups."GV_Backup_WebBase_diferido_20260926" enable row level security;
--
-- Foto de picking: sacar los artículos que el corte (o el corte viejo del 24/09) movió de NP.
--   delete from public."PPP_Web_Base" b
--    where b.empresa = 'lk' and (b.order_id, b.np_idx, upper(btrim(b.articulo))) in (
--      (1524,1,'566E'),(1524,1,'951E'),(1524,1,'952E'),
--      (1524,2,'566E'),(1524,2,'954E'),(1524,2,'955E'),(1524,2,'956E'),
--      (1540,3,'323E'),
--      (1448,3,'970E'),(1448,3,'971E'),
--      (1474,5,'323E'),(1474,5,'970E'),(1474,5,'971E'));
--
-- Rollback Gestión:
--   update pg_proc no: se restaura el armador desde zz_backups."GV_Backup_Funciones" (motivo 'pre v22.98 diferido tarde');
--   drop view public.gv_ppp_diferido_antes_de_tiempo;
--   drop function public.gv_ppp_web_diferido_tarde(text, jsonb, boolean, text);
--   insert into public."PPP_Web_Base" select * from zz_backups."GV_Backup_WebBase_diferido_20260926" on conflict do nothing;
