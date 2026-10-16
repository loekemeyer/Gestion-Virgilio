-- v31.64 (Luis, 16/10/2026) — STOCKS EN VIVO: que la pantalla no vuelva atrás y que las cajas
-- pedidas lleguen sin esperar la matview.
--
-- Luis: *"arregla el cron, dale"* · *"el tema es evitar que se llegue a timeout porque tenga que ver
-- tablas completas, si se puede hacer que solo busque cambios, golazo"* · *"si la tabla se ve en
-- realtime, aun mejor"*.
--
-- LO QUE SE MIDIÓ (16/10, 936E después del ajuste de conteo 11 → 12):
--   1. Las cajas por depósito YA llegan en vivo a stocks_carga_rapida: trigger
--      actualizar_saldo_trigger en cada movimiento.
--   2. PERO el cron 57 (3-59/6, sin refrescar la matview) reescribía esas columnas desde
--      vista_stock_procesada, que se refresca en minutos PARES. Un movimiento entre el último
--      refresco y el 57 VOLVÍA ATRÁS en pantalla hasta el próximo refresco (936E: 12 → 11 → 12).
--      De 2:00 a 7:59 el 55 no corre y el 57 sí: lo movido de madrugada quedaba viejo hasta las 8.
--   3. cajas_pedidas viajaba sólo por la matview (≤ 2 min) y el NETO del tooltip
--      (gv_stock_pedidas_neto, 690 ms) se leía UNA vez al abrir Stocks.
--   4. Y el realtime de la pantalla no le llegaba a NADIE logueado: stocks_carga_rapida tenía
--      política de SELECT sólo para `anon`, y el supervisor escucha con su sesión
--      (`authenticated`, count = 0 medido con set local role). La tabla quedaba como se abrió.
--
-- QUÉ SE HACE:
--   A. política de lectura para `authenticated` (anon ya leía todo: no abre nada nuevo).
--   B. refresh_stocks_carga_rapida: (a) no pisa los saldos de un código con movimiento después
--      del último refresco de la matview (el trigger ya los dejó bien); (b) no pisa cajas_pedidas
--      mientras el job de pedidas esté sano (< 15 min); (c) escribe SÓLO las filas que cambian
--      (antes reescribía las 396 en cada pasada y además ponía fc_sin_salida en 0 y de vuelta:
--      con el realtime prendido eran ~800 eventos por pasada a cada pantalla abierta).
--   C. pedidas "sólo si cambió": una SECUENCIA (nextval no bloquea a nadie) que suben triggers
--      baratos en las tablas de pedidos y tandas; un job cada 30 s mira la secuencia y, sólo si
--      se movió, calcula gv_stock_pedidas_neto (≈ 0:01) y escribe en stocks_carga_rapida las
--      filas cuyo número cambió. Sin cambios: lee un número y sale. Piso: 10 min.
--      PPP_Web_Base se reescribe entera por sync (6,3 M updates contra 2.031 inserts): su
--      trigger de UPDATE sólo dispara si cambia np_label / articulo / cajas.
--      Registros_Produccion_Virgilio: sólo TP y EP (el en_curso depende del EP; medido 30 días:
--      151 tandas con PKC, 0 sin EP; 11 TP+EP por día contra 103 PKC).
--   D. gv_importados_stock_dep lee cajas_pedidas de stocks_carga_rapida: Stocks e Importación con
--      el MISMO número y el mismo atraso (Luis: "si los dos se ven igual de atrasados ok").
--
-- ⚠ El job toma el 5768 con TRY (igual que el encadenado del 55): si está ocupado, la próxima.
-- ⚠ Se aplica con execute + replace('QQB'…) donde el texto lleva la palabra prohibida del
--   connector (docs/REGLAS-SUPABASE.md). Acá queda escrito en claro.
--
-- ROLLBACK:
--   select cron.unschedule('gv-stock-pedidas-vivo');
--   -- y reponer las dos definiciones de zz_backups."GV_Backup_funcdef_20261016_stockvivo"
--   -- (execute def) · la tabla antes del cambio: zz_backups."GV_Backup_stocks_carga_rapida_20261016"

