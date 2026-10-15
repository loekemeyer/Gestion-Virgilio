-- v31.00 (Luis, 15/10): "en GP2 tenemos lo que significa un cajon (un cajon de batidores son 29.99kg y cada unidad
-- son 0.098kg, por lo que podemos saber cuantas unidades hay por cajon) y quiero que se vea esa conversion en GV.
-- (sigue funcionando en base a unidad de medida cajones, esto es simplemente para que se vea y quede vinculada)".
-- SOLO LECTURA: por cada insumo de Virgilio vinculado en GP2.insumo_equivalencia (match sin mayusculas ni espacios,
-- igual que la espejo), el componente de Cervantes y su cajon: kg x uni, uni x cajon y kg x cajon (= kg x uni x uni x cajon).
-- No toca stock ni unidades de Virgilio. SECURITY DEFINER porque anon no lee GP2.
create or replace function public.gv_insumo_gp2_cajon()
returns table(cod text, cod_c text, kg_x_uni numeric, uni_x_cajon numeric, kg_x_cajon numeric)
language sql stable security definer set search_path to 'public' as $f$
  -- marcador v31.00-cajon-gp2
  select i.cod, c.codigo, c.kg_x_uni, c.uni_x_cajon,
         case when c.kg_x_uni > 0 and c.uni_x_cajon > 0 then round(c.kg_x_uni * c.uni_x_cajon, 2) end
    from public."Insumos" i
    join "GP2".insumo_equivalencia e on upper(trim(e.cod_virgilio)) = upper(trim(i.cod))
    join "GP2".componente c on c.id = e.componente_id
$f$;
revoke all on function public.gv_insumo_gp2_cajon() from public;
grant execute on function public.gv_insumo_gp2_cajon() to anon, authenticated;
