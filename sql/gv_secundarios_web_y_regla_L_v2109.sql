-- v21.09 (Luis, 2026-09-22) — el panel de correccion ve los pedidos WEB, y la L vuelve a
-- ser de Cencosud (y TdF), no de todos los supers que facturan por Chef.
--
-- 1) LA REGLA DE LA L, dicha por Luis: "lo de la L deberia aplicar unicamente a CENCOSUD y a
--    pedidos que van a TIERRA DEL FUEGO".
--
--    La L NO la decide "el super factura por Chef": la decide si sus ARTICULOS son de
--    Loekemeyer. Eso ya estaba escrito en el propio codigo de admin-supercot.js:
--      isChefSuper(k)     -> el super usa cliente/RPC/sheets de Chef (Cencosud y Dorinka)
--      usesChefProducts(k)-> ademas MATCHEA sus productos contra el catalogo de CHEF (Dorinka)
--    Cencosud factura por Chef pero pide articulos de LK  -> LLEVA L.
--    Dorinka  factura por Chef y sus articulos SON de Chef -> NO lleva L.
--
--    Medido en precios_super.cadena (LK): `empresa='chef' and usa_productos_chef=false`
--    devuelve UNA cadena, Cencosud. Exactamente la regla del dueno.
--
--    Lo roto estaba en pagina-LK-copia/admin-supercot.js (y su espejo Gestion-Virgilio/admin/):
--      linea ~3290 (PDF):     state.superKey === "cencosud" || state.superKey === "dorinka"
--      linea ~3534 (SUBMIT):  var addLSuffix = isChef;
--    El admin de CHEF (paginach) siempre estuvo bien: `state.superKey === "cencosud"`, con el
--    comentario "Dorinka NO lleva L (son art. de Chef); solo Cencosud".
--
--    Consecuencia medida: el pedido 229 (Dorinka / Chango Mas, NP CH 0025) salio con los 5
--    codigos con L (769L, 840L, 838L, 865EL, 798EL) y del lado de LK no hay UNA caja de
--    ninguno: 769 -> 0, 798E -> 0, 840 -> 0, 865E -> 0. Todo el stock esta en Chef
--    (40, 74, 85 y 9). Son articulos de Chef.
--
--    Hoy se arregla con `isChefSuper(k) && !usesChefProducts(k)`, derivado de la config y no
--    hardcodeado: si manana entra otro super que factura Chef con articulos de LK, le
--    corresponde la L por la misma regla. Si la config no cargo, isChefSuper da false y NO se
--    pone L (fail-safe).
--
--    ⚠ En PPP_Web_Base quedo UNA sola linea con L de mas: el 838L de CH 0025, que ademas era
--    el duplicado (el 838 estaba dos veces). La programacion de esa NP decia 113 cajas y las
--    lineas sumaban 161 con el 838L y 113 sin el, asi que la fila que sobraba era esa.
--    Backup: zz_backups."GV_Backup_PPPWebBase_CH0025_20260922" (las 6 filas originales).
--
--      delete from public."PPP_Web_Base"
--       where empresa='chef' and order_id=229 and np_idx=1 and upper(btrim(articulo))='838L';
--
-- 2) EL PANEL DE LA OPERADORA NO VEIA LOS PEDIDOS WEB. vista_pedidos_secundarios (la que
--    avisa "esta NP pide 839, arma 838E" y que al confirmar hace que el picking levante el
--    principal) leia SOLO GV_PPP_Base_Pedidos, que es la base de los pedidos de ISIS. Los de
--    la pagina viven en PPP_Web_Base y la vista nunca la nombro: no es que los filtrara, no
--    los leia. Por eso el 839 de ISIS tiene 13 correcciones registradas y el 839 de CH 0004 /
--    CH 0015 no tiene ninguna. Medido: la vista paso de 0 a 6 filas.
--
--    ⚠ Para BUSCAR la familia se pela la L ('838L' es el 838): eso es comparar, no reescribir.
--    cod_secundario sale CRUDO, con su L, porque es el codigo que esta en el pedido y el que
--    viaja a Correcciones_Pedido y a la factura.
--
-- 3) EL MISMO AGUJERO EN vista_pedidos_equivalencia (Equivalencias_Codigos: "el cliente pidio
--    029, facturá 437E"). Tambien cruzaba solo contra ISIS. Hoy da 0 filas web, pero el dia
--    que entre una nadie se entera. Corregida igual.
--
--    ⚠ PENDIENTE, NO TOCADO: reporte_agentes_equivalencia_facturar() tiene el mismo problema
--    y ademas MANDA TELEGRAM. Sumarle la web cambia lo que sale afuera, asi que lo decide el
--    dueno.
--
-- Chequeo:
--   select * from public.vista_pedidos_secundarios order by np;   -- 6 filas al 22/09
--   begin; set local role anon; select count(*) from public.vista_pedidos_secundarios; commit;
--   -- anon tiene que ver las MISMAS filas (trampa del security_invoker, v20.45): medido 6 = 6.
-- Rollback: las dos vistas vuelven sacando el bloque UNION del final (y reponiendo
--   `alter view ... set (security_invoker = true)`, que un CREATE OR REPLACE se come).

create or replace view public.vista_pedidos_secundarios as
 SELECT btrim(b.pedido) AS np,
    upper(btrim(b.articulo)) AS cod_secundario,
    ef.cod_principal,
    ef.descripcion,
    sum(COALESCE(b.cajas, 0::numeric)) AS cajas
   FROM "GV_PPP_Base_Pedidos" b
     JOIN "Equivalencias_Familia" ef ON ef.cod_secundario = regexp_replace(upper(btrim(b.articulo)), '^0+(?=.)'::text, ''::text)
  WHERE b.pedido IS NOT NULL AND btrim(b.pedido) <> ''::text AND NOT (EXISTS ( SELECT 1
           FROM "GV_PPP_Entregados_Historico" e
          WHERE btrim(e.np) = btrim(b.pedido))) AND NOT (EXISTS ( SELECT 1
           FROM "Facturacion_NP" f
          WHERE btrim(f.np) = btrim(b.pedido)))
  GROUP BY (btrim(b.pedido)), (upper(btrim(b.articulo))), ef.cod_principal, ef.descripcion
UNION ALL
 SELECT btrim(w.np_label) AS np,
    upper(btrim(w.articulo)) AS cod_secundario,
    ef.cod_principal,
    ef.descripcion,
    sum(COALESCE(w.cajas, 0::numeric)) AS cajas
   FROM "PPP_Web_Base" w
     JOIN "Equivalencias_Familia" ef ON ef.cod_secundario = regexp_replace(regexp_replace(upper(btrim(w.articulo)), '([0-9E])L$'::text, '\1'::text), '^0+(?=.)'::text, ''::text)
  WHERE w.np_label IS NOT NULL AND btrim(w.np_label) <> ''::text AND NOT (EXISTS ( SELECT 1
           FROM "GV_PPP_Entregados_Historico" e
          WHERE btrim(e.np) = btrim(w.np_label))) AND NOT (EXISTS ( SELECT 1
           FROM "Facturacion_NP" f
          WHERE btrim(f.np) = btrim(w.np_label)))
  GROUP BY (btrim(w.np_label)), (upper(btrim(w.articulo))), ef.cod_principal, ef.descripcion;

alter view public.vista_pedidos_secundarios set (security_invoker = true);

create or replace view public.vista_pedidos_equivalencia as
 SELECT DISTINCT btrim(bp.pedido) AS np, bp.articulo AS cod_pedido, eq.cod_real, COALESCE(eq.nota, ''::text) AS nota
   FROM "GV_PPP_Base_Pedidos" bp
   JOIN "Equivalencias_Codigos" eq ON regexp_replace(upper(TRIM(BOTH FROM bp.articulo)), '^0+(.)'::text, '\1'::text) = regexp_replace(upper(TRIM(BOTH FROM eq.cod_pedido)), '^0+(.)'::text, '\1'::text)
UNION
 SELECT DISTINCT btrim(w.np_label) AS np, w.articulo AS cod_pedido, eq.cod_real, COALESCE(eq.nota, ''::text) AS nota
   FROM "PPP_Web_Base" w
   JOIN "Equivalencias_Codigos" eq ON regexp_replace(regexp_replace(upper(TRIM(BOTH FROM w.articulo)), '([0-9E])L$'::text, '\1'::text), '^0+(.)'::text, '\1'::text) = regexp_replace(upper(TRIM(BOTH FROM eq.cod_pedido)), '^0+(.)'::text, '\1'::text)
  WHERE w.np_label IS NOT NULL AND btrim(w.np_label) <> ''::text;

alter view public.vista_pedidos_equivalencia set (security_invoker = true);