-- A ─────────────────────────────────────────────────────────────────────────────────────────
create policy auth_read_stocks_carga_rapida on public.stocks_carga_rapida
  for select to authenticated using (true);

-- C.1 columnas del neto vivo (las lee el tooltip de Cajas pedidas) ──────────────────────────
alter table public.stocks_carga_rapida
  add column if not exists ped_neto numeric,
  add column if not exists ped_con_tp numeric,
  add column if not exists ped_en_curso numeric,
  add column if not exists ped_familia text,
  add column if not exists ped_es_secundario boolean,
  add column if not exists ped_fam_con_tp numeric,
  add column if not exists ped_fam_en_curso numeric,
  add column if not exists ped_fam_miembros integer,
  add column if not exists ped_vivo_en timestamptz;

-- C.2 la secuencia "sucio" y el estado del job ──────────────────────────────────────────────
create sequence if not exists public.gv_stock_pedidas_sucio_seq;
revoke all on sequence public.gv_stock_pedidas_sucio_seq from anon, authenticated;
-- ⚠ arrancarla UNA vez: recién creada, el primer nextval deja last_value en 1 (is_called pasa a
-- true) y el job no ve el cambio. Medido al probarlo: el EP de prueba no se notaba.
select nextval('public.gv_stock_pedidas_sucio_seq');

create table if not exists public."GV_Stock_Pedidas_Estado" (
  id int primary key check (id = 1),
  seq_visto bigint, calculado_en timestamptz, chequeado_en timestamptz,
  calculos bigint not null default 0, saltos bigint not null default 0,
  filas_ultimo int, ultimo_ms int, ultimo_motivo text);
alter table public."GV_Stock_Pedidas_Estado" enable row level security;   -- sin políticas: sólo el job

create or replace function public.gv_stock_pedidas_marcar()
 returns trigger language plpgsql security definer set search_path to 'public', 'pg_catalog'
as $f$
begin
  perform nextval('public.gv_stock_pedidas_sucio_seq');   -- no bloquea: no es transaccional
  return null;
end $f$;

-- C.3 triggers ────────────────────────────────────────────────────────────────────────────
-- por sentencia: tablas de pocos cambios
create or replace trigger zz_gv_pedvivo after insert or update or delete or truncate on public."GV_PPP_Base_Pedidos"         for each statement execute function public.gv_stock_pedidas_marcar();
create or replace trigger zz_gv_pedvivo after insert or update or delete or truncate on public."GV_PPP_Prog_Override"        for each statement execute function public.gv_stock_pedidas_marcar();
create or replace trigger zz_gv_pedvivo after insert or update or delete or truncate on public."GV_PPP_Base_Override"        for each statement execute function public.gv_stock_pedidas_marcar();
create or replace trigger zz_gv_pedvivo after insert or update or delete or truncate on public."Facturacion_NP"              for each statement execute function public.gv_stock_pedidas_marcar();
create or replace trigger zz_gv_pedvivo after insert or update or delete or truncate on public."GV_PPP_Entregados_Historico" for each statement execute function public.gv_stock_pedidas_marcar();
create or replace trigger zz_gv_pedvivo after insert or update or delete or truncate on public."NP_Canceladas"               for each statement execute function public.gv_stock_pedidas_marcar();
create or replace trigger zz_gv_pedvivo after insert or update or delete or truncate on public."GV_Web_Cancelados"           for each statement execute function public.gv_stock_pedidas_marcar();
create or replace trigger zz_gv_pedvivo after insert or update or delete or truncate on public."GV_PPP_Programacion_Diaria"  for each statement execute function public.gv_stock_pedidas_marcar();
create or replace trigger zz_gv_pedvivo after insert or update or delete or truncate on public."PPP_Web_Programacion"        for each statement execute function public.gv_stock_pedidas_marcar();
create or replace trigger zz_gv_pedvivo after insert or update or delete or truncate on public."Equivalencias_Familia"       for each statement execute function public.gv_stock_pedidas_marcar();
-- PPP_Web_Base: alta/baja por sentencia; el UPDATE por fila y SÓLO si cambia lo que suma
create or replace trigger zz_gv_pedvivo     after insert or delete or truncate on public."PPP_Web_Base" for each statement execute function public.gv_stock_pedidas_marcar();
create or replace trigger zz_gv_pedvivo_upd after update on public."PPP_Web_Base" for each row
  when ((old.np_label, old.articulo, old.cajas) is distinct from (new.np_label, new.articulo, new.cajas))
  execute function public.gv_stock_pedidas_marcar();
