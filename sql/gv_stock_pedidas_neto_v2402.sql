-- ============================================================================
-- v24.02 (Luis, 2026-09-29) — LAS CAJAS PEDIDAS SE CONTEMPLAN IGUAL EN LAS DOS PANTALLAS
--
-- Luis, textual: *"si lo comprometido no es stock disponible, esta bien. pero se tiene que
-- contemplar igual en OCs que en Stocks"* y *"el neto adelante y el pickeado en el tooltip
-- (que pickeado seria «pickeados», osea los que TP, y los que estan pickeados ahora sin TP.
-- que lo aclare el tooltip)"*.
--
-- EL PROBLEMA, medido el 29/09 sobre el 501: Stocks dice 251 cajas pedidas y OCs dice 225.
-- No es redondeo ni un bug: son DOS COLUMNAS DE LA MISMA FILA de vista_stock_procesada con
-- dos criterios distintos —`cajas_pedidas` (toda la demanda viva) y `cajas_pedidas_familia`
-- (la que excluye las NP cuya tanda ya tiene TP, regla v19.85 de Thomas)— y cada pantalla
-- lee una. El criterio de OCs es el correcto y NO se toca: una caja ya pickeada esta separada
-- para su pedido, no es demanda a comprar, igual que no es stock disponible. Lo que estaba
-- mal es que Stocks no lo contemplaba.
--
-- Impacto medido (29/09): 109 codigos cambian, 13.132,33 -> 11.279,33 cajas (-1.853 ya
-- pickeadas). NO se mueve ni una caja de compra: el generador de OC ya usaba el neto.
--
-- ⚠ LA MATVIEW NO SE TOCA, A PROPOSITO. `cajas_pedidas` vive en `vista_stock_procesada`, que
-- es una MATERIALIZED VIEW: cambiarla obliga a DROP + CREATE, y su CASCADE arrastra tres
-- dependientes —`Stock_Saldos`, `gv_importados_stock_dep` y, en SEGUNDO nivel,
-- `gv_importados_ordenes`—, que es exactamente lo que dejo la pantalla de Importados en 404
-- dos veces (v16.20 y v16.33). Las tres columnas nuevas van en `stocks_carga_rapida`, que es
-- lo que la pantalla de Stocks lee de verdad (regla v21.48), con un ALTER ADD COLUMN que no
-- reescribe una sola fila.
--
-- ⚠ Y `cajas_pedidas` (el total) SE CONSERVA, tambien a proposito: es lo que sostiene
-- `visible_en_stock` y el `_stkHasAny` del front. Bajando la columna a secas, 9 codigos
-- quedarian en 0 pedidos y 5 de ellos —198E, 951E, 952E, 953E, 970E— desapareceria del
-- listado por tener stock 0, que es el pozo de la v20.95 ("una fila que no sale no se
-- distingue de un codigo que no existe"). Con el total intacto, la visibilidad no se mueve.
--
-- Rollback (deja todo como estaba; el front cae al total solo):
--   alter table public.stocks_carga_rapida
--     drop column if exists cajas_pedidas_neto,
--     drop column if exists cajas_pedidas_tp,
--     drop column if exists cajas_pedidas_en_curso;
--   drop function if exists public.gv_demanda_neta_por_codigo();
--   delete from public."GV_Reglas_Centinela" where version = 'v24.02';
--   -- y reponer refresh_stocks_carga_rapida() desde el backup de abajo.
-- ============================================================================

-- 0) BACKUP de la definicion viva de la funcion que se parchea (protocolo del repo).
create table if not exists zz_backups."GV_Backup_RefreshCargaRapida_20260929" as
  select 'refresh_stocks_carga_rapida' as objeto,
         pg_get_functiondef('public.refresh_stocks_carga_rapida()'::regprocedure) as def,
         now() as guardado_en;
alter table zz_backups."GV_Backup_RefreshCargaRapida_20260929" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_RefreshCargaRapida_20260929"
  from anon, authenticated;

-- 1) LAS TRES COLUMNAS. Nullable y sin default: no reescribe la tabla.
alter table public.stocks_carga_rapida
  add column if not exists cajas_pedidas_neto     numeric,
  add column if not exists cajas_pedidas_tp       numeric,
  add column if not exists cajas_pedidas_en_curso numeric;

