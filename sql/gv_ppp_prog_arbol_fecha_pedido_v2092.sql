-- v20.92 — «F. pedido» de la Programación: que no quede ninguna NP sin fecha de entrada.
--
-- Qué se midió (2026-09-22, rango hoy..+30): 183 NP programadas, 14 sin `fecha_pedido`.
-- Las 14 son web y las 14 tienen `PPP_Web_Programacion.fecha_recep` en NULL. Salían con «—»
-- en la hoja impresa y vacías en el Excel.
--
-- ⚠ ESTO NO REEMPLAZA A LA v20.63 (`sql/gv_fecha_recep_armador_v2063.sql`). Ahí está el
-- arreglo de raíz: el armador persiste la fecha en la tabla. Esto es el lado de la LECTURA,
-- y cubre dos cosas que aquél no puede:
--   · las 14 filas que ya estaban programadas sin fecha (su UPDATE sigue esperando el «sí»);
--   · los otros CUATRO caminos de escritura de `PPP_Web_Programacion` — la v20.63 arregló el
--     del armador, que es uno solo.
-- El centinela `gv_ppp_sin_fecha_recep` sigue diciendo la verdad sobre la TABLA, así que esto
-- no tapa nada: si una fila nueva entra sin fecha, ahí se ve igual.
--
-- La cascada, en orden:
--   1. `PPP_Web_Programacion.fecha_recep`     ← el que ya se usaba
--   2. `lk_pedidos_match.fecha_pedido`        ← la fecha real del pedido de la página (tabla
--                                                local, la empuja el cron de LK cada 15 min)
--   3. `PPP_Web_NP.creado_at` (a hora AR)     ← el día en que se le asignó la NP
--
-- ⚠ El (3) es una APROXIMACIÓN, no la fecha del pedido: es cuándo se numeró. Se midió que
-- para las 9 NP de LK coincide exactamente con (2). Las 5 de Chef de formato nuevo (order_id
-- 1001430/31/32) NO están en `lk_pedidos_match` —su feed no las trae, y eso es del lado de
-- Chef— así que (3) es lo único que hay: da 2026-09-14 para las tres.
--
-- Después del cambio: 183 de 183 con fecha; `anon` las ve todas (probado con `set local role`).
-- NINGÚN valor previo cambia: es un COALESCE, sólo rellena los NULL.
--
-- ⚠ Lo que NO tapa: las NP de ISIS ya facturadas/entregadas cuya fila desapareció del espejo
-- (origen `fact`/`hist`). En una ventana de 120 días son 622 y las 622 son de numeración ISIS:
-- `gv_ppp_programacion_diaria` guarda sólo lo programado y después se borra, así que su
-- `fecha_recep` no está en ningún lado. Son días pasados; la impresión mira días por venir.
--
-- Rollback: volver a poner `w.fecha_recep::date,` en lugar del coalesce de la rama `web`.

CREATE OR REPLACE FUNCTION public.gv_ppp_prog_arbol(p_desde date, p_hasta date)
 RETURNS TABLE(fecha date, tanda text, np text, np_num numeric, cod text, razon_social text, localidad text, zona text, zona_corta text, empresa text, origen text, m3 numeric, estado text, estado_orden integer, clave text, pide_horario boolean, horario_fecha date, horario_franja text, horario_origen text, barrio text, fecha_pedido date)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