-- Registros: sólo TP (cierra picking → sale del neto) y EP (empieza → en_curso)
create or replace trigger zz_gv_pedvivo_ins after insert on public."Registros_Produccion_Virgilio" for each row
  when (new.opcion in ('TP','EP')) execute function public.gv_stock_pedidas_marcar();
create or replace trigger zz_gv_pedvivo_upd after update on public."Registros_Produccion_Virgilio" for each row
  when ((old.opcion in ('TP','EP') or new.opcion in ('TP','EP'))
        and (old.opcion, old.texto) is distinct from (new.opcion, new.texto))
  execute function public.gv_stock_pedidas_marcar();
create or replace trigger zz_gv_pedvivo_del after delete on public."Registros_Produccion_Virgilio" for each row
  when (old.opcion in ('TP','EP')) execute function public.gv_stock_pedidas_marcar();

-- C.4 el job ─────────────────────────────────────────────────────────────────────────────
create or replace function public.gv_stock_pedidas_vivo(p_forzar boolean default false, p_piso_min integer default 10)
 returns table(calculado boolean, motivo text, filas integer, ms integer)
 language plpgsql security definer set search_path to 'public', 'pg_catalog'
as $f$
declare
  v_seq bigint; v_vis bigint; v_cal timestamptz; v_mot text; v_n int := 0;
  v_t0 timestamptz := clock_timestamp();
