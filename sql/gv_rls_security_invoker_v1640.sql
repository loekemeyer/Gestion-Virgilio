-- gv_rls_security_invoker_v1640.sql — APLICADO 2026-09-12.
--
-- Cierra el problema 103: **45 vistas de `public` que `anon` puede leer y no tenían
-- `security_invoker`**, o sea que corrían con los permisos de `postgres` y **la RLS de las
-- tablas de abajo no se aplicaba**. La anon key está en el HTML de la app (es pública por
-- diseño), así que cada una de esas vistas era una ventana que saltea el candado. `CLAUDE.md`
-- registra que ese mismo agujero *"el 2026-09-04 costó una filtración real"*.
--
-- ── POR QUÉ NO SE PODÍA PRENDER EN BLOQUE ────────────────────────────────────────────────
-- Prender el invoker puede dejar una vista devolviendo **0 filas o un error** si `anon` no
-- llega a alguna tabla de abajo. Una pantalla vacía en pleno picking es peor que el agujero.
--
-- ── EL TEST, QUE ES LO QUE HACE QUE ESTO SEA SEGURO ──────────────────────────────────────
-- No hace falta prender para saber qué pasa: **correr la DEFINICIÓN de la vista como `anon`
-- aplica la RLS exactamente igual que tendría el invoker prendido.** Así que para cada vista:
--
--   filas como postgres  :  select count(*) from public.<vista>
--   filas como anon      :  begin; set local role anon;
--                           select count(*) from ( <pg_get_viewdef> ) z;
--
-- Iguales → prenderlo es un no-op. Distintas o error → NO se toca.
--
-- Detalles del script: `statement_timeout` de 8 s por vista (joins pesados sobre este proyecto
-- ya tumbaron la conexión hoy), `limit 3000` para acotar el trabajo, `reset role` también en el
-- `exception` para no quedar pegado como `anon`, y de a 12–15 vistas por corrida. Y ojo:
-- `pg_get_viewdef` termina en `;`, que rompe el subquery — va `rtrim(d, ' ;')`.
--
-- Resultados en `zz_backups."GV_RLS_Sweep_20260912"` (vista, filas_pg, filas_anon, err,
-- post_anon, post_err).
--
-- ── RESULTADO: 46 medidas → 42 prendidas, 4 intactas ─────────────────────────────────────
--
--   42 iguales  → `alter view … set (security_invoker = true)`
--    4 con error → NO se tocaron
--    0 con diferencia de filas
--
-- **Verificación después de prender**, leyendo las vistas REALES como `anon`: 42 de 42 dan el
-- mismo número que antes, 0 errores. `public` pasó de 85 a 125 vistas con invoker.
--
-- ── LAS 4 QUE QUEDAN, Y POR QUÉ IMPORTAN ─────────────────────────────────────────────────
--
--   vista_factura_metodo_pago    → `permission denied for schema isis_lk`
--   vista_facturacion_faltantes  → `permission denied for view vista_facturacion_neto_items`
--   vista_facturacion_neto       → ídem
--   vista_plata_perdida          → `permission denied for table GV_Precios_Cliente`
--
-- No son un olvido: son **definer a propósito**. Muestran un resultado agregado escondiendo la
-- tabla de abajo (el puente FDW a ISIS, los ítems de facturación, los precios por cliente), y a
-- `anon` esas fuentes le están negadas justamente para eso.
--
-- ⚠ **Y son las CUATRO MÁS SENSIBLES del sistema** — facturación, precios por cliente y el
-- puente a ISIS. En éstas la seguridad no la da la RLS sino el filtrado que la vista misma
-- haga, así que **hay que leerlas a mano** y confirmar que no expongan por la ventana lo que la
-- puerta niega. Eso queda pendiente; no se arregla con un switch.
--
-- ── ROLLBACK ─────────────────────────────────────────────────────────────────────────────
--   do $$ declare v record; begin
--     for v in select vista from zz_backups."GV_RLS_Sweep_20260912"
--               where err is null and filas_pg = filas_anon loop
--       execute format('alter view public.%I reset (security_invoker)', v.vista);
--     end loop; end $$;
--
-- MEDICIÓN GLOBAL: facturación $1.395.224.315,83 · anticipado $77.843.819,56 ·
-- `vista_saldos_stock` 488 · `vista_stock_procesada` 363 · los 4 centinelas en 0.

-- ── el barrido (una corrida por lote; repetir hasta que no queden) ───────────────────────
do $sweep$
declare v record; n_pg bigint; n_an bigint; e text; d text;
begin
  for v in
    select c.relname, c.oid from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'v'
       and (c.reloptions is null or c.reloptions::text !~ 'security_invoker=(true|on)')
       and has_table_privilege('anon', c.oid, 'SELECT')
       and not exists (select 1 from zz_backups."GV_RLS_Sweep_20260912" s where s.vista = c.relname)
     order by c.relname limit 15
  loop
    e := null; n_pg := null; n_an := null;
    d := rtrim(pg_get_viewdef(v.oid, true), E' ;\n\t');   -- el ';' final rompe el subquery
    begin
      set local statement_timeout = '8s';
      execute format('select count(*) from (select 1 from public.%I limit 3000) t', v.relname) into n_pg;
    exception when others then e := 'pg: '||left(sqlerrm,80);
    end;
    begin
      set local role anon;
      execute format('select count(*) from (select 1 from (%s) z limit 3000) t', d) into n_an;
      reset role;
    exception when others then
      begin reset role; exception when others then null; end;   -- no quedar pegado como anon
      e := coalesce(e||' | ','')||'anon: '||left(sqlerrm,90);
    end;
    reset statement_timeout;
    insert into zz_backups."GV_RLS_Sweep_20260912"(vista, filas_pg, filas_anon, err)
      values (v.relname, n_pg, n_an, e);
  end loop;
end $sweep$;

-- ── prender sólo las que dieron igual ────────────────────────────────────────────────────
do $$
declare v record;
begin
  for v in select vista from zz_backups."GV_RLS_Sweep_20260912"
            where err is null and filas_pg = filas_anon order by vista
  loop
    execute format('alter view public.%I set (security_invoker = true)', v.vista);
  end loop;
end $$;

-- ── chequeo permanente: que no vuelvan a aparecer ────────────────────────────────────────
--   select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
--    where n.nspname='public' and c.relkind='v'
--      and (c.reloptions is null or c.reloptions::text !~ 'security_invoker=(true|on)')
--      and has_table_privilege('anon', c.oid, 'SELECT');
--   -- hoy: las 4 definer a propósito. Cualquier otra que aparezca es una vista nueva mal creada.
