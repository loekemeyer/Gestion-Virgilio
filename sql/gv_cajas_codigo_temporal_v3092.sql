-- v30.92 (Luis, 15/10, D8): "que aparezca mientras haya" — el aviso de cajas con código temporal sin cruzar.
-- Dos casos (los cruza Naza):
--   · virgilio  — una caja que el operario escribió a mano y quedó TMP-… en Insumos (falta aceptarla con su código real);
--   · cervantes — una caja de GP2 Sector Caja con código provisorio CJ<n> (falta su código de Cervantes).
-- SECURITY DEFINER porque anon no lee GP2; sólo devuelve código, nombre y motivo.
create or replace function public.gv_cajas_codigo_temporal()
returns table(lado text, cod text, nombre text, motivo text)
language sql stable security definer set search_path to 'public' as $f$
  -- marcador v30.92-cajas-tmp
  select 'virgilio'::text, i.cod, i.nombre, 'escrita a mano: aceptarla con su código en Stock y Compras → Insumos'::text
    from public."Insumos" i
   where i.categoria = 'cajas' and i.cod ~* '^TMP-'
  union all
  select 'cervantes'::text, c.codigo, c.descripcion, 'código de Cervantes provisorio'::text
    from "GP2".componente c
   where c.sector_id = 11 and c.codigo ~* '^CJ' and not coalesce(c.discontinuado, false)
  order by 1 desc, 2
$f$;
revoke all on function public.gv_cajas_codigo_temporal() from public;
grant execute on function public.gv_cajas_codigo_temporal() to anon, authenticated;
