-- gv_stock_procesada_dup_v1633.sql — APLICADO 2026-09-12.
--
-- PROBLEMA (auditoría, problema 100). El REFRESH MATERIALIZED VIEW CONCURRENTLY de
-- `vista_stock_procesada` necesita el índice único `idx_vista_stock_procesada_cod`, y la
-- consulta del matview estaba produciendo `cod` repetidos. Medido sobre 24 h de
-- `cron.job_run_details`:
--
--   cron 55 (*/2, el REFRESH)                → 212 fallas de 688 corridas (31%)
--   cron 57 (*/5, refresh_stocks_carga_rapida) →  96 fallas de 275 (35%)
--
-- Todas con `duplicate key value violates unique constraint` / `could not create unique index`.
-- Códigos que duplicaban: 547 (121 veces), 101 (84), 505 (48), 505I, 53, 531, 280, 530, 809E,
-- 508, 518, 513, 437E. Consecuencia: **el stock que ven los operarios se quedaba viejo un
-- tercio del tiempo**, y en silencio — el cron no le avisa a nadie.
--
-- CAUSA RAÍZ. El CTE `stock` normalizaba la clave (`053` → `53`) pero **no agrupaba**. Dos
-- grafías del mismo artículo conviviendo en `vista_saldos_stock` (`053` y `53`, `0547` y `547`)
-- daban dos filas con el mismo `codn`, y de ahí dos filas en el matview. Al 12/09 la tabla
-- estaba limpia — por eso el fallo era intermitente: aparecía cada vez que alguien escribía un
-- movimiento con la grafía que faltaba, y se iba cuando se normalizaba. El matview estaba a
-- UN movimiento mal escrito de fallar, sobre cualquier código.
--
-- FIX. El CTE `stock` agrupa por el código normalizado y SUMA. Es lo semánticamente correcto:
-- `053` y `53` son el mismo artículo, que es justamente lo que dice la normalización.
--
-- ⚠ `create or replace` no existe para matviews → DROP CASCADE + CREATE, que se lleva puestas
--   las dos vistas que dependen (`Stock_Saldos`, `gv_importados_stock_dep`). Por eso la
--   migración las respalda y las vuelve a crear con sus opciones y sus grants, todo en UNA
--   transacción.
--
-- ⚠⚠ Y NO ALCANZA CON MIRAR UN NIVEL. Acá me equivoqué: la consulta de dependencias que corrí
--   antes del DROP devolvía sólo las DIRECTAS, y `gv_importados_ordenes` cuelga de
--   `gv_importados_stock_dep`, o sea segundo nivel. CASCADE baja hasta el fondo, así que se la
--   llevó y la pantalla de Importados quedó en 404 hasta que la recreé
--   (`sql/gv_importados_ordenes_completa_v1634.sql`). **Es la segunda vez que pasa**: el mismo
--   CASCADE se la había llevado en la v16.20. La cazó el centinela `gv_endpoints_rotos`, que
--   pasó de 0 a 1.
--
--   Antes de un DROP CASCADE, listar los dependientes TRANSITIVOS:
--
--     with recursive dep as (
--       select c.oid, c.relname, c.relkind, 1 lvl
--         from pg_class c where c.oid = 'public.<el objeto>'::regclass
--       union
--       select c.oid, c.relname, c.relkind, dep.lvl + 1
--         from dep
--         join pg_depend d  on d.refobjid = dep.oid
--         join pg_rewrite r on r.oid = d.objid
--         join pg_class c   on c.oid = r.ev_class and c.oid <> dep.oid
--     )
--     select lvl, relkind, relname from dep where lvl > 1 order by lvl, relname;
--
--   Y DESPUÉS del CREATE, mirar `select * from public.gv_endpoints_rotos;` — para eso está.
--
-- MEDICIÓN antes/después — idéntica, o sea que sobre los datos de hoy el cambio es un no-op
-- comprobado, y lo único que hace es que no pueda volver a fallar:
--
--   filas 363 · stock_total 48197.00 · cajas_pedidas 4720.66 · a_pedir 7561.00
--   uni_x_caja 5163.00 · visibles 361 · Stock_Saldos 363 · gv_importados_stock_dep 482
--
--   Y después: `refresh materialized view concurrently` corre limpio, y
--   `refresh_stocks_carga_rapida()` deja `stocks_carga_rapida` en 363 / 48197.00.
--
-- BACKUP: `zz_backups."GV_Backup_stock_procesada_20260912"` — la definición vieja del matview,
-- sus índices, y la definición + opciones + grants de las dos vistas dependientes. El ROLLBACK
-- es correr esta misma migración con `def` en vez de `replace(d, viejo, nuevo)`.

