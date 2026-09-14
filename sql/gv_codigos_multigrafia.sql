-- =====================================================================
--  gv_codigos_multigrafia — centinela de grafías duplicadas (v17.02, 2026-09-14)
--
--  POR QUÉ
--  El mismo artículo escrito de dos formas (`66` y `066`, `H201Part` y `H201PART`)
--  no rompe los saldos —las vistas canonizan— pero **ensucia toda consulta que
--  agrupe por el código crudo**, y el 14/09 hizo reportar dos negativos que no
--  existían. Peor: si dos escritores usan grafías distintas y el índice de
--  idempotencia compara por `upper(trim(cod))`, los ve como filas distintas y
--  duplica (problema 130).
--
--  EL HALLAZGO, que es lo que hace útil a esta vista: la correlación es perfecta.
--  Las tablas con trigger de canonización dan **cero**; las 9 que no lo tienen
--  acumulan 30 códigos con doble grafía.
--
--  | tabla | códigos | por qué importa |
--  |---|--:|---|
--  | `Planimetria` | 16 | marcada para retirar en el plan del sufijo |
--  | `precios_super_lk` | 5 | el cotizador busca por el código canónico, así que una lista de súper puede no matchear y el pedido se valoriza con la lista general |
--  | `Ordenes_Compra` | 2 | `515`/`0515`, `725`/`0725` — se cruzan con stock y proyección |
--  | `Insumos_Historial` | 2 | `h201Part`/`H201Part`, `7`/`007` |
--  | `Stock_Ubicaciones`, `Insumos_Ubicaciones`, `Insumos_Ubicaciones_Unificadas`, `Stock_Inicial_Cartones`, `Ubicaciones_Articulos` | 1 c/u | ubicaciones; `538e` vs `538E` |
--
--  ⚠ Los datos NO se corrigieron a propósito. Cada tabla tiene su lector, y
--  normalizar sin mirar al lector es exactamente lo que causó el problema 130 ese
--  mismo día: se normalizó `66`→`066` con el cron corriendo, el índice dejó de
--  matchear y el cron duplicó el picking. **Primero el escritor, después los datos.**
--
--  ⚠⚠ Y las tablas de INSUMOS no se pueden canonizar con `fn_canon_col_cod`: esa
--  resuelve contra `OC_Maximos`, que es el maestro de ARTÍCULOS y no lleva insumos.
--  Para un insumo el maestro es `Insumos` (es el error 3 de la sesión del 13/09).
--
--  `Proveedores.codigo` queda fuera de la vista a propósito: tiene 21 códigos con
--  doble grafía pero son códigos de PROVEEDOR, otro dominio; la canonización de
--  artículos no aplica.
--
--  Uso: `select * from public.gv_codigos_multigrafia;` — vacío = todo bien.
-- =====================================================================

create or replace view public.gv_codigos_multigrafia
with (security_invoker = true) as
with pares as (
  select 'Ordenes_Compra'::text tabla, 'codigo'::text col, btrim(codigo) c from public."Ordenes_Compra" where coalesce(btrim(codigo),'')<>''
  union all select 'precios_super_lk','cod', btrim(cod) from public.precios_super_lk where coalesce(btrim(cod),'')<>''
  union all select 'Planimetria','cod', btrim(cod) from public."Planimetria" where coalesce(btrim(cod),'')<>''
  union all select 'Ubicaciones_Articulos','cod_art', btrim(cod_art) from public."Ubicaciones_Articulos" where coalesce(btrim(cod_art),'')<>''
  union all select 'Stock_Ubicaciones','codigo', btrim(codigo) from public."Stock_Ubicaciones" where coalesce(btrim(codigo),'')<>''
  union all select 'Stock_Inicial_Cartones','cod', btrim(cod) from public."Stock_Inicial_Cartones" where coalesce(btrim(cod),'')<>''
  union all select 'Insumos_Historial','cod', btrim(cod) from public."Insumos_Historial" where coalesce(btrim(cod),'')<>''
  union all select 'Insumos_Ubicaciones','cod', btrim(cod) from public."Insumos_Ubicaciones" where coalesce(btrim(cod),'')<>''
  union all select 'Insumos_Ubicaciones_Unificadas','cod', btrim(cod) from public."Insumos_Ubicaciones_Unificadas" where coalesce(btrim(cod),'')<>''
  union all select 'Movimientos_Stock','cod_art', btrim(cod_art) from public."Movimientos_Stock" where coalesce(btrim(cod_art),'')<>''
  union all select 'OC_Maximos','cod', btrim(cod) from public."OC_Maximos" where coalesce(btrim(cod),'')<>''
  union all select 'Insumos','cod', btrim(cod) from public."Insumos" where coalesce(btrim(cod),'')<>''
  union all select 'GV_UxB','cod', btrim(cod) from public."GV_UxB" where coalesce(btrim(cod),'')<>''
  union all select 'GV_Lugar_Item','cod', btrim(cod) from public."GV_Lugar_Item" where coalesce(btrim(cod),'')<>''
  union all select 'Racks_Planimetria','cod_art', btrim(cod_art) from public."Racks_Planimetria" where coalesce(btrim(cod_art),'')<>''
  union all select 'Capacidad_Sector','cod', btrim(cod) from public."Capacidad_Sector" where coalesce(btrim(cod),'')<>''
),
n as (select tabla, col, regexp_replace(upper(c),'^0+(?=.)','') k, c, count(*) filas from pares group by 1,2,3,4)
select tabla, col, k cod_norm, count(*) grafias,
       string_agg(c||' ('||filas||')', ' | ' order by filas desc) detalle,
       exists(select 1 from pg_trigger tg join pg_class cl on cl.oid=tg.tgrelid
               join pg_proc p on p.oid=tg.tgfoid
              where cl.relname=n.tabla and not tg.tgisinternal and p.proname ilike '%canon%') tiene_trigger_canon
from n group by tabla, col, k having count(*) > 1
order by tabla, k;

grant select on public.gv_codigos_multigrafia to anon, authenticated;

-- v17.02: el trigger de Movimientos_Stock era el UNICO de los 11 que cubria solo INSERT.
-- Los otros 10 son BEFORE INSERT OR UPDATE OF <col>, asi que un UPDATE de cod_art se
-- canonizaba en todas las tablas menos en la principal. Ahora tambien:
CREATE OR REPLACE TRIGGER trg_canon_cod_art
  BEFORE INSERT OR UPDATE OF cod_art ON public."Movimientos_Stock"
  FOR EACH ROW EXECUTE FUNCTION fn_canon_cod_art();
