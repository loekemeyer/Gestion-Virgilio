/* ============================================================================
   v21.13 — "438E LK" NO ES UN CODIGO: el articulo va pelado y la empresa al lado

   Luis, 2026-09-22:
     "ahi figura que se facturo un 026L. Ahora, para el stock, se deberia descontar
      el 026 (regla de codigos L). Por que figura ahi?"
     "si hay 11 que salen los 11 deberian aparecer como 026 y ninguno como 026L
      para fc s/salida, es rarisimo eso. Aplica esa logica a todos esos codigos."
     "COMO QUE 438E LK... NO EXISTE ESE CODIGO. Deberia ser en todos lados 438E de
      la empresa LK o de la empresa CH como dato en una columna aparte que viaje
      con el codigo a todos lados."

   EL STOCK ESTABA BIEN — se midio primero, porque era la duda de fondo
   -------------------------------------------------------------------
   0 movimientos de `Movimientos_Stock` terminan en L, y de las 34 lineas con L
   facturadas 31 drenaron contra el codigo pelado y la gondola que corresponde. El
   026 de ese pedido: picking 26/08 (excedente -1, separar_pedidos +1) · separado
   27/08 · facturado 21/09 (`ref = D47B|CH 0030`, empresa LK, delta -1).

   EL MODELO CORRECTO YA EXISTE, y es el de `Movimientos_Stock`
   -----------------------------------------------------------
     Movimientos_Stock : cod_art = '438E'  + columna `empresa` = LK/CH   <- asi va
     GV_Lugar_Item     : cod     = '438E'  + el sector dice la empresa   <- asi va
     stocks_carga_rapida: cod = '438E LK'  … pero YA tiene `cod_base` + `linea`

   O sea: el string concatenado vive en UN solo lugar (8 filas de 367: los 4 duales
   x 2 empresas), es una CLAVE heredada de `vista_stock_procesada`, y la tabla ya
   guarda los dos datos separados al lado. Nada nuevo se escribe asi.

   EL SINTOMA
   ----------
   El modulo Stocks mostraba una fila fantasma `026L` — sin LK/CH, sin descripcion,
   sin gondola, stock 0 — con 1 caja en FC s/Salida, mientras la fila `026` decia 10.
   Son la misma caja.

   LA CAUSA
   --------
   `vista_fc_sin_salida` agrupaba por `norm_cod(Entregas_Virgilio.cod_art)`, y
   `norm_cod()` SOLO saca ceros a la izquierda y pone mayusculas: NO pela la L. Y
   `Entregas_Virgilio` lleva la L CRUDA a proposito — es el codigo que va a la
   factura y al Excel de ISIS (regla "LA L NO ES UN CODIGO, ES UNA DENOTACION").
   Despues `index.html` fabrica una fila por cada codigo de esa vista que no exista
   en el universo de stock: de ahi la fila fantasma.

   LO MEDIDO (22/09)
   -----------------
   - 32 codigos con L en la vista, todos del mismo pedido: Alesso Vilarino Liliana,
     NP CH 0030/0031/0032, tanda D47B, facturado 21/09 (pedido de Chef con articulos
     de Loeke, el caso de la regla). Historico: 38 filas / 36 codigos / 6 NP.
   - EN LOS DUALES EL BADGE NO FUNCIONABA NI CON L NI SIN L: la vista devolvia
     `438EL` y `438E`, el universo los tiene como `438E LK` / `438E CH`, y
     `refresh_stocks_carga_rapida` cruzaba con `scr.cod = fc.cod` (igualdad EXACTA):
     los dos quedaban en 0. Y el fallback `codBase` del front le asignaba las mismas
     cajas a las DOS filas del dual.

   EL ARREGLO — dos datos, dos funciones, dos columnas
   ---------------------------------------------------
     gv_cod_stock_de_entrega  -> el ARTICULO  (026L -> 26, 438EL -> 438E)
     gv_empresa_de_entrega    -> la EMPRESA   (LK / CH)
   y NUNCA se vuelven a pegar. La vista los publica en dos columnas y el refresh
   cruza por `(cod_base, linea)`, las dos que la tabla ya tenia separadas.

   ⚠ La empresa de un codigo con L es LK, la da la L y NUNCA la NP: un `438EL` de
     una NP de Chef resuelto por NP daria CH y el badge miraria la gondola equivocada.
   ⚠ En un codigo NO dual la empresa la da el ARTICULO, no el pedido (regla v19.26).

   VERIFICADO
   ----------
   - 0 codigos con L y 0 con sufijo pegado en la vista (antes 32 con L).
   - El 026 pasa de 10 a 11 cajas; `438E` LK de 0 a 4; `437E` LK 1; `809E` LK 4 / CH 4.
   - Total IDENTICO antes y despues: 2.084 = 2.084 contra la fuente cruda, y la suma
     de `fc_sin_salida` en la tabla da los mismos 2.084 (o sea: nada se cuenta doble).
   - 0 codigos de la vista sin fila en `stocks_carga_rapida`.

   ⚠ UN DATO PREEXISTENTE QUE APARECIO AL CRUZAR POR cod_base: el `439E` tiene TRES
     filas en `stocks_carga_rapida` — `439E` (pelada, stock 0, residual de antes del
     desdoble), `439E LK` (15) y `439E CH` (8). Sin el segundo filtro del WHERE el
     badge se contaba dos veces del lado LK. La fila residual NO se toco (es un dato,
     no codigo); queda reportada.

   ROLLBACK: `sql/backups/` no hace falta — no se toco ningun dato. Para volver:
   la vista a `norm_cod(e.cod_art) AS cod` sin la columna `empresa`, y el bloque
   final del refresh a `WHERE scr.cod = fc.cod`.
   (md5 de la definicion de la vista antes de todo: 213d01c1049e02685be0c19299c2668c)
   ============================================================================ */

