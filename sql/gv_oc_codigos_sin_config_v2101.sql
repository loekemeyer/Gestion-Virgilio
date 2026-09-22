-- v21.01 (Luis, 2026-09-22) — "quiero entender por que figura el 838 en OCs y la logica
-- subyacente para encontrar otros codigos que esten errados".
--
-- LA LOGICA, que es lo que hay que entender antes de mirar la lista:
--
--   vista_generador_oc arma su universo como la UNION de CINCO fuentes
--     stk (vista_saldos_stock) ∪ proy (proyeccion_madre) ∪ dem (pedidos pendientes)
--     ∪ cap (Capacidad_Sector) ∪ cfg (OC_Maximos)
--   y despues resuelve la configuracion con un LEFT JOIN contra OC_Maximos:
--
--       COALESCE("OC_Maximos".activo, true) AS activo
--
--   O sea: un codigo que NO esta en OC_Maximos entra igual al generador —lo arrastra
--   cualquiera de las otras cuatro fuentes— y nace ACTIVO por DEFAULT. "activo" nunca
--   quiso decir "alguien decidio que este articulo se compra": dice "nadie dijo lo
--   contrario". Lo unico que lo saca de la lista de compra es tiene_prov_real
--   (c.proveedor IS NOT NULL), que para un codigo sin fila da false.
--
-- CASO TESTIGO (22/09): el 838 "Filtro para Mate y Cafe" figuraba activo en el generador
-- y no esta en OC_Maximos. Lo metio la DEMANDA: dos pedidos web de Chef de Dorinka
-- (CH 0025 · 48 cajas, CH 0027 · 32 cajas) con entrega el 25/09. No tiene gondola, ni
-- capacidad, ni proyeccion, ni proveedor: no se puede pickear ni comprar. Y no es teorico
-- —la tanda E41A ya se pickeo el 15/09 y las tres filas del 838 en Movimientos_Stock
-- quedaron en delta 0—. El 838E (Rallador Cilindrico Mini) si esta completo: OC_Maximos,
-- Capacidad_Sector, proyeccion_madre y gondola.
--
-- ⚠ LO QUE NO ES UN ERROR, y por eso el centinela NO lo lista: 73 codigos tienen fila
-- activa en OC_Maximos SIN proveedor. 72 de los 73 terminan en E, o sea IMPORTADOS: no
-- tienen proveedor local y esta bien que no lo tengan. El unico que no es 865ED, y no
-- tiene pedidos. Filtrar por "activo sin proveedor" habria dado 73 falsos positivos.
--
-- ⚠ Y LA NORMALIZACION LLEVA EL SUFIJO DE EMPRESA: un dual entra al generador como
-- "438E LK" / "438E CH" (universo_e) pero en OC_Maximos vive como "438E". Comparando el
-- codigo crudo salen 8 duales sanos como si estuvieran sin configurar. Se pela
-- ' +(LK|CH|LOKE)$' ANTES de los ceros de adelante, de los dos lados.
--
-- MEDIDO al 22/09 sobre las 356 filas del generador:
--   16 sin fila en OC_Maximos (activo=true por default) · 7 con pedidos, 82 cajas
--   73 fila activa sin proveedor  → 72 importados, NO es error
--   26 fila marcada inactiva
--  241 configurados ok            ← el numero de "activos" del chequeo del CLAUDE.md
--
-- Chequeo:  select * from public.gv_oc_codigos_sin_config order by pedidos desc;
-- Rollback: drop view public.gv_oc_codigos_sin_config;

create or replace view public.gv_oc_codigos_sin_config as
with g as (
  select v.cod,
         coalesce(nullif(btrim(v.descripcion), ''), '(sin nombre)') as descripcion,
         coalesce(v.pedidos, 0)::numeric as pedidos,
         coalesce(v.stock,   0)::numeric as stock,
         coalesce(v.cap,     0)::numeric as cap,
         coalesce(v.proy,    0)::numeric as proy,
         regexp_replace(regexp_replace(upper(btrim(v.cod)), ' +(LK|CH|LOKE)$', ''), '^0+(?=.)', '') as codn
    from public.vista_generador_oc v
), m as (
  select distinct regexp_replace(regexp_replace(upper(btrim(cod)), ' +(LK|CH|LOKE)$', ''), '^0+(?=.)', '') as codn
    from public."OC_Maximos"
), gon as (
  select distinct regexp_replace(regexp_replace(upper(btrim(cod)), ' +(LK|CH|LOKE)$', ''), '^0+(?=.)', '') as codn
    from public.gv_lugar_articulo
)
select g.cod,
       g.descripcion,
       g.pedidos,
       g.stock,
       g.cap,
       round(g.proy, 2) as proy,
       (g.codn in (select codn from gon)) as tiene_gondola,
       case
         when g.pedidos > 0 and g.codn not in (select codn from gon)
           then 'PEDIDO SIN GONDOLA - hay cajas pedidas y el codigo no tiene sector de picking'
         when g.pedidos > 0
           then 'PEDIDO SIN OC - se vende pero no se puede comprar (sin proveedor ni maximo)'
         when g.stock > 0
           then 'STOCK SIN OC - hay cajas en el deposito y el codigo no esta configurado'
         else 'RESTO - sin pedidos ni stock, probable codigo viejo o mal tipeado'
       end as motivo
  from g
 where g.codn not in (select codn from m);

alter view public.gv_oc_codigos_sin_config set (security_invoker = true);

-- ⚠ security_invoker sobre una tabla con RLS devuelve MENOS FILAS sin dar error (v20.45).
-- Medido el 22/09: postgres ve 16 y anon ve 16, asi que la vista no miente leida desde el
-- navegador. Si algun dia se le prende RLS a OC_Maximos o a gv_lugar_articulo, volver a medir:
--   begin; set local role anon; select count(*) from public.gv_oc_codigos_sin_config; commit;

comment on view public.gv_oc_codigos_sin_config is
 'v21.01 (Luis, 22/09) - codigos que ENTRAN a vista_generador_oc sin tener fila en OC_Maximos. El universo del generador es la UNION de stock+proyeccion+demanda+capacidad+OC_Maximos, y activo sale de COALESCE(OC_Maximos.activo, true): sin fila, el codigo nace ACTIVO sin que nadie lo haya decidido. Caso testigo: 838 (Filtro Mate/Cafe), 80 cajas de Dorinka por la web de Chef, sin gondola ni proveedor.';
