-- v20.00 (2026-09-18) — Las cuatro tablas que el renombrador no tocaba, y el rastro de quién es
-- cada caja en la pila de facturar
-- =============================================================================================
-- PEDIDO DE THOMAS (18/09), sobre dos cosas distintas:
--   (1) "Agregalas": las tablas que se quedaban con el código viejo cuando una tanda se renombra.
--   (2) Sobre el drenaje del facturado que se llevó las cajas de otra NP: *"que el sistema
--       empiece a trackear la info por si hay que hacer una corrección (y sabemos qué le
--       corresponde a cada uno). Suficientemente infrecuente como para que no amerite ningún
--       otro cambio."* → NO se toca el módulo de Facturación: se agrega la trazabilidad.
-- =============================================================================================

-- ── 1. LAS SEIS TABLAS QUE AHORA VIAJAN CON LA TANDA ────────────────────────────────────────
-- Se agregan al final de `gv_ppp_tanda_renombrar`, antes de GV_PPP_Armados_Espera. El cuerpo
-- completo y vivo de la función sale de `pg_get_functiondef`; acá va sólo el bloque nuevo.
--
-- Thomas aprobó cuatro (Etiquetas_Lio, GV_Conciliacion_Facturacion, GV_PPP_Prog_Override,
-- Faltantes_Tareas). Se suman `Faltantes_Avisados` y `Faltantes_Revisados` porque son la misma
-- familia y comparten la trampa de abajo — quedan dichas acá para que se vea que se agregaron.
--
-- ⚠ `Faltantes_Avisados` y `Faltantes_Revisados` tienen la tanda EN LA CLAVE PRIMARIA
-- `(tanda, cod)`. Mismo tratamiento que el candado de la v19.96: primero el DELETE del origen que
-- choca (manda el destino, que es la tanda que sobrevive) y recién después el UPDATE. Al revés,
-- el update explota contra el unique y la RPC entera devuelve 400 — el pozo del problema 407.
-- Las otras cuatro tienen la PK en `id` o en `np`, así que el update pelado alcanza.

  delete from public."Faltantes_Avisados" o
   where upper(btrim(o.tanda)) = v_a
     and exists (select 1 from public."Faltantes_Avisados" d
                  where upper(btrim(d.tanda)) = v_b and d.cod = o.cod);
  update public."Faltantes_Avisados" set tanda = v_b where upper(btrim(tanda)) = v_a;

  delete from public."Faltantes_Revisados" o
   where upper(btrim(o.tanda)) = v_a
     and exists (select 1 from public."Faltantes_Revisados" d
                  where upper(btrim(d.tanda)) = v_b and d.cod = o.cod);
  update public."Faltantes_Revisados" set tanda = v_b where upper(btrim(tanda)) = v_a;

  update public."Etiquetas_Lio"               set tanda = v_b where upper(btrim(coalesce(tanda,''))) = v_a;
  update public."Faltantes_Tareas"            set tanda = v_b where upper(btrim(coalesce(tanda,''))) = v_a;
  update public."GV_Conciliacion_Facturacion" set tanda = v_b where upper(btrim(coalesce(tanda,''))) = v_a;
  update public."GV_PPP_Prog_Override"        set tanda = v_b where upper(btrim(coalesce(tanda,''))) = v_a;

-- ⚠ NO se tocan los LIBROS DE HISTORIA: `GV_Desarmes`, `GV_Tanda_Anulada` y
-- `GV_Stock_Drenaje_Bloqueado` anotan que algo pasó bajo ESE nombre, en ESE momento.
-- Renombrarlos sería reescribir el pasado, que es lo contrario de para lo que existen.
--
-- PROBADO CORRIÉNDOLO (tandas ZZ80Z/ZZ81Z, borradas después): con `Faltantes_Avisados` cargada
-- como ZZ80Z/501 + ZZ80Z/502 + ZZ81Z/501, el renombre dejó ZZ81Z/501 (la del destino) y movió
-- ZZ81Z/502. Cero violaciones de unique.

