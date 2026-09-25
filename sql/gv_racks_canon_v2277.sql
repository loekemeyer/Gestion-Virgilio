-- v22.76 (Luis, 25/09): RACKS con una sola fuente por dato.
--   · QUÉ posiciones hay y si están reservadas (Pedidos/Cajas/bastidor) → GV_Lugar (tipo rack, uso)
--   · CUÁNTO hay de cada código en cada posición → Movimientos_Stock (deposito racks/racks_ch, ubicacion = sector)
--   · cajas por master (para mostrar MC) → GV_Rack_CxM
--   · lo que la planimetría vieja decía y el stock NO respalda → GV_Rack_Revisar («a contar», se ve en el Mapa)
-- Racks_Planimetria pasa a ser VISTA con las mismas columnas (+ fuente / motivo). La tabla vieja queda como
-- Racks_Planimetria_legacy (sin escritura) para el rollback.
--
-- ROLLBACK: drop view public."Racks_Planimetria" cascade; alter table public."Racks_Planimetria_legacy" rename to
--   "Racks_Planimetria"; recrear dependientes desde zz_backups."GV_Backup_RacksPlani_defs_20260925"; restaurar las
--   funciones racks_plani_* / registrar_baja_racks / gv_rack_posicion_guardar desde
--   zz_backups."GV_Backup_RacksFn_20260925" (columna def); y borrar los movimientos de la migración:
--   delete from public."Movimientos_Stock" where ref = 'ubicar racks · v22.76';  (suman 0 por código)

-- 1) piezas nuevas ---------------------------------------------------------------------------------------------
create table if not exists public."GV_Rack_CxM" (
  cod text not null, emp text not null, cxm numeric not null check (cxm > 0),
  actualizado_en timestamptz not null default now(), primary key (cod, emp));
alter table public."GV_Rack_CxM" enable row level security;
drop policy if exists gv_rack_cxm_sel on public."GV_Rack_CxM";
create policy gv_rack_cxm_sel on public."GV_Rack_CxM" for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public."GV_Rack_CxM" from anon, authenticated;
grant select on public."GV_Rack_CxM" to anon, authenticated;

create table if not exists public."GV_Rack_Revisar" (
  id bigserial primary key, sector text not null, cod text not null, emp text,
  cajas_planimetria numeric, master_planimetria numeric, cajas_stock numeric,
  motivo text not null, creado_en timestamptz not null default now(),
  resuelto_en timestamptz, resuelto_por text, nota text);
alter table public."GV_Rack_Revisar" enable row level security;
drop policy if exists gv_rack_revisar_sel on public."GV_Rack_Revisar";
create policy gv_rack_revisar_sel on public."GV_Rack_Revisar" for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public."GV_Rack_Revisar" from anon, authenticated;
grant select on public."GV_Rack_Revisar" to anon, authenticated;

-- sector de rack canónico a partir de un texto libre (W1 → W01). NULL si no es una posición de rack.
create or replace function public.gv_rack_sector(p text) returns text
language sql stable set search_path = public as $$
  select l.sector from public."GV_Lugar" l
   where l.tipo = 'rack' and l.activo
     and l.sector = regexp_replace(upper(regexp_replace(coalesce(p,''), '\s+', '', 'g')), '^([A-Z]{1,2})(\d)$', '\10\2')
$$;

