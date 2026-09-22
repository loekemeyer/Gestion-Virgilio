/* ============================================================================
   v21.11 — FC s/Salida: el codigo de la FACTURA no es el codigo de la GONDOLA
   Pedido de Luis, 2026-09-22:
     "si hay 11 que salen los 11 deberian aparecer como 026 y ninguno como 026L
      para fc s/salida, es rarisimo eso. Aplica esa logica a todos esos codigos."

   EL SINTOMA
   ----------
   El modulo Stocks mostraba una fila fantasma `026L` — sin LK/CH, sin descripcion,
   sin gondola, stock 0 — con 1 caja en la columna FC s/Salida, mientras la fila
   `026` decia 10. Son la misma caja de Colador Ø 8cm: el badge partia el articulo
   en dos.

   LA CAUSA
   --------
   `vista_fc_sin_salida` agrupaba por `norm_cod(Entregas_Virgilio.cod_art)`, y
   `norm_cod()` SOLO saca ceros a la izquierda y pone mayusculas: NO pela la L.
   Y `Entregas_Virgilio` lleva la L CRUDA a proposito — es el codigo que va a la
   factura y al Excel de ISIS (regla "LA L NO ES UN CODIGO, ES UNA DENOTACION").

   Despues, `index.html` (~18579) fabrica una fila nueva por cada codigo de esa
   vista que no exista en el universo de stock. De ahi la fila fantasma.

   LO MEDIDO (22/09)
   -----------------
   - Movimientos_Stock con codigo terminado en L: 0. El STOCK estaba BIEN.
     El 026 se descontó como corresponde: picking 26/08 (excedente -1,
     separar_pedidos +1) · separado 27/08 · facturado 21/09 (ref `D47B|CH 0030`,
     empresa LK, delta -1). `pkResolveArt` hace su trabajo.
   - 32 codigos con L en la vista, todos del mismo pedido: Alesso Vilarino Liliana,
     NP CH 0030/0031/0032, tanda D47B, facturado 21/09 (pedido de Chef con
     articulos de Loeke, el caso de la regla).
   - Historico en Entregas_Virgilio: 38 filas / 36 codigos / 6 NP desde el 07/07.
   - EN LOS DUALES EL BADGE NO FUNCIONABA NI CON L NI SIN L: la vista devolvia
     `438EL` y `438E`, y el universo de stock los tiene como `438E LK` / `438E CH`.
     `refresh_stocks_carga_rapida` cruza con `scr.cod = fc.cod` (igualdad EXACTA),
     asi que los dos quedaban en 0. Y el fallback `codBase` del front le asignaba
     las mismas cajas a las DOS filas del dual.

   EL ARREGLO
   ----------
   Una sola resolucion, `gv_cod_stock_de_entrega`, que es `pkResolveArt` de
   index.html en SQL: pela la L, fuerza LK para esos codigos, y le pone el sufijo
   de empresa SOLO si el base es dual. Arregla las DOS puntas (el popup del front
   lee la vista; `stocks_carga_rapida.fc_sin_salida` tambien) sin tocar el front.

     026L  -> 026        (no dual: la L solo dice de que gondola salio)
     438EL -> 438E LK    (dual: la L manda LK aunque la NP sea de Chef)
     438E  -> 438E CH    (dual sin L, NP de Chef)
     505   -> 505        (sin cambios)

   ⚠ La empresa la da la L, NUNCA la NP. Ese es el orden del CASE y no se invierte:
     un `438EL` de una NP de Chef resuelto por NP daria `438E CH` y el badge
     miraria la gondola equivocada.

   VERIFICADO
   ----------
   - 0 codigos con L en la vista (antes 32).
   - El 026 pasa de 10 a 11 cajas.
   - `438E LK` pasa de 0 a 4.
   - Total de cajas IDENTICO antes y despues: 2.084 = 2.084 contra la fuente cruda.
     El cambio es de AGRUPACION, no de filtro.

   ROLLBACK: volver `entregas_pend` a `norm_cod(e.cod_art) AS cod` y
   `alter view public.vista_fc_sin_salida set (security_invoker = true);`
   (md5 de la definicion anterior: 213d01c1049e02685be0c19299c2668c)
   ============================================================================ */