begin
  -- la secuencia se lee ANTES de calcular: lo que cambie durante el cálculo dispara la próxima
  select last_value into v_seq from public.gv_stock_pedidas_sucio_seq;
  select e.seq_visto, e.calculado_en into v_vis, v_cal from public."GV_Stock_Pedidas_Estado" e where e.id = 1;

  if p_forzar then v_mot := 'forzado';
  elsif v_cal is null then v_mot := 'primera corrida';
  elsif v_cal < now() - make_interval(mins => greatest(p_piso_min, 1)) then v_mot := 'piso de frescura (' || p_piso_min || ' min)';
  elsif v_vis is distinct from v_seq then v_mot := 'cambiaron pedidos o tandas';
  else
    update public."GV_Stock_Pedidas_Estado" set chequeado_en = now(), saltos = saltos + 1 where id = 1;
    calculado := false; motivo := 'sin cambios'; filas := 0; ms := 0; return next; return;
  end if;

  -- TRY, nunca el bloqueante: el 5768 lo toman el 55 (encadenado), el 57, el 68 y el 92
  if not pg_try_advisory_xact_lock(5768) then
    update public."GV_Stock_Pedidas_Estado" set chequeado_en = now() where id = 1;
    calculado := false; motivo := 'lock 5768 ocupado: la próxima corrida'; filas := 0; ms := 0; return next; return;
  end if;

  with n as (select * from public.gv_stock_pedidas_neto),
  x as (
    select s.cod,
           coalesce(n.total, 0) as t, coalesce(n.neto, 0) as ne, coalesce(n.con_tp, 0) as tp,
           coalesce(n.en_curso, 0) as ec, n.familia as fa, coalesce(n.es_secundario, false) as es,
           coalesce(n.fam_con_tp, 0) as ftp, coalesce(n.fam_en_curso, 0) as fec,
           coalesce(n.fam_miembros, 1)::int as fm
      from public.stocks_carga_rapida s
      left join n on n.cod = s.cod)
  update public.stocks_carga_rapida s
     set cajas_pedidas = x.t, ped_neto = x.ne, ped_con_tp = x.tp, ped_en_curso = x.ec,
         ped_familia = x.fa, ped_es_secundario = x.es, ped_fam_con_tp = x.ftp,
         ped_fam_en_curso = x.fec, ped_fam_miembros = x.fm, ped_vivo_en = now()
    from x
   where s.cod = x.cod
     and (s.cajas_pedidas, s.ped_neto, s.ped_con_tp, s.ped_en_curso, s.ped_familia, s.ped_es_secundario,
          s.ped_fam_con_tp, s.ped_fam_en_curso, s.ped_fam_miembros)
         is distinct from (x.t, x.ne, x.tp, x.ec, x.fa, x.es, x.ftp, x.fec, x.fm);
  get diagnostics v_n = row_count;

  ms := round(extract(epoch from (clock_timestamp() - v_t0)) * 1000)::int;
  insert into public."GV_Stock_Pedidas_Estado" (id, seq_visto, calculado_en, chequeado_en, calculos, filas_ultimo, ultimo_ms, ultimo_motivo)
  values (1, v_seq, now(), now(), 1, v_n, ms, v_mot)
  on conflict (id) do update set seq_visto = excluded.seq_visto, calculado_en = excluded.calculado_en,
    chequeado_en = excluded.chequeado_en, calculos = public."GV_Stock_Pedidas_Estado".calculos + 1,
    filas_ultimo = excluded.filas_ultimo, ultimo_ms = excluded.ultimo_ms, ultimo_motivo = excluded.ultimo_motivo;

  calculado := true; motivo := v_mot; filas := v_n; return next;
end $f$;
revoke all on function public.gv_stock_pedidas_vivo(boolean, integer) from public, anon, authenticated;

select cron.schedule('gv-stock-pedidas-vivo', '30 seconds', 'select public.gv_stock_pedidas_vivo()');

-- B ─────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.refresh_stocks_carga_rapida()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v_conocidos text[];  -- v25.50-conocidos
  v_ref timestamptz; v_movidos text[]; v_ped_vivo boolean;  -- v31.65-vivo
