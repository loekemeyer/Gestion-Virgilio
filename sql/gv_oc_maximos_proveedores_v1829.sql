-- =====================================================================================
-- gv_oc_maximos_proveedores_v1829.sql
-- "104 de 354 filas de OC_Maximos no tienen proveedor" — problema 226.
-- ✅ APLICADO el 2026-09-15 (sólo los 3 casos inequívocos). Tarea Planify 3430.
--
-- ⚠ EL DIAGNÓSTICO ORIGINAL ESTABA MAL DIMENSIONADO, y esto es lo que hay que leer:
-- ---------------------------------------------------------------------------------
-- El problema 226 decía "104 códigos sin proveedor → nunca van a tener OC, y cada caja que
-- entre manda un WhatsApp". La primera mitad es cierta; la segunda era teórica. Medido
-- contra las entregas reales ("Entregas Tallerista Virgilio" + "Entregas Prov AT"):
--
--     de los 104 sin proveedor, SÓLO 3 recibieron mercadería alguna vez.
--
-- Los otros 101 nunca entraron por recepción ni tuvieron una OC previa: no generan ningún
-- aviso, porque el aviso lo dispara RECIBIR algo. Son filas de configuración que no
-- corresponden a nada que hoy se compre. No se les inventa proveedor.
--
-- LO QUE SÍ SE APLICÓ: los 3 con entregas
-- ---------------------------------------------------------------------------------
-- Los tres tienen UN solo entregador histórico y es el mismo, `Log/ Fabr`, que además es
-- el proveedor más usado de la tabla (57 códigos). Inequívoco:
--
--   323E  Rallador 4 Lados Mini          ← Log/ Fabr (2 entregas, 86 cj)
--   702E  Abrelata Mariposa.             ← Log/ Fabr (1 entrega, 60 cj)
--   727E  Sacacorcho Doble Imp. Ac X12   ← Log/ Fabr (4 entregas, 99 cj)
--
-- Efecto medido en `vista_generador_oc`: 95 → 96 líneas, 3.586 → 3.648 cajas. El que entra
-- es el 323E con 62 cajas (proy 35, stock 2, pedidos 11, cap 100); 702E y 727E tienen stock
-- de sobra y siguen pidiendo 0, que es lo correcto.
--
-- LO QUE NO SE TOCÓ, Y POR QUÉ — problema 250
-- ---------------------------------------------------------------------------------
-- El ruido real de "SIN OC generada" no venía de los códigos sin proveedor. Cruzando los
-- 173 códigos que recibieron mercadería en 120 días contra OC_Maximos:
--
--   104 coinciden · 19 tienen varios entregadores · 3 sin proveedor (éstos) ·
--     8 no figuran en OC_Maximos · 81 con un proveedor distinto al que entrega
--
-- De esos 81, **59 son falsa alarma**: la RPC `oc_vigentes_por_proveedor` ya los resuelve
-- con el alias Pettofrezza→Rafael (19) y con su regla de prefijo de hasta 2 caracteres de
-- diferencia, que cubre Martin C→Martin (25) y Carlos E→Carlos (15).
--
-- Quedan **22 que la RPC no puede resolver**, y ésos sí disparan el aviso:
--     Oscar → Log/ Fabr .............. 14 códigos · 5.626 cajas
--     Pintos → Log/ Fabr .............  4 códigos ·   160 cajas
--     Tierra Nativa → Log/ Fabr ......  1 código  ·    44 cajas
--     Log/ Fabr → Pedernera ..........  1 código  ·   104 cajas
--     Pedernera → AGUIRRE CARLOS R. ..  1 código  ·    68 cajas
--     Pettofrezza → German ...........  1 código  ·   131 cajas
--
-- Y los 8 que no figuran son todos de Log/ Fabr y casi todos la versión **sin E** de un
-- código que sí existe con E (582/582E, 583/583E, 599/599E, 727/727E): huelen a código mal
-- tipeado en la recepción, no a artículo nuevo.
--
-- ⚠ Nada de esto se corrige solo: **a quién se le compra cada artículo es una decisión
--   comercial del dueño**, y la versión sin E puede ser un error de carga que se arregla en
--   el remito, no en la configuración. Queda en el problema 250, abierto.
--
-- Respaldo: zz_backups."GV_Backup_OC_Maximos_20260915" (las 354 filas, 104 sin proveedor).
-- =====================================================================================


-- 1) APLICAR ==========================================================================
update public."OC_Maximos"
   set proveedor = 'Log/ Fabr', actualizado = now()
 where regexp_replace(upper(btrim(cod)),'^0+(?=.)','') in ('323E','702E','727E')
   and nullif(btrim(coalesce(proveedor,'')),'') is null;
-- esperado: UPDATE 3


-- 2) VERIFICAR ========================================================================
-- (a) quedan 101 sin proveedor, y ninguno de ellos recibió mercadería nunca
select count(*) from public."OC_Maximos" where nullif(btrim(coalesce(proveedor,'')),'') is null;

-- (b) el generador: 96 líneas / 3.648 cajas
select count(*) lineas, sum(total) cajas
  from public.vista_generador_oc where total > 0 and activo and tiene_prov_real;

-- (c) los tres, con su cuenta
select cod, proveedor, proy, stock, pedidos, cap, maximo, total
  from public.vista_generador_oc where codn in ('323E','702E','727E');

-- (d) el cruce que hay que volver a mirar cuando se decidan los 22 (problema 250)
with ent as (
  select regexp_replace(upper(btrim("Cod")),'^0+(?=.)','') cod, btrim("Nombre_Tall") quien,
         "Cajas"::numeric cajas, created_at ts
    from public."Entregas Tallerista Virgilio"
   where nullif(btrim(coalesce("Nombre_Tall",'')),'') is not null
),
rec as (select cod, count(distinct quien) provs, max(quien) unico, sum(cajas) cajas
          from ent where ts >= now() - interval '120 days' group by 1),
om as (select regexp_replace(upper(btrim(cod)),'^0+(?=.)','') codn,
              nullif(btrim(coalesce(proveedor,'')),'') prov,
              nullif(btrim(coalesce(proveedor2,'')),'') prov2 from public."OC_Maximos")
select o.prov || '  →  ' || r.unico par, count(*) codigos, sum(r.cajas) cajas
  from rec r join om o on o.codn = r.cod
 where r.provs = 1 and o.prov is not null
   and lower(o.prov) <> lower(r.unico) and lower(coalesce(o.prov2,'')) <> lower(r.unico)
 group by 1 order by codigos desc;


-- 3) ROLLBACK =========================================================================
update public."OC_Maximos" o
   set proveedor = b.proveedor, actualizado = b.actualizado
  from zz_backups."GV_Backup_OC_Maximos_20260915" b
 where b.cod = o.cod
   and regexp_replace(upper(btrim(o.cod)),'^0+(?=.)','') in ('323E','702E','727E');