-- 2) migración de datos (con backup) ---------------------------------------------------------------------------
do $mig$
declare _mr record; v_rest numeric; v_tomar numeric; v_cod text := ''; v_emp text := '';
begin
  create table zz_backups."GV_Backup_RacksPlani_20260925" as select * from public."Racks_Planimetria";
  alter table zz_backups."GV_Backup_RacksPlani_20260925" enable row level security;
  create table zz_backups."GV_Backup_RacksFn_20260925" as
    select p.proname::text, pg_get_functiondef(p.oid) def from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('racks_plani_descontar','racks_plani_ingreso','racks_plani_ingreso_nacional',
                         'racks_plani_mover','registrar_baja_racks','gv_rack_posicion_guardar');
  alter table zz_backups."GV_Backup_RacksFn_20260925" enable row level security;

  -- posiciones que la planimetría vieja da por ocupadas con un artículo
  create temp table _pos on commit drop as
  select r.id, upper(btrim(r.sector)) sec_raw, public.gv_rack_sector(r.sector) sec, upper(btrim(r.cod_art)) cod,
         coalesce(public.gv_empresa_de_articulo(upper(btrim(r.cod_art))),
                  replace(upper(coalesce(nullif(btrim(r.emp),''),'LK')),'LOKE','LK')) emp,
         coalesce(r.innercajas,0) q, coalesce(r.master_cajas,0) m, 0::numeric asig
    from public."Racks_Planimetria" r
   where r.estado = 'ocupado' and upper(btrim(coalesce(r.cod_art,''))) not in ('','PEDIDOS','CAJAS');

  -- cajas por master: sólo donde la relación es exacta y la misma en todas las posiciones
  insert into public."GV_Rack_CxM"(cod, emp, cxm)
  select cod, emp, sum(q)/sum(m) from _pos where m > 0 and q > 0
   group by cod, emp having count(distinct round(q/m, 3)) = 1 and sum(q) % sum(m) = 0
  on conflict (cod, emp) do nothing;

  -- libro de stock de racks hoy, por ubicación (texto crudo, puede ser NULL o basura)
  create temp table _cur on commit drop as
  select deposito dep, upper(btrim(cod_art)) cod,
         case when deposito = 'racks_ch' then 'CH' else upper(coalesce(empresa,'LK')) end emp,
         ubicacion ubic, sum(delta) s
    from public."Movimientos_Stock" where deposito in ('racks','racks_ch')
   group by 1,2,3,4;
  create temp table _tot on commit drop as
  select cod, emp, dep, sum(s) s, row_number() over (partition by cod, emp order by sum(s) desc, dep) rk
    from _cur group by cod, emp, dep;

  -- reparto: el stock canónico se asigna a las posiciones de la planimetría, en orden de sector
  for _mr in select p.*, coalesce(t.s,0) disp from _pos p left join _tot t on t.cod = p.cod and t.emp = p.emp and t.rk = 1
            where p.sec is not null order by p.cod, p.emp, p.sec loop
    if _mr.cod <> v_cod or _mr.emp <> v_emp then v_rest := greatest(_mr.disp,0); v_cod := _mr.cod; v_emp := _mr.emp; end if;
    v_tomar := least(_mr.q, v_rest);
    update _pos set asig = v_tomar where id = _mr.id;
    v_rest := v_rest - v_tomar;
  end loop;

  -- objetivo por (dep, cod, emp, ubicación): lo asignado en su sector; el resto sin ubicar (NULL)
  create temp table _obj on commit drop as
  with principal as (select cod, emp, dep, s from _tot where rk = 1),
       asignado as (select p.cod, p.emp, t.dep, p.sec ubic, sum(p.asig) s
                      from _pos p join principal t on t.cod = p.cod and t.emp = p.emp
                     where p.asig > 0 group by 1,2,3,4)
  select cod, emp, dep, ubic, s from asignado
  union all
  select t.cod, t.emp, t.dep, null, t.s - coalesce((select sum(a.s) from asignado a where a.cod=t.cod and a.emp=t.emp and a.dep=t.dep),0)
    from _tot t;

  -- una sola sentencia: los avisos de stock negativo ven el saldo final
  insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, descripcion, ubicacion, unidad, legajo, empresa)
  select k.cod, k.dep, coalesce(o.s,0) - coalesce(c.s,0), 'ajuste', 'ubicar racks · v22.76',
         'Migración: la cantidad por posición de rack pasa al libro de stock', k.ubic, 'inner', 'sistema', k.emp
    from (select dep, cod, emp, ubic from _cur union select dep, cod, emp, ubic from _obj) k
    left join (select dep, cod, emp, ubic, sum(s) s from _cur group by 1,2,3,4) c
           on c.dep = k.dep and c.cod = k.cod and c.emp = k.emp and c.ubic is not distinct from k.ubic
    left join (select dep, cod, emp, ubic, sum(s) s from _obj group by 1,2,3,4) o
           on o.dep = k.dep and o.cod = k.cod and o.emp = k.emp and o.ubic is not distinct from k.ubic
   where coalesce(o.s,0) - coalesce(c.s,0) <> 0;

  -- lo que no cierra va a la lista «a contar» del Mapa
  insert into public."GV_Rack_Revisar"(sector, cod, emp, cajas_planimetria, master_planimetria, cajas_stock, motivo)
  select coalesce(sec, sec_raw), cod, emp, q, m, asig,
         case when sec is null then 'La planimetría lo ponía en ' || sec_raw || ', que no es una posición de rack'
              when asig = 0 then 'La planimetría decía ' || q || ' cajas y el stock de racks no respalda ninguna'
              else 'La planimetría decía ' || q || ' cajas y el stock de racks alcanza para ' || asig end
    from _pos where sec is null or asig < q;
  insert into public."GV_Rack_Revisar"(sector, cod, emp, cajas_planimetria, cajas_stock, motivo)
  select public.gv_rack_sector(c.ubic), c.cod, c.emp, sum(c.s), 0,
         'El libro de stock lo ubicaba acá (' || round(sum(c.s)) || ' cajas) y la planimetría no'
    from _cur c
   where public.gv_rack_sector(c.ubic) is not null
     and not exists (select 1 from _pos p where p.sec = public.gv_rack_sector(c.ubic) and p.cod = c.cod and p.asig > 0)
   group by 1,2,3 having sum(c.s) > 0;

  -- W02 figuraba como Pedidos en la planimetría y el lugar no lo tenía
  update public."GV_Lugar" set uso = 'pedidos', updated_at = now() where sector = 'W02' and tipo = 'rack' and uso is null;
end $mig$;