-- 1) La resolucion canonica: codigo de ENTREGA/FACTURA -> codigo de STOCK.
create or replace function public.gv_cod_stock_de_entrega(
  p_cod text, p_np text default null, p_emp text default null)
returns text
language sql
stable
set search_path = public, pg_temp
as $$
  with x as (
    select regexp_replace(public.norm_cod(p_cod), '([0-9E])L$', '\1') as base,
           case
             -- LA L MANDA. Ningun articulo termina en L (verificado 02/09 sobre
             -- loke_products, chef_articulos_activos, milver_products y los remaps),
             -- asi que "termina en L -> LK" es una regla sin excepcion.
             when upper(btrim(coalesce(p_cod,''))) ~ '[0-9E]L$' then 'LK'
             when upper(coalesce(public.gv_emp_de_np(p_np), p_emp, '')) like 'LK%' then 'LK'
             when upper(coalesce(public.gv_emp_de_np(p_np), p_emp, '')) like 'CH%' then 'CH'
             else null
           end as emp
  )
  select case
           when x.emp is not null
            and exists (select 1 from public.codigos_duales d
                         where public.norm_cod(d.cod) = x.base)
           then x.base || ' ' || x.emp
           else x.base
         end
    from x;
$$;

-- Pruebas de la resolucion (las 7 dan lo de la derecha, medido 22/09):
--   gv_cod_stock_de_entrega('026L' ,'CH 0030','chef') = '26'        no dual con L
--   gv_cod_stock_de_entrega('438EL','CH 0030','chef') = '438E LK'   dual con L -> LK
--   gv_cod_stock_de_entrega('438E' ,'CH 0030','chef') = '438E CH'   dual sin L
--   gv_cod_stock_de_entrega('438E' ,'98615'  ,'lk'  ) = '438E LK'
--   gv_cod_stock_de_entrega('505'  ,'98615'  ,'lk'  ) = '505'
--   gv_cod_stock_de_entrega('0505L',null     ,'chef') = '505'       ceros + L
--   gv_cod_stock_de_entrega('438E LK','98615','lk'  ) = '438E LK'   idempotente

