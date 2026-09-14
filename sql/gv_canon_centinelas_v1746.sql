-- =====================================================================
--  ETAPA 0 y 1 del plan de canonización única — v17.46 (2026-09-14)
--  Plan completo: docs/PLAN-CANONIZACION-UNICA.md
--  Problema: "No existe UNA definición de código canónico" (alto, abierto)
--
--  ── POR QUÉ LOS CENTINELAS VAN PRIMERO ───────────────────────────────
--  El ciclo que hay que cortar no es "el sufijo de empresa vuelve": es que **nada avisa
--  cuando aparece el objeto n+1 con su propio regexp**. Cada sesión arregla el lugar que
--  mira, con la canonizadora que tiene más cerca, y el escritor siguiente cae en otra que
--  cubre un subconjunto distinto de los 5 pasos. Sin esto, cada etapa que sigue es a ciegas.
--
--  Los dos no tocan nada existente: son vistas nuevas. Riesgo cero de verdad.
--
--  ── LÍNEA DE BASE AL APLICARLOS (2026-09-14) ─────────────────────────
--    gv_canon_sin_funcion   → 22 objetos con regexp copiado a mano
--                             (8 de ellos ESCRIBEN; sólo 1 saca el sufijo de empresa)
--    gv_canon_divergencias  → 59 códigos, repartidos así:
--        D. resuelve grafía contra OC_Maximos ......... 28
--        B. punto medio (insumo), gv_cod_stock TRUNCA .. 14
--        E. resuelve Equivalencias_Codigos ............ 13
--        C. variante L ................................. 2
--        A. sufijo de empresa .......................... 2
--        Z. ALARMA ..................................... 0   ← esta tiene que quedar en CERO
--
--  **Estos números son la línea de base: lo que importa es que NO SUBAN.** Las categorías
--  A-F son divergencias de DISEÑO (cada canonizadora hace un subconjunto distinto a
--  propósito), así que la vista nunca va a dar vacía. La Z es otra cosa: son las que
--  DEBERÍAN ser idénticas. Si la Z devuelve una fila, alguien las hizo divergir.
--
--  ── ETAPA 1: por qué se hizo sólo la mitad ───────────────────────────
--  Medido sobre el **dominio real completo** — 523 entradas distintas: todo `cod_art` de
--  `Movimientos_Stock`, más `OC_Maximos`, `Insumos`, `GV_Lugar_Item`, `Capacidad_Sector`,
--  las dos columnas de `Equivalencias_Codigos`, `GV_Precios_Cliente`, y los bordes
--  `null` / `''` / `'   '`:
--
--    • `canon_cod` ≡ `norm_cod` ........................ 0 diferencias
--    • `cob_norm_cod` ≡ `nullif(norm_cod(x), '')` ...... 0 diferencias
--    • `cob_norm_cod` ≡ `norm_cod` ..................... 3 diferencias (null, '', '   ')
--
--  **`cob_norm_cod` SÍ se fusionó** (no está en ningún índice). ⚠ El `nullif` no es
--  cosmético: devuelve NULL para vacío donde `norm_cod` devuelve `''`, y de eso dependen
--  sus 4 funciones + 3 vistas consumidoras. Sin el `nullif` son esas 3 diferencias.
--
--  **`canon_cod` NO se tocó**, y es una decisión, no un olvido: está dentro del índice
--  único `gv_precios_cliente_canon_uk ON "GV_Precios_Cliente" (empresa, cod_cliente,
--  canon_cod(cod))`. Cambiarle el cuerpo a una función IMMUTABLE que vive en un índice
--  obliga a reindexar, y si el cuerpo nuevo difiere en un solo valor el índice puede no
--  reconstruirse por clave duplicada. Como ya es **idéntica** a `norm_cod`, fusionarla no
--  arregla nada hoy: su único beneficio —que no diverja— lo entrega la fila Z del
--  centinela. Queda para una ventana, junto con la etapa 3.
--  (Para cuando se haga: la tabla tiene 4 filas y 0 claves cambian.)
--
--  ── POR QUÉ NO SE VERIFICÓ HASHEANDO LAS 12 VISTAS ───────────────────
--  Se hizo, y fue la verificación equivocada. Las tres funciones son `IMMUTABLE` y puras
--  (una expresión, sin tablas): si dan idéntico resultado para todo input posible, no
--  pueden cambiar la salida de ninguna vista. Materializar `vista_plata_perdida` y
--  `vista_deudores_documentos` enteras contra producción es más invasivo que el cambio en
--  sí, y tardó más de 60 s. **La verificación correcta es sobre el DOMINIO DE ENTRADAS**,
--  y cuesta milisegundos.
--  Igual quedó la foto de las 12 en `zz_backups."GV_Backup_CanonFoto_20260914"`, y las 3
--  que consumen `cob_norm_cod` se re-hashearon después: **hash idéntico** en las tres
--  (`cobranzas_precios` 327, `cobranzas_precios_super` 522,
--   `vista_facturacion_neto_items` 10.711).
--
--  ⚠ Y se llamó de verdad a las 4 funciones que la usan, porque **Postgres no revalida el
--  cuerpo de una función hasta la primera llamada** (la lección del `DROP COLUMN` de la
--  v16.39): `cob_estado_articulo`, `cobranzas_resumen`, `cobranzas_valorizar_np` y
--  `gv_ppp_web_valor_items` (ésta última valoriza los ítems de un pedido web, o sea camino
--  de precio). Las 4 sin error, dentro de una transacción con ROLLBACK.
--
--  Rollback:
--    drop view if exists public.gv_canon_divergencias;
--    drop view if exists public.gv_canon_sin_funcion;
--    -- y el cuerpo viejo de cob_norm_cod:
--    create or replace function public.cob_norm_cod(p text) returns text language sql immutable
--    as $$ select nullif(regexp_replace(upper(btrim(coalesce(p,''))), '^0+(?=.)', ''), '') $$;
-- =====================================================================