-- 1) EL ARTICULO. Solo el codigo: pela la L final pegada a digito o E, y tambien el
--    sufijo de empresa si alguien se lo pego antes. NUNCA devuelve "438E LK".
create or replace function public.gv_cod_stock_de_entrega(
  p_cod text, p_np text default null, p_emp text default null)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select regexp_replace(
           regexp_replace(public.norm_cod(p_cod), '\s+(LK|CH|LOKE)$', ''),
           '([0-9E])L$', '\1');
$$;

-- 2) LA EMPRESA, aparte. Es el dato que desambigua un DUAL; en el resto la da el articulo.
create or replace function public.gv_empresa_de_entrega(
  p_cod text, p_np text default null, p_emp text default null)
returns text
language sql
stable
set search_path = public, pg_temp
as $$
  with x as (select public.gv_cod_stock_de_entrega(p_cod) as base)
  select case
    -- DUAL (437E/438E/439E/809E): vive en las dos gondolas, asi que la empresa la da
    -- el PEDIDO. Y ahi LA L MANDA: un 438EL de una NP de Chef sale de la gondola LK.
    when exists (select 1 from public.codigos_duales d
                  where public.norm_cod(d.cod) = x.base) then
      case
        when upper(btrim(coalesce(p_cod,''))) ~ '[0-9E]L$' then 'LK'
        when upper(coalesce(public.gv_emp_de_np(p_np), p_emp, '')) like 'LK%' then 'LK'
        when upper(coalesce(public.gv_emp_de_np(p_np), p_emp, '')) like 'CH%' then 'CH'
        else null
      end
    -- NO dual: la empresa la da el ARTICULO, no el pedido (regla v19.26 de Luis).
    else upper(public.gv_empresa_de_articulo(x.base))
  end
  from x;
$$;

-- Pruebas (medido 22/09) — articulo | empresa:
--   ('026L' ,'CH 0030') = 26   | LK      no dual con L
--   ('505L' ,'CH 0031') = 505  | LK
--   ('598EL','CH 0031') = 598E | LK      la E queda, la L se va
--   ('438EL','CH 0030') = 438E | LK      DUAL con L -> manda la L, no la NP
--   ('439EL','44600'  ) = 439E | LK
--   ('438E' ,'CH 0030') = 438E | CH      dual sin L -> ahi si manda la NP
--   ('438E' ,'98615'  ) = 438E | LK
--   ('438E LK','98615') = 438E | LK      idempotente: pela el sufijo heredado

-- 3) LA VISTA: dos columnas, `cod` y `empresa`. Nunca concatenadas.
--    ⚠ El CREATE OR REPLACE lleva el `with (security_invoker = true)` Y el alter de
--    abajo: sin eso la vista corre como postgres y saltea la RLS.
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
         -- v21.13 (Luis, 22/09): EL CODIGO VA PELADO Y LA EMPRESA VIAJA AL LADO.
         -- Entregas_Virgilio guarda el codigo CRUDO con L (026L, 438EL) porque es el
         -- que va a la FACTURA. Aca se parte en sus dos datos: `cod` (026, 438E — el
         -- articulo, que es lo unico que existe) y `empresa` (LK/CH — de que gondola
         -- salio). NUNCA se concatenan: "438E LK" no es un codigo.
         SELECT public.gv_cod_stock_de_entrega(e.cod_art, p.np_n, e.gv_empresa) AS cod,
            public.gv_empresa_de_entrega(e.cod_art, p.np_n, e.gv_empresa) AS empresa,
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
    jsonb_agg(jsonb_build_object('np', np, 'cajas', cajas, 'tanda', tanda, 'rs', razon_social, 'fecha', fecha) ORDER BY fecha DESC) AS detalle_nps,
    empresa
   FROM entregas_pend
  WHERE cod <> ''::text
  GROUP BY cod, empresa
  ORDER BY cod;

alter view public.vista_fc_sin_salida set (security_invoker = true);

