-- v28.33 (Luis, 07/10: "cerrá el tema de las OCs")
-- (1) generar_ocs_automaticas (cron de las 07:00) insertaba con el proveedor crudo de OC_Maximos:
--     la OC de Pedernera / Blistpack / Oscar salía a nombre del FABRICANTE, mientras la manual
--     (gv_oc_generar_pendientes) ya usaba gv_oc_emite_a -> Log/ Fabr. El 07/10 quedaron 10 códigos
--     con dos OC (07:00 al fabricante + 11:03 a Log/ Fabr). Parche idempotente sobre la def viva:
do $$ declare d text := pg_get_functiondef('public.generar_ocs_automaticas(boolean)'::regprocedure); n text;
begin
  if d ~ 'gv_oc_emite_a' then return; end if;
  n := replace(d, $q$select v_hoy, 'Art Term', prov, cod,$q$, $q$select v_hoy, 'Art Term', public.gv_oc_emite_a(prov) /* v28.33-emite */, cod,$q$);
  if n = d then raise exception 'no matcheo el insert'; end if;
  execute n;
end $$;
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('generar_ocs_automaticas','funcion','gv_oc_emite_a\(prov\)','la OC automática del fabricante (Pedernera/Blistpack/Oscar) se emite a quien recibe la orden (Log/ Fabr), igual que la manual','Luis','v28.33');

-- (2) Anuladas (no borradas) las 11 OC duplicadas del 07/10 sin nada recibido:
--     1905 544 · 1910 558 · 1921 580 · 1936 654 · 1937 658 · 1938 659 · 1948 758 · 1950 764 ·
--     1951 769 · 1953 802 (al fabricante, 07:00) y 1909 55289 (Log/ Fabr 07:00; OC_Maximos ya dice
--     Pettofrezza y la de 11:03 salió a Pettofrezza). Backup: zz_backups."GV_Backup_OC_dup_20261007".
--     Rollback: update "Ordenes_Compra" o set estado = b.estado, notas = b.notas
--               from zz_backups."GV_Backup_OC_dup_20261007" b where o.id = b.id;
--     Quedan con dos OC a propósito (split de OC_Maximos): 123, 505, 506, 510, 789.

-- (3) gv_oc_recompute_recibido había perdido la regla de duales v22.37 (otra sesión la pisó con la
--     v21.98). Se repuso el CREATE de sql/gv_oc_dual_empresa_v2237.sql (la viva no tenía nada propio).
