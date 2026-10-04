-- v26.54 (Luis, 04/10/2026): el m³/h de picking AJUSTADO por dificultad, a la vista en el Mon. Admin.
--
-- Luis: «si en un picking de dificultad alta la persona promedió 0,5 m³/h, ¿cuánto hace que mejore?» y,
-- cuando se le propuso aplicarlo sin mostrarlo: «me estás pidiendo aplicar algo que no me estás mostrando».
-- Lo que se muestra: en el pop-up de m³/h picking de cada operario (Mon. Admin → celda m³/h), por tanda,
-- dos columnas más — «Dif.» (grado 1-10 y nivel) y «Ajust. m³/h» = ritmo × (1 + 0,1 × (grado − 5)):
-- Baja ×0,6-0,7 · Media ×0,8-1,0 · Alta ×1,1-1,3 · Muy alta ×1,4-1,5 — y en la celda, chiquito, el
-- ajustado del día («→ 1,4») cuando todas sus tandas ya tienen grado. La TV de los operarios no lo lleva.
--
-- Un solo objeto nuevo, de LECTURA: el grado ya vive en GV_Picking_Tanda (caché que rehace el cron
-- gv-picking-tanda-refresh cada 10 min, v26.50); esta RPC lo devuelve por lista de tandas con la clave
-- pública, como gv_picking_pickeado. No cambia gv_picking_pickeado (cambiarle el tipo de retorno exige
-- un DROP, que desde la sesión se cuelga) ni ninguna función con centinela.
--
-- APLICADO el 04/10/2026 (sin «sí» aparte: lo pidió Luis — regla «el pedido es la autorización»).
-- Verificado como anon: E48K (104, 6 Alta ×1,1) · E89A (104, 3 Media ×0,8) · E89B (277, 3 Media ×0,8) ·
-- F22A (104, 7 Alta ×1,2) · F22E (104, 4 Media ×0,9).
--
-- Rollback, una línea:  drop function if exists public.gv_picking_grado(text[]);

create or replace function public.gv_picking_grado(p_tandas text[])
returns table (tanda text, legajo text, grado int, nivel text, multiplicador numeric, dificultad numeric,
               lineas int, paradas int, esc int, calc_at timestamptz)
language sql stable security definer set search_path = public
as $fn$
  -- v26.54 (Luis, 04/10): el grado de dificultad 1-10 de cada tanda pickeada (GV_Picking_Tanda, caché c/10 min)
  -- para que el Mon. Admin muestre el m³/h AJUSTADO = m³/h × multiplicador (1 + 0,1 × (grado − 5)). Sólo lectura.
  select t.tanda, t.legajo, t.grado, t.nivel, t.multiplicador, round(t.dificultad::numeric, 3),
         t.lineas, t.paradas, t.esc, t.calc_at
    from public."GV_Picking_Tanda" t
   where t.tanda = any (select upper(btrim(x)) from unnest(coalesce(p_tandas, '{}')) x)
   order by t.tanda, t.tp desc
$fn$;
revoke all on function public.gv_picking_grado(text[]) from public;
grant execute on function public.gv_picking_grado(text[]) to anon, authenticated;

-- Chequeo (tiene que devolver las tandas pedidas, con su grado):
--   select * from public.gv_picking_grado(array['F22A','E89A']);
-- Y como el celular / el admin (la clave pública):
--   do $$ declare n int; begin set local role anon;
--     select count(*) into n from public.gv_picking_grado(array['F22A']); reset role;
--     raise exception 'anon ve % filas', n; end $$;
