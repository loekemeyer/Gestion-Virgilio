-- v29.35 (Thomas, 09/10, D43 y D44). Lo válido es GP2.
-- D44: el nombre de un FLEJE en Virgilio = «<medida de GP2> · <nombre de GP2>» (84 x 1,75 · Fleje N° 13):
--      la medida adelante sigue ordenando la lista del operario (_insMedida).
-- D43: en Recibir insumos aparecen TODOS los componentes de GP2 del rubro elegido. Elegir uno que Virgilio
--      no tiene lo da de alta con el código y el nombre de GP2 y lo vincula (importado_virgilio_componente),
--      así nadie tiene excusa para cargarlo como «insumo nuevo».
-- Rubro → sector GP2: partes_crudo 1 · parte_procesado 2 · fleje 5 · partes_plasticas 6 · cajas 11 · plastico 14.

-- BACKUP de los nombres de flejes (restore-ready):
-- update public."Insumos" set nombre = v.n from (values
--  ('25','76,5 X 2,8'),('4','46 X 2,1'),('5','38 X 0,55'),('62','75,5 X 2'),('N°13','84 X 1,75'),('N°17','95 X 1,4'),
--  ('N°19','13,6 X 0,8'),('N°2','65 X 1,25'),('N°20','11 X 0,9'),('N°22','121 X 1,20'),('N°24','42 X 1,5'),('N°41','84 x 1'),
--  ('N°45','117 X 0,8'),('N°7','60 X 2,10'),('N°74','0,8 X 64'),('N°90','Alambre p/ filtro / N° 16'),('N°92','132 x 1,5'),
--  ('N°93','1,0 x 121'),('N°94','84 x 1,5')) v(c,n) where "Insumos".cod = v.c;

create or replace function public.gv_gp2_sector_de_cat(p_cat text) returns int
language sql immutable as $$
  select case p_cat when 'partes_crudo' then 1 when 'parte_procesado' then 2 when 'fleje' then 5
                    when 'partes_plasticas' then 6 when 'cajas' then 11 when 'plastico' then 14 end
$$;

create or replace function public.gv_gp2_nombre_insumo(p_comp bigint) returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select case when c.sector_id = 5 and nullif(btrim(f.medida_mm::text), '') is not null
              then btrim(f.medida_mm::text) || ' · ' || c.descripcion else c.descripcion end
    from "GP2".componente c left join "GP2".fleje_detalle f on f.componente_id = c.id
   where c.id = p_comp
$$;
revoke all on function public.gv_gp2_nombre_insumo(bigint) from public, anon, authenticated;

-- Catálogo de GP2 para Recibir insumos (sólo lectura). cod_virgilio = el insumo de Virgilio ya vinculado (null = falta).
create or replace function public.gv_gp2_componentes_ri()
returns table (categoria text, comp_id bigint, codigo text, nombre text, unidad text, cod_virgilio text)
language sql stable security definer set search_path = public, pg_temp as $$  -- marcador v29.35-ri-gp2
  select k.cat, c.id, c.codigo, public.gv_gp2_nombre_insumo(c.id), lower(coalesce(c.unidad_medida, 'unidad')),
         (select i.cod from "GP2".importado_virgilio_componente m
            join public."Insumos" i on upper(btrim(i.cod)) = m.cod_virgilio
           where m.componente_id = c.id limit 1)
    from "GP2".componente c
    join (values ('partes_crudo',1),('parte_procesado',2),('fleje',5),('partes_plasticas',6),('cajas',11),('plastico',14)) k(cat, sec)
      on k.sec = c.sector_id
   where not coalesce(c.discontinuado, false)
$$;
revoke all on function public.gv_gp2_componentes_ri() from public;
grant execute on function public.gv_gp2_componentes_ri() to anon, authenticated;

-- Alta en Virgilio de un componente de GP2 (lo llama el celular al elegirlo en Recibir insumos). Idempotente.
create or replace function public.gv_insumo_desde_gp2(p_comp_id bigint, p_legajo text default null)
returns text language plpgsql security definer set search_path = public, pg_temp as $fn$  -- marcador v29.35-ri-gp2
declare
  v_cod text; v_c record; v_cat text;