comment on column public.stocks_carga_rapida.cajas_pedidas_neto is
  'v24.02 — Demanda viva del codigo SIN las NP cuya tanda ya tiene TP. Es el numero que la '
  'pantalla de Stocks muestra y el MISMO criterio que usa el generador de OC. La columna '
  'cajas_pedidas (el total) se conserva para la visibilidad de la fila.';
comment on column public.stocks_carga_rapida.cajas_pedidas_tp is
  'v24.02 — Lo que el neto deja afuera: demanda cuya tanda ya termino el picking (TP). Ya esta '
  'separada para su pedido, no se compra. Se muestra en el tooltip.';
comment on column public.stocks_carga_rapida.cajas_pedidas_en_curso is
  'v24.02 — Del NETO, lo que esta en tandas con el picking EMPEZADO y sin TP (hay cajas '
  'levantadas de gondola pero la tanda no cerro): sigue contando como demanda. Tooltip.';

-- 2) UNA SOLA FUENTE para las tres cifras. Mismo `cerradas` y mismo gv_cod_stock_dem que
--    usa `dem_raw` de la matview, asi el total que devuelve coincide exactamente con
--    `cajas_pedidas` y la resta cierra (verificado: 13.132,3334 en los dos).
create or replace function public.gv_demanda_neta_por_codigo()
returns table (cod text, total numeric, neto numeric, con_tp numeric, en_curso numeric)
language sql stable
set search_path to 'public'
as $$
  with pick as (
    select distinct upper(btrim(texto)) t
      from "Registros_Produccion_Virgilio"
     where opcion = 'TP' and nullif(btrim(coalesce(texto,'')),'') is not null),
  encurso as (
    -- picking EMPEZADO y sin cerrar. El texto de un PKC puede venir como 'TANDA|NP', asi que
    -- la tanda sale del primer campo (mismo criterio que gv_evento_tanda).
    select distinct upper(btrim(split_part(texto,'|',1))) t
      from "Registros_Produccion_Virgilio"
     where opcion in ('EP','PKC') and nullif(btrim(coalesce(texto,'')),'') is not null
       and upper(btrim(split_part(texto,'|',1))) not in (select t from pick)),
  cerradas as (
    select np from "Facturacion_NP"            where np is not null
    union select np from "GV_PPP_Entregados_Historico" where np is not null
    union select np from "NP_Canceladas"       where np is not null
    union select np_label from "GV_Web_Cancelados" where np_label is not null),
  np_raw as (
    select btrim(p.np) np, upper(btrim(coalesce(p.tanda,''))) tanda
      from "GV_PPP_Programacion_Diaria" p
    union all
    select gv_ppp_web_np_label(w.empresa, w.np, w.np_idx), upper(btrim(coalesce(w.tanda,'')))
      from "PPP_Web_Programacion" w),
  -- ⚠ UNA tanda por NP: sin esto el left join MULTIPLICA la demanda de toda NP que aparezca
  --   en las dos tablas (medido en el primer intento: el 501 daba 251 contra 235).
  np_t as (
    select distinct on (np) np, tanda from np_raw order by np, (tanda <> '') desc, tanda),
  d as (
    select gv_cod_stock_dem(b.articulo, b.pedido) as c, btrim(b.pedido) np,
           sum(coalesce(b.cajas,0)) cajas
      from gv_demanda_pedidos b
     where nullif(btrim(b.articulo),'') is not null
       and not exists (select 1 from cerradas x where x.np = b.pedido)
     group by 1,2)
  select d.c,
         sum(d.cajas),
         coalesce(sum(d.cajas) filter (where coalesce(t.tanda,'') not in (select t from pick)), 0),
         coalesce(sum(d.cajas) filter (where coalesce(t.tanda,'')     in (select t from pick)), 0),
         coalesce(sum(d.cajas) filter (where coalesce(t.tanda,'')     in (select t from encurso)), 0)
    from d left join np_t t on t.np = d.np
   group by d.c
  having sum(d.cajas) > 0;
$$;
revoke all on function public.gv_demanda_neta_por_codigo() from public;
grant execute on function public.gv_demanda_neta_por_codigo() to anon, authenticated, service_role;