-- 3) Racks_Planimetria pasa a VISTA (dependientes recreados con su definición viva) --------------------------
do $swap$
declare _sr record; i text;
begin
  create temp table _dep on commit drop as
  with recursive dep as (
    select c.oid, c.relname::text rel, c.relkind, 1 lvl from pg_class c where c.oid = 'public."Racks_Planimetria"'::regclass
    union
    select c.oid, c.relname::text, c.relkind, dep.lvl + 1 from dep
      join pg_depend d on d.refobjid = dep.oid join pg_rewrite rw on rw.oid = d.objid
      join pg_class c on c.oid = rw.ev_class and c.oid <> dep.oid)
  select rel, relkind, max(lvl) lvl from dep where lvl > 1 group by rel, relkind;
  create table zz_backups."GV_Backup_RacksPlani_defs_20260925" as
  select d.rel, d.relkind::text relkind, d.lvl, pg_get_viewdef(c.oid, true) def, c.reloptions opts,
         obj_description(c.oid, 'pg_class') cmt,
         array(select indexdef from pg_indexes where schemaname='public' and tablename=d.rel) idx,
         array(select format('grant %s on public.%I to %s', a.privilege_type, d.rel,
                  case when a.grantee = 0 then 'public' else quote_ident(pg_get_userbyid(a.grantee)) end)
                from aclexplode(c.relacl) a where a.grantee <> c.relowner) grants
    from _dep d join pg_class c on c.relname = d.rel and c.relnamespace = 'public'::regnamespace;
  alter table zz_backups."GV_Backup_RacksPlani_defs_20260925" enable row level security;

  alter table public."Racks_Planimetria" rename to "Racks_Planimetria_legacy";
  revoke insert, update, delete, truncate on public."Racks_Planimetria_legacy" from anon, authenticated;

  create view public."Racks_Planimetria" with (security_invoker = true) as
  with lug as (
    select l.sector, l.empresa, l.uso, l.created_at from public."GV_Lugar" l where l.tipo = 'rack' and l.activo
  ), st as (
    select public.gv_rack_sector(m.ubicacion) sector, upper(btrim(m.cod_art)) cod,
           case when m.deposito = 'racks_ch' then 'CH' else upper(coalesce(m.empresa,'LK')) end emp,
           sum(m.delta) cajas, min(m.ts) desde
      from public."Movimientos_Stock" m
     where m.deposito in ('racks','racks_ch') and m.ubicacion is not null
     group by 1,2,3 having sum(m.delta) > 0
  ), rev as (
    select v.id, coalesce(public.gv_rack_sector(v.sector), v.sector) sector, v.cod, v.emp,
           coalesce(v.cajas_planimetria, v.cajas_stock, 0) cajas, v.master_planimetria, v.motivo, v.creado_en
      from public."GV_Rack_Revisar" v where v.resuelto_en is null
  ), cont as (
    select s.sector, s.cod, s.emp, s.cajas, 'stock'::text fuente, null::bigint revisar_id, null::text motivo,
           s.desde, null::numeric master_plani
      from st s where s.sector is not null
    union all
    select r.sector, r.cod, r.emp, r.cajas, 'a_contar', r.id, r.motivo, r.creado_en, r.master_planimetria
      from rev r where not exists (select 1 from st s where s.sector = r.sector and s.cod = r.cod)
  ), secs as (select sector from lug union select sector from cont)
  select abs(hashtextextended(x.sector || '|' || coalesce(c.cod,'') || '|' || coalesce(c.fuente,''), 0))::bigint as id,
         coalesce(c.emp, l.empresa) as emp,
         x.sector,
         coalesce(c.cod, case l.uso when 'pedidos' then 'Pedidos' when 'cajas' then 'Cajas' end) as cod_art,
         case when c.cod is null then 0
              when c.fuente = 'a_contar' then coalesce(c.master_plani, 0)
              else coalesce(round(c.cajas / x2.cxm), 0) end::numeric as master_cajas,
         coalesce(c.cajas, 0)::numeric as innercajas,
         case when c.cod is not null or l.uso in ('pedidos','cajas') then 'ocupado' else 'libre' end as estado,
         coalesce(c.desde, l.created_at) as created_at,
         c.fuente, c.motivo, c.revisar_id
    from secs x
    left join lug l on l.sector = x.sector
    left join cont c on c.sector = x.sector
    left join public."GV_Rack_CxM" x2 on x2.cod = c.cod and x2.emp = c.emp;
  comment on view public."Racks_Planimetria" is
    'v22.76: VISTA. Posiciones = GV_Lugar (tipo rack); cantidad = Movimientos_Stock (racks, ubicacion); MC = GV_Rack_CxM; fuente a_contar = GV_Rack_Revisar abierto. Escribir por racks_plani_* / registrar_baja_racks / gv_rack_posicion_guardar. Tabla vieja: Racks_Planimetria_legacy.';
  grant select on public."Racks_Planimetria" to anon, authenticated;

  for _sr in select * from zz_backups."GV_Backup_RacksPlani_defs_20260925" order by lvl desc loop
    if _sr.relkind = 'm' then execute format('drop materialized view if exists public.%I cascade', _sr.rel);
    else execute format('drop view if exists public.%I cascade', _sr.rel); end if;
  end loop;
  for _sr in select * from zz_backups."GV_Backup_RacksPlani_defs_20260925" order by lvl, rel loop
    execute format('create %s public.%I %s as %s', case when _sr.relkind='m' then 'materialized view' else 'view' end, _sr.rel,
      case when _sr.opts is not null then 'with (' || array_to_string(_sr.opts, ',') || ')' else '' end, _sr.def);
    foreach i in array _sr.idx loop execute i; end loop;
    foreach i in array _sr.grants loop execute i; end loop;
    if _sr.cmt is not null then
      execute format('comment on %s public.%I is %L', case when _sr.relkind='m' then 'materialized view' else 'view' end, _sr.rel, _sr.cmt);
    end if;
  end loop;