begin
  select i.cod into v_cod from "GP2".importado_virgilio_componente m
    join public."Insumos" i on upper(btrim(i.cod)) = m.cod_virgilio
   where m.componente_id = p_comp_id limit 1;
  if v_cod is not null then return v_cod; end if;

  select c.id, btrim(c.codigo) codigo, c.sector_id into v_c
    from "GP2".componente c where c.id = p_comp_id and not coalesce(c.discontinuado, false);
  if v_c.id is null then raise exception 'GP2: el componente % no existe o está discontinuado', p_comp_id; end if;
  v_cat := case v_c.sector_id when 1 then 'partes_crudo' when 2 then 'parte_procesado' when 5 then 'fleje'
                              when 6 then 'partes_plasticas' when 11 then 'cajas' when 14 then 'plastico' end;
  if v_cat is null then raise exception 'GP2: el sector % no se recibe en Virgilio', v_c.sector_id; end if;

  -- mismo código y mismo rubro en Virgilio, sin vincular: es el mismo insumo → sólo se vincula (y toma el nombre de GP2)
  select i.cod into v_cod from public."Insumos" i
   where upper(btrim(i.cod)) = upper(v_c.codigo) and i.categoria = v_cat
     and not exists (select 1 from "GP2".importado_virgilio_componente m where m.cod_virgilio = upper(btrim(i.cod)))
   limit 1;
  if v_cod is not null then
    update public."Insumos" set nombre = public.gv_gp2_nombre_insumo(p_comp_id) where cod = v_cod;
    insert into "GP2".importado_virgilio_componente (cod_virgilio, componente_id, nota, creado_por)
    values (upper(btrim(v_cod)), p_comp_id, 'v29.35 vinculado desde Recibir insumos', 'gv-ri ' || coalesce(p_legajo, ''));
    return v_cod;
  end if;

  v_cod := v_c.codigo;
  if exists (select 1 from public."Insumos" where upper(btrim(cod)) = upper(v_cod))
     or exists (select 1 from "GP2".importado_virgilio_componente where cod_virgilio = upper(v_cod)) then
    -- el mismo código ya es otra cosa en Virgilio (los códigos de GP2 se repiten entre sectores)
    v_cod := v_cod || ' ' || case v_c.sector_id when 1 then 'CR' when 2 then 'PR' when 5 then 'FL'
                                               when 6 then 'PL' when 11 then 'CJ' when 14 then 'BO' end;
    if exists (select 1 from public."Insumos" where upper(btrim(cod)) = upper(v_cod)) then
      raise exception 'GP2: no hay un código libre para % en Virgilio', v_c.codigo;
    end if;
  end if;

  insert into public."Insumos" (cod, nombre, categoria, creado_por)
  values (v_cod, public.gv_gp2_nombre_insumo(p_comp_id), v_cat, 'GP2 · legajo ' || coalesce(nullif(btrim(p_legajo), ''), '?'));
  insert into "GP2".importado_virgilio_componente (cod_virgilio, componente_id, nota, creado_por)
  values (upper(btrim(v_cod)), p_comp_id, 'v29.35 alta desde Recibir insumos', 'gv-ri ' || coalesce(p_legajo, ''));
  return v_cod;
end;
$fn$;
revoke all on function public.gv_insumo_desde_gp2(bigint, text) from public;
grant execute on function public.gv_insumo_desde_gp2(bigint, text) to anon, authenticated;

-- D44: flejes vinculados → medida + nombre de GP2
with src as (
  select i.id, public.gv_gp2_nombre_insumo(m.componente_id) n
    from public."Insumos" i
    join "GP2".importado_virgilio_componente m on m.cod_virgilio = upper(btrim(i.cod))
   where i.categoria = 'fleje'
), u as (
  update public."Insumos" i set nombre = s.n from src s
   where i.id = s.id and s.n is not null and i.nombre is distinct from s.n
  returning i.cod, i.nombre
) select * from u order by cod;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_insumo_desde_gp2', 'funcion', 'importado_virgilio_componente',
        'Recibir insumos: elegir un componente de GP2 que falta en Virgilio lo da de alta con el nombre de GP2 y lo vincula',
        'Thomas', 'v29.35');
