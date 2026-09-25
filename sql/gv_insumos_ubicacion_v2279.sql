-- v22.80 (Luis, 25/09): las ubicaciones de INSUMOS conectadas al Mapa (GV_Lugar), con el nomenclador que ya existe.
--   · Luis: "es un mismo depósito físico … lo que preguntás son racks de insumos. Dejalos con el nomenclador que ya
--     existe, no inventes uno nuevo · AD adelante AT atrás · sí, ponelo en el mapa".
--   · Los racks de insumos ya estaban en GV_Lugar como empresa 'IN' (R01AD, K04, X20…). Se suman los que faltaban:
--     la grilla A1…L6 CON SU NOMBRE (A1, no A01: A01 es góndola) y las posiciones R/V/AF/AE que no estaban.
--   · Z07 e Y29 NO se agregan: son celdas de GÓNDOLA; un insumo anotado ahí queda «a revisar».
-- ROLLBACK: delete from public."GV_Lugar" where notas = 'v22.80 insumos'; restaurar gv_lugar_sector_fmt ('[0-9]{2,}');
--   vista_insumos desde zz_backups."GV_Backup_vista_insumos_def_20260925"; drop de gv_insumo_ubicacion y la RPC.

-- 1) el nombre de un rack de insumos puede tener UN dígito (A1): es el nombre real del lugar
alter table public."GV_Lugar" drop constraint gv_lugar_sector_fmt;
alter table public."GV_Lugar" add constraint gv_lugar_sector_fmt check (sector ~ '^[A-ZÑ]{1,2}[0-9]{1,}(AD|AT)?$');

-- 2) resolver un texto libre a una posición de rack: primero el nombre EXACTO (A1), después con cero (W1 → W01, R1Ad → R01AD)
create or replace function public.gv_rack_sector(p text) returns text
language sql stable set search_path = public as $$
  select coalesce(
    (select l.sector from public."GV_Lugar" l where l.tipo = 'rack' and l.activo
      and l.sector = upper(regexp_replace(coalesce(p,''), '\s+', '', 'g'))),
    (select l.sector from public."GV_Lugar" l where l.tipo = 'rack' and l.activo
      and l.sector = regexp_replace(upper(regexp_replace(coalesce(p,''), '\s+', '', 'g')), '^([A-Z]{1,2})(\d)(AD|AT)?$', '\10\2\3')))
$$;

-- 3) las posiciones que faltaban en el Mapa
insert into public."GV_Lugar"(sector, tipo, empresa, orden, activo, notas)
select s, 'rack', 'IN', 872 + row_number() over (order by s), true, 'v22.80 insumos'
  from unnest(array[
    'A1','A2','A3','A5','A6','B1','B2','B3','B4','B5','B6','C1','C2','C5','C6','D1','D3','D4','D5','D6',
    'E1','E2','E5','E6','F1','F2','F6','G1','G2','G3','G4','G5','G6','H1','H2','H3','H4','H5','H6','H7',
    'I4','J1','J2','J3','J4','J6','L1','L2','L3','L4','L5','L6',
    'AE04','AF02','AF04','AF07','AF16','AF18','R07AD','R10AD','R10AT','R12AT','R16AD',
    'V01AD','V02AT','V05AT','V11AT','V12AT','V13AD']) s
on conflict (sector) do nothing;

-- 4) dónde está cada insumo, ya resuelto contra el Mapa (una fila por posición; «A1 · C5» son dos)
create or replace view public.gv_insumo_ubicacion with (security_invoker = true) as
select iu.id, iu.cod, btrim(p.txt) texto, public.gv_rack_sector(btrim(p.txt)) sector, iu.cantidad, iu.unidad,
       case when public.gv_rack_sector(btrim(p.txt)) is null then 'sin_lugar' else 'ok' end estado,
       iu.updated_at
  from public."Insumos_Ubicaciones" iu
  cross join lateral regexp_split_to_table(coalesce(iu.sector,''), '\s*·\s*') p(txt)
 where btrim(p.txt) <> '';
grant select on public.gv_insumo_ubicacion to anon, authenticated;

-- 5) vista_insumos: la ubicación que ve el módulo sale del Mapa (resuelta), no del texto suelto
create table zz_backups."GV_Backup_vista_insumos_def_20260925" as
  select pg_get_viewdef('public.vista_insumos'::regclass, true) def;
