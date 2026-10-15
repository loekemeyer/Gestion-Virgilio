-- v31.14 (Luis, 15/10/2026): la canónica de empaque (GV_Rack_CxM) guarda las TRES relaciones:
--   cxm          = inner × master   (cajas por master; el nombre de la columna se mantiene: la leen la planimetría y el front)
--   uni_x_inner  = unidades × inner (caja)
--   uni_x_master = unidades × master
-- «Relaciones simples pero que cubren todos los casos de uso para cuando, por ejemplo, los productos vienen en
--  una caja grande (MC) sin inner.»
--
-- Casos:
--   con inner y master   → cxm, uni_x_inner, uni_x_master (si están las tres: uni_x_master = cxm × uni_x_inner)
--   MC SIN inner         → sin_inner = true, cxm vacío, uni_x_master cargado (en racks cada «caja» es una master: 1:1)
--   SIN master (suelto)  → sin_master = true, cxm y uni_x_master vacíos
-- Las unidades se cargan desde Importados_Volumen SÓLO donde su cociente coincide con la canónica; los que no
-- coinciden siguen en gv_cxm_conflictos hasta que Luis decida (D8).

create table if not exists zz_backups."GV_Rack_CxM_v3114" as select * from public."GV_Rack_CxM";

alter table public."GV_Rack_CxM" add column if not exists uni_x_inner numeric;
alter table public."GV_Rack_CxM" add column if not exists uni_x_master numeric;
alter table public."GV_Rack_CxM" add column if not exists sin_inner boolean not null default false;
alter table public."GV_Rack_CxM" drop constraint if exists gv_rack_cxm_valor;
alter table public."GV_Rack_CxM" add constraint gv_rack_cxm_valor check (
      (sin_master and not sin_inner and cxm is null and uni_x_master is null)
   or (sin_inner and not sin_master and cxm is null and uni_x_inner is null and uni_x_master > 0)
   or (not sin_master and not sin_inner and cxm > 0)
);
alter table public."GV_Rack_CxM" add constraint gv_rack_cxm_cierra check (
   cxm is null or uni_x_inner is null or uni_x_master is null or uni_x_master = cxm * uni_x_inner
);
alter table public."GV_Rack_CxM" add constraint gv_rack_cxm_unidades_pos check (
   coalesce(uni_x_inner, 1) > 0 and coalesce(uni_x_master, 1) > 0
);
comment on column public."GV_Rack_CxM".cxm is 'inner × master (cajas por master). Vacío si sin_master o sin_inner.';
comment on column public."GV_Rack_CxM".uni_x_inner is 'unidades × inner (caja).';
comment on column public."GV_Rack_CxM".uni_x_master is 'unidades × master. Si están las tres: = cxm × uni_x_inner.';
comment on column public."GV_Rack_CxM".sin_inner is 'La master viene SIN inner (unidades sueltas adentro): en racks cada caja es una master.';

-- el ingreso a racks (gv_rack_cxm_anotar, protegida: no se toca) puede cambiar cxm. Si las unidades dejan de cerrar,
-- se limpian (el conteo físico manda sobre la planilla) y la diferencia aparece en gv_cxm_conflictos. Así el ingreso
-- nunca choca con gv_rack_cxm_cierra. Y si vuelve a tener inner, deja de ser sin_inner.
create or replace function public.gv_rack_cxm_coherente()
 returns trigger language plpgsql set search_path to 'public'
as $function$
begin
  if new.cxm is not null and new.sin_inner then new.sin_inner := false; end if;
  if new.cxm is not null and new.uni_x_inner is not null and new.uni_x_master is not null
     and new.uni_x_master <> new.cxm * new.uni_x_inner then
    new.uni_x_inner := null; new.uni_x_master := null;
  end if;
  if new.sin_master then new.uni_x_master := null; end if;
  return new;
end $function$;
create or replace trigger trg_gv_rack_cxm_coherente
  before insert or update on public."GV_Rack_CxM"
  for each row execute function public.gv_rack_cxm_coherente();

-- unidades de importación donde coinciden con la canónica
update public."GV_Rack_CxM" g
   set uni_x_inner = v.uni_inner, uni_x_master = v.uni_master
  from public."Importados_Volumen" v
 where upper(btrim(v.cod)) = g.cod and v.uni_inner > 0 and v.uni_master > 0
   and g.cxm is not null and v.uni_master = g.cxm * v.uni_inner
   and g.uni_x_inner is null and g.uni_x_master is null;