with esp as (
  select regexp_replace(upper(btrim(e.np)), '\.0+$', '') as np
    from public."GV_PPP_Armados_Espera" e
),
fuentes as (
  select 1 as pri,
         regexp_replace(btrim(p.np), '\.0+$', '')                          as np,
         upper(btrim(coalesce(p.tanda, '')))                               as tanda,
         coalesce(p.m3, 0)::numeric                                        as m3,
         nullif(left(btrim(p.fecha_entrega), 10), '')::date                as fe,
         coalesce(btrim(p.cod), '')                                        as cod,
         coalesce(btrim(p.razon_social), '')                               as razon_social,
         coalesce(nullif(btrim(coalesce(p.barrio, '')), ''),
                  btrim(coalesce(p.direccion, '')))                        as localidad,
         coalesce(btrim(p.zona), '')                                       as zona,
         regexp_replace(btrim(p.np), '\.0+$', '')                          as clave,
         nullif(btrim(coalesce(p.barrio, '')), '')                         as barrio,
         case when left(btrim(coalesce(p.fecha_recep, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
              then left(btrim(p.fecha_recep), 10)::date end                as fecha_pedido,
         'isis'::text                                                      as origen
    from public.gv_ppp_programacion_diaria p
   where left(btrim(coalesce(p.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
      -- v19.29: una NP de ISIS en espera quedó sin fecha en el espejo; igual tiene que entrar,
      -- porque su día lo pone la marca.
      or exists (select 1 from esp where esp.np = regexp_replace(upper(btrim(p.np)), '\.0+$', ''))
  union all
  select 2,
         public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx),
         upper(btrim(coalesce(w.tanda, ''))),
         coalesce(w.m3, 0)::numeric,
         w.fecha_entrega,
         coalesce(btrim(w.cod_cliente), ''),
         coalesce(btrim(w.razon_social), ''),
         coalesce(nullif(btrim(coalesce(w.barrio, '')), ''), btrim(coalesce(w.direccion, ''))),
         coalesce(btrim(w.zona), ''),
         w.order_id::text,
         nullif(btrim(coalesce(w.barrio, '')), ''),
         -- v20.92: fecha de entrada del pedido en cascada. `fecha_recep` queda NULL cuando la
         -- fila la escribe un camino que no lo carga; el dato igual existe en el espejo del
         -- pedido web y, en último lugar, en el día en que se asignó la NP.
         coalesce(w.fecha_recep::date,
                  (select lp.fecha_pedido from public.lk_pedidos_match lp
                    where lp.empresa = w.empresa and lp.order_id = w.order_id limit 1),
                  (select (n.creado_at at time zone 'America/Argentina/Buenos_Aires')::date
                     from public."PPP_Web_NP" n
                    where n.empresa = w.empresa and n.np = w.np and n.np_idx = w.np_idx)),
         'web'
    from public."PPP_Web_Programacion" w
   where w.tanda is not null and btrim(w.tanda) <> ''
  union all
  -- v19.11: `ovf` — una NP que ya solo figura facturada se puede reprogramar por el override.
  select 3,
         regexp_replace(upper(btrim(f.np)), '\.0+$', ''),
         upper(btrim(coalesce(f.tanda, ''))),
         coalesce(f.m3, 0)::numeric,
         coalesce(ovf.fecha_entrega, f.fecha_salida),
         coalesce(btrim(f.cod_cliente), ''),
         coalesce(btrim(f.razon_social), ''),
         '', '', regexp_replace(upper(btrim(f.np)), '\.0+$', ''), null::text, null::date, 'fact'
    from public."Facturacion_NP" f
    left join public."GV_PPP_Prog_Override" ovf
      on ovf.np = regexp_replace(upper(btrim(f.np)), '\.0+$', '')
   where f.fecha_salida is not null
  union all
  select 4,
         regexp_replace(btrim(h.np), '\.0+$', ''),
         upper(btrim(coalesce(h.tanda, ''))),
         coalesce(h.m3, 0)::numeric,
         coalesce(ovh.fecha_entrega,
                  case when left(btrim(coalesce(h.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
                       then left(btrim(h.fecha_entrega), 10)::date end),
         coalesce(btrim(h.cod), ''),
         coalesce(btrim(h.rs), ''),
         '', '', regexp_replace(btrim(h.np), '\.0+$', ''), null::text, null::date, 'hist'
    from public."GV_PPP_Entregados_Historico" h
    left join public."GV_PPP_Prog_Override" ovh
      on ovh.np = regexp_replace(btrim(h.np), '\.0+$', '')
),
fuera as (
  select o.np
    from public."GV_PPP_Prog_Override" o
   where coalesce(o.oculto, false) or coalesce(o.desprogramada, false)
  union
  select regexp_replace(btrim(coalesce(c.np, '')), '\.0+$', '')
    from public."NP_Canceladas" c
),
uni as (
  select distinct on (f.np) f.*,
         exists (select 1 from esp where esp.np = upper(f.np)) as en_espera
    from fuentes f
   where f.np <> ''
     and (f.fe is not null or exists (select 1 from esp where esp.np = upper(f.np)))
     and not exists (select 1 from fuera x where x.np = f.np)
   order by f.np, f.pri, f.m3 desc
),
dia as (
  -- v19.29: el día de una NP en espera es el centinela. Con eso entra en el rango sólo cuando
  -- quien pregunta llega hasta ahí (la Programación), y nunca en un rango de días reales
  -- (Pedidos atrasados, Avance del día).
  select u.*, (case when u.en_espera then public.gv_ppp_espera_fecha() else u.fe end) as fe_dia
    from uni u
   where (case when u.en_espera then public.gv_ppp_espera_fecha() else u.fe end) between p_desde and p_hasta
),
ev as (
  select upper(btrim(r.texto)) as tanda, r.opcion, r.ts_cliente
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('EP','TP','AP','TAP')
     and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> ''
     and r.ts_cliente >= (p_desde - interval '60 days')
),
pick as (select distinct on (tanda) tanda, opcion from ev where opcion in ('EP','TP') order by tanda, ts_cliente desc),
arm  as (select distinct on (tanda) tanda, opcion from ev where opcion in ('AP','TAP') order by tanda, ts_cliente desc),
salio as (
  select distinct regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN','CRN') and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> ''
),
fact as (select distinct regexp_replace(upper(btrim(f.np)), '\.0+$', '') as np from public."Facturacion_NP" f),
est as (
  select d.fe_dia as fe, d.np, d.tanda, d.m3, d.cod, d.razon_social, d.localidad, d.zona, d.origen, d.clave, d.barrio, d.fecha_pedido,
         (fc.np is not null)                          as b_fact,
         (s.np is not null or a.opcion = 'TAP')       as b_arm,
         (a.opcion = 'AP' or p.opcion in ('TP','EP')) as b_curso,
         -- v19.32: PISO de estado por NP. Una NP armada que se separa a una tanda nueva no tiene
         -- el TAP de esa tanda, y sin esto figuraria "pendiente". Lo graba gv_ppp_pedido_mover.
         coalesce(case he.estado when 'facturado' then 4 when 'armado' then 3 when 'proceso' then 2 end, 1) as piso
    from dia d
    left join salio s on s.np = upper(d.np)
    left join fact fc on fc.np = upper(d.np)
    left join pick  p on p.tanda = d.tanda and d.tanda <> ''
    left join arm   a on a.tanda = d.tanda and d.tanda <> ''
    left join public."GV_PPP_NP_Estado" he on he.np = upper(d.np)
)
select e.fe,
       coalesce(nullif(e.tanda, ''), '—'),
       e.np,
       nullif(regexp_replace(e.np, '\D', '', 'g'), '')::numeric,
       e.cod, e.razon_social, e.localidad, e.zona,
       case when e.zona ~* 'retira'                                    then 'Retira'
            when public.gv_es_super_np(e.np, e.cod)
              or e.zona ~* 'super|coto|carrefour|chango|krikos'        then 'Súper'
            else coalesce(substring(e.zona, '^(Zona\s*[0-9]+)'), nullif(btrim(e.zona), ''), 'Sin zona') end,
       case when upper(e.np) like 'LK%' then 'LK'
            when upper(e.np) like 'CH%' then 'CH'
            when coalesce(nullif(regexp_replace(e.np, '\D', '', 'g'), '')::numeric, 0) > 90000 then 'LK'
            else 'CH' end,
       e.origen, e.m3,
       case greatest(case when e.b_fact then 4 when e.b_arm then 3 when e.b_curso then 2 else 1 end, e.piso)
            when 4 then 'facturado' when 3 then 'armado' when 2 then 'proceso' else 'pendiente' end,
       greatest(case when e.b_fact then 4 when e.b_arm then 3 when e.b_curso then 2 else 1 end, e.piso),
       e.clave,
       public.gv_pide_horario_np(e.np, e.cod, e.zona),
       h.fecha, h.franja, h.origen,
       e.barrio, e.fecha_pedido
  from est e
  left join public."GV_Pedido_Horario" h
    on h.empresa = public.gv_emp_de_np(e.np)
   and h.clave in (e.clave, regexp_replace(upper(btrim(e.np)), '\.0+$', ''))
 order by e.fe, coalesce(nullif(e.tanda, ''), '—'),
          nullif(regexp_replace(e.np, '\D', '', 'g'), '')::numeric nulls last, e.np;
$function$;

-- Chequeo (tiene que dar 0 en días por venir):
-- select count(*) filter (where fecha_pedido is null)
--   from public.gv_ppp_prog_arbol(current_date, current_date + 30);

-- Centinela de la regla (FALTA EJECUTARLO — es un insert, va con el «sí» del dueño):
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
-- values ('gv_ppp_prog_arbol(date,date)', 'funcion', 'lk_pedidos_match lp',
--         'La rama web de gv_ppp_prog_arbol resuelve fecha_pedido en cascada: fecha_recep, '
--         'lk_pedidos_match.fecha_pedido y PPP_Web_NP.creado_at. Sin la cascada, 14 de 179 NP '
--         'programadas salen sin fecha de pedido en la hoja y en el Excel.',
--         'Thomas', 'v20.92');
