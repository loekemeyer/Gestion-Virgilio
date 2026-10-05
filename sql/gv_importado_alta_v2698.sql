-- v26.98 (Luis, 05/10/2026) — Pedidos Importación → solapa «➕ Agregar artículo».
-- Pide: código, medidas MC e inner, uni x inner y uni x MC, FOB, descripción, MOQ, proveedor
-- y deja ajustar A MANO el primer pedido a mandar.
--
--  · Importados.moq           MOQ del ARTÍCULO (u). NULL = el del proveedor (GV_Imp_Proveedor.moq).
--  · Importados.pedido_manual  ya existía sin uso (0 filas): es el PRIMER PEDIDO a mano, en UNIDADES.
--                             Pedidos lo toma como MC pedido mientras el código no tenga pedido en curso,
--                             y se borra solo al cargar el primer bache (trigger de abajo).
--  · Importados_Volumen.inner_* medidas del inner (cm) y su m³.
--  · gv_importado_alta(jsonb)  alta en una transacción (Importados + Importados_Volumen), sólo supervisor.
--
-- Rollback:
--   drop trigger if exists gv_importados_bache_primer_pedido on public."GV_Importados_Baches";
--   drop function if exists public.gv_importados_bache_primer_pedido();
--   drop function if exists public.gv_importado_alta(jsonb);
--   alter table public."Importados" drop column if exists moq;
--   alter table public."Importados_Volumen" drop column if exists inner_largo_cm, drop column if exists inner_ancho_cm,
--     drop column if exists inner_alto_cm, drop column if exists m3_inner;

alter table public."Importados" add column if not exists moq numeric;
alter table public."Importados_Volumen" add column if not exists inner_largo_cm numeric;
alter table public."Importados_Volumen" add column if not exists inner_ancho_cm numeric;
alter table public."Importados_Volumen" add column if not exists inner_alto_cm numeric;
alter table public."Importados_Volumen" add column if not exists m3_inner numeric;

