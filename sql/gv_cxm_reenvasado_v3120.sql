-- v31.20 (Luis, 15/10/2026): lo que se REENVASA entra de importación como INSUMO.
-- «Si hay que reenvasar el artículo, no entra de impo directo para la venta: entra como insumo y después se manda a la
--  fábrica o a un proveedor para reenvasar. 440E en racks siempre es insumo cuando entra de impo directo. Si García
--  entrega (ése es el terminado) puede ir a racks.»
--
-- Consecuencias en la canónica de empaque (GV_Rack_CxM = cómo está el TERMINADO en racks / góndola):
--   · Importados_Volumen describe cómo viene la IMPORTACIÓN. Si el importado entra como insumo (está en
--     GV_Importados_Insumo_Map o viene suelto, uni_inner = 0), sus unidades NO son las del terminado: no es conflicto,
--     la pantalla no las pisa y el alta automática desde importación no crea fila de producto.
--   · «Sin inner» ya no se ofrece para un producto: una master con unidades sueltas es un insumo a reenvasar.
-- Insumo reenvasado = public.gv_cxm_es_insumo_impo(cod).

create or replace function public.gv_cxm_es_insumo_impo(p_cod text)
 returns boolean language sql stable set search_path to 'public'
as $function$
  select exists (select 1 from public."GV_Importados_Insumo_Map" m where upper(btrim(m.importado_cod)) = upper(btrim(p_cod)))
      or exists (select 1 from public."Importados_Volumen" v where upper(btrim(v.cod)) = upper(btrim(p_cod)) and v.uni_inner = 0)
$function$;
grant execute on function public.gv_cxm_es_insumo_impo(text) to anon, authenticated;

create or replace view public.gv_cxm_estado with (security_invoker = true) as
with st as (
  select upper(regexp_replace(btrim(cod_art), '\s+(LK|CH)$', '')) cod, min(descripcion) descripcion, min(empresa) empresa,
         sum(coalesce(racks,0) + coalesce(racks_ch,0)) racks, sum(coalesce(a_guardar,0) + coalesce(excedente,0)) a_guardar,
         sum(coalesce(terminado,0)) gondola
    from public.vista_saldos_stock group by 1),
imp as (select distinct upper(btrim(cod_art)) cod from public."Importados" where coalesce(activo, true)),
can as (select cod, min(cxm) cxm, min(uni_x_inner) uni_x_inner, min(uni_x_master) uni_x_master,
               bool_or(sin_inner) sin_inner, bool_or(sin_master) sin_master, min(fuente) fuente, min(nota) nota, max(actualizado_en) actualizado_en
          from public."GV_Rack_CxM" group by cod),
iv as (select upper(btrim(cod)) cod, min(uni_master) uni_master, min(uni_inner) uni_inner from public."Importados_Volumen" group by 1),
mp as (select distinct upper(btrim(importado_cod)) cod from public."GV_Importados_Insumo_Map"),
art as (select upper(btrim("Cod_Art")) cod, max(nullif("Uni_x_Caja",0)) uxc from public."Articulos Virgilio X Tallerista" group by 1),
u as (select cod from st where racks > 0 or a_guardar > 0 union select cod from imp)
select u.cod, st.descripcion, st.empresa, round(coalesce(st.racks,0)) racks, round(coalesce(st.a_guardar,0)) a_guardar,
       round(coalesce(st.gondola,0)) gondola, (imp.cod is not null) importado,
       can.cxm, can.uni_x_inner, can.uni_x_master, coalesce(can.sin_inner,false) sin_inner, coalesce(can.sin_master,false) sin_master,
       can.fuente, can.nota, can.actualizado_en,
       iv.uni_master iv_uni_master, iv.uni_inner iv_uni_inner, art.uxc sugerido_uni_x_inner,
       case
         when can.cod is null then 'sin dato'
         when (mp.cod is null and coalesce(iv.uni_inner, 1) <> 0)
              and iv.uni_inner > 0 and iv.uni_master > 0 and (can.cxm is null or iv.uni_master <> can.cxm * iv.uni_inner) then 'no coincide con importación'
         when can.sin_master then null
         when can.cxm is not null and can.uni_x_inner is not null and can.uni_x_master is not null then null
         else 'incompleto'
       end as pendiente,
       (mp.cod is not null or iv.uni_inner = 0) as importa_como_insumo
  from u left join st on st.cod = u.cod left join imp on imp.cod = u.cod left join can on can.cod = u.cod
  left join iv on iv.cod = u.cod left join mp on mp.cod = u.cod left join art on art.cod = u.cod;
