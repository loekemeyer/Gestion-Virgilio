-- v31.12 (Luis, 15/10/2026): UNA tabla canónica para las CAJAS POR MASTER (cxm) de cada artículo.
-- «Hay que hacer una tabla que sea la canónica y unificar para que todas las funciones y cosas que
--  busquen el dato lo busquen de ahí.»
--
-- La canónica es GV_Rack_CxM (ya era la fuente de racks desde la v22.77: la planimetría deriva sus MC
-- de ahí). Se extiende a TODO el sistema. Las otras fuentes que había:
--   · "Articulos Virgilio X Tallerista"."Cajas_x_Master"  (9 valores) → RETIRADA como fuente (se migra acá)
--   · ratio inner/master calculado de la planimetría en el front → RETIRADO (era GV_Rack_CxM con ruido de
--     las filas «a contar»: por eso el 368E daba 3,5/4)
--   · "Importados_Volumen".uni_master / uni_inner           → siguen siendo UNIDADES (importación); su
--     cociente se compara contra la canónica en gv_cxm_conflictos y alimenta códigos nuevos (trigger)
--   · impo_comex.productos_referencia (planilla COMEX)       → sólo referencia, en gv_cxm_conflictos
--   · Insumos_Factores (MC de insumos, en unidades)          → otro dato, no se toca
--
-- Nada cambia de comportamiento: se cargó con el MISMO valor que la app usaba hoy.

-- 0) backups
create table if not exists zz_backups."GV_Rack_CxM_v3112" as select * from public."GV_Rack_CxM";
create table if not exists zz_backups."Articulos_cxm_v3112" as
  select id, "Cod_Art", "Cajas_x_Master" from public."Articulos Virgilio X Tallerista" where coalesce("Cajas_x_Master",0) <> 0;

-- 1) columnas: sin_master (va suelto, 1:1), fuente y nota; cxm puede ir vacío sólo si sin_master
alter table public."GV_Rack_CxM" add column if not exists sin_master boolean not null default false;
alter table public."GV_Rack_CxM" add column if not exists fuente text;
alter table public."GV_Rack_CxM" add column if not exists nota text;
alter table public."GV_Rack_CxM" alter column cxm drop not null;
alter table public."GV_Rack_CxM" drop constraint if exists "GV_Rack_CxM_cxm_check";
alter table public."GV_Rack_CxM" add constraint gv_rack_cxm_valor
  check ((sin_master and cxm is null) or (not sin_master and cxm > 0));
update public."GV_Rack_CxM" set fuente = 'ingreso a racks' where fuente is null;
comment on table public."GV_Rack_CxM" is 'CANÓNICA (v31.12): cajas (inner) por master de cada artículo. Toda pantalla/función que necesite el dato lee de acá. sin_master = va suelto (1:1).';

-- 2) carga inicial (sólo códigos que NO tenían fila)
-- 2a) lo que la app leía de Articulos.Cajas_x_Master (entero)
insert into public."GV_Rack_CxM"(cod, emp, cxm, fuente)
select upper(btrim(a."Cod_Art")), coalesce(public.gv_empresa_de_articulo(upper(btrim(a."Cod_Art"))), 'LK'), max(a."Cajas_x_Master"),
       'Articulos Virgilio X Tallerista (v31.12)'
from public."Articulos Virgilio X Tallerista" a
where a."Cajas_x_Master" > 0 and a."Cajas_x_Master" = trunc(a."Cajas_x_Master")
  and not exists (select 1 from public."GV_Rack_CxM" g where g.cod = upper(btrim(a."Cod_Art")))
group by 1, 2
on conflict (cod, emp) do nothing;
-- 2b) importación: uni_master / uni_inner entero (sin L: el stock no usa la L)
insert into public."GV_Rack_CxM"(cod, emp, cxm, fuente)
select upper(btrim(v.cod)), coalesce(public.gv_empresa_de_articulo(upper(btrim(v.cod))), 'LK'), v.uni_master / v.uni_inner,
       'Importados_Volumen (v31.12)'
from public."Importados_Volumen" v
where v.uni_master > 0 and v.uni_inner > 0 and v.uni_master % v.uni_inner = 0
  and upper(btrim(v.cod)) !~ '\dE?L$'
  and not exists (select 1 from public."GV_Rack_CxM" g where g.cod = upper(btrim(v.cod)))
on conflict (cod, emp) do nothing;
-- 2c) sin master confirmados (docs/RACKS-MASTER-CAJAS.md, 09/08): se bajan sueltos
insert into public."GV_Rack_CxM"(cod, emp, cxm, sin_master, fuente)
select c, 'LK', null, true, 'sin master confirmado (docs/RACKS-MASTER-CAJAS.md)'
from unnest(array['505I','504','505','501']) c
where not exists (select 1 from public."GV_Rack_CxM" g where g.cod = c)
on conflict (cod, emp) do nothing;

-- 3) gv_rack_cxm_anotar: el ingreso a racks sigue anotando, ahora con fuente
create or replace function public.gv_rack_cxm_anotar(p_cod text, p_emp text, p_inner numeric, p_master numeric)
 returns void language sql security definer set search_path to 'public'
as $function$
 insert into public."GV_Rack_CxM"(cod, emp, cxm, sin_master, fuente)
 select upper(btrim(p_cod)), upper(p_emp), p_inner / p_master, false, 'ingreso a racks'
 where coalesce(p_master,0) > 0 and coalesce(p_inner,0) > 0 and p_inner % p_master = 0
 on conflict (cod, emp) do update set cxm = excluded.cxm, sin_master = false, fuente = excluded.fuente, actualizado_en = now()
$function$;

