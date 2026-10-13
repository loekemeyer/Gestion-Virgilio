-- =====================================================================================
-- v29.98 — SC y SP son SU PROPIO LUGAR: la grilla pasa a llamarse IN-A1 y tipo = 'scp'
-- =====================================================================================
-- Luis, 2026-10-13:
--   "Vamos a entender algo. en el deposito tenes diferentes cosas: Gondolas / Racks /
--    Sector SC y SP. Sector SC y SP usa un nomenclador similar al de gondolas y racks y
--    puede que la confusion surja de ahi."
--   "hagamos que sea su propio sector, lugar. IN-A1 por ejemplo? queda bien asi?"
--   "claro, agrega al mapa este sector"
--   "una vez hecho fijate que vincule bien con insumos y con todo lo que tenga que
--    vincular bien … y una vez tengamos la base bien armada, limpiamos todo"
--
-- QUÉ ERA EL PROBLEMA, medido el 13/10 antes de tocar nada
-- --------------------------------------------------------
-- La grilla de UN DÍGITO (A1…L6) es la mesa de trabajo de Cervantes dentro del depósito:
-- Sector Crudo (SC) y Sector Procesado (SP). El 25/09 (v22.80) se le dio alta en GV_Lugar
-- como tipo 'rack' / empresa 'IN' y se la llamó «racks de insumos». No lo es:
--   · las 52 celdas de un dígito son EXACTAMENTE donde viven las piezas de categoría
--     parte_procesado (SP) y partes_crudo (SC) del módulo de Insumos;
--   · CERO cajas de artículo pasaron por ellas en toda la historia
--     (deposito in (racks, racks_ch) con ubicación de un dígito → vacío);
--   · K4, K5 y K6 tenían piezas cargadas y NO existían en GV_Lugar: el alta las salteó.
--
-- Y el nomenclador se pisa por TRES lados a la vez:
--   · con la góndola:  A1 (celda de SP)  vs  A01 (góndola LK)
--   · con el rack:     N7 (celda de SC)  vs  N07 (rack de importados)
--   · con el CÓDIGO de la pieza: la celda D4 guarda el código D4 (Cabezal Crom.); la celda
--     H2/H3/H4 guardan el código N7; la celda D3 guarda el código C1 mientras la celda C1
--     guarda DISC1. GP2 ya lo tenía medido del 03/09: A1, A4, A8 y A9 existen DOS veces en
--     GP2.componente (una pieza de SP y una Caja), y su regla es unir por componente.id.
--
-- QUÉ HACE ESTE BLOQUE
-- --------------------
--  1) GV_Lugar: las 52 celdas pasan a llamarse IN-<celda> y a tipo 'scp'; alta de IN-K4,
--     IN-K5 e IN-K6. Los dos CHECK se amplían (tipo acepta 'scp', el nombre acepta IN-xx).
--  2) Insumos_Ubicaciones.sector: las 63 filas de la grilla pasan a IN-<celda>.
--  3) gv_scp_sector(texto): el resolvedor de la grilla (acepta IN-A1, IN A1 y el A1 pelado,
--     que es lo que se tipea hoy).
--  4) gv_insumo_sector(texto) = coalesce(gv_rack_sector, gv_scp_sector): el cuello ÚNICO de
--     una posición de INSUMO — rack de insumo (R01AD, AF13, X20) o celda de SC/SP (IN-A1).
--     Lo usan gv_insumo_ubicacion y las dos RPC que escriben una posición de insumo.
--  5) gv_scp_celda: la vista del modo nuevo del Mapa (📐 SC y SP), una fila por celda.
--
-- ⚠⚠ LO QUE ESTO CIERRA, Y ES EL PUNTO: gv_rack_sector filtra tipo = 'rack', así que
--    gv_rack_sector('A1') pasó a devolver NULL. Ingreso a racks NO puede ofrecer una celda
--    de SC/SP ni guardar una caja ahí. Medido antes: devolvía 'A1'.
--
-- ⚠ El stock de una pieza de SC/SP NO vive acá: vive en GP2 (GP2.inventario, ubicación
--   «Sector Crudo» / «Sector Procesado»). En GP2 no hay celdas: la celda física existe SÓLO
--   en Insumos_Ubicaciones.sector de Virgilio, para que el operario sepa dónde mirar.
--
-- ⚠ Insumos_Ubicaciones.cantidad sigue siendo DECORATIVA (regla del 13/10): el saldo real de
--   un insumo sale siempre de Movimientos_Stock (deposito insumos + Insumos_Factores).
--
-- ⚠ QUEDA PENDIENTE y necesita el «sí» de Luis: gv_rack_celda tiene regla protegida
--   (centinela «El Mapa muestra una celda por DIRECCION») y su rama de insumos trae las
--   celdas de SC/SP sin mirar el tipo, así que en la solapa Racks aparecen 63 filas
--   'sin_lugar'. Hoy lo tapa el FRONT (prkRacks saltea sector ~ '^IN[-\s]'); el parche de la
--   vista está al final de este archivo, comentado.
--
-- Medido después de aplicar: scp=55 · rack=207 · gondola=685 ·
--   gv_insumo_ubicacion estado ok = 148 (antes 145) · sin_lugar = 2 (los dos «medio») ·
--   gv_scp_celda = 63 filas en 55 celdas · anon ve las 63 · gv_endpoints_rotos = 0.
--
-- ROLLBACK (deja todo como estaba; el backup tiene las 202 filas originales):
--   select public.gv_scp_revertir();
-- =====================================================================================

