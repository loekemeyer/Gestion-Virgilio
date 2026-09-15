-- ============================================================================
-- v18.23 — DOS ARREGLOS DE PERMISOS sobre public."GV_Web_Cancelados" (Virgilio).
-- Aparecieron midiendo, mientras se armaba "Modificar Pedidos". Los dos son
-- aditivos: un policy de lectura y dos grants. No cambian ninguna fila.
--
-- (1) LA APP NO VEÍA LAS ANULACIONES. La tabla quedó con RLS prendida y CERO
--     policies. Las tres vistas que la usan -- gv_ppp_web_estado,
--     gv_ppp_en_salida y gv_fac_armado_sin_facturar -- son `security_invoker`,
--     o sea que corren con el rol del que consulta: `anon` y `authenticated`
--     veían 0 filas de cancelados y la anulación no tenía NINGÚN efecto en la
--     pantalla. Las funciones SECURITY DEFINER que la leen (gv_pedido_anular,
--     gv_ppp_np_cancelar, gv_ppp_np_desarmar, gv_pedidos_web_excluidos) sí la
--     veían, así que el efecto se veía a medias y era difícil de notar.
--     Medición (NP LK 0052, order_id 1375, cancelada el 15/09):
--       postgres      -> gv_ppp_web_estado.estado = 'desarmado'
--       authenticated -> gv_ppp_web_estado.estado = 'sin_programar'   ← el bug
--     Después del policy las dos dicen lo mismo.
--
-- (2) LK NO PODÍA LEER LA VISTA POR FDW. `gv_pedido_web_estado_pagina` la lee
--     LK con el rol `lk_ppp_reader`, que tenía el grant de la vista pero no el
--     de esta tabla nueva, así que cualquier lectura desde LK cortaba con
--       ERROR 42501: permission denied for table GV_Web_Cancelados
--     Eso rompía `edit_order_fast` de LK -- la RPC con la que un CLIENTE edita
--     su pedido desde la página, que usa esa vista como guarda de "ya
--     facturado" -- y rompía también la guarda del guardado nuevo.
-- ============================================================================

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                   and tablename='GV_Web_Cancelados' and policyname='gv_web_cancelados_lee') then
    create policy gv_web_cancelados_lee on public."GV_Web_Cancelados"
      for select to anon, authenticated, lk_ppp_reader, ch_ppp_reader using (true);
  end if;
end $$;

grant select on public."GV_Web_Cancelados" to lk_ppp_reader, ch_ppp_reader;

-- Comprobación: los dos roles tienen que leer lo mismo.
-- do $$
-- declare a text; b text;
-- begin
--   select e.estado into a from public.gv_ppp_web_estado e where e.order_id = 1375 limit 1;
--   set local role authenticated;
--   select e.estado into b from public.gv_ppp_web_estado e where e.order_id = 1375 limit 1;
--   reset role;
--   if a is distinct from b then raise exception 'SIGUE MAL: postgres=% authenticated=%', a, b; end if;
-- end $$;

-- Y el barrido de las que queden con RLS prendida y sin ningún policy, que es el
-- mismo pozo: la tabla existe, el grant está, y aun así la app lee cero.
-- select c.relname
--   from pg_class c join pg_namespace n on n.oid = c.relnamespace
--  where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
--    and has_table_privilege('anon', c.oid, 'SELECT')
--    and not exists (select 1 from pg_policies p
--                     where p.schemaname = 'public' and p.tablename = c.relname);