end $swap$;

-- 4) funciones que escriben: todas terminan en Movimientos_Stock con ubicacion = sector ----------------------
-- cajas de un código en una posición (según el libro de stock)
create or replace function public.gv_rack_saldo_pos(p_sector text, p_cod text, p_emp text default null)
returns numeric language sql stable set search_path = public as $$
  select coalesce(sum(m.delta), 0) from public."Movimientos_Stock" m
   where m.deposito in ('racks','racks_ch') and m.ubicacion is not null
     and public.gv_rack_sector(m.ubicacion) = public.gv_rack_sector(p_sector)
     and upper(btrim(m.cod_art)) = upper(btrim(p_cod))
     and (p_emp is null or (case when m.deposito='racks_ch' then 'CH' else upper(coalesce(m.empresa,'LK')) end) = upper(p_emp))
$$;

create or replace function public.gv_rack_cxm_anotar(p_cod text, p_emp text, p_inner numeric, p_master numeric)
returns void language sql security definer set search_path = public as $$
  insert into public."GV_Rack_CxM"(cod, emp, cxm)
  select upper(btrim(p_cod)), upper(p_emp), p_inner / p_master
   where coalesce(p_master,0) > 0 and coalesce(p_inner,0) > 0 and p_inner % p_master = 0
  on conflict (cod, emp) do update set cxm = excluded.cxm, actualizado_en = now()
$$;
revoke all on function public.gv_rack_cxm_anotar(text,text,numeric,numeric) from public, anon, authenticated;

-- ¿la posición admite este código? devuelve NULL si sí, o el texto de error/ocupado (mismo contrato de antes)
create or replace function public.gv_rack_pos_chequear(p_sector text, p_cod text) returns text
language plpgsql stable set search_path = public as $$
declare v_sec text := public.gv_rack_sector(p_sector); v_uso text; v_otro text;
begin
  if v_sec is null then return 'error: la posición ' || coalesce(p_sector,'?') || ' no existe como rack'; end if;
  select uso into v_uso from public."GV_Lugar" where sector = v_sec;
  if v_uso in ('pedidos','cajas') then return 'error: el destino es un lugar reservado'; end if;
  select cod_art into v_otro from public."Racks_Planimetria"
   where sector = v_sec and estado = 'ocupado' and fuente is not null and upper(cod_art) <> upper(btrim(p_cod)) limit 1;
  if v_otro is not null then return 'ocupado:' || v_otro; end if;
  return null;
end $$;

create or replace function public.racks_plani_ingreso(p_sector text, p_cod text, p_master numeric, p_inner numeric, p_emp text, p_legajo text)
returns text language plpgsql security definer set search_path = public as $$
-- v22.76: la cantidad vive en Movimientos_Stock con ubicacion = sector (Racks_Planimetria es vista).
declare
  v_sec text := public.gv_rack_sector(p_sector);
  v_cod text := upper(btrim(coalesce(p_cod,'')));
  v_inner numeric := coalesce(p_inner, 0); v_master numeric := coalesce(p_master, 0);
  v_emp text := coalesce(public.gv_empresa_de_articulo(upper(btrim(coalesce(p_cod,'')))), nullif(upper(btrim(coalesce(p_emp,''))),''), 'LK');
  v_chk text;
begin
  if btrim(coalesce(p_sector,'')) = '' or v_cod = '' then return 'error: falta sector o codigo'; end if;
  if v_inner <= 0 then return 'error: las cajas deben ser mayor a 0'; end if;
  v_chk := public.gv_rack_pos_chequear(p_sector, v_cod);
  if v_chk is not null then return v_chk; end if;
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo, empresa, ubicacion)
  values (v_cod, 'racks', v_inner, 'ingreso', 'ingreso a racks '||v_sec||' ('||coalesce(v_master,0)||' master)', 'inner', nullif(p_legajo,''), v_emp, v_sec);
  perform public.gv_rack_cxm_anotar(v_cod, v_emp, v_inner, v_master);
  update public."GV_Rack_Revisar" set resuelto_en = now(), resuelto_por = 'ingreso ' || coalesce(nullif(p_legajo,''),'?'),
         nota = 'se ingresaron ' || v_inner || ' cajas de ' || v_cod
   where resuelto_en is null and public.gv_rack_sector(sector) = v_sec and upper(cod) = v_cod;
  return 'ok';
end $$;

create or replace function public.racks_plani_ingreso_nacional(p_sector text, p_cod text, p_master numeric, p_inner numeric, p_origen text, p_emp text, p_legajo text)
returns text language plpgsql security definer set search_path = public as $$
-- v22.76: igual que antes (sale de a_guardar / excedente) pero la posición la da el movimiento de racks.
declare
  v_sec text := public.gv_rack_sector(p_sector); v_cod text := upper(btrim(coalesce(p_cod,'')));
  v_codn text := upper(regexp_replace(btrim(coalesce(p_cod,'')), '^0+(.)', '\1'));
  v_inner numeric := coalesce(p_inner, 0); v_master numeric := coalesce(p_master, 0);
  v_orig text := lower(btrim(coalesce(p_origen,'')));
  v_emp text := coalesce(public.gv_empresa_de_articulo(upper(btrim(coalesce(p_cod,'')))), nullif(upper(btrim(coalesce(p_emp,''))),''), 'LK');
  v_cutoff timestamptz; v_disp numeric; v_chk text;
