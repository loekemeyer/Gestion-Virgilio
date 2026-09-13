-- v16.49 — Problema 84 (mitad "duales"): UNA sola lista de códigos duales
--
-- Antes: tres tablas con las mismas 4 filas y ningún vínculo entre ellas.
--   public."Codigos_Duales"   (cod, nombre_lk, nombre_ch, actualizado_en) — HUÉRFANA:
--                              no la lee ninguna función, ninguna vista ni el front.
--   public.codigos_duales     (cod, nota, creado) — la VIVA: la leen el trigger
--                              actualizar_saldo_trigger(), trg_normalizar_empresa_stock(),
--                              gv_stock_clave(), aceptar_conteo(), public.vista_saldos_stock
--                              y public.gv_articulo_empresa.
--   stock_v2.codigos_duales   (cod, nota, creado) — el origen histórico: la leen
--                              stock_v2.trg_normalizar_empresa() (tablas de prueba
--                              mov_prueba / mov_dedup) y stock_v2.vista_saldos_stock.
--
-- Hoy las tres coinciden (437E, 438E, 439E, 809E). El riesgo es futuro: alguien agrega
-- un 5.º dual en una sola y el stock de LK y CH se mezcla en los otros dos caminos.
--
-- Después: public.codigos_duales es la ÚNICA tabla. Las otras dos pasan a ser VISTAS
-- sobre ella (mismas columnas, mismo nombre), así que no pueden divergir nunca más.
--
-- Backup previo: zz_backups."GV_Backup_codigos_duales_20260913" (clave: origen + cod).

begin;

-- 0) backup de las tres, con la PK de cada una
create table zz_backups."GV_Backup_codigos_duales_20260913" as
  select 'public.Codigos_Duales'::text as origen, cod, null::text as nota,
         nombre_lk, nombre_ch, actualizado_en as ts
    from public."Codigos_Duales"
  union all
  select 'public.codigos_duales', cod, nota, null, null, creado from public.codigos_duales
  union all
  select 'stock_v2.codigos_duales', cod, nota, null, null, creado from stock_v2.codigos_duales;

alter table zz_backups."GV_Backup_codigos_duales_20260913" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_codigos_duales_20260913"
  from anon, authenticated;

-- 1) la canónica absorbe las columnas que sólo tenía la huérfana (nullable, sin default)
alter table public.codigos_duales add column if not exists nombre_lk      text;
alter table public.codigos_duales add column if not exists nombre_ch      text;
alter table public.codigos_duales add column if not exists actualizado_en timestamptz;

update public.codigos_duales c
   set nombre_lk      = m.nombre_lk,
       nombre_ch      = m.nombre_ch,
       actualizado_en = m.actualizado_en
  from public."Codigos_Duales" m
 where m.cod = c.cod;

-- 2) la canónica hereda la guarda de formato que tenía la huérfana
alter table public.codigos_duales drop constraint if exists codigos_duales_cod_check;
alter table public.codigos_duales add  constraint codigos_duales_cod_check
  check (cod = upper(btrim(cod)) and cod !~ '\s+(LK|CH|LOKE)$');

drop trigger if exists trg_canon_codigos_duales_cod on public.codigos_duales;
create trigger trg_canon_codigos_duales_cod
  before insert or update of cod on public.codigos_duales
  for each row execute function public.fn_canon_col_cod();

-- 3) la huérfana pasa a ser una vista sobre la canónica (mismas columnas y orden)
drop table public."Codigos_Duales";
create view public."Codigos_Duales" with (security_invoker = true) as
  select cod, nombre_lk, nombre_ch, coalesce(actualizado_en, creado) as actualizado_en
    from public.codigos_duales;
grant select on public."Codigos_Duales" to anon, authenticated;

-- 4) la de stock_v2 también (su única dependiente se recrea idéntica)
drop view stock_v2.vista_saldos_stock;
drop table stock_v2.codigos_duales;

create view stock_v2.codigos_duales with (security_invoker = true) as
  select cod, nota, creado from public.codigos_duales;

create view stock_v2.vista_saldos_stock as
 WITH cfg AS (
         SELECT ( SELECT "Stock_Config".valor
                   FROM "Stock_Config"
                  WHERE "Stock_Config".clave = 'cutoff_ts'::text
                 LIMIT 1) AS cutoff
        ), canon AS (
         SELECT m.ts, m.tipo, m.deposito, m.delta, m.cod_art,
            regexp_replace(regexp_replace(upper(btrim(m.cod_art)), '\s+(LK|CH|LOKE)$'::text, ''::text), '^0+(?=.)'::text, ''::text) AS base,
                CASE
                    WHEN upper(btrim(m.cod_art)) ~ '\s+(LK|LOKE)$'::text THEN 'LK'::text
                    WHEN upper(btrim(m.cod_art)) ~ '\s+CH$'::text THEN 'CH'::text
                    ELSE NULL::text
                END AS suf
           FROM "Movimientos_Stock" m
        ), keyed AS (
         SELECT c_1.ts, c_1.tipo, c_1.deposito, c_1.delta, c_1.cod_art, c_1.base, c_1.suf,
                CASE
                    WHEN d.cod IS NOT NULL THEN COALESCE(c_1.suf, 'SIN'::text)
                    ELSE 'Mixto'::text
                END AS empresa
           FROM canon c_1
             LEFT JOIN stock_v2.codigos_duales d ON regexp_replace(upper(btrim(d.cod)), '^0+(?=.)'::text, ''::text) = c_1.base
        )
 SELECT c.base AS cod_base,
    c.empresa,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'terminado'::text), 0::numeric) AS terminado,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'excedente'::text), 0::numeric) AS excedente,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'separar_pedidos'::text), 0::numeric) AS separar_pedidos,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'a_facturar'::text), 0::numeric) AS a_facturar,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'a_guardar'::text), 0::numeric) AS a_guardar,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'racks'::text), 0::numeric) AS racks,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'racks_ch'::text), 0::numeric) AS racks_ch,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'para_envasar'::text), 0::numeric) AS para_envasar,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'insumos'::text), 0::numeric) AS insumos
   FROM keyed c, cfg
  WHERE cfg.cutoff IS NULL OR c.tipo = 'inicial'::text OR c.ts >= cfg.cutoff::timestamp with time zone
  GROUP BY c.base, c.empresa;

-- 5) la canónica sólo se lee desde las apps: sacar los grants de escritura que nadie usa
--    (la RLS ya lo bloqueaba — la única policy es de SELECT — pero el grant sobraba)
revoke insert, update, delete, truncate on public.codigos_duales from anon, authenticated;

commit;
