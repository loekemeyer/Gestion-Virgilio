-- v31.14 (Luis, 15/10): "los insumos en las tablas deberían tener «Descripcion GV» y «Descripción GP2»" y el alta
-- de un insumo puede "tomar un codigo de GP2 ya existente … ya viene con el codigo de GP2 y toda la info que tenga
-- cargada alli". Las dos son SOLO LECTURA de GP2 (anon no lee GP2: SECURITY DEFINER). GV no escribe en GP2 desde acá:
-- el vinculo lo hace gv_insumo_desde_gp2 (v29.35), igual que en Recibir insumos.

-- 1) por insumo de Virgilio vinculado: el componente de Cervantes, su descripción y su cajón.
--    Reemplaza a gv_insumo_gp2_cajon (v31.00), que no traía la descripción.
create or replace function public.gv_insumo_gp2_info()
returns table(cod text, cod_c text, desc_c text, isis text, kg_x_uni numeric, uni_x_cajon numeric, kg_x_cajon numeric)
language sql stable security definer set search_path to 'public' as $f$
  -- marcador v31.14-gp2-info
  select i.cod, c.codigo, c.descripcion, e.isis, c.kg_x_uni, c.uni_x_cajon,
         case when c.kg_x_uni > 0 and c.uni_x_cajon > 0 then round(c.kg_x_uni * c.uni_x_cajon, 2) end
    from public."Insumos" i
    join "GP2".insumo_equivalencia e on upper(trim(e.cod_virgilio)) = upper(trim(i.cod))
    join "GP2".componente c on c.id = e.componente_id
$f$;
revoke all on function public.gv_insumo_gp2_info() from public;
grant execute on function public.gv_insumo_gp2_info() to anon, authenticated;

-- 2) los componentes de GP2 de una categoría de Virgilio, para el alta «Tomar un código de GP2».
--    Mismo mapa categoría → sector que gv_gp2_componentes_ri / gv_insumo_desde_gp2. vinculado_a = el insumo de
--    Virgilio que ya lo usa (el alta lo ofrece deshabilitado: no se duplica).
create or replace function public.gv_gp2_componentes_alta(p_categoria text)
returns table(comp_id bigint, codigo text, descripcion text, nombre_gv text, unidad text,
              kg_x_uni numeric, uni_x_cajon numeric, kg_x_cajon numeric, vinculado_a text)
language sql stable security definer set search_path to 'public' as $f$
  -- marcador v31.14-gp2-alta
  select c.id, c.codigo, c.descripcion, public.gv_gp2_nombre_insumo(c.id), lower(coalesce(c.unidad_medida, 'unidad')),
         c.kg_x_uni, c.uni_x_cajon,
         case when c.kg_x_uni > 0 and c.uni_x_cajon > 0 then round(c.kg_x_uni * c.uni_x_cajon, 2) end,
         (select i.cod from "GP2".insumo_equivalencia m
            join public."Insumos" i on upper(btrim(i.cod)) = upper(btrim(m.cod_virgilio))
           where m.componente_id = c.id limit 1)
    from "GP2".componente c
    join (values ('partes_crudo',1),('parte_procesado',2),('fleje',5),('partes_plasticas',6),('cajas',11),('plastico',14)) k(cat, sec)
      on k.sec = c.sector_id
   where k.cat = p_categoria and not coalesce(c.discontinuado, false)
   order by c.codigo
$f$;
revoke all on function public.gv_gp2_componentes_alta(text) from public;
grant execute on function public.gv_gp2_componentes_alta(text) to anon, authenticated;
