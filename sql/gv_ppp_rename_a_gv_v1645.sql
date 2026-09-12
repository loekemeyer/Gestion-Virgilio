-- ============================================================================
-- v16.45 — Las tablas de la era PPP/ISIS pasan a nombre GV. Ya no queda ninguna
--          "PPP_*" vieja en public.
-- Proyecto Supabase: hrxfctzncixxqmpfhskv (Gestion Virgilio)
--
-- Dueño, 2026-09-12: "te dejo borrar las viejas de ppp, ya no se usan mas.
-- Ya pasamos a usar solo GV".
--
-- POR QUE NO SE BORRARON, SE RENOMBRARON
-- ---------------------------------------
-- Se midio antes de tocar, y BORRARLAS habria perdido datos vivos:
--   * "PPP_Base_Pedidos" + "PPP_Programacion_Diaria" cargan 59 pedidos pendientes
--     con 3.994,66 cajas, TODOS programados, y entre ellos 8 con entrega FUTURA y
--     sin ningun evento: 5 del lunes 14/09 (Arguello 98615/98616, Succarelli 98621,
--     Martinelli 98622, Extralimp 98651 con 300 cajas) y 3 de Matiz (16/09, 07/10,
--     28/10). Ademas son la pata ISIS de gv_demanda_pedidos (v16.43).
--   * "PPP_Entregados_Meta" es el UNICO registro del m3 entregado historico: sin
--     ella, vista_tanda_m3 pierde 1.114 de sus 1.196 tandas (961 m3).
-- El renombre cumple el objetivo ("solo GV", ninguna PPP_* vieja) sin perder nada,
-- y es reversible con otro rename.
--
-- POR QUE UN RENAME Y NO REESCRIBIR 70 OBJETOS
-- ---------------------------------------------
-- Las VISTAS referencian por OID, no por nombre: un rename es transparente para
-- las 29 vistas + la matview, que siguen andando sin tocarlas. Solo hay que
-- reescribir lo que nombra por TEXTO: las funciones (prosrc) y la app.
-- Eso baja el cambio de ~70 objetos a 31 funciones + 1 constante del front.
--
-- QUE SE HIZO
-- -----------
--   "PPP_Base_Pedidos"        -> "GV_PPP_Base_Pedidos"          (9.786 filas)
--   "PPP_Programacion_Diaria" -> "GV_PPP_Programacion_Diaria"   (133)
--   "PPP_Entregados_Meta"     -> "GV_PPP_Entregados_Historico"  (2.783)
--   31 funciones reescritas (replace del nombre sobre pg_get_functiondef).
--   index.html: PPP_TABLE apunta a los nombres nuevos (pppSubir daria 404 si no).
--   cron.unschedule(27) + drop de sync_ppp_entregados_meta(): el Sheet ya no
--     existe y esa funcion hace TRUNCATE, o sea que un cron mal prendido borraba
--     el historico de m3.
--
-- VERIFICACION (todos los numeros identicos al baseline previo)
-- -------------------------------------------------------------
--   tablas PPP_* viejas que quedan ........ 0
--   vistas que nombran las viejas ......... 0
--   funciones que nombran las viejas ...... 0
--   gv_endpoints_rotos .................... vacia
--   refresh materialized view concurrently  OK
--   vista_stock_procesada ... 366 filas · 7409,66 pedidas · 9092 a_pedir
--   gv_ppp_base_pedidos 9668 · gv_ppp_programacion_diaria 123
--   gv_ppp_entregados_meta 2866 · vista_tanda_m3 1196 filas / 1041 m3
--   vista_generador_oc 345 · v_cajas_pedidas 254 · gv_ppp_en_salida 20
--   las 8 NP pendientes (incluidas las 5 del lunes) intactas
--   RLS y policies sobrevivieron el rename; anon SELECT si, DELETE no
--
-- Backups: zz_backups."GV_Backup_PPP_*_20260912" (copia completa de las 3 tablas)
--          zz_backups."GV_Backup_funcdefs_ppp_20260912" (32 definiciones previas)
-- Rollback: renombrar al reves y volver a correr el loop de funciones al derecho.
-- ============================================================================

begin;

drop function if exists public.sync_ppp_entregados_meta();
-- select cron.unschedule(27);   -- ya ejecutado

alter table public."PPP_Base_Pedidos"        rename to "GV_PPP_Base_Pedidos";
alter table public."PPP_Programacion_Diaria" rename to "GV_PPP_Programacion_Diaria";
alter table public."PPP_Entregados_Meta"     rename to "GV_PPP_Entregados_Historico";

do $do$
declare r record; d text; n int := 0;
begin
  for r in select p.oid, p.oid::regprocedure::text as firma
             from pg_proc p join pg_namespace nn on nn.oid = p.pronamespace
            where nn.nspname = 'public'
              and p.prosrc ~ '"(PPP_Base_Pedidos|PPP_Programacion_Diaria|PPP_Entregados_Meta)"'
  loop
    d := pg_get_functiondef(r.oid);
    d := replace(d, '"PPP_Base_Pedidos"',        '"GV_PPP_Base_Pedidos"');
    d := replace(d, '"PPP_Programacion_Diaria"', '"GV_PPP_Programacion_Diaria"');
    d := replace(d, '"PPP_Entregados_Meta"',     '"GV_PPP_Entregados_Historico"');
    begin
      execute d;
    exception when others then
      raise exception 'fallo al reescribir %: %', r.firma, sqlerrm;
    end;
    n := n + 1;
  end loop;
  raise notice 'funciones reescritas: %', n;
end $do$;

commit;

-- ============ Chequeo ============
-- select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
--  where n.nspname='public' and c.relname in ('PPP_Base_Pedidos','PPP_Programacion_Diaria','PPP_Entregados_Meta');  -- 0
-- select * from public.gv_endpoints_rotos;                                   -- vacia
-- refresh materialized view concurrently public.vista_stock_procesada;       -- OK