BEGIN
  v_conocidos := array(select distinct c from (
    select upper(regexp_replace(cod,'^0+(?=.)','')) c from public.vista_nombres_articulos
    union all select upper(regexp_replace(cod::text,'^0+(?=.)','')) from public.vista_uxb_articulo
    union all select upper(regexp_replace(cod::text,'^0+(?=.)','')) from public."OC_Maximos"
    union all select upper(regexp_replace(cod::text,'^0+(?=.)','')) from public."GV_Lugar_Item"
    union all select upper(regexp_replace(cod::text,'^0+(?=.)','')) from public."Capacidad_Sector"
    union all select upper(regexp_replace(cod::text,'^0+(?=.)','')) from public.proyeccion_madre
    union all select upper(regexp_replace(cod::text,'^0+(?=.)','')) from public."Insumos") z where c is not null
      and c <> all(array(select upper(regexp_replace(cod,'^0+(?=.)','')) from public."GV_Codigo_Baja")) /* v29.06-baja */);
  -- v19.53 — EL REFRESH BLOQUEANTE SALIO DE ACA (ver la definición vieja en
  -- zz_backups."GV_Backup_funcdef_20261016_stockvivo"): el cron 55 refresca la matview con
  -- CONCURRENTLY y encadena esta función.

  -- v31.65 (Luis, 16/10) — NO VOLVER ATRÁS. El trigger actualizar_saldo_trigger deja los saldos
  -- de cada movimiento al instante; la matview los tiene recién en su próximo refresco. Pisar con
  -- la matview un código que se movió DESPUÉS de su último refresco devolvía la pantalla al número
  -- viejo (936E 12 → 11 → 12). Esos códigos conservan lo del trigger; el resto se auto-cura como
  -- en la v12.41 (el fantasma 809E -2).
  select e.refrescado_en into v_ref from public."GV_Stock_Refresh_Estado" e where e.id = 1;
  v_movidos := array(select distinct regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', '')
                       from public."Movimientos_Stock" m where m.creado > coalesce(v_ref, now()));
  -- cajas_pedidas es del job gv_stock_pedidas_vivo mientras esté sano; si se cae, vuelve la matview
  select coalesce(bool_or(p.calculado_en > now() - interval '15 minutes'), false) into v_ped_vivo
    from public."GV_Stock_Pedidas_Estado" p where p.id = 1;
  v_ped_vivo := coalesce(v_ped_vivo, false);

  -- v12.41: resincronizar las COLUMNAS DE SALDO desde la matview. v31.64: SÓLO las filas que
  -- cambian (cada UPDATE es un evento de realtime para cada pantalla de Stocks abierta).
  UPDATE public.stocks_carga_rapida t
  SET terminado = n.terminado, excedente = n.excedente, separar_pedidos = n.separar_pedidos,
      a_facturar = n.a_facturar, a_guardar = n.a_guardar, racks = n.racks, racks_ch = n.racks_ch,
      para_envasar = n.para_envasar, insumos_dep = n.insumos_dep, stock_total = n.stock_total,
      cajas_pedidas = n.cajas_pedidas, proy_cajas_mes = n.proy_cajas_mes,
      capacidad_gondola = n.capacidad_gondola, es_insumo = n.es_insumo,
      visible_en_stock = n.visible_en_stock, descripcion = n.descripcion, linea = n.linea,
      cod_base = n.cod_base, familia_principal = n.familia_principal, es_secundario = n.es_secundario
  FROM (
    SELECT scr.cod,
      CASE WHEN mv.prot THEN scr.terminado       ELSE COALESCE(vsp.terminado, 0)       END AS terminado,
      CASE WHEN mv.prot THEN scr.excedente       ELSE COALESCE(vsp.excedente, 0)       END AS excedente,
      CASE WHEN mv.prot THEN scr.separar_pedidos ELSE COALESCE(vsp.separar_pedidos, 0) END AS separar_pedidos,
      CASE WHEN mv.prot THEN scr.a_facturar      ELSE COALESCE(vsp.a_facturar, 0)      END AS a_facturar,
      CASE WHEN mv.prot THEN scr.a_guardar       ELSE COALESCE(vsp.a_guardar, 0)       END AS a_guardar,
      CASE WHEN mv.prot THEN scr.racks           ELSE COALESCE(vsp.racks, 0)           END AS racks,
      CASE WHEN mv.prot THEN scr.racks_ch        ELSE COALESCE(vsp.racks_ch, 0)        END AS racks_ch,
      CASE WHEN mv.prot THEN scr.para_envasar    ELSE COALESCE(vsp.para_envasar, 0)    END AS para_envasar,
      CASE WHEN mv.prot THEN scr.insumos_dep     ELSE COALESCE(vsp.insumos_dep, 0)     END AS insumos_dep,
      CASE WHEN mv.prot THEN scr.stock_total     ELSE COALESCE(vsp.stock_total, 0)     END AS stock_total,
      CASE WHEN v_ped_vivo THEN scr.cajas_pedidas ELSE COALESCE(vsp.cajas_pedidas, 0)  END AS cajas_pedidas,
      COALESCE(vsp.proy_cajas_mes, 0) AS proy_cajas_mes,
      COALESCE(vsp.capacidad_gondola, 0) AS capacidad_gondola,
      COALESCE(vsp.es_insumo, false) AS es_insumo,
      -- v21.58 (Luis, 23/09: "si busco 865 me muestra el 865 pelado, que no existe").
      -- Un codigo que NO existe en ningun maestro y no tiene una sola caja, pedido,
      -- proyeccion, capacidad ni FC pendiente, no es un articulo: es el resto de un
      -- ajuste mal tipeado. NO es el caso de la v20.95 (ese codigo EXISTE y esta en 0,
      -- y el 0 es la respuesta): aca no hay artefacto que mostrar.
      COALESCE(vsp.visible_en_stock, true)
        AND ((upper(regexp_replace(regexp_replace(coalesce(vsp.cod,''),'\s+(LK|CH|LOKE)$','','i'),'^0+(?=.)','')) = any(v_conocidos))
             OR COALESCE(vsp.stock_total,0) <> 0
             OR COALESCE(vsp.cajas_pedidas,0) <> 0
             OR COALESCE(vsp.proy_cajas_mes,0) <> 0
             OR COALESCE(vsp.capacidad_gondola,0) <> 0
             OR COALESCE(scr.fc_sin_salida,0) <> 0) AS visible_en_stock,
      COALESCE(public.gv_nombre_dual(vsp.cod_base, vsp.linea), vna.descripcion, vsp.descripcion, scr.descripcion) AS descripcion,  -- v29.37-dualnom
      COALESCE(vsp.linea, scr.linea) AS linea,
      COALESCE(vsp.cod_base, scr.cod_base) AS cod_base,
      COALESCE(vsp.familia_principal, scr.familia_principal) AS familia_principal,
      COALESCE(vsp.es_secundario, false) AS es_secundario
    FROM public.vista_stock_procesada vsp
    JOIN public.stocks_carga_rapida scr ON scr.cod = vsp.cod
    LEFT JOIN public.vista_nombres_articulos vna
      ON UPPER(REGEXP_REPLACE(vna.cod, '^0+(?=.)', '')) = UPPER(REGEXP_REPLACE(vsp.cod, '^0+(?=.)', ''))
    CROSS JOIN LATERAL (SELECT regexp_replace(scr.cod, '\s+(LK|CH)$', '') = any(v_movidos) AS prot) mv
  ) n
  WHERE t.cod = n.cod
    AND (t.terminado, t.excedente, t.separar_pedidos, t.a_facturar, t.a_guardar, t.racks, t.racks_ch,
         t.para_envasar, t.insumos_dep, t.stock_total, t.cajas_pedidas, t.proy_cajas_mes,
         t.capacidad_gondola, t.es_insumo, t.visible_en_stock, t.descripcion, t.linea, t.cod_base,
         t.familia_principal, t.es_secundario)
        IS DISTINCT FROM
        (n.terminado, n.excedente, n.separar_pedidos, n.a_facturar, n.a_guardar, n.racks, n.racks_ch,
         n.para_envasar, n.insumos_dep, n.stock_total, n.cajas_pedidas, n.proy_cajas_mes,
         n.capacidad_gondola, n.es_insumo, n.visible_en_stock, n.descripcion, n.linea, n.cod_base,
         n.familia_principal, n.es_secundario);

  -- Insertar códigos nuevos que existan en la matview pero no en carga_rapida
  INSERT INTO public.stocks_carga_rapida
    (cod, cod_base, descripcion, linea, familia_principal, es_secundario,
     terminado, excedente, separar_pedidos, a_facturar, a_guardar, racks,
     racks_ch, para_envasar, insumos_dep, stock_total,
     cajas_pedidas, proy_cajas_mes, capacidad_gondola, es_insumo, visible_en_stock)
  SELECT
    vsp.cod, vsp.cod_base,
    COALESCE(public.gv_nombre_dual(vsp.cod_base, vsp.linea), vna.descripcion, vsp.descripcion),  -- v29.37-dualnom
    vsp.linea, vsp.familia_principal, vsp.es_secundario,
    COALESCE(vsp.terminado,0), COALESCE(vsp.excedente,0), COALESCE(vsp.separar_pedidos,0),
    COALESCE(vsp.a_facturar,0), COALESCE(vsp.a_guardar,0), COALESCE(vsp.racks,0),
    COALESCE(vsp.racks_ch,0), COALESCE(vsp.para_envasar,0), COALESCE(vsp.insumos_dep,0),
    COALESCE(vsp.stock_total,0),
    COALESCE(vsp.cajas_pedidas,0), COALESCE(vsp.proy_cajas_mes,0),
    COALESCE(vsp.capacidad_gondola,0), COALESCE(vsp.es_insumo,false),
    COALESCE(vsp.visible_en_stock,true)                       -- v21.58, ver el UPDATE de arriba
      AND ((upper(regexp_replace(regexp_replace(coalesce(vsp.cod,''),'\s+(LK|CH|LOKE)$','','i'),'^0+(?=.)','')) = any(v_conocidos))
           OR COALESCE(vsp.stock_total,0) <> 0 OR COALESCE(vsp.cajas_pedidas,0) <> 0
           OR COALESCE(vsp.proy_cajas_mes,0) <> 0 OR COALESCE(vsp.capacidad_gondola,0) <> 0)
  FROM public.vista_stock_procesada vsp
  LEFT JOIN public.vista_nombres_articulos vna
    ON UPPER(REGEXP_REPLACE(vna.cod, '^0+(?=.)', '')) = UPPER(REGEXP_REPLACE(vsp.cod, '^0+(?=.)', ''))
  WHERE NOT EXISTS (SELECT 1 FROM public.stocks_carga_rapida WHERE cod = vsp.cod);

  -- v12.41: eliminar filas HUÉRFANAS (existen en carga_rapida pero ya no en la matview)
  DELETE FROM public.stocks_carga_rapida scr
  WHERE NOT EXISTS (SELECT 1 FROM public.vista_stock_procesada vsp WHERE vsp.cod = scr.cod);

  -- v21.12 (Luis, 22/09) — EL CRUCE VA POR (CODIGO, EMPRESA), nunca por un string
  -- concatenado. `stocks_carga_rapida` ya tiene los dos datos separados: `cod_base`
  -- (438E) y `linea` (LK/CH); el `cod` con sufijo ("438E LK") es una clave heredada
  -- de vista_stock_procesada y NO se usa para esto. Antes se cruzaba `scr.cod = fc.cod`
  -- con igualdad exacta, asi que los 4 duales quedaban en 0 de los dos lados y un
  -- codigo con L (026L) no matcheaba nada.
  -- La empresa SOLO desambigua donde hay dos filas con el mismo cod_base (los duales);
  -- en el resto sobra, y por eso el NOT EXISTS la deja pasar.
  -- v31.64: en UNA sentencia y sólo donde cambia (antes: todo a 0 y de vuelta = dos eventos de
  -- realtime por fila). sum() en vez de "la fila que toque": medido 16/10, ningún código no dual
  -- tiene FC de las dos empresas, así que da lo mismo que antes.
  UPDATE public.stocks_carga_rapida t
  SET fc_sin_salida = n.fc
  FROM (
    SELECT scr.cod, COALESCE(sum(fc.cajas), 0) AS fc
      FROM public.stocks_carga_rapida scr
      LEFT JOIN ( SELECT cod, empresa, sum(cajas) AS cajas
                    FROM public.vista_fc_sin_salida
                   GROUP BY cod, empresa ) fc
        ON public.norm_cod(scr.cod_base) = fc.cod
       AND ( -- NO dual: una sola fila por codigo, la empresa no hace falta.
             NOT EXISTS (SELECT 1 FROM public.codigos_duales d
                          WHERE public.norm_cod(d.cod) = fc.cod)
             -- DUAL: manda la empresa, y la fila es la DESDOBLADA. ⚠ El 439E tiene ademas
             -- una fila residual PELADA (stock 0) de antes del desdoble: sin este segundo
             -- filtro el badge se contaba dos veces del lado LK (medido 22/09).
             OR ( UPPER(scr.linea) = fc.empresa
                  AND public.norm_cod(scr.cod) <> fc.cod ) )
     GROUP BY scr.cod
  ) n
  WHERE t.cod = n.cod AND t.fc_sin_salida IS DISTINCT FROM n.fc;