begin
  if btrim(coalesce(p_sector,'')) = '' or v_cod = '' then return 'error: falta sector o codigo'; end if;
  if v_inner <= 0 then return 'error: las cajas deben ser mayor a 0'; end if;
  if v_orig not in ('a_guardar','excedente') then return 'error: origen invalido'; end if;
  select valor::timestamptz into v_cutoff from "Stock_Config" where clave='cutoff_ts' limit 1;
  select coalesce(sum(m.delta),0) into v_disp from "Movimientos_Stock" m
   where m.deposito = v_orig and upper(regexp_replace(btrim(m.cod_art), '^0+(.)', '\1')) = v_codn
     and (v_cutoff is null or m.tipo='inicial' or m.ts >= v_cutoff);
  if v_disp < v_inner then return 'sin_stock:'||round(coalesce(v_disp,0)); end if;
  v_chk := public.gv_rack_pos_chequear(p_sector, v_cod);
  if v_chk is not null then return v_chk; end if;
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo, empresa, ubicacion) values
    (v_cod, v_orig,  -v_inner, 'traslado', 'nacional a racks '||v_sec, 'inner', nullif(p_legajo,''), v_emp, null),
    (v_cod, 'racks',  v_inner, 'traslado', 'nacional desde '||v_orig||' a '||v_sec, 'inner', nullif(p_legajo,''), v_emp, v_sec);
  perform public.gv_rack_cxm_anotar(v_cod, v_emp, v_inner, v_master);
  update public."GV_Rack_Revisar" set resuelto_en = now(), resuelto_por = 'ingreso ' || coalesce(nullif(p_legajo,''),'?'),
         nota = 'se ingresaron ' || v_inner || ' cajas de ' || v_cod
   where resuelto_en is null and public.gv_rack_sector(sector) = v_sec and upper(cod) = v_cod;
  return 'ok';
end $$;

create or replace function public.racks_plani_mover(p_origen text, p_cod text, p_destino text, p_inner numeric, p_master numeric)
returns text language plpgsql security definer set search_path = public as $$
-- v22.76: mover = par de movimientos en el libro de racks (−origen / +destino). El total de racks no cambia.
declare
  v_o text := public.gv_rack_sector(p_origen); v_d text := public.gv_rack_sector(p_destino);
  v_cod text := upper(replace(btrim(coalesce(p_cod,'')), ' ', ''));
  r record; v_chk text;
begin
  if p_inner is null or p_inner <= 0 or p_inner > 100000 then return 'error: cantidad inválida'; end if;
  if coalesce(btrim(p_origen),'') = '' or coalesce(btrim(p_destino),'') = '' then return 'error: falta ubicación'; end if;
  if v_o is null then return 'error: el origen no es una posición de rack'; end if;
  if v_d is null then return 'error: el destino no existe en la planimetría'; end if;
  if v_o = v_d then return 'error: mismo lugar'; end if;
  select m.deposito dep, case when m.deposito='racks_ch' then 'CH' else upper(coalesce(m.empresa,'LK')) end emp, sum(m.delta) s
    into r from public."Movimientos_Stock" m
   where m.deposito in ('racks','racks_ch') and m.ubicacion is not null and public.gv_rack_sector(m.ubicacion) = v_o
     and upper(btrim(m.cod_art)) = v_cod
   group by 1,2 having sum(m.delta) > 0 order by sum(m.delta) desc limit 1;
  if r.s is null then return 'error: el origen no tiene ese artículo'; end if;
  if r.s < p_inner then return 'error: no hay tantas cajas en el origen'; end if;
  v_chk := public.gv_rack_pos_chequear(v_d, v_cod);
  if v_chk like 'ocupado:%' then return 'error: el destino está ocupado por otro artículo'; end if;
  if v_chk is not null then return v_chk; end if;
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo, empresa, ubicacion) values
    (v_cod, r.dep, -p_inner, 'traslado', 'mover rack '||v_o||' → '||v_d, 'inner', 'mover', r.emp, v_o),
    (v_cod, r.dep,  p_inner, 'traslado', 'mover rack '||v_o||' → '||v_d, 'inner', 'mover', r.emp, v_d);
  perform public.gv_rack_cxm_anotar(v_cod, r.emp, p_inner, p_master);
  return 'ok';
end $$;

-- descontar: la cantidad ya la descuenta registrar_baja_racks (con la posición). Queda por compatibilidad.
create or replace function public.racks_plani_descontar(p_sector text, p_cod text, p_inner numeric)
returns void language plpgsql security definer set search_path = public as $$
begin
  -- v22.76: sin efecto. Antes descontaba de la tabla Racks_Planimetria; hoy la posición la descuenta
  -- el movimiento de registrar_baja_racks (ubicacion = sector) y los avisos salen de ahí.
  return;
end $$;