create or replace function public.gv_importado_alta(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
-- v26.98-alta-imp
declare
  v_cod  text := upper(btrim(coalesce(p->>'cod','')));
  v_marca text := btrim(coalesce(p->>'marca',''));
  v_prov text := btrim(coalesce(p->>'proveedor',''));
  v_desc text := btrim(coalesce(p->>'descripcion',''));
  v_fob  numeric := nullif(p->>'fob','')::numeric;
  v_um   numeric := nullif(p->>'uni_mc','')::numeric;
  v_ui   numeric := nullif(p->>'uni_inner','')::numeric;
  v_moq  numeric := nullif(p->>'moq','')::numeric;
  v_ped  numeric := nullif(p->>'primer_pedido_u','')::numeric;
  v_ml numeric := nullif(p->>'mc_largo','')::numeric;  v_ma numeric := nullif(p->>'mc_ancho','')::numeric;  v_mh numeric := nullif(p->>'mc_alto','')::numeric;
  v_il numeric := nullif(p->>'in_largo','')::numeric;  v_ia numeric := nullif(p->>'in_ancho','')::numeric;  v_ih numeric := nullif(p->>'in_alto','')::numeric;
  v_por text := coalesce(nullif(btrim(p->>'por'),''), auth.jwt()->>'email', 'gestion');
  v_simular boolean := coalesce((p->>'simular')::boolean, false);
  v_canon text; v_id bigint; v_m3 numeric; v_m3i numeric; v_vol_existe boolean;
begin
  if not public.es_supervisor_virgilio() then raise exception 'SUPERVISOR: sólo un supervisor logueado puede dar de alta un importado'; end if;
  if v_cod = '' then raise exception 'FALTA: el código'; end if;
  if v_marca not in ('LK','CH','Loke','Mixto') then raise exception 'FALTA: la empresa (LK, CH, Loke o Mixto)'; end if;
  if v_prov = '' then raise exception 'FALTA: el proveedor'; end if;
  if v_desc = '' then raise exception 'FALTA: la descripción'; end if;
  if v_fob is null or v_fob <= 0 then raise exception 'FALTA: el FOB (u$s por unidad, mayor a 0)'; end if;
  if v_um is null or v_um <= 0 then raise exception 'FALTA: las unidades por master caja'; end if;
  if v_ui is null or v_ui < 0 then raise exception 'FALTA: las unidades por inner (0 = viene suelto)'; end if;
  if v_ui > 0 and mod(v_um, v_ui) <> 0 then raise exception 'NO CIERRA: % u por MC no es múltiplo de % u por inner', v_um, v_ui; end if;
  if v_moq is not null and v_moq < 0 then raise exception 'NO CIERRA: el MOQ no puede ser negativo'; end if;
  if v_ped is not null and v_ped < 0 then raise exception 'NO CIERRA: el primer pedido no puede ser negativo'; end if;
  if v_ped is not null and mod(v_ped, v_um) <> 0 then raise exception 'NO CIERRA: el primer pedido (% u) tiene que ser master cajas enteras de % u', v_ped, v_um; end if;

  v_canon := public.canon_cod_art_val(v_cod);
  if exists (select 1 from public."Importados" where upper(btrim(cod_art)) = upper(v_canon) and coalesce(marca,'') = v_marca) then
    raise exception 'YA_EXISTE: el % de % ya está en el maestro de importados', v_canon, v_marca;
  end if;
  v_m3  := case when v_ml > 0 and v_ma > 0 and v_mh > 0 then round(v_ml*v_ma*v_mh/1000000.0, 6) end;
  v_m3i := case when v_il > 0 and v_ia > 0 and v_ih > 0 then round(v_il*v_ia*v_ih/1000000.0, 6) end;
  select exists(select 1 from public."Importados_Volumen" where upper(btrim(cod)) = upper(v_canon)) into v_vol_existe;

  if v_simular then
    return jsonb_build_object('ok', true, 'simular', true, 'cod', v_canon, 'm3_master', v_m3, 'm3_inner', v_m3i, 'volumen_existe', v_vol_existe);
  end if;

  insert into public."Importados" (cod_art, marca, proveedor, descripcion, fob_uni, uni_x_caja, moq, pedido_manual,
                                   principal, activo, notas, creado, actualizado)
  values (v_canon, v_marca, v_prov, v_desc, v_fob, nullif(v_ui,0), v_moq, nullif(v_ped,0),
          true, true, 'Alta desde Gestión (➕ Agregar artículo) · ' || v_por || ' · ' ||
          to_char(now() at time zone 'America/Argentina/Buenos_Aires','DD/MM/YY HH24:MI'), now(), now())
  returning id into v_id;

  insert into public."Importados_Volumen" (cod, largo_cm, ancho_cm, alto_cm, m3_master, uni_master, uni_inner,
                                           inner_largo_cm, inner_ancho_cm, inner_alto_cm, m3_inner, fuente, actualizado)
  values (v_canon, v_ml, v_ma, v_mh, v_m3, v_um, v_ui, v_il, v_ia, v_ih, v_m3i, 'Alta Gestión ' || v_por, now())
  on conflict (cod) do update set
    largo_cm = coalesce(excluded.largo_cm, "Importados_Volumen".largo_cm),
    ancho_cm = coalesce(excluded.ancho_cm, "Importados_Volumen".ancho_cm),
    alto_cm  = coalesce(excluded.alto_cm,  "Importados_Volumen".alto_cm),
    m3_master = coalesce(excluded.m3_master, "Importados_Volumen".m3_master),
    uni_master = excluded.uni_master, uni_inner = excluded.uni_inner,
    inner_largo_cm = coalesce(excluded.inner_largo_cm, "Importados_Volumen".inner_largo_cm),
    inner_ancho_cm = coalesce(excluded.inner_ancho_cm, "Importados_Volumen".inner_ancho_cm),
    inner_alto_cm  = coalesce(excluded.inner_alto_cm,  "Importados_Volumen".inner_alto_cm),
    m3_inner = coalesce(excluded.m3_inner, "Importados_Volumen".m3_inner),
    fuente = excluded.fuente, actualizado = now();

  return jsonb_build_object('ok', true, 'id', v_id, 'cod', v_canon, 'm3_master', v_m3, 'm3_inner', v_m3i, 'volumen_existia', v_vol_existe);
end $f$;
revoke all on function public.gv_importado_alta(jsonb) from public, anon;
grant execute on function public.gv_importado_alta(jsonb) to authenticated;

-- el primer pedido a mano se usa una vez: apenas el código tiene su primer bache, se borra
create or replace function public.gv_importados_bache_primer_pedido()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
begin
  -- v26.98-primer-pedido
  update public."Importados" set pedido_manual = null, actualizado = now()
   where upper(btrim(cod_art)) = upper(btrim(new.cod_art)) and pedido_manual is not null;
  return new;
end $f$;
create or replace trigger gv_importados_bache_primer_pedido after insert on public."GV_Importados_Baches"
  for each row execute function public.gv_importados_bache_primer_pedido();

-- (aplicado como CTE: centinelas 332 y 333)
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_importados_bache_primer_pedido','funcion','pedido_manual = null',
        'el primer pedido a mano (Importados.pedido_manual) se borra al cargar el primer bache del código','Luis','v26.98'),
       ('gv_importado_alta','funcion','YA_EXISTE','el alta de un importado no pisa un (código, empresa) que ya existe','Luis','v26.98');