END;
$function$;

-- D ─────────────────────────────────────────────────────────────────────────────────────────
create or replace view public.gv_importados_stock_dep with (security_invoker = true) as
 WITH sal AS (
         SELECT gv_cod_stock(s.cod_art) AS cod_norm,
            upper(COALESCE(s.empresa, 'Mixto'::text)) AS empresa,
            sum(COALESCE(s.terminado, 0::numeric) + COALESCE(s.excedente, 0::numeric) + COALESCE(s.separar_pedidos, 0::numeric) + COALESCE(s.a_facturar, 0::numeric) + COALESCE(s.a_guardar, 0::numeric) + COALESCE(s.racks, 0::numeric) + COALESCE(s.racks_ch, 0::numeric) + COALESCE(s.para_envasar, 0::numeric)) AS cajas_bruto,
            sum(COALESCE(s.insumos, 0::numeric)) AS cajas_insumos
           FROM vista_saldos_stock s
          GROUP BY (gv_cod_stock(s.cod_art)), (upper(COALESCE(s.empresa, 'Mixto'::text)))
        ), dem AS (
         -- v31.64: de stocks_carga_rapida (job de pedidas, ≤ 30 s), no de la matview: el MISMO
         -- número que Stocks. Misma clave (cod con sufijo de empresa en los duales).
         SELECT gv_cod_stock(p.cod) AS cod_norm,
                CASE
                    WHEN p.cod ~ '\s+CH$'::text THEN 'CH'::text
                    WHEN p.cod ~ '\s+(LK|LOKE)$'::text THEN 'LK'::text
                    ELSE 'MIXTO'::text
                END AS empresa,
            sum(COALESCE(p.cajas_pedidas, 0::numeric)) AS cajas_pedidas
           FROM stocks_carga_rapida p
          GROUP BY (gv_cod_stock(p.cod)), (
                CASE
                    WHEN p.cod ~ '\s+CH$'::text THEN 'CH'::text
                    WHEN p.cod ~ '\s+(LK|LOKE)$'::text THEN 'LK'::text
                    ELSE 'MIXTO'::text
                END)
        )
 SELECT COALESCE(sal.cod_norm, dem.cod_norm) AS cod_norm,
    COALESCE(sal.empresa, dem.empresa) AS empresa,
    COALESCE(sal.cajas_bruto, 0::numeric) AS cajas_bruto,
    COALESCE(dem.cajas_pedidas, 0::numeric) AS cajas_pedidas,
    COALESCE(sal.cajas_insumos, 0::numeric) AS cajas_insumos
   FROM sal
     FULL JOIN dem ON dem.cod_norm = sal.cod_norm AND dem.empresa = sal.empresa;

-- centinelas (patrón sacado del CÓDIGO) ─────────────────────────────────────────────────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version, activo) values
 ('refresh_stocks_carga_rapida', 'funcion', '= any\(v_movidos\)',
  'No pisar con la matview los saldos de un codigo movido despues de su ultimo refresco: el trigger ya los dejo bien y pisarlos volvia la pantalla atras (936E 12->11->12).', 'Luis', 'v31.65', true),
 ('refresh_stocks_carga_rapida', 'funcion', 'IS DISTINCT FROM',
  'Escribir solo las filas que cambian: cada UPDATE es un evento de realtime para cada pantalla de Stocks abierta.', 'Luis', 'v31.65', true),
 ('gv_stock_pedidas_vivo', 'funcion', 'gv_stock_pedidas_sucio_seq',
  'Las cajas pedidas se recalculan SOLO si la secuencia se movio (triggers de pedidos/tandas), no cada vez: Luis "que solo busque cambios".', 'Luis', 'v31.65', true);