create or replace function public.registrar_baja_racks(p_items jsonb)
returns integer language plpgsql security definer set search_path = public as $$
-- v22.76: el movimiento de racks lleva la posición (ubicacion) → baja la cantidad de ESA posición.
-- Los avisos de «rack libre» / «sin stock en racks» (antes en racks_plani_descontar) salen de acá.
declare it jsonb; v_cid text; v_cod text; v_caj numeric; v_desc text; v_sec text; v_ubic text; v_ref text; v_leg text;
        v_ord bigint; v_emp text; n int := 0; v_ins int; v_pos numeric; v_tot numeric; v_otras text; v_nombre text;
        v_bucket text := to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYYMMDD_HH24MI');
begin
  if p_items is null then return 0; end if;
  for it in select value from jsonb_array_elements(p_items) as t(value) loop
    v_cod := nullif(btrim(it->>'cod_art'), ''); v_caj := coalesce((it->>'cajas')::numeric, 0);
    if v_cod is null or v_caj <= 0 then continue; end if;
    v_cid := nullif(it->>'cid',''); if v_cid is null then v_cid := 'br_' || replace(gen_random_uuid()::text,'-',''); end if;
    v_desc := it->>'descripcion'; v_sec := nullif(it->>'sector',''); v_ubic := public.gv_rack_sector(v_sec);
    v_ref := coalesce(nullif(it->>'ref',''), 'rack ' || coalesce(v_sec,'s/sector'));
    v_leg := coalesce(nullif(it->>'legajo',''), '0'); v_ord := nullif(it->>'orden_id','')::bigint;
    v_emp := nullif(btrim(it->>'emp'),'');
    if v_emp is null and v_ubic is not null then
      select emp into v_emp from "Racks_Planimetria" where sector = v_ubic and upper(cod_art) = upper(v_cod) limit 1;
    end if;
    insert into public."Racks_Bajadas" (orden_id, cod_art, descripcion, cajas, estado, aprobada_at, creada_por, sector, client_id)
    values (v_ord, v_cod, v_desc, v_caj, 'aprobada', now(), v_leg, v_sec, v_cid) on conflict do nothing;
    insert into public."Movimientos_Stock" (cod_art, descripcion, deposito, delta, tipo, ref, legajo, client_id, empresa, ubicacion)
    values (v_cod, v_desc, 'racks', -v_caj, 'baja_racks', v_ref, v_leg, v_cid || '-r', v_emp, v_ubic) on conflict do nothing;
    get diagnostics v_ins = row_count;
    insert into public."Movimientos_Stock" (cod_art, descripcion, deposito, delta, tipo, ref, legajo, client_id, empresa)
    values (v_cod, v_desc, 'terminado', v_caj, 'baja_racks', v_ref, v_leg, v_cid || '-t', v_emp) on conflict do nothing;
    n := n + 1;
    -- avisos, sólo la primera vez que entra (la cola offline reintenta el mismo client_id)
    if v_ins > 0 and v_ubic is not null then
      v_pos := public.gv_rack_saldo_pos(v_ubic, v_cod);
      select coalesce(sum(delta),0) into v_tot from public."Movimientos_Stock"
       where deposito in ('racks','racks_ch') and upper(btrim(cod_art)) = upper(btrim(v_cod));
      v_nombre := v_desc;
      if v_pos <= 0 then
        select string_agg(sector || ' (' || innercajas || ' cj)', ', ' order by sector) into v_otras
          from "Racks_Planimetria" where upper(cod_art) = upper(btrim(v_cod)) and fuente = 'stock' and sector <> v_ubic;
        perform tg_enqueue(
          '📦 RACK LIBRE — La posición ' || v_ubic || ' quedó VACÍA: se bajó TODO el ' || v_cod ||
          coalesce(' · ' || v_nombre, '') || ' que había EN ESA POSICIÓN. Quedó LIBRE para otro palet.' ||
          case when v_otras is not null then E'\n✅ El ' || v_cod || ' TODAVÍA tiene stock en rack: ' || v_otras || '.'
               else E'\n⚠ El ' || v_cod || ' ya NO queda en ninguna otra posición de rack.' end,
          'rackpos0|' || v_ubic || '|' || upper(v_cod) || '|' || v_bucket);
      end if;
      if v_tot <= 0 then
        perform tg_enqueue('🚨 SIN STOCK EN RACKS — ' || v_cod || coalesce(' · ' || v_nombre, '') ||
          ' quedó en 0 en TODAS sus posiciones de rack. No queda nada para bajar de ese código.',
          'rackzero|' || upper(v_cod) || '|' || v_bucket);
      end if;
    end if;
  end loop;
  return n;
end $$;