-- ── 2. DE QUIÉN ES CADA CAJA DE LA PILA DE FACTURAR ─────────────────────────────────────────
-- El drenaje del facturado escribe `ref = 'TANDA|NP'`, pero a veces sale con la tanda sola. Con
-- tres pedidos en la misma tanda, la pila `a_facturar` es una sola y el descuento no distingue de
-- quién era cada caja: el 17/09 la factura de 98615/98616 se llevó las 92 de 98622 (problema 446).
-- Thomas decidió no tocar el módulo. Entonces lo que se agrega es el RASTRO, para que una
-- corrección sepa a quién le corresponde qué.
create or replace view public.gv_fac_cajas_por_np
with (security_invoker = true) as
with armado as (
  select upper(btrim(e.tanda)) tanda, regexp_replace(btrim(e.np),'\.0+$','') np,
         upper(btrim(e.cod_art)) cod, sum(e.cajas_entregadas) armadas
    from public."Entregas_Virgilio" e
   where coalesce(e.cajas_entregadas,0) > 0
   group by 1,2,3),
dren as (
  select upper(split_part(btrim(m.ref),'|',1)) tanda,
         nullif(regexp_replace(btrim(split_part(btrim(m.ref),'|',2)),'\.0+$',''),'') np,
         upper(btrim(m.cod_art)) cod, -sum(m.delta) drenado
    from public."Movimientos_Stock" m
   where m.tipo = 'facturado'
   group by 1,2,3)
select a.tanda, a.np, a.cod, a.armadas,
       coalesce(d.drenado, 0) drenado_a_su_nombre,
       a.armadas - coalesce(d.drenado, 0) pendiente,
       exists (select 1 from public."Facturacion_NP" f
                where regexp_replace(btrim(f.np::text),'\.0+$','') = a.np) facturada,
       (select coalesce(sum(s.drenado),0) from dren s
         where s.tanda = a.tanda and s.np is null and s.cod = a.cod) drenado_sin_dueno_en_la_tanda
  from armado a
  left join dren d on d.tanda = a.tanda and d.np = a.np and d.cod = a.cod;
alter view public.gv_fac_cajas_por_np set (security_invoker = true);

-- El centinela: un drenaje sin dueño cuyos renglones calzan EXACTO con una NP que no está
-- facturada. Vacía = todo bien.
create or replace view public.gv_fac_drenaje_cruzado
with (security_invoker = true) as
with dren as (
  select upper(btrim(m.ref)) tanda, upper(btrim(m.cod_art)) cod, -sum(m.delta) cajas, max(m.ts) ts
    from public."Movimientos_Stock" m
   where m.tipo = 'facturado' and position('|' in btrim(m.ref)) = 0
   group by 1,2),
dtot as (select tanda, count(*) cods, sum(cajas) cajas, max(ts) ts from dren group by 1 having count(*) >= 3),
ent as (
  select upper(btrim(e.tanda)) tanda, regexp_replace(btrim(e.np),'\.0+$','') np,
         upper(btrim(e.cod_art)) cod, sum(e.cajas_entregadas) cajas
    from public."Entregas_Virgilio" e group by 1,2,3)
select d.tanda, e.np, dt.cods codigos_drenados, dt.cajas cajas_drenadas, dt.ts cuando,
       'El facturado descargo la pila de la tanda y los renglones calzan EXACTO con esta NP, que NO esta facturada. Las cajas son de ella.' as que_significa
  from dren d
  join dtot dt on dt.tanda = d.tanda
  join ent e   on e.tanda = d.tanda and e.cod = d.cod and e.cajas = d.cajas
 where not exists (select 1 from public."Facturacion_NP" f
                    where regexp_replace(btrim(f.np::text),'\.0+$','') = e.np)
 group by 1,2,3,4,5
having count(*) = dt.cods;
alter view public.gv_fac_drenaje_cruzado set (security_invoker = true);

-- ⚠ PROBADO CONTRA EL CASO REAL: hoy da vacía porque el arreglo de la v19.99 se llevó las
-- Entregas de 98622. Corriendo la MISMA lógica con el backup
-- `zz_backups."GV_Backup_98622_D69C_Entregas_20260918"` unido a Entregas_Virgilio, devuelve
-- exactamente `D69C | 98622 | facturada = false`. O sea: lo habría cazado.
--
-- Chequeos:
--   select * from public.gv_fac_drenaje_cruzado;                         -- vacía = todo bien
--   select * from public.gv_fac_cajas_por_np where tanda = 'D69C';       -- de quién es cada caja