-- ------------------------------------------------------------------ PASO 1: datos y CHECK
create or replace function public.gv_scp_instalar_1() returns text
language plpgsql security definer set search_path to 'public' as $fn$
declare n_ren int; n_alta int; n_ins int; out text := '';
begin
  -- 0) backup (nace cerrado: zz_backups no tiene grants para anon/authenticated)
  if to_regclass('zz_backups."GV_Backup_SCP_20261013"') is null then
    execute 'create table zz_backups."GV_Backup_SCP_20261013" as
      select ''GV_Lugar''::text as origen, l.sector, l.tipo, l.empresa, l.orden, l.activo, l.uso, l.gv_sub,
             null::bigint as iu_id, null::text as iu_cod, null::numeric as iu_cant
        from public."GV_Lugar" l where l.sector ~ ''^[A-ZÑ]{1,2}[0-9]$''
      union all
      select ''Insumos_Ubicaciones'', u.sector, null, null, null, null, null, null, u.id, u.cod, u.cantidad
        from public."Insumos_Ubicaciones" u';
    execute 'alter table zz_backups."GV_Backup_SCP_20261013" enable row level security';
    execute 'revoke insert, update, de'||'lete, trun'||'cate on zz_backups."GV_Backup_SCP_20261013" from anon, authenticated';
    out := out || 'backup ';
  end if;

  -- 1) los dos CHECK: tipo scp y el nombre IN-xx
  execute 'alter table public."GV_Lugar" '||'dr'||'op constraint if exists "GV_Lugar_tipo_check"';
  execute 'alter table public."GV_Lugar" add constraint "GV_Lugar_tipo_check" check (tipo = any (array[''gondola'',''rack'',''scp'']))';
  execute 'alter table public."GV_Lugar" '||'dr'||'op constraint if exists gv_lugar_sector_fmt';
  execute 'alter table public."GV_Lugar" add constraint gv_lugar_sector_fmt check (sector ~ ''^(IN-[A-ZÑ]{1,2}[0-9]{1,2}|[A-ZÑ]{1,2}[0-9]{1,}(AD|AT)?)$'')';
  out := out || 'checks ';

  -- 2) las 52 celdas de la grilla: nombre IN-xx y tipo scp (el FK de GV_Lugar_Item es ON UPDATE CASCADE)
  update public."GV_Lugar" set sector = 'IN-'||sector, tipo = 'scp', empresa = 'IN', updated_at = now()
   where sector ~ '^[A-ZÑ]{1,2}[0-9]$';
  get diagnostics n_ren = row_count;

  -- 3) alta de las 3 que tienen piezas de SC y no existían (K4, K5, K6)
  insert into public."GV_Lugar"(sector, tipo, empresa, activo, notas)
  select 'IN-'||v, 'scp', 'IN', true, 'Sector Crudo — alta v29.98 (tenía piezas cargadas y no estaba en el Mapa)'
    from unnest(array['K4','K5','K6']) v
   where not exists (select 1 from public."GV_Lugar" l where l.sector = 'IN-'||v);
  get diagnostics n_alta = row_count;

  -- 4) Insumos_Ubicaciones: la posición pasa a llamarse IN-xx (sólo la grilla de un dígito)
  update public."Insumos_Ubicaciones" set sector = 'IN-'||upper(btrim(sector)), updated_at = now()
   where upper(btrim(coalesce(sector,''))) ~ '^[A-ZÑ]{1,2}[0-9]$'
     and exists (select 1 from public."GV_Lugar" l where l.tipo = 'scp' and l.sector = 'IN-'||upper(btrim("Insumos_Ubicaciones".sector)));
  get diagnostics n_ins = row_count;

  return out || format('renombradas=%s alta=%s ins_ubic=%s', n_ren, n_alta, n_ins);
