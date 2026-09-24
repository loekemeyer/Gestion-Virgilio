-- v22.14 (Luis, 24/09): gv_oc_codigos_sin_config deja afuera los IMPORTADOS.
-- Un importado no se compra por OC: se compra por el submodulo Importaciones
-- (tabla "Importados", proveedor Becky etc.). La linea Acacia (989E, 990E, 992E)
-- salia como "PEDIDO SIN OC" y era un falso positivo.
-- Se aplico sobre pg_get_viewdef (definicion viva) agregando el CTE imp.
-- ⚠ Al reemplazar la vista se reponen las opciones: security_invoker = true.
CREATE OR REPLACE VIEW public.gv_oc_codigos_sin_config WITH (security_invoker = true) AS
 WITH g AS (
         SELECT v.cod,
            COALESCE(NULLIF(btrim(v.descripcion), ''::text), '(sin nombre)'::text) AS descripcion,
            COALESCE(v.pedidos, 0::numeric) AS pedidos,
            COALESCE(v.stock, 0::numeric) AS stock,
            COALESCE(v.cap, 0::numeric) AS cap,
            COALESCE(v.proy, 0::numeric) AS proy,
            regexp_replace(regexp_replace(upper(btrim(v.cod)), ' +(LK|CH|LOKE)$'::text, ''::text), '^0+(?=.)'::text, ''::text) AS codn
           FROM vista_generador_oc v
        ), m AS (
         SELECT DISTINCT regexp_replace(regexp_replace(upper(btrim("OC_Maximos".cod)), ' +(LK|CH|LOKE)$'::text, ''::text), '^0+(?=.)'::text, ''::text) AS codn
           FROM "OC_Maximos"
        ), imp AS (
         SELECT DISTINCT regexp_replace(regexp_replace(upper(btrim("Importados".cod_art)), ' +(LK|CH|LOKE)$'::text, ''::text), '^0+(?=.)'::text, ''::text) AS codn
           FROM "Importados"
          WHERE "Importados".cod_art IS NOT NULL
        ), gon AS (
         SELECT DISTINCT regexp_replace(regexp_replace(upper(btrim(gv_lugar_articulo.cod)), ' +(LK|CH|LOKE)$'::text, ''::text), '^0+(?=.)'::text, ''::text) AS codn
           FROM gv_lugar_articulo
        )
 SELECT cod,
    descripcion,
    pedidos,
    stock,
    cap,
    round(proy, 2) AS proy,
    (codn IN ( SELECT gon.codn
           FROM gon)) AS tiene_gondola,
        CASE
            WHEN pedidos > 0::numeric AND NOT (codn IN ( SELECT gon.codn
               FROM gon)) THEN 'PEDIDO SIN GONDOLA - hay cajas pedidas y el codigo no tiene sector de picking'::text
            WHEN pedidos > 0::numeric THEN 'PEDIDO SIN OC - se vende pero no se puede comprar (sin proveedor ni maximo)'::text
            WHEN stock > 0::numeric THEN 'STOCK SIN OC - hay cajas en el deposito y el codigo no esta configurado'::text
            ELSE 'RESTO - sin pedidos ni stock, probable codigo viejo o mal tipeado'::text
        END AS motivo
   FROM g
  WHERE NOT (codn IN ( SELECT m.codn
           FROM m))
    AND NOT (codn IN ( SELECT imp.codn
           FROM imp));
ALTER VIEW public.gv_oc_codigos_sin_config SET (security_invoker = true);

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_oc_codigos_sin_config','vista','FROM "Importados"',
        'los importados no se compran por OC: no van en el chequeo de codigos sin config','Luis','v22.14');