alter table zz_backups."GV_Backup_vista_insumos_def_20260925" enable row level security;
create or replace view public.vista_insumos with (security_invoker = true) as
 SELECT id, cod, nombre, categoria, isis, creado_por, creado, orden,
    COALESCE(
      NULLIF(( SELECT string_agg(DISTINCT coalesce(u.sector, u.texto), ' · ') FROM public.gv_insumo_ubicacion u
                WHERE upper(btrim(u.cod)) = upper(btrim(i.cod))), ''),
      NULLIF(( SELECT string_agg(rp.sector, ' · ' ORDER BY rp.sector) FROM public."Racks_Planimetria" rp
                WHERE upper(TRIM(BOTH FROM rp.cod_art)) = upper(TRIM(BOTH FROM i.cod)) AND rp.estado = 'ocupado'), ''),
      COALESCE(ubicacion, '')) AS ubicacion
   FROM public."Insumos" i;

-- 6) el editor de la pestaña Insumos escribe por acá: valida cada posición contra el Mapa
create or replace function public.gv_insumo_ubicaciones_guardar(p_cod text, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare it jsonb; v_cod text := btrim(coalesce(p_cod,'')); v_sec text; v_malas text[] := '{}'; n int := 0;
begin
  -- mismo permiso que insumo_editar: el panel de Stock usa la clave del proyecto
  if v_cod = '' then raise exception 'Falta el código.'; end if;
  for it in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    if public.gv_rack_sector(it->>'sector') is null then v_malas := v_malas || coalesce(it->>'sector','?'); end if;
  end loop;
  if array_length(v_malas,1) > 0 then
    raise exception 'Estas posiciones no existen en el Mapa: %. Dalas de alta en 📍 Lugares o corregí el nombre (ej. R1Ad, V9 At, A1).',
      array_to_string(v_malas, ', ');
  end if;
  delete from public."Insumos_Ubicaciones" where btrim(cod) = v_cod;
  for it in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    v_sec := public.gv_rack_sector(it->>'sector');
    insert into public."Insumos_Ubicaciones"(cod, sector, cantidad, updated_at)
    values (v_cod, v_sec, nullif(it->>'cantidad','')::numeric, now())
    on conflict (cod, sector) do update set cantidad = excluded.cantidad, updated_at = now();
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'cod', v_cod, 'posiciones', n);
end $$;
grant execute on function public.gv_insumo_ubicaciones_guardar(text, jsonb) to anon, authenticated;

-- 7) el Mapa de racks muestra también los insumos (con su cantidad declarada) donde no hay stock de artículo
create or replace view public.gv_rack_celda with (security_invoker = true) as
with lug as (
 select upper(btrim(sector)) sector, empresa, orden, uso from public."GV_Lugar" where activo and tipo = 'rack'
), rp as (
 select sector, emp, nullif(btrim(cod_art),'') cod, coalesce(master_cajas,0) master_cajas, coalesce(innercajas,0) innercajas,
 fuente, motivo, revisar_id
 from public."Racks_Planimetria" where estado = 'ocupado' and nullif(btrim(cod_art),'') is not null
 union all
 select u.sector, 'IN', u.cod, 0, coalesce(u.cantidad,0), 'insumo', null, null
   from public.gv_insumo_ubicacion u
  where u.sector is not null
    and not exists (select 1 from public."Racks_Planimetria" r where r.sector = u.sector and upper(r.cod_art) = upper(btrim(u.cod)) and r.fuente is not null)
), sec as (select sector from lug union select sector from rp),
nom as (
 select gv_cod_stock(cod) k, min(descripcion) descripcion from public.vista_nombres_articulos
 where descripcion is not null and btrim(descripcion) <> '' group by 1)
select s.sector, substring(s.sector, '^[A-ZÑ]+') rack, l.orden, coalesce(l.empresa, r.emp) empresa, l.uso,
 r.cod, coalesce(n.descripcion, (select i.nombre from public."Insumos" i where upper(btrim(i.cod)) = upper(r.cod) limit 1)) descripcion,
 r.master_cajas, r.innercajas, r.emp emp_carga,
 case when l.sector is null then 'sin_lugar' when r.cod is null then 'libre' else 'ocupado' end estado,
 r.fuente, r.motivo, r.revisar_id
 from sec s left join lug l on l.sector = s.sector left join rp r on r.sector = s.sector
 left join nom n on n.k = gv_cod_stock(r.cod);
grant select on public.gv_rack_celda to anon, authenticated;

-- 8) los «a contar» de racks que eran insumos: su ubicación ya la lleva el módulo de Insumos
update public."GV_Rack_Revisar" v set resuelto_en = now(), resuelto_por = 'sistema v22.80',
       nota = 'Es un insumo: dónde está lo lleva el módulo de Insumos (Insumos_Ubicaciones), no el stock de racks'
 where v.resuelto_en is null
   and exists (select 1 from public."Insumos" i where upper(btrim(i.cod)) = upper(v.cod))
   and exists (select 1 from public.gv_insumo_ubicacion u where upper(btrim(u.cod)) = upper(v.cod) and u.sector = public.gv_rack_sector(v.sector));