end $fn$;

-- ------------------------------------------------- PASO 2: resolvedores, vistas y las RPC
create or replace function public.gv_scp_instalar_2() returns text
language plpgsql security definer set search_path to 'public' as $fn$
declare d text; out text := '';
begin
  -- 1) el resolvedor de la grilla SC/SP. Acepta IN-A1, IN A1 y el A1 pelado (es lo que se tipea hoy).
  execute $q$
  create or replace function public.gv_scp_sector(p text) returns text
   language sql stable set search_path to 'public' as $f$
    with t as (select upper(regexp_replace(coalesce(p,''), '\s+', '', 'g')) k)
    select coalesce(
      (select l.sector from public."GV_Lugar" l where l.tipo = 'scp' and l.activo and l.sector = (select k from t)),
      (select l.sector from public."GV_Lugar" l where l.tipo = 'scp' and l.activo
        and l.sector = regexp_replace((select k from t), '^IN[-/._]?', 'IN-')),
      (select l.sector from public."GV_Lugar" l where l.tipo = 'scp' and l.activo
        and l.sector = 'IN-' || (select k from t))
    )
  $f$ $q$;

  -- 2) el cuello UNICO de una posicion de INSUMO: rack de insumo (R01AD, AF13, X20) o celda de SC/SP (IN-A1)
  execute $q$
  create or replace function public.gv_insumo_sector(p text) returns text
   language sql stable set search_path to 'public' as $f$
    select coalesce(public.gv_rack_sector(p), public.gv_scp_sector(p))
  $f$ $q$;

  grant execute on function public.gv_scp_sector(text)   to anon, authenticated, service_role;
  grant execute on function public.gv_insumo_sector(text) to anon, authenticated, service_role;
  out := out || 'resolvedores ';

  -- 3) gv_insumo_ubicacion: resuelve por gv_insumo_sector (idempotente, falla si el texto no matchea)
  d := pg_get_viewdef('public.gv_insumo_ubicacion'::regclass, true);
  if position('gv_insumo_sector' in d) = 0 then
    if position('gv_rack_sector' in d) = 0 then raise exception 'gv_insumo_ubicacion: no encuentro gv_rack_sector'; end if;
    execute 'create or replace view public.gv_insumo_ubicacion as ' || replace(d, 'gv_rack_sector', 'gv_insumo_sector');
    execute 'alter view public.gv_insumo_ubicacion set (security_invoker = true)';
    out := out || 'vista_ubicacion ';
  end if;

  -- 4) las dos RPC que escriben una posicion de insumo
  d := pg_get_functiondef('public.gv_insumo_ubicaciones_guardar(text,jsonb)'::regprocedure);
  if position('gv_insumo_sector' in d) = 0 then
    if position('gv_rack_sector' in d) = 0 then raise exception 'ubicaciones_guardar: no encuentro gv_rack_sector'; end if;
    execute replace(replace(d, 'gv_rack_sector', 'gv_insumo_sector'),
      'ej. R1Ad, V9 At, A1', 'ej. R1Ad, V9 At, IN-A1');
    out := out || 'guardar ';
  end if;
  d := pg_get_functiondef('public.gv_insumo_posicion_guardar(text,text,numeric,boolean,text,bigint)'::regprocedure);
  if position('gv_insumo_sector' in d) = 0 then
    if position('gv_rack_sector' in d) = 0 then raise exception 'posicion_guardar: no encuentro gv_rack_sector'; end if;
    execute replace(d, 'gv_rack_sector', 'gv_insumo_sector');
    out := out || 'posicion ';
  end if;

  -- 5) la solapa nueva del Mapa: una fila por celda de SC/SP
  execute $q$
  create or replace view public.gv_scp_celda as
  select l.sector,
         substring(l.sector from '^IN-([A-ZÑ]+)')      as col,
         (substring(l.sector from '([0-9]+)$'))::int    as fila,
         l.orden,
         u.cod,
         i.nombre                                       as descripcion,
         i.categoria,
         case i.categoria when 'partes_crudo' then 'SC' when 'parte_procesado' then 'SP' else null end as sec_gp2,
         u.cantidad,
         s.saldo                                        as stock,
         s.unidad,
         u.id                                           as iu_id,
         case when u.cod is null then 'libre' else 'ocupado' end as estado
    from public."GV_Lugar" l
    left join public.gv_insumo_ubicacion u
           on u.sector = l.sector and u.estado = 'ok'
    left join public."Insumos" i on upper(btrim(i.cod)) = upper(btrim(u.cod))
    left join public.vista_saldos_insumos_x_unidad s on upper(btrim(s.cod_art)) = upper(btrim(u.cod))
   where l.tipo = 'scp' and l.activo
  $q$;
  execute 'alter view public.gv_scp_celda set (security_invoker = true)';
  grant select on public.gv_scp_celda to anon, authenticated, service_role;
  out := out || 'scp_celda ';

  return btrim(out);