create or replace function public.gv_rack_posicion_guardar(p_sector text, p_cod text, p_master numeric, p_inner numeric, p_emp text, p_motivo text)
returns jsonb language plpgsql security definer set search_path = public as $$
-- v22.76: editar una posición desde el Mapa = ajuste en el libro de racks con ubicacion = sector.
-- p_cod vacío = vaciar la posición. 'Pedidos' / 'Cajas' marcan el lugar como reservado (GV_Lugar.uso).
-- Guardar cierra lo que la posición tenía «a contar».
declare
  v_sec text := public.gv_rack_sector(p_sector);
  v_cod text := nullif(upper(btrim(coalesce(p_cod,''))),'');
  v_inner numeric := coalesce(p_inner,0); v_mast numeric := coalesce(p_master,0);
  v_mot text := nullif(btrim(coalesce(p_motivo,'')),'');
  v_quien text := 'sup:' || coalesce(auth.jwt() ->> 'email', session_user::text);
  v_emp text; r record; d numeric; v_res jsonb := '[]'::jsonb; v_tiene numeric;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede editar los racks.';
  end if;
  if v_sec is null then raise exception 'La posición % no existe como rack.', coalesce(p_sector,'?'); end if;
  if v_mot is null then raise exception 'Escribí el motivo del cambio (queda en el movimiento de stock).'; end if;
  if v_inner < 0 or v_mast < 0 then raise exception 'Las cantidades no pueden ser negativas.'; end if;
  perform pg_advisory_xact_lock(hashtext('gv_rack_pos|' || v_sec));

  if v_cod in ('PEDIDOS','CAJAS') then v_inner := 0; end if;
  if v_cod is not null and v_cod not in ('PEDIDOS','CAJAS') then
    if v_inner <= 0 then raise exception 'Poné las cajas que hay en la posición (o vaciala).'; end if;
    if not public.gv_stock_cod_conocido(v_cod) then raise exception 'El código % no existe.', v_cod; end if;
  end if;
  v_emp := upper(coalesce(case when v_cod is not null then public.gv_empresa_de_articulo(v_cod) end,
                          nullif(btrim(coalesce(p_emp,'')),''),
                          (select empresa from public."GV_Lugar" where sector = v_sec), 'LK'));
  if v_emp not in ('LK','CH') then raise exception 'Empresa inválida: % (va LK o CH).', v_emp; end if;

  -- lo que hay hoy en la posición según el libro: todo lo que no sea el código nuevo sale
  for r in select m.deposito dep, upper(btrim(m.cod_art)) cod,
                  case when m.deposito='racks_ch' then 'CH' else upper(coalesce(m.empresa,'LK')) end emp, sum(m.delta) s
             from public."Movimientos_Stock" m
            where m.deposito in ('racks','racks_ch') and m.ubicacion is not null and public.gv_rack_sector(m.ubicacion) = v_sec
            group by 1,2,3 having sum(m.delta) <> 0 loop
    if v_cod is null or v_cod in ('PEDIDOS','CAJAS') or r.cod <> v_cod or r.emp <> v_emp then
      insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, descripcion, unidad, legajo, empresa, ubicacion)
      values (r.cod, r.dep, -r.s, 'ajuste', 'rack ' || v_sec || ' · mapa', 'Mapa de racks: ' || v_mot, 'inner', v_quien, r.emp, v_sec);
      v_res := v_res || jsonb_build_object('cod', r.cod, 'emp', r.emp, 'delta', -r.s);
    end if;
  end loop;

  if v_cod is not null and v_cod not in ('PEDIDOS','CAJAS') then
    v_tiene := public.gv_rack_saldo_pos(v_sec, v_cod, v_emp);
    d := v_inner - v_tiene;
    if d <> 0 then
      insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, descripcion, unidad, legajo, empresa, ubicacion)
      values (v_cod, 'racks', d, 'ajuste', 'rack ' || v_sec || ' · mapa', 'Mapa de racks: ' || v_mot, 'inner', v_quien, v_emp, v_sec);
      v_res := v_res || jsonb_build_object('cod', v_cod, 'emp', v_emp, 'delta', d);
    end if;
    perform public.gv_rack_cxm_anotar(v_cod, v_emp, v_inner, v_mast);
  end if;

  update public."GV_Lugar" set uso = case v_cod when 'PEDIDOS' then 'pedidos' when 'CAJAS' then 'cajas' else null end,
         updated_at = now()
   where sector = v_sec and (uso in ('pedidos','cajas') or v_cod in ('PEDIDOS','CAJAS'))
     and uso is distinct from case v_cod when 'PEDIDOS' then 'pedidos' when 'CAJAS' then 'cajas' else null end;

  update public."GV_Rack_Revisar" set resuelto_en = now(), resuelto_por = v_quien, nota = 'Mapa: ' || v_mot
   where resuelto_en is null and coalesce(public.gv_rack_sector(sector), sector) = v_sec;

  return jsonb_build_object('ok', true, 'sector', v_sec, 'cod', v_cod, 'inner', v_inner, 'master', v_mast, 'emp', v_emp, 'stock', v_res);
end $$;
revoke all on function public.gv_rack_posicion_guardar(text,text,numeric,numeric,text,text) from public, anon;
grant execute on function public.gv_rack_posicion_guardar(text,text,numeric,numeric,text,text) to authenticated;