do $mig$
declare d text; viejo text; nuevo text; def_ss text; def_isd text;
begin
  d       := (select def from zz_backups."GV_Backup_stock_procesada_20260912" where obj='vista_stock_procesada');
  def_ss  := (select def from zz_backups."GV_Backup_stock_procesada_20260912" where obj='Stock_Saldos');
  def_isd := (select def from zz_backups."GV_Backup_stock_procesada_20260912" where obj='gv_importados_stock_dep');

  viejo := $v$), stock AS (
         SELECT regexp_replace(upper(TRIM(BOTH FROM vista_saldos_stock.clave)), '^0+(?=.)'::text, ''::text) AS codn,
            vista_saldos_stock.descripcion,
            COALESCE(vista_saldos_stock.terminado, 0::numeric) AS terminado,
            COALESCE(vista_saldos_stock.excedente, 0::numeric) AS excedente,
            COALESCE(vista_saldos_stock.separar_pedidos, 0::numeric) AS separar_pedidos,
            COALESCE(vista_saldos_stock.a_facturar, 0::numeric) AS a_facturar,
            COALESCE(vista_saldos_stock.a_guardar, 0::numeric) AS a_guardar,
            COALESCE(vista_saldos_stock.racks, 0::numeric) AS racks,
            COALESCE(vista_saldos_stock.racks_ch, 0::numeric) AS racks_ch,
            COALESCE(vista_saldos_stock.para_envasar, 0::numeric) AS para_envasar,
            COALESCE(vista_saldos_stock.insumos, 0::numeric) AS insumos_dep
           FROM vista_saldos_stock
        ), stock_e AS ($v$;

  nuevo := $v$), stock AS (
         SELECT regexp_replace(upper(TRIM(BOTH FROM vista_saldos_stock.clave)), '^0+(?=.)'::text, ''::text) AS codn,
            max(vista_saldos_stock.descripcion) AS descripcion,
            sum(COALESCE(vista_saldos_stock.terminado, 0::numeric)) AS terminado,
            sum(COALESCE(vista_saldos_stock.excedente, 0::numeric)) AS excedente,
            sum(COALESCE(vista_saldos_stock.separar_pedidos, 0::numeric)) AS separar_pedidos,
            sum(COALESCE(vista_saldos_stock.a_facturar, 0::numeric)) AS a_facturar,
            sum(COALESCE(vista_saldos_stock.a_guardar, 0::numeric)) AS a_guardar,
            sum(COALESCE(vista_saldos_stock.racks, 0::numeric)) AS racks,
            sum(COALESCE(vista_saldos_stock.racks_ch, 0::numeric)) AS racks_ch,
            sum(COALESCE(vista_saldos_stock.para_envasar, 0::numeric)) AS para_envasar,
            sum(COALESCE(vista_saldos_stock.insumos, 0::numeric)) AS insumos_dep
           FROM vista_saldos_stock
          GROUP BY (regexp_replace(upper(TRIM(BOTH FROM vista_saldos_stock.clave)), '^0+(?=.)'::text, ''::text))
        ), stock_e AS ($v$;

  if position(viejo in d) = 0 then raise exception 'no se encontro el CTE stock'; end if;
  if def_ss is null or def_isd is null then raise exception 'falta la def de alguna dependiente'; end if;

  execute 'drop materialized view public.vista_stock_procesada cascade';
  execute 'create materialized view public.vista_stock_procesada as ' || replace(d, viejo, nuevo);
  execute 'create unique index idx_vista_stock_procesada_cod on public.vista_stock_procesada using btree (cod)';

  execute 'create view public."Stock_Saldos" as ' || def_ss;
  execute 'create view public.gv_importados_stock_dep with (security_invoker = true) as ' || def_isd;

  execute 'grant select, insert, update, delete, truncate, references, trigger on public."Stock_Saldos" to anon, authenticated, service_role';
  execute 'grant select, insert, update, delete, truncate, references, trigger on public.gv_importados_stock_dep to anon, authenticated, service_role';
end $mig$;

-- ── CENTINELA ────────────────────────────────────────────────────────────────────────────
-- El CTE `stock` era UNA de cinco fuentes que le pueden meter un cod repetido al matview. Las
-- otras cuatro (`vista_uni_x_caja`, `vista_nombres_articulos`, `Equivalencias_Familia`, y el
-- UNION ALL de proyección) hoy están limpias, pero nada garantiza que sigan así, y el modo de
-- falla es mudo. Esta vista las mira a las cinco: **vacía = todo bien**.
create or replace view public.gv_stock_procesada_dup
with (security_invoker = true) as
  select 'vista_saldos_stock' as fuente, codn as cod, n
    from (select regexp_replace(upper(btrim(clave)),'^0+(?=.)','') codn, count(*) n
            from public.vista_saldos_stock group by 1) t where n > 1
union all
  select 'vista_uni_x_caja', codn, n
    from (select codn, count(*) n from public.vista_uni_x_caja group by 1) t where n > 1
union all
  select 'vista_nombres_articulos', cod, n
    from (select cod, count(*) n from public.vista_nombres_articulos group by 1) t where n > 1
union all
  select 'Equivalencias_Familia.cod_secundario', sec, n
    from (select regexp_replace(upper(btrim(cod_secundario)),'^0+(?=.)','') sec, count(*) n
            from public."Equivalencias_Familia" group by 1) t where n > 1
union all
  select 'proyeccion (madre + GV_Proyeccion_Emp)', codn, n
    from (select codn, count(*) n from (
            select regexp_replace(upper(btrim(cod)),'^0+(?=.)','') codn
              from public.proyeccion_madre group by 1
            union all
            select public.gv_cod_stock(g.cod) || case when g.empresa='chef' then ' CH' else ' LK' end
              from public."GV_Proyeccion_Emp" g group by public.gv_cod_stock(g.cod), g.empresa) u
          group by 1) t where n > 1;
revoke all on public.gv_stock_procesada_dup from anon, authenticated;
grant select on public.gv_stock_procesada_dup to anon, authenticated;

-- Chequeo:
--   select * from public.gv_stock_procesada_dup;   -- 0 filas = el REFRESH no va a fallar