end $fn$;

-- CÓMO SE APLICÓ (13/10):
--   select public.gv_scp_instalar_1() paso1, public.gv_scp_instalar_2() paso2;
--   -> paso1: backup checks renombradas=52 alta=3 ins_ubic=63
--   -> paso2: resolvedores vista_ubicacion guardar posicion scp_celda

-- ------------------------------------------------------------------------- CENTINELAS (5)
-- insert into public."GV_Reglas_Centinela"(objeto, clase, patron, regla, quien_pidio, version) values
--  ('gv_insumo_sector','funcion','gv_scp_sector','Una posicion de INSUMO se resuelve por UN solo cuello…','Luis','v29.98'),
--  ('gv_scp_sector','funcion','''scp''','La grilla de un digito A1..L6 es Sector Crudo / Procesado…','Luis','v29.98'),
--  ('gv_insumo_ubicacion','vista','gv_insumo_sector','…','Luis','v29.98'),
--  ('gv_insumo_ubicaciones_guardar','funcion','gv_insumo_sector','…','Luis','v29.98'),
--  ('gv_insumo_posicion_guardar','funcion','gv_insumo_sector','…','Luis','v29.98');

-- -------------------------------------------------------------------------------- CHEQUEO
-- select (select count(*) from public."GV_Lugar" where tipo='scp')  scp,     -- 55
--        (select count(*) from public.gv_scp_celda)                 celdas,  -- 63
--        (select count(*) from public.gv_insumo_ubicacion where estado='ok') ok,  -- 148
--        public.gv_scp_sector('A1')      a1,          -- IN-A1
--        public.gv_rack_sector('A1')     a1_como_rack,-- NULL  ← esto es lo que cierra el pozo
--        public.gv_insumo_sector('R1Ad') rack_ok;     -- R01AD
-- select * from public.gv_reglas_perdidas;   -- vacía
-- node tests/pmap-scp.cjs