grant select on public.gv_cxm_estado to anon, authenticated;

create or replace view public.gv_cxm_conflictos with (security_invoker = true) as
with can as (select cod, min(cxm) cxm, bool_or(sin_master) sin_master, bool_or(sin_inner) sin_inner,
                    min(uni_x_inner) uni_x_inner, min(uni_x_master) uni_x_master, min(fuente) fuente
               from public."GV_Rack_CxM" group by cod),
iv as (select upper(btrim(cod)) cod, uni_master, uni_inner from public."Importados_Volumen"
        where not public.gv_cxm_es_insumo_impo(cod)),
pr as (select upper(btrim(x)) cod, min(uni_master_box / nullif(uni_inner_box,0)) r
       from impo_comex.productos_referencia, unnest(array[cod_lk, cod_ch]) x
       where uni_master_box > 0 and uni_inner_box > 0 and uni_master_box <> uni_inner_box and x is not null
         and not public.gv_cxm_es_insumo_impo(x) group by 1),
art as (select upper(btrim("Cod_Art")) cod, max("Cajas_x_Master") v from public."Articulos Virgilio X Tallerista" where "Cajas_x_Master" > 0 group by 1)
select can.cod, can.cxm as canonica, can.sin_master, can.fuente,
       case when iv.uni_inner = 0 then 'suelto' when iv.uni_inner > 0 then round(iv.uni_master / iv.uni_inner, 2)::text end as importados_volumen,
       iv.uni_master, iv.uni_inner, round(pr.r, 2) as comex, art.v as articulos_viejo,
       can.sin_inner, can.uni_x_inner, can.uni_x_master
from can left join iv on iv.cod = can.cod left join pr on pr.cod = can.cod left join art on art.cod = can.cod
where (iv.uni_inner > 0 and iv.uni_master > 0 and (can.cxm is null or abs(iv.uni_master / iv.uni_inner - can.cxm) > 0.001))
   or (pr.r is not null and (can.cxm is null or abs(pr.r - can.cxm) > 0.001))
   or (art.v is not null and (can.cxm is null or abs(art.v - can.cxm) > 0.001));
revoke select on public.gv_cxm_conflictos from anon, authenticated;

-- alta automática desde importación: nunca para lo que entra como insumo, y ya no crea «sin inner»
create or replace function public.gv_cxm_desde_importados_volumen()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare v_cod text := upper(btrim(new.cod));
begin
  if v_cod ~ '\dE?L$' or not (new.uni_master > 0) or not (new.uni_inner > 0) then return new; end if;
  if public.gv_cxm_es_insumo_impo(v_cod) then return new; end if;   -- v31.20: se reenvasa → es insumo
  if not exists (select 1 from public."GV_Rack_CxM" g where g.cod = v_cod) then
    if new.uni_master % new.uni_inner = 0 then
      insert into public."GV_Rack_CxM"(cod, emp, cxm, uni_x_inner, uni_x_master, fuente)
      values (v_cod, coalesce(public.gv_empresa_de_articulo(v_cod), 'LK'), new.uni_master / new.uni_inner, new.uni_inner, new.uni_master, 'Importados_Volumen (alta)')
      on conflict (cod, emp) do nothing;
    end if;
  else
    update public."GV_Rack_CxM" g set uni_x_inner = new.uni_inner, uni_x_master = new.uni_master
     where g.cod = v_cod and g.cxm is not null and new.uni_master = g.cxm * new.uni_inner
       and g.uni_x_inner is null and g.uni_x_master is null;
  end if;
  return new;
end $function$;