-- 4) EL CRUCE. Va por (cod_base, linea) — las dos columnas que la tabla ya tiene
--    separadas — nunca por el string concatenado. Reemplaza SOLO el bloque final de
--    refresh_stocks_carga_rapida; el resto de la funcion no se toca. Se aplica sobre
--    la definicion VIVA y falla con un raise si el texto no matchea, en vez de
--    escribir una version vieja encima (varias sesiones tocan esta funcion).
do $mig$
declare v_def text; v_viejo text; v_nuevo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='refresh_stocks_carga_rapida';

  v_viejo := '  UPDATE public.stocks_carga_rapida scr
  SET fc_sin_salida = COALESCE(fc.cajas, 0)
  FROM public.vista_fc_sin_salida fc
  WHERE scr.cod = fc.cod;';

  v_nuevo := '  -- v21.13 (Luis, 22/09) — EL CRUCE VA POR (CODIGO, EMPRESA), nunca por un string
  -- concatenado. `stocks_carga_rapida` ya tiene los dos datos separados: `cod_base`
  -- (438E) y `linea` (LK/CH); el `cod` con sufijo ("438E LK") es una clave heredada
  -- de vista_stock_procesada y NO se usa para esto. Antes se cruzaba `scr.cod = fc.cod`
  -- con igualdad exacta, asi que los 4 duales quedaban en 0 de los dos lados y un
  -- codigo con L (026L) no matcheaba nada.
  UPDATE public.stocks_carga_rapida scr
  SET fc_sin_salida = COALESCE(fc.cajas, 0)
  FROM ( SELECT cod, empresa, sum(cajas) AS cajas
           FROM public.vista_fc_sin_salida
          GROUP BY cod, empresa ) fc
  WHERE public.norm_cod(scr.cod_base) = fc.cod
    AND ( -- NO dual: una sola fila por codigo, la empresa no hace falta.
          NOT EXISTS (SELECT 1 FROM public.codigos_duales d
                       WHERE public.norm_cod(d.cod) = fc.cod)
          -- DUAL: manda la empresa, y la fila es la DESDOBLADA. ⚠ El 439E tiene ademas
          -- una fila residual PELADA (stock 0) de antes del desdoble: sin este segundo
          -- filtro el badge se contaba dos veces del lado LK (medido 22/09).
          OR ( UPPER(scr.linea) = fc.empresa
               AND public.norm_cod(scr.cod) <> fc.cod ) );';

  if position(v_viejo in v_def) = 0 then
    if position('norm_cod(scr.cod_base)' in v_def) > 0 then
      raise notice 'ya estaba aplicado';
      return;
    end if;
    raise exception 'la definicion viva de refresh_stocks_carga_rapida no tiene el bloque esperado — otra sesion la toco, revisar a mano';
  end if;
  execute replace(v_def, v_viejo, v_nuevo);
end $mig$;

-- 5) Centinelas: si alguien reemplaza estos objetos con una copia vieja, se ve.
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values
 ('vista_fc_sin_salida','vista','gv_empresa_de_entrega\s*\(',
  'La vista FC s/Salida publica el codigo y la empresa en DOS columnas separadas, nunca concatenados. Sin gv_empresa_de_entrega el dual no se puede desambiguar y el badge queda en 0 de los dos lados.',
  'Luis','v21.13'),
 ('gv_cod_stock_de_entrega','funcion','LK\|CH\|LOKE',
  'gv_cod_stock_de_entrega devuelve SOLO el codigo (026L -> 026, 438EL -> 438E) y ADEMAS pela cualquier sufijo de empresa que le llegue pegado. "438E LK" NO es un codigo: la empresa viaja aparte, en gv_empresa_de_entrega. (Luis, 22/09)',
  'Luis','v21.13'),
 ('gv_empresa_de_entrega','funcion','''LK''',
  'La empresa de un codigo con L es LOEKEMEYER: la da la L, NUNCA la NP. Y en un codigo NO dual la da el ARTICULO (gv_empresa_de_articulo), no el pedido (regla v19.26).',
  'Luis','v21.13'),
 ('refresh_stocks_carga_rapida','funcion','norm_cod\(scr\.cod_base\)',
  'El badge FC s/Salida se cruza por (cod_base, linea) — las dos columnas que la tabla YA tiene separadas — nunca por el string concatenado scr.cod = fc.cod. Con igualdad exacta los 4 duales quedaban en 0 y un codigo con L no matcheaba nada.',
  'Luis','v21.13')
on conflict do nothing;

select public.refresh_stocks_carga_rapida();

-- CHEQUEOS
--   select * from public.gv_reglas_perdidas;                                     -- vacia
--   select count(*) from public.vista_fc_sin_salida where cod ~ '[0-9E]L$';      -- 0
--   select count(*) from public.vista_fc_sin_salida where cod ~ ' (LK|CH)$';     -- 0
--   select sum(fc_sin_salida) from public.stocks_carga_rapida;                   -- = sum(cajas) de la vista
--   select cod_art from public."Movimientos_Stock" where cod_art ~ '[0-9E]L$';   -- vacio
--   node tests/fcs-codigo-l.cjs
