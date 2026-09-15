-- v18.63 — Problema 236: las 7 vistas "crudas" de Importados / multigrafía dejan de ser
-- legibles por anon y authenticated.
--
-- QUÉ SE MIDIÓ (15/09, contra la base real):
--   El problema 236 decía "8 tablas con RLS y sin policies detrás de vistas security_invoker
--   que la app lee" — o sea, pantallas en blanco. Medido endpoint por endpoint, la app NO lee
--   esas vistas: llama 8 RPC SECURITY DEFINER, y las 8 devuelven filas como anon Y como
--   authenticated (9 / 8 / 3 / 2 / 60 / 8 / 8 / 10). Las tablas son:
--     GV_Imp_Carga_Pedido, GV_Imp_NTL_Mov, GV_Imp_Pagos, GV_Imp_Pedido_CC, GV_Imp_Prov_Mov,
--     GV_Importados_Baches, Insumos_Ubicaciones_Unificadas, Ubicaciones_Articulos.
--   El patrón es deliberado: la vista arma el dato crudo y corre como el que la llama; el
--   wrapper SECURITY DEFINER es el que la app tiene permitido ejecutar. La RLS sin policies
--   es lo que impide que la anon key —que es pública, viaja en index.html— lea los pagos a
--   proveedores en crudo. Por eso NO se agregan policies: eso sí sería abrir la puerta.
--
-- QUÉ QUEDABA MAL DE VERDAD: esas mismas vistas eran SELECT-ables por anon y devolvían
--   0 filas en silencio (RLS sin policies no da error, simplemente no ve nada). El día que
--   alguien escriba una pantalla nueva y lea la vista en vez del RPC, ve una pantalla vacía
--   sin un solo error en la consola. Revocando el SELECT, ese error se vuelve ruidoso
--   ("permission denied") en lugar de silencioso.
--
-- IMPACTO MEDIDO: ninguno. Las 8 RPC siguen devolviendo lo mismo después del revoke (se probó
--   primero en una transacción abortada, después aplicado, como anon y como authenticated), y
--   gv_endpoints_rotos sigue vacía. Los 6 consumidores de estas vistas son todos funciones
--   SECURITY DEFINER (corren como el dueño, no les afecta el grant):
--     gv_imp_cargas() · gv_imp_cc_lista() · gv_imp_conciliacion() · gv_imp_ntl_mov(int,text,text)
--     gv_imp_ntl_resumen() · gv_importados_pedidos_curso()
--   gv_codigos_multigrafia no la llama nadie desde el front: es de diagnóstico, se mira por MCP
--   (que entra como postgres).
--
-- ROLLBACK:
--   grant select on public.gv_imp_cargas, public.gv_imp_conciliacion, public.gv_imp_cuenta_corriente,
--     public.gv_imp_ntl_cuenta, public.gv_imp_ntl_resumen, public.gv_importados_pedidos_curso,
--     public.gv_codigos_multigrafia to anon, authenticated;

revoke select on public.gv_imp_cargas, public.gv_imp_conciliacion, public.gv_imp_cuenta_corriente,
  public.gv_imp_ntl_cuenta, public.gv_imp_ntl_resumen, public.gv_importados_pedidos_curso,
  public.gv_codigos_multigrafia from anon, authenticated;

-- chequeo: las 7 en false, las dos columnas
select c.relname,
       has_table_privilege('anon', c.oid, 'SELECT')          as anon_sel,
       has_table_privilege('authenticated', c.oid, 'SELECT') as auth_sel
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public'
   and c.relname in ('gv_imp_cargas','gv_imp_conciliacion','gv_imp_cuenta_corriente',
                     'gv_imp_ntl_cuenta','gv_imp_ntl_resumen','gv_importados_pedidos_curso',
                     'gv_codigos_multigrafia')
 order by 1;

-- chequeo: lo que la app llama de verdad sigue contestando (correr con «set local role anon;»)
-- select 'gv_imp_cargas' fn, count(*) n from public.gv_imp_cargas()
-- union all select 'gv_imp_conciliacion',         count(*) from public.gv_imp_conciliacion()
-- union all select 'gv_imp_ntl_resumen',          count(*) from public.gv_imp_ntl_resumen()
-- union all select 'gv_imp_ntl_pendientes',       count(*) from public.gv_imp_ntl_pendientes()
-- union all select 'gv_imp_ntl_mov',              count(*) from public.gv_imp_ntl_mov(60,null,null)
-- union all select 'gv_imp_cc_lista',             count(*) from public.gv_imp_cc_lista()
-- union all select 'gv_importados_pedidos_curso', count(*) from public.gv_importados_pedidos_curso()
-- union all select 'gv_imp_prov_alias',           count(*) from public.gv_imp_prov_alias();