-- ubicar a mano lo que está en racks sin posición (o cerrar un «a contar» de un sector que no existe)
create or replace function public.gv_rack_ubicar(p_cod text, p_emp text, p_sector text, p_cajas numeric, p_motivo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_sec text := public.gv_rack_sector(p_sector); v_cod text := upper(btrim(coalesce(p_cod,'')));
  v_emp text := upper(coalesce(nullif(btrim(coalesce(p_emp,'')),''), public.gv_empresa_de_articulo(upper(btrim(coalesce(p_cod,'')))), 'LK'));
  v_quien text := 'sup:' || coalesce(auth.jwt() ->> 'email', session_user::text);
  v_sin numeric; v_dep text; v_chk text;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede ubicar racks.';
  end if;
  if v_sec is null then raise exception 'La posición % no existe como rack.', coalesce(p_sector,'?'); end if;
  if coalesce(p_cajas,0) <= 0 then raise exception 'Poné cuántas cajas van a esa posición.'; end if;
  if nullif(btrim(coalesce(p_motivo,'')),'') is null then raise exception 'Escribí quién lo contó / por qué.'; end if;
  v_chk := public.gv_rack_pos_chequear(v_sec, v_cod);
  if v_chk is not null then raise exception '%', v_chk; end if;
  select deposito, sum(delta) into v_dep, v_sin from public."Movimientos_Stock"
   where deposito in ('racks','racks_ch') and upper(btrim(cod_art)) = v_cod
     and (ubicacion is null or public.gv_rack_sector(ubicacion) is null)
     and (case when deposito='racks_ch' then 'CH' else upper(coalesce(empresa,'LK')) end) = v_emp
   group by deposito order by sum(delta) desc limit 1;
  if coalesce(v_sin,0) < p_cajas then
    raise exception 'Del % hay % cajas sin ubicar en racks, no alcanzan para %.', v_cod, round(coalesce(v_sin,0)), p_cajas;
  end if;
  insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, descripcion, unidad, legajo, empresa, ubicacion) values
    (v_cod, v_dep, -p_cajas, 'traslado', 'ubicar en rack ' || v_sec, 'Ubicar racks: ' || p_motivo, 'inner', v_quien, v_emp, null),
    (v_cod, v_dep,  p_cajas, 'traslado', 'ubicar en rack ' || v_sec, 'Ubicar racks: ' || p_motivo, 'inner', v_quien, v_emp, v_sec);
  return jsonb_build_object('ok', true, 'sector', v_sec, 'cod', v_cod, 'cajas', p_cajas);
end $$;
revoke all on function public.gv_rack_ubicar(text,text,text,numeric,text) from public, anon;
grant execute on function public.gv_rack_ubicar(text,text,text,numeric,text) to authenticated;

-- cerrar un «a contar» sin tocar stock (ej. «no hay nada, está bien vacío»)
create or replace function public.gv_rack_revisar_cerrar(p_id bigint, p_nota text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede cerrar un conteo de racks.';
  end if;
  if nullif(btrim(coalesce(p_nota,'')),'') is null then raise exception 'Escribí qué encontraste.'; end if;
  update public."GV_Rack_Revisar" set resuelto_en = now(), nota = p_nota,
         resuelto_por = 'sup:' || coalesce(auth.jwt() ->> 'email', session_user::text)
   where id = p_id and resuelto_en is null;
  if not found then raise exception 'Ese conteo ya estaba cerrado.'; end if;
  return jsonb_build_object('ok', true, 'id', p_id);
end $$;
revoke all on function public.gv_rack_revisar_cerrar(bigint,text) from public, anon;
grant execute on function public.gv_rack_revisar_cerrar(bigint,text) to authenticated;

-- stock de racks que no está en ninguna posición (para ubicarlo a mano desde el Mapa)
create or replace view public.gv_rack_sin_ubicar with (security_invoker = true) as
select upper(btrim(m.cod_art)) cod,
       case when m.deposito='racks_ch' then 'CH' else upper(coalesce(m.empresa,'LK')) end emp,
       sum(m.delta) cajas
  from public."Movimientos_Stock" m
 where m.deposito in ('racks','racks_ch') and (m.ubicacion is null or public.gv_rack_sector(m.ubicacion) is null)
 group by 1,2 having sum(m.delta) <> 0;
grant select on public.gv_rack_sin_ubicar to anon, authenticated;

-- la celda del Mapa: ahora dice si viene del stock o está «a contar»
create or replace view public.gv_rack_celda with (security_invoker = true) as
with lug as (
  select upper(btrim(sector)) sector, empresa, orden, uso from public."GV_Lugar" where activo and tipo = 'rack'
), rp as (
  select sector, emp, nullif(btrim(cod_art),'') cod, coalesce(master_cajas,0) master_cajas, coalesce(innercajas,0) innercajas,
         fuente, motivo, revisar_id
    from public."Racks_Planimetria" where estado = 'ocupado' and nullif(btrim(cod_art),'') is not null
), sec as (select sector from lug union select sector from rp),
nom as (
  select gv_cod_stock(cod) k, min(descripcion) descripcion from public.vista_nombres_articulos
   where descripcion is not null and btrim(descripcion) <> '' group by 1)
select s.sector, substring(s.sector, '^[A-ZÑ]+') rack, l.orden, coalesce(l.empresa, r.emp) empresa, l.uso,
       r.cod, n.descripcion, r.master_cajas, r.innercajas, r.emp emp_carga,
       case when l.sector is null then 'sin_lugar' when r.cod is null then 'libre' else 'ocupado' end estado,
       r.fuente, r.motivo, r.revisar_id
  from sec s left join lug l on l.sector = s.sector left join rp r on r.sector = s.sector
  left join nom n on n.k = gv_cod_stock(r.cod);
grant select on public.gv_rack_celda to anon, authenticated;