-- ── CENTINELA 1 ──────────────────────────────────────────────────────
-- Objetos de public que canonizan con un regexp COPIADO A MANO en vez de llamar a una
-- función. Es lo único que avisa cuando aparece el objeto n+1 con su propia regla.
-- Catálogo puro: no escanea ninguna tabla de datos.
create or replace view public.gv_canon_sin_funcion
with (security_invoker = true) as
with obj as (
  select 'funcion'::text tipo, p.proname nombre, p.prosrc src,
         exists(select 1 from pg_trigger t where t.tgfoid = p.oid and not t.tgisinternal) es_trigger
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosrc ~ '\^0\+\(\?='
  union all
  select 'vista', c.relname, pg_get_viewdef(c.oid), false
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('v','m') and pg_get_viewdef(c.oid) ~ '\^0\+\(\?='
)
select tipo, nombre, es_trigger,
       (src ~ '\(LK\|CH\|LOKE\)\$')     saca_sufijo_empresa,
       (src ~ '\[0-9E\]\)?L\$')         saca_variante_l,
       (src ~* 'OC_Maximos')            resuelve_oc_maximos,
       (src ~* 'Equivalencias_Codigos') resuelve_equivalencias,
       (src ~ '·')                      corta_en_punto_medio,
       (src ~* '\minsert into\M|\mupdate \M|\mdelete from\M') escribe
from obj
-- las canonizadoras mismas son la EXCEPCION legitima: ahi vive la regla
where nombre not in ('gv_cod_stock','norm_cod','canon_cod','cob_norm_cod','canon_cod_art_val',
                     'resolver_equiv','fn_canon_cod_art','trg_normalizar_empresa_stock',
                     'gv_stock_clave','gv_canon_sin_funcion','gv_canon_divergencias')
order by escribe desc, tipo, nombre;

grant select on public.gv_canon_sin_funcion to anon, authenticated;


-- ── CENTINELA 2 ──────────────────────────────────────────────────────
create or replace view public.gv_canon_divergencias
with (security_invoker = true) as
with dom as (
  select cod_art c from public."Movimientos_Stock"
  union select cod from public."OC_Maximos"
  union select cod from public."Insumos"
  union select cod from public."GV_Lugar_Item"
  union select cod from public."Capacidad_Sector"
  union select cod_pedido from public."Equivalencias_Codigos"
  union select cod_real from public."Equivalencias_Codigos"
  union select null::text union select ''::text union select '   '::text
),
r as (
  select c,
         public.gv_cod_stock(c)      f_stock,
         public.canon_cod_art_val(c) f_catalogo,
         public.norm_cod(c)          f_ceros,
         public.resolver_equiv(c)    f_equiv,
         public.canon_cod(c)         f_canon_cod,
         public.cob_norm_cod(c)      f_cob
  from dom
)
-- (1) divergencias de DISEÑO: cada canonizadora hace un subconjunto distinto de los 5 pasos.
--     Nunca va a dar vacio; lo que importa es que el conteo por motivo NO SUBA.
select c codigo, f_stock, f_catalogo, f_ceros, f_equiv,
       case
         when c ~* '\s+(LK|CH|LOKE)$'               then 'A. sufijo de empresa'
         when c ~ '·'                               then 'B. punto medio (insumo): gv_cod_stock lo TRUNCA'
         when c ~ '[0-9E]L$' and f_stock <> f_ceros then 'C. variante L'
         when f_catalogo <> f_ceros                 then 'D. resuelve grafia contra OC_Maximos'
         when f_equiv    <> f_ceros                 then 'E. resuelve Equivalencias_Codigos'
         else 'F. otro' end motivo
from r
where c is not null and btrim(c) <> ''
  and (f_stock is distinct from f_catalogo or f_stock is distinct from f_ceros
    or f_catalogo is distinct from f_ceros or f_catalogo is distinct from f_equiv)
union all
-- (2) ALARMA: estas DEBERIAN ser identicas. canon_cod no se fusiono con norm_cod porque esta
--     dentro del indice unico gv_precios_cliente_canon_uk de "GV_Precios_Cliente"; cob_norm_cod
--     ya es un envoltorio (v17.46). Si alguna fila sale aca, alguien las hizo divergir.
select coalesce(c,'(null)'), f_canon_cod, f_ceros, f_cob, null,
       'Z. ALARMA: canon_cod/cob_norm_cod divergen de norm_cod'
from r
where f_canon_cod is distinct from f_ceros
   or f_cob       is distinct from nullif(f_ceros,'');

grant select on public.gv_canon_divergencias to anon, authenticated;


-- ── ETAPA 1 (mitad segura) ───────────────────────────────────────────
-- cob_norm_cod pasa a ser un envoltorio de norm_cod. Ver el encabezado: el nullif preserva
-- el NULL-para-vacio del que dependen sus 4 funciones + 3 vistas consumidoras.
CREATE OR REPLACE FUNCTION public.cob_norm_cod(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select nullif(public.norm_cod(p), '')
$function$;


-- ── CÓMO MIRARLO ─────────────────────────────────────────────────────
-- select * from public.gv_canon_sin_funcion where escribe;          -- los 8 que importan
-- select motivo, count(*) from public.gv_canon_divergencias group by 1 order by 1;
-- select * from public.gv_canon_divergencias where motivo like 'Z.%';  -- TIENE que dar vacio
