-- v23.19 (Luis, 2026-09-28) — PROYECTO LK (kwkclwhmoygunqmlegrg). Problema 587.
-- gv_clientes_nuevos_calc contaba los pedidos con un LEFT JOIN a sales_lines y
-- count(DISTINCT ROW(s.empresa, s.invoice_date)): sin ventas, ROW(null,null) NO es null y cuenta 1.
-- Efecto: 140 clientes que nunca compraron figuraban con 1 pedido -> gv_clin_pipeline_lote los
-- marcaba recurrentes y arrancaban en Speech 1 sin análisis (caso Autoservicio Capo, LK 4286).
-- Y al revés: 12 clientes con 2 compras reales (y un código vinculado sin ventas) contaban 3 y
-- dejaban de ser clientes nuevos.
-- Medido: antes 1:245 2:72 (317) · después 0:140 1:123 2:66 (329).
-- Backup de la definición: zz_backups."Backup_viewdef_gv_clientes_nuevos_calc_20260928" (LK).
do $$ declare d text; n text; begin
  d := pg_get_viewdef('public.gv_clientes_nuevos_calc'::regclass, true);
  if d ~ 'FILTER \(WHERE s\.customer_code IS NOT NULL\) AS pedidos' then raise notice 'ya'; return; end if;
  n := replace(d, 'count(DISTINCT ROW(s.empresa, s.invoice_date)) AS pedidos',
                  'count(DISTINCT ROW(s.empresa, s.invoice_date)) FILTER (WHERE s.customer_code IS NOT NULL) AS pedidos');
  if n = d then raise exception 'no matcheo'; end if;
  execute 'create or replace view public.gv_clientes_nuevos_calc with (security_invoker = true) as ' || n;
end $$;
select public.sync_clientes_nuevos_virgilio();

-- Datos, mismo día (con el sí de Luis): pedidos web LK 1548/1549 de Capo cargados con el código
-- inexistente 4318 -> 4286 (orders en LK; lk_pedidos_match y PPP_Web_Programacion en Gestión) y
-- devueltos a Cuarentena con gv_cuarentena_devolver (E18F/E18G sin eventos ni stock). Problema 588.
-- Backups: LK zz_backups."Backup_orders_Capo_20260928"; Gestión zz_backups."GV_Backup_PPPWebProg_Capo_20260928"
-- y "GV_Backup_LkPedMatch_Capo_20260928".
