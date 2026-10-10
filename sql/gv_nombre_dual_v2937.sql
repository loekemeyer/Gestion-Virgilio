-- v29.37 (10/10/2026): "el 809E de Chef en todos lados es SOLAMENTE el Corta Queso; el de Loeke, SOLAMENTE el Corta Pizza".
-- stocks_carga_rapida tomaba el nombre de un dual del libro de stock (texto libre) y "809E LK" salía "Corta Queso X 12".
-- Ahora un dual toma el nombre de SU empresa en GV_UxB (curado por Thomas el 12/09).
create or replace function public.gv_nombre_dual(p_cod text, p_emp text)
returns text language sql stable as $$
  select nullif(btrim(regexp_replace(u.descripcion, '\s+', ' ', 'g')), '')
    from public."GV_UxB" u
   where upper(btrim(u.cod)) = upper(btrim(p_cod)) and upper(btrim(u.empresa)) = upper(btrim(p_emp))
     and exists (select 1 from public.codigos_duales d where upper(btrim(d.cod)) = upper(btrim(p_cod)))
   limit 1;
$$;
grant execute on function public.gv_nombre_dual(text, text) to anon, authenticated;

-- parche idempotente sobre la definición VIVA de refresh_stocks_carga_rapida
do $p$
declare d text := pg_get_functiondef('public.refresh_stocks_carga_rapida()'::regprocedure); n text;
begin
  if d ~ 'v29\.37-dualnom' then return; end if;
  n := replace(d, 'descripcion       = COALESCE(vna.descripcion, vsp.descripcion, scr.descripcion),',
                  'descripcion       = COALESCE(public.gv_nombre_dual(vsp.cod_base, vsp.linea), vna.descripcion, vsp.descripcion, scr.descripcion),  -- v29.37-dualnom');
  n := replace(n, E'    COALESCE(vna.descripcion, vsp.descripcion),\n',
                  E'    COALESCE(public.gv_nombre_dual(vsp.cod_base, vsp.linea), vna.descripcion, vsp.descripcion),  -- v29.37-dualnom\n');
  if (length(n) - length(replace(n, 'v29.37-dualnom', ''))) / length('v29.37-dualnom') <> 2 then
    raise exception 'refresh_stocks_carga_rapida: el texto no matchea, no se aplica';
  end if;
  execute n;
end $p$;
-- Rollback: volver a la definición sin las dos líneas "v29.37-dualnom" (COALESCE(vna.descripcion, …)).