-- 2) La vista. Lo unico que cambia es la expresion de `cod` en `entregas_pend`.
--    ⚠ El CREATE OR REPLACE lleva el `with (security_invoker = true)` Y el alter
--    de abajo: sin eso la vista corre como postgres y saltea la RLS.
create or replace view public.vista_fc_sin_salida
with (security_invoker = true) as
 WITH np_clean AS (
         SELECT regexp_replace(TRIM(BOTH FROM "Facturacion_NP".np), '\.0+$'::text, ''::text) AS np_n,
            "Facturacion_NP".tanda,
            "Facturacion_NP".razon_social,
            "Facturacion_NP".facturado_at
           FROM "Facturacion_NP"
          WHERE "Facturacion_NP".facturado_at >= '2026-06-22 00:00:00-03'::timestamp with time zone AND NULLIF(TRIM(BOTH FROM "Facturacion_NP".np), ''::text) IS NOT NULL
        ), fss AS (
         SELECT regexp_replace(TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1)), '\.0+$'::text, ''::text) AS np_n,
            max("Registros_Produccion_Virgilio".ts_cliente) AS last_fss
           FROM "Registros_Produccion_Virgilio"
          WHERE "Registros_Produccion_Virgilio".opcion = 'FSS'::text AND "Registros_Produccion_Virgilio".ts_cliente >= '2026-06-22 00:00:00-03'::timestamp with time zone AND NULLIF(TRIM(BOTH FROM "Registros_Produccion_Virgilio".texto), ''::text) IS NOT NULL
          GROUP BY (regexp_replace(TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1)), '\.0+$'::text, ''::text))
        ), ccn AS (
         SELECT regexp_replace(TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1)), '\.0+$'::text, ''::text) AS np_n,
            max("Registros_Produccion_Virgilio".ts_cliente) AS last_ccn
           FROM "Registros_Produccion_Virgilio"
          WHERE "Registros_Produccion_Virgilio".opcion = 'CCN'::text AND "Registros_Produccion_Virgilio".ts_cliente >= '2026-06-22 00:00:00-03'::timestamp with time zone AND NULLIF(TRIM(BOTH FROM "Registros_Produccion_Virgilio".texto), ''::text) IS NOT NULL
          GROUP BY (regexp_replace(TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1)), '\.0+$'::text, ''::text))
        ), cargados AS (
         SELECT c.np_n
           FROM ccn c
             LEFT JOIN fss f ON f.np_n = c.np_n
          WHERE f.last_fss IS NULL OR f.last_fss <= c.last_ccn
        ), pendientes AS (
         SELECT DISTINCT ON (np_clean.np_n) np_clean.np_n,
            np_clean.tanda,
            np_clean.razon_social,
            np_clean.facturado_at::date AS fecha
           FROM np_clean
          WHERE NOT (np_clean.np_n IN ( SELECT cargados.np_n
                   FROM cargados))
          ORDER BY np_clean.np_n, np_clean.facturado_at DESC
        ), entregas_pend AS (
         -- v21.11 (Luis, 22/09): el codigo de Entregas_Virgilio viaja CRUDO con la L
         -- (438EL, 026L) porque es el que va a la FACTURA. Para el badge de Stock hay
         -- que resolverlo al codigo de GONDOLA, que es lo que hace pkResolveArt en el
         -- front: 026L -> 026, 438EL -> 438E LK. Con norm_cod() a secas la L quedaba
         -- pegada y el badge partia el articulo en dos filas (026 = 10, 026L = 1).
         SELECT public.gv_cod_stock_de_entrega(e.cod_art, p.np_n, e.gv_empresa) AS cod,
            p.np_n AS np,
            p.tanda,
            p.razon_social,
            p.fecha,
            e.cajas_entregadas AS cajas
           FROM "Entregas_Virgilio" e
             JOIN pendientes p ON regexp_replace(TRIM(BOTH FROM e.np), '\.0+$'::text, ''::text) = p.np_n
          WHERE e.cajas_entregadas > 0::numeric AND NULLIF(TRIM(BOTH FROM e.cod_art), ''::text) IS NOT NULL
        )
 SELECT cod,
    sum(cajas) AS cajas,
    count(DISTINCT np) AS cant_nps,
    jsonb_agg(jsonb_build_object('np', np, 'cajas', cajas, 'tanda', tanda, 'rs', razon_social, 'fecha', fecha) ORDER BY fecha DESC) AS detalle_nps
   FROM entregas_pend
  WHERE cod <> ''::text
  GROUP BY cod
  ORDER BY cod;

alter view public.vista_fc_sin_salida set (security_invoker = true);

-- 3) Centinelas: si alguien reemplaza estos objetos con una copia vieja, se ve.
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values
 ('vista_fc_sin_salida','vista','gv_cod_stock_de_entrega\s*\(',
  'El badge FC s/Salida resuelve el codigo de Entregas_Virgilio (que viaja CRUDO con L) al codigo de gondola: 026L -> 026, 438EL -> 438E LK. Sin esto la L queda pegada y el articulo sale partido en dos filas.',
  'Luis','v21.11'),
 ('gv_cod_stock_de_entrega','funcion','''LK''',
  'Un codigo que termina en L (pegada a digito o E) es de LOEKEMEYER: la empresa la da la L, NUNCA la NP. Sin esto un dual (438EL) de una NP de Chef se resuelve a 438E CH y el badge mira la gondola equivocada.',
  'Luis','v21.11')
on conflict do nothing;

-- CHEQUEOS
--   select * from public.gv_reglas_perdidas;                                  -- vacia = todo bien
--   select count(*) from public.vista_fc_sin_salida where cod ~ '[0-9E]L$';   -- 0
--   select cod_art from public."Movimientos_Stock" where cod_art ~ '[0-9E]L$';-- vacio
--   node tests/fcs-codigo-l.cjs