-- gv_cxm_guardar: no carga «sin inner» y no pisa Importados_Volumen de lo que se reenvasa
create or replace function public.gv_cxm_guardar(p_cod text, p_cxm numeric, p_uni_x_inner numeric, p_uni_x_master numeric,
                                                 p_sin_inner boolean default false, p_sin_master boolean default false, p_nota text default null)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_cod text := upper(regexp_replace(btrim(coalesce(p_cod,'')), '\s+(LK|CH)$', ''));
  v_cxm numeric := nullif(p_cxm, 0); v_ui numeric := nullif(p_uni_x_inner, 0); v_um numeric := nullif(p_uni_x_master, 0);
  v_si boolean := coalesce(p_sin_inner, false); v_sm boolean := coalesce(p_sin_master, false);
  v_quien text := coalesce(nullif(auth.jwt() ->> 'email', ''), session_user::text);
  v_n int; r record;
begin
  perform public.gv_rpc_guard('gv_cxm_guardar');
  if v_cod = '' then raise exception 'Falta el código'; end if;
  if v_si and v_sm then raise exception 'No puede ser «sin inner» y «sin master» a la vez'; end if;
  if v_si then raise exception 'Una master con unidades sueltas entra como INSUMO (se reenvasa): no se carga como producto (Luis 15/10)'; end if;
  if v_sm then v_cxm := null; v_um := null; end if;
  if v_si then
    v_cxm := null; v_ui := null;
    if v_um is null then raise exception 'Sin inner: falta cuántas unidades trae la master'; end if;
  end if;
  if not v_si and not v_sm then
    if v_cxm is null and v_ui > 0 and v_um > 0 then
      if v_um % v_ui <> 0 then raise exception 'Unidades × master (%) no se divide en unidades × inner (%)', v_um, v_ui; end if;
      v_cxm := v_um / v_ui;
    end if;
    if v_cxm is null then raise exception 'Faltan datos: con dos de los tres sale el tercero'; end if;
    if v_cxm <> trunc(v_cxm) or v_cxm <= 0 then raise exception 'Inner × master tiene que ser un entero positivo'; end if;
    if v_ui is not null and v_um is not null and v_um <> v_cxm * v_ui then
      raise exception 'No cierra: % × % = %, no %', v_cxm, v_ui, v_cxm * v_ui, v_um;
    end if;
    if v_ui is null and v_um is not null then
      if v_um % v_cxm <> 0 then raise exception 'Unidades × master (%) no se divide en % inner', v_um, v_cxm; end if;
      v_ui := v_um / v_cxm;
    end if;
    if v_um is null and v_ui is not null then v_um := v_cxm * v_ui; end if;
  end if;

  update public."GV_Rack_CxM"
     set cxm = v_cxm, uni_x_inner = v_ui, uni_x_master = v_um, sin_inner = v_si, sin_master = v_sm,
         fuente = 'a mano (' || v_quien || ')', nota = coalesce(nullif(btrim(p_nota), ''), nota), actualizado_en = now()
   where cod = v_cod;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    insert into public."GV_Rack_CxM"(cod, emp, cxm, uni_x_inner, uni_x_master, sin_inner, sin_master, fuente, nota)
    values (v_cod, coalesce(public.gv_empresa_de_articulo(v_cod), 'LK'), v_cxm, v_ui, v_um, v_si, v_sm,
            'a mano (' || v_quien || ')', nullif(btrim(p_nota), ''));
  end if;

  -- importación: mismas unidades (sin inner = uni_inner 0). Sin master no se toca (es de nacionales).
  -- v31.20: lo que entra como insumo (se reenvasa) tiene en Importados_Volumen el empaque de la IMPORTACIÓN: no se pisa
  if not v_sm and v_um is not null and not public.gv_cxm_es_insumo_impo(v_cod) then
    update public."Importados_Volumen"
       set uni_master = v_um, uni_inner = case when v_si then 0 else v_ui end, actualizado = now()
     where upper(btrim(cod)) = v_cod
       and (uni_master is distinct from v_um or uni_inner is distinct from (case when v_si then 0 else v_ui end));
  end if;

  select * into r from public.gv_cxm_estado where cod = v_cod;
  return jsonb_build_object('ok', true, 'cod', v_cod, 'cxm', v_cxm, 'uni_x_inner', v_ui, 'uni_x_master', v_um,
                            'sin_inner', v_si, 'sin_master', v_sm, 'pendiente', r.pendiente);
end $function$;