-- MC sin inner de importación (uni_inner = 0 = «viene suelto», Thomas 29/09) que no estaban en la canónica
insert into public."GV_Rack_CxM"(cod, emp, cxm, uni_x_master, sin_inner, fuente)
select upper(btrim(v.cod)), coalesce(public.gv_empresa_de_articulo(upper(btrim(v.cod))), 'LK'), null, v.uni_master, true,
       'Importados_Volumen (v31.14, sin inner)'
  from public."Importados_Volumen" v
 where v.uni_inner = 0 and v.uni_master > 0 and upper(btrim(v.cod)) !~ '\dE?L$'
   and not exists (select 1 from public."GV_Rack_CxM" g where g.cod = upper(btrim(v.cod)))
on conflict (cod, emp) do nothing;

-- importación da de alta / corrige un código → entra a la canónica con sus tres relaciones (nunca pisa lo que hay)
create or replace function public.gv_cxm_desde_importados_volumen()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare v_cod text := upper(btrim(new.cod));
begin
  if v_cod ~ '\dE?L$' or not (new.uni_master > 0) then return new; end if;
  if not exists (select 1 from public."GV_Rack_CxM" g where g.cod = v_cod) then
    if new.uni_inner = 0 then
      insert into public."GV_Rack_CxM"(cod, emp, cxm, uni_x_master, sin_inner, fuente)
      values (v_cod, coalesce(public.gv_empresa_de_articulo(v_cod), 'LK'), null, new.uni_master, true, 'Importados_Volumen (alta, sin inner)')
      on conflict (cod, emp) do nothing;
    elsif new.uni_inner > 0 and new.uni_master % new.uni_inner = 0 then
      insert into public."GV_Rack_CxM"(cod, emp, cxm, uni_x_inner, uni_x_master, fuente)
      values (v_cod, coalesce(public.gv_empresa_de_articulo(v_cod), 'LK'), new.uni_master / new.uni_inner, new.uni_inner, new.uni_master, 'Importados_Volumen (alta)')
      on conflict (cod, emp) do nothing;
    end if;
  elsif new.uni_inner > 0 then
    -- ya está: sólo completa las unidades si cierran con su cxm
    update public."GV_Rack_CxM" g set uni_x_inner = new.uni_inner, uni_x_master = new.uni_master
     where g.cod = v_cod and g.cxm is not null and new.uni_master = g.cxm * new.uni_inner
       and g.uni_x_inner is null and g.uni_x_master is null;
  end if;
  return new;
end $function$;

-- conflictos: ahora también compara las unidades
create or replace view public.gv_cxm_conflictos with (security_invoker = true) as
with can as (select cod, min(cxm) cxm, bool_or(sin_master) sin_master, bool_or(sin_inner) sin_inner,
                    min(uni_x_inner) uni_x_inner, min(uni_x_master) uni_x_master, min(fuente) fuente
               from public."GV_Rack_CxM" group by cod),
iv as (select upper(btrim(cod)) cod, uni_master, uni_inner from public."Importados_Volumen"),
pr as (select upper(btrim(x)) cod, min(uni_master_box / nullif(uni_inner_box,0)) r
       from impo_comex.productos_referencia, unnest(array[cod_lk, cod_ch]) x
       where uni_master_box > 0 and uni_inner_box > 0 and uni_master_box <> uni_inner_box and x is not null group by 1),
art as (select upper(btrim("Cod_Art")) cod, max("Cajas_x_Master") v from public."Articulos Virgilio X Tallerista" where "Cajas_x_Master" > 0 group by 1)
select can.cod, can.cxm as canonica, can.sin_master, can.fuente,
       case when iv.uni_inner = 0 then 'suelto' when iv.uni_inner > 0 then round(iv.uni_master / iv.uni_inner, 2)::text end as importados_volumen,
       iv.uni_master, iv.uni_inner, round(pr.r, 2) as comex, art.v as articulos_viejo,
       can.sin_inner, can.uni_x_inner, can.uni_x_master
from can left join iv on iv.cod = can.cod left join pr on pr.cod = can.cod left join art on art.cod = can.cod
where (iv.uni_inner > 0 and iv.uni_master > 0 and (can.cxm is null or abs(iv.uni_master / iv.uni_inner - can.cxm) > 0.001))
   or (iv.uni_inner = 0 and not can.sin_inner)
   or (pr.r is not null and (can.cxm is null or abs(pr.r - can.cxm) > 0.001))
   or (art.v is not null and (can.cxm is null or abs(art.v - can.cxm) > 0.001));
revoke select on public.gv_cxm_conflictos from anon, authenticated;
