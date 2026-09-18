-- v19.85 (2026-09-18) — El STOCK del generador de OC pasa a ser el DISPONIBLE
-- ---------------------------------------------------------------------------
-- Thomas: "lo comprometido (separar_pedidos y a_facturar) no debería contar como stock
-- disponible para la cuenta de 'lo que tenemos - lo que nos falta'".
--
-- EL PROBLEMA (problema 428). vista_generador_oc calcula
--     total = maximo + pedidos - stock
-- y su CTE pend_np EXCLUYE las NP cuya tanda ya tiene TP (pickeada), así que esos pedidos
-- dejan de compensar. Pero el `stock` sumaba los OCHO depósitos, incluidos separar_pedidos y
-- a_facturar — que es exactamente donde ese picking dejó la mercadería. O sea: la caja ya
-- vendida se contaba como disponible Y su pedido ya no se contaba como demanda. Se pedía de
-- menos. La premisa de la v7.18 ("ya se pickeó, la góndola ya bajó") no se cumple con la
-- definición de stock de hoy: la caja no salió del conteo, sólo cambió de depósito.
--
-- EL CAMBIO. Un solo CASE, dos tokens: el `stock` que expone la vista pasa a salir de
-- `fin_dep` —que el CTE stk/stk_e YA calculaba— en vez de `stock`:
--     fin_dep = terminado + a_guardar + racks + excedente + para_envasar + racks_ch
--     stock   = fin_dep + separar_pedidos + a_facturar
-- No se agrega ni se saca ninguna columna (siguen siendo 22), así que ningún consumidor se
-- entera salvo por el valor.
--
-- MEDIDO al aplicarlo (382 filas activas):
--   a pedir  10.606 -> 11.422  (+816 cajas, 64 códigos, NINGUNO baja)
--   stock    45.733 -> 44.528  (-1.205 cajas comprometidas)
--   peores:  505 787->877 · 501 944->1008 · 510 746->807 · 583E 197->247 · 506 993->1031
--   ⚠ 256 (Mate Madera Cerámica) queda con stock -1: tiene 2 cajas comprometidas y 1 de saldo
--     total, o sea que el libro ya venía con un sobre-pickeo. No lo causa este cambio, lo
--     destapa; el greatest(0, ...) del total lo contiene (pide 5 en vez de 3).
--
-- Lo lee también el front de Producción Virgilio y el cron `ocs-auto-miercoles`
-- (generar_ocs_automaticas, miércoles 10:00 UTC): desde ahora piden el disponible.
-- Por eso la entrada en docs/ROLLBACK-PRODUCCION.md.
--
-- CÓMO SE APLICÓ: replace sobre pg_get_viewdef de la definición VIVA, con guard de ancla
-- única (la vista la tocaron otras dos sesiones el mismo día: v19.62 los pedidos web, v19.71
-- el tope de góndola, v19.80 los duales por empresa — nunca partir de una copia del repo).
-- Respaldos: zz_backups."GV_Backup_Def_GeneradorOC_20260918c" (la definición previa) y
-- zz_backups."GV_Backup_GeneradorOC_Filas_20260918c" (las 382 filas de antes).

do $mig$
declare
  v_def text := pg_get_viewdef('public.vista_generador_oc'::regclass, true);
  v_anc text := E'                CASE\n                    WHEN u.emp IS NULL THEN COALESCE(s.stock, 0::numeric)\n                    ELSE COALESCE(se.stock, 0::numeric)\n                END AS stock,';
  v_new text := E'                CASE\n                    WHEN u.emp IS NULL THEN COALESCE(s.fin_dep, 0::numeric)\n                    ELSE COALESCE(se.fin_dep, 0::numeric)\n                END AS stock,';
  v_n   int;
begin
  v_n := (length(v_def) - length(replace(v_def, v_anc, ''))) / length(v_anc);
  if v_n <> 1 then
    raise exception 'ancla no unica: % apariciones — la vista cambio, abortado', v_n;
  end if;
  v_def := replace(v_def, v_anc, v_new);
  if position('COALESCE(s.fin_dep, 0::numeric)' in v_def) = 0 then
    raise exception 'el replace no dejo el fin_dep, abortado';
  end if;
  execute 'create or replace view public.vista_generador_oc as ' || v_def;
  execute 'alter view public.vista_generador_oc set (security_invoker = true)';   -- NUNCA olvidarlo
end
$mig$;

-- centinela, para que no vuelva de contrabando
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('vista_generador_oc','vista','COALESCE\(s\.fin_dep',
 'El STOCK del generador de OC es el DISPONIBLE: no cuenta separar_pedidos ni a_facturar.',
 'Thomas','v19.85')
on conflict do nothing;

-- CHEQUEOS
select relname, reloptions from pg_class where oid='public.vista_generador_oc'::regclass;  -- security_invoker=true
select * from public.gv_reglas_perdidas;    -- vacía
select * from public.gv_endpoints_rotos;    -- vacía
select sum(total) a_pedir, sum(stock) stock from public.vista_generador_oc where activo;

-- ROLLBACK (vuelve a contar lo comprometido como disponible)
-- do $rb$
-- declare v_def text;
-- begin
--   select def into v_def from zz_backups."GV_Backup_Def_GeneradorOC_20260918c";
--   execute 'create or replace view public.vista_generador_oc as ' || v_def;
--   execute 'alter view public.vista_generador_oc set (security_invoker = true)';
--   update public."GV_Reglas_Centinela" set activo = false where patron = 'COALESCE\(s\.fin_dep';
-- end $rb$;
