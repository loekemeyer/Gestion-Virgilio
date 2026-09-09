-- BACKUP + ROLLBACK — OC_Maximos: sacar de OC los E importados (proveedor 'Racks')
-- Fecha: 2026-09-09 · v14.60
--
-- CONTEXTO (regla del dueño 09/09/2026): "Todos los de E son importados. No se piden por OC
-- salvo por los de Danica." En OC_Maximos, 'Racks' NO es un proveedor: es donde se estiba lo
-- importado. Los 78 códigos E con proveedor='Racks' entraban al flujo de OC (tiene_prov_real
-- => maximo/a_pedir => generador `ocs-auto-*` + pestaña Compras). Se les saca el proveedor
-- para que dejen de pedirse por OC. Garcia (11) y Log/ Fabr (9) son proveedores REALES y se
-- MANTIENEN (Danica ≈ Garcia según el dueño).
--
-- CAMBIO APLICADO:
--   update public."OC_Maximos" set proveedor = null
--   where btrim(coalesce(proveedor,'')) = 'Racks';   -- 78 filas, todas cod ~* 'E'
--
-- IMPACTO MEDIDO (antes): 78 E con prov 'Racks'; 2 de ellos con a_pedir>0 (809E CH=283,
--   y otros según proy/dem). Después: esas 78 quedan tiene_prov_real=false => fuera del
--   generador `where activo and total>0 and tiene_prov_real`. Garcia/Log-Fabr intactos.
--
-- ROLLBACK (restaurar proveedor='Racks' en los 78 códigos):
update public."OC_Maximos"
set proveedor = 'Racks'
where regexp_replace(upper(btrim(cod)), '^0+(?=.)', '') in (
  '56E','102E','106E','124E','198E','260E','323E','328E','360E','361E','363E','366E','367E',
  '368E','404E','503E','514E','522E','525E','529E','536E','538E','539E','540E','541E','566E',
  '574E','580E','585E','589E','598E','601E','606E','607E','702E','702EN','712E','725E','727E',
  '727EN','729E','798E','809E','810E','811E','812E','816E','817E','819E','865E','865ED','870E',
  '931E','932E','933E','934E','935E','936E','937E','951E','952E','953E','954E','955E','956E',
  '957E','958E','960E','969E','970E','971E','980E','981E','982E','983E','984E','985E','988E'
);
-- Después del rollback: REFRESH MATERIALIZED VIEW public.vista_stock_procesada; (o esperar el cron cada 2 min)