-- 4) importación da de alta un código con uni_master/uni_inner → si no está en la canónica, entra
create or replace function public.gv_cxm_desde_importados_volumen()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  if new.uni_master > 0 and new.uni_inner > 0 and new.uni_master % new.uni_inner = 0
     and upper(btrim(new.cod)) !~ '\dE?L$'
     and not exists (select 1 from public."GV_Rack_CxM" g where g.cod = upper(btrim(new.cod))) then
    insert into public."GV_Rack_CxM"(cod, emp, cxm, fuente)
    values (upper(btrim(new.cod)), coalesce(public.gv_empresa_de_articulo(upper(btrim(new.cod))), 'LK'),
            new.uni_master / new.uni_inner, 'Importados_Volumen (alta)')
    on conflict (cod, emp) do nothing;
  end if;
  return new;
end $function$;
create or replace trigger trg_cxm_desde_importados_volumen
  after insert or update of uni_master, uni_inner on public."Importados_Volumen"
  for each row execute function public.gv_cxm_desde_importados_volumen();

-- 5) vista de bajadas: cajas_x_master sale de la canónica
create or replace view public.vista_racks_bajadas_pendientes with (security_invoker = true) as
 SELECT rb.id, rb.orden_id, rb.cod_art, rb.descripcion, rb.cajas, rb.estado, rb.creada_por, rb.ts, rb.sector,
    COALESCE((SELECT max(g.cxm) FROM "GV_Rack_CxM" g WHERE g.cod = upper(TRIM(BOTH FROM rb.cod_art))), (0)::numeric) AS cajas_x_master,
    COALESCE(a."Uni_x_Caja", 0) AS uni_x_caja
   FROM ("Racks_Bajadas" rb
     LEFT JOIN LATERAL ( SELECT "Articulos Virgilio X Tallerista"."Uni_x_Caja"
           FROM "Articulos Virgilio X Tallerista"
          WHERE (upper(TRIM(BOTH FROM "Articulos Virgilio X Tallerista"."Cod_Art")) = upper(TRIM(BOTH FROM rb.cod_art)))
         LIMIT 1) a ON (true))
  WHERE (rb.estado = 'propuesta'::text)
  ORDER BY rb.ts;

-- 6) donde las otras fuentes NO coinciden con la canónica (para que Luis decida)
create or replace view public.gv_cxm_conflictos with (security_invoker = true) as
with can as (select cod, min(cxm) cxm, bool_or(sin_master) sin_master, min(fuente) fuente from public."GV_Rack_CxM" group by cod),
iv as (select upper(btrim(cod)) cod, uni_master, uni_inner from public."Importados_Volumen"),
pr as (select upper(btrim(x)) cod, min(uni_master_box / nullif(uni_inner_box,0)) r
       from impo_comex.productos_referencia, unnest(array[cod_lk, cod_ch]) x
       where uni_master_box > 0 and uni_inner_box > 0 and uni_master_box <> uni_inner_box and x is not null group by 1),
art as (select upper(btrim("Cod_Art")) cod, max("Cajas_x_Master") v from public."Articulos Virgilio X Tallerista" where "Cajas_x_Master" > 0 group by 1)
select can.cod, can.cxm as canonica, can.sin_master, can.fuente,
       case when iv.uni_inner = 0 then 'suelto' when iv.uni_inner > 0 then round(iv.uni_master / iv.uni_inner, 2)::text end as importados_volumen,
       iv.uni_master, iv.uni_inner, round(pr.r, 2) as comex, art.v as articulos_viejo
from can left join iv on iv.cod = can.cod left join pr on pr.cod = can.cod left join art on art.cod = can.cod
where (iv.uni_inner > 0 and iv.uni_master > 0 and (can.cxm is null or abs(iv.uni_master / iv.uni_inner - can.cxm) > 0.001))
   or (iv.uni_inner = 0 and can.cxm is not null)
   or (pr.r is not null and (can.cxm is null or abs(pr.r - can.cxm) > 0.001))
   or (art.v is not null and (can.cxm is null or abs(art.v - can.cxm) > 0.001));
-- sin grant a anon/authenticated: cruza impo_comex (que no es público). Se consulta desde la sesión (MCP).
revoke select on public.gv_cxm_conflictos from anon, authenticated;

comment on column public."Articulos Virgilio X Tallerista"."Cajas_x_Master" is
  'RETIRADA como fuente (v31.12): las cajas por master viven en GV_Rack_CxM. No leer ni escribir acá.';

-- 7) centinelas (aplicadas con la etiqueta 'v31.07': la sesión arrancó con ese número y el guardián no deja
--    retocar GV_Reglas_Centinela sin un «sí»; son estas 3 filas)
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
 ('vista_racks_bajadas_pendientes','vista','GV_Rack_CxM','Las cajas por master salen de la canónica GV_Rack_CxM, no de Articulos.Cajas_x_Master','Luis','v31.12'),
 ('gv_rack_cxm_anotar','funcion','sin_master = false','El ingreso a racks anota cajas por master en la canónica GV_Rack_CxM','Luis','v31.12'),
 ('gv_cxm_desde_importados_volumen','funcion','GV_Rack_CxM','Un importado nuevo con uni_master/uni_inner entra a la canónica de cajas por master','Luis','v31.12')
) v(objeto, clase, patron, regla, quien_pidio, version)
where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto = v.objeto and c.patron = v.patron);

-- ROLLBACK: restaurar GV_Rack_CxM desde zz_backups."GV_Rack_CxM_v3112" (las columnas nuevas quedan inertes);
-- vista_racks_bajadas_pendientes vuelve a leer a."Cajas_x_Master" (definición en el git log de este archivo).