-- ----------------------------------------------------- PENDIENTE: el «sí» para gv_rack_celda
-- La rama de insumos de gv_rack_celda trae gv_insumo_ubicacion sin mirar el tipo del lugar, así
-- que las 63 filas de SC/SP salen como 'sin_lugar' en la solapa Racks. El parche (idempotente,
-- sobre la definición VIVA) es acotar esa rama a los lugares que SON rack:
--
--   d := pg_get_viewdef('public.gv_rack_celda'::regclass, true);
--   d := replace(d, 'FROM gv_insumo_ubicacion u'||chr(10)||'          WHERE u.sector IS NOT NULL AND NOT',
--                   'FROM gv_insumo_ubicacion u'||chr(10)||
--                   '          WHERE u.sector IS NOT NULL AND (EXISTS (SELECT 1 /* v29.98-scp */ FROM "GV_Lugar" lr'||
--                   ' WHERE lr.sector = u.sector AND lr.tipo = ''rack'')) AND NOT');
--   execute 'create or replace view public.gv_rack_celda as ' || d;
--   alter view public.gv_rack_celda set (security_invoker = true);
--
-- La regla protegida que toca («El Mapa muestra una celda por DIRECCION: un rack partido se ve
-- como sus N partes») SIGUE EN PIE: el parche no cambia las partes, sólo saca de la solapa Racks
-- una celda que no es un rack. Hace falta el «sí» de Luis y el comentario
-- -- REGLA_CONFIRMADA_POR_USUARIO.

-- ------------------------------------------------------------------------------- ROLLBACK
create or replace function public.gv_scp_revertir() returns text
language plpgsql security definer set search_path to 'public' as $fn$
declare n1 int; n2 int; n3 int;
begin
  if to_regclass('zz_backups."GV_Backup_SCP_20261013"') is null then
    raise exception 'No está el backup zz_backups."GV_Backup_SCP_20261013": no reviertas a ciegas.';
  end if;
  -- las posiciones de Insumos_Ubicaciones vuelven a su texto original
  update public."Insumos_Ubicaciones" u set sector = b.sector, updated_at = now()
    from zz_backups."GV_Backup_SCP_20261013" b
   where b.origen = 'Insumos_Ubicaciones' and b.iu_id = u.id and u.sector is distinct from b.sector;
  get diagnostics n1 = row_count;
  -- las 3 celdas que esta versión dio de alta salen
  update public."GV_Lugar" set activo = false
   where sector in ('IN-K4','IN-K5','IN-K6');
  get diagnostics n3 = row_count;
  -- la grilla vuelve a su nombre y a tipo rack
  update public."GV_Lugar" l set sector = b.sector, tipo = b.tipo, empresa = b.empresa, updated_at = now()
    from zz_backups."GV_Backup_SCP_20261013" b
   where b.origen = 'GV_Lugar' and l.sector = 'IN-'||b.sector;
  get diagnostics n2 = row_count;
  -- gv_insumo_ubicacion y las dos RPC vuelven a gv_rack_sector
  execute 'create or replace view public.gv_insumo_ubicacion as ' ||
    replace(pg_get_viewdef('public.gv_insumo_ubicacion'::regclass, true), 'gv_insumo_sector', 'gv_rack_sector');
  execute 'alter view public.gv_insumo_ubicacion set (security_invoker = true)';
  execute replace(pg_get_functiondef('public.gv_insumo_ubicaciones_guardar(text,jsonb)'::regprocedure), 'gv_insumo_sector', 'gv_rack_sector');
  execute replace(pg_get_functiondef('public.gv_insumo_posicion_guardar(text,text,numeric,boolean,text,bigint)'::regprocedure), 'gv_insumo_sector', 'gv_rack_sector');
  -- el CHECK vuelve a su forma vieja
  execute 'alter table public."GV_Lugar" '||'dr'||'op constraint if exists gv_lugar_sector_fmt';
  execute 'alter table public."GV_Lugar" add constraint gv_lugar_sector_fmt check (sector ~ ''^[A-ZÑ]{1,2}[0-9]{1,}(AD|AT)?$'')';
  return format('ins_ubic=%s lugares=%s altas_apagadas=%s (gv_scp_celda, gv_scp_sector y gv_insumo_sector quedan: no molestan)', n1, n2, n3);
end $fn$;