-- 3) Que el refresco las escriba. Se aplica SOBRE LA DEFINICION VIVA (varias sesiones tocan
--    esta funcion), es idempotente y FALLA con un raise si el texto no matchea, en vez de
--    pisar la funcion con una copia vieja.
do $aplica$
declare v_def text; v_new text;
begin
  v_def := pg_get_functiondef('public.refresh_stocks_carga_rapida()'::regprocedure);
  if position('v24.02-pedidas-neto' in v_def) > 0 then
    raise notice 'ya aplicado, no hago nada'; return;
  end if;
  if position('cajas_pedidas     = COALESCE(vsp.cajas_pedidas, 0),' in v_def) = 0 then
    raise exception 'ABORTADO: no encontre el ancla `cajas_pedidas = COALESCE(...)` en la '
      'definicion viva de refresh_stocks_carga_rapida(). Otra sesion la cambio: mirar '
      'pg_get_functiondef y rehacer el parche a mano.';
  end if;
  v_new := replace(v_def,
    'cajas_pedidas     = COALESCE(vsp.cajas_pedidas, 0),',
    'cajas_pedidas     = COALESCE(vsp.cajas_pedidas, 0),' || chr(10) ||
    '    -- v24.02-pedidas-neto (Luis, 29/09): las tres cifras que la pantalla de Stocks' || chr(10) ||
    '    -- muestra con el MISMO criterio que el generador de OC (el neto adelante, el resto' || chr(10) ||
    '    -- en el tooltip). Salen de gv_demanda_neta_por_codigo(), que es la unica fuente.' || chr(10) ||
    '    cajas_pedidas_neto     = COALESCE(dn.neto,     vsp.cajas_pedidas, 0),' || chr(10) ||
    '    cajas_pedidas_tp       = COALESCE(dn.con_tp,   0),' || chr(10) ||
    '    cajas_pedidas_en_curso = COALESCE(dn.en_curso, 0),');
  -- el FROM de ese UPDATE ya trae vsp; se le suma la fuente nueva como LEFT JOIN LATERAL para
  -- no perder ninguna fila que la funcion no encuentre (ahi el neto cae al total).
  if position('FROM public.vista_stock_procesada vsp' in v_new) = 0 then
    raise exception 'ABORTADO: no encontre el FROM de vista_stock_procesada en el UPDATE.';
  end if;
  v_new := replace(v_new, 'FROM public.vista_stock_procesada vsp',
    'FROM public.vista_stock_procesada vsp' || chr(10) ||
    '    LEFT JOIN LATERAL (select * from public.gv_demanda_neta_por_codigo() z' || chr(10) ||
    '                        where z.cod = vsp.cod limit 1) dn ON true');
  execute v_new;
  raise notice 'refresh_stocks_carga_rapida() parchada (v24.02-pedidas-neto)';
end $aplica$;

-- 4) Centinelas: que ninguna sesion se lleve puesta la regla sin que nadie se entere.
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values
 ('refresh_stocks_carga_rapida', 'funcion', 'cajas_pedidas_neto',
  'Stocks muestra las cajas pedidas con el MISMO criterio que OCs (sin las NP de tandas con TP). '
  'Luis, 29/09: "se tiene que contemplar igual en OCs que en Stocks".', 'Luis', 'v24.02'),
 ('gv_demanda_neta_por_codigo', 'funcion', 'distinct on \(np\)',
  'UNA tanda por NP: sin el distinct on el left join multiplica la demanda de toda NP que este '
  'en las dos tablas de programacion (el 501 daba 251 en vez de 235).', 'Luis', 'v24.02')
on conflict do nothing;

-- 5) CHEQUEO
-- a) el total de la fuente nueva tiene que coincidir con el de la matview:
--    select (select sum(total) from public.gv_demanda_neta_por_codigo()) fuente_nueva,
--           (select sum(cajas_pedidas) from public.vista_stock_procesada) matview;   -- iguales
-- b) la fila del 501, con las tres cifras:
--    select cod, cajas_pedidas, cajas_pedidas_neto, cajas_pedidas_tp, cajas_pedidas_en_curso
--      from public.stocks_carga_rapida where cod = '501';
-- c) que el neto coincida con lo que muestra OCs:
--    select s.cod, s.cajas_pedidas_neto, o.pedidos
--      from public.stocks_carga_rapida s join public.vista_generador_oc o on o.cod = s.cod
--     where s.cajas_pedidas_neto is distinct from o.pedidos;   -- solo familias (fila = familia)
-- d) ninguna regla perdida:
--    select * from public.gv_reglas_perdidas;
