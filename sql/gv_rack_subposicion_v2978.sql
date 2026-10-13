-- ═══════════════════════════════════════════════════════════════════════════════════════
-- v29.78 — SUB-POSICIONES DE RACK (Luis, 2026-10-13)
--
-- «Algunos racks tienen mucho espacio que estamos desaprovechando, por lo que nos gustaría
--  poder guardar multiples codigos en un espacio … si alguien guarda algo a un rack que ya
--  esta ocupado por otro codigo, promptee para decir de que lado lo dejan … que separe ese
--  rack en Izq y Der (basicamente, una subdivision de racks)» · «pongamos la posibilidad de,
--  por ejemplo, Y25-1, Y25-2, Y25-3».
--
-- EL MODELO, en una línea:
--   un rack puede estar DIVIDIDO en N partes (1..9, numeradas de izquierda a derecha) y la
--   DIRECCIÓN de una parte es «Y25-2». Sin partir (N = 1) la dirección sigue siendo «Y25»,
--   o sea que para los 258 racks de hoy NADA cambia.
--
-- POR QUÉ ASÍ y no con filas nuevas en GV_Lugar (Y25I / Y25D):
--   `gv_rack_sector()` es el cuello único — 18 funciones y 12 vistas cuelgan de ahí. Si la
--   parte viaja DENTRO del texto de la dirección y esa función la pela, todo lo que hoy
--   agrupa, ordena y alerta POR RACK (Mapa, gv_rack_sin_ubicar, desfase, stock sin lugar,
--   orden de urgencia de Bajar de racks, alertas de Telegram) sigue andando sin tocarlo,
--   y NINGUNA función cambia de firma: la parte entra por el mismo argumento de siempre.
--   Con filas nuevas en GV_Lugar habría que duplicar el layout, migrar el stock que ya está
--   y decidir qué devuelve gv_rack_sector('Y25') — tres problemas nuevos para el mismo fin.
--
-- DOS FUNCIONES, DOS PREGUNTAS DISTINTAS (no se confunden):
--   gv_rack_sector(txt) → EL RACK            («Y25-2» → «Y25»)   · para AGRUPAR y validar
--   gv_rack_pos(txt)    → LA DIRECCIÓN       («Y25 2» → «Y25-2»)  · para ESCRIBIR ubicacion
--
-- LO QUE SOSTIENE QUE NO SE PIERDA UNA CAJA:
--   un rack partido EXIGE la parte en todo movimiento (trigger aa_gv_racks_ajuste_sin_posicion
--   → RACKS_FALTA_PARTE). Sin eso las cajas caerían «en el rack, sin parte» y el Mapa
--   mostraría una parte fantasma que nadie sabe dónde está.
--
-- FORWARD-FACING: al 13/10 hay 258 racks activos, 89 posiciones con stock y CERO con dos
-- códigos (el guard de hoy lo prohíbe), así que no hay nada que migrar.
--
-- Rollback al final del archivo.
-- ═══════════════════════════════════════════════════════════════════════════════════════

-- ── 1) la subdivisión es del RACK, no del movimiento ───────────────────────────────────
alter table public."GV_Lugar" add column if not exists gv_sub smallint;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'gv_lugar_gv_sub_chk') then
    alter table public."GV_Lugar" add constraint gv_lugar_gv_sub_chk check (gv_sub is null or gv_sub between 1 and 9);
  end if;
end $$;
comment on column public."GV_Lugar".gv_sub is
  'v29.78 — en cuántas partes está dividido el rack (1..9, de izquierda a derecha). NULL o 1 = entero. La dirección de una parte es «Y25-2».';

-- bitácora de particiones: quién partió un rack y por qué (append-only)
create table if not exists public."GV_Rack_Particion" (
  id bigserial primary key,
  sector text not null,
  partes smallint not null,
  partes_antes smallint,
  por text,
  motivo text,
  ts timestamptz not null default now()
);
alter table public."GV_Rack_Particion" enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='GV_Rack_Particion' and policyname='gv_rkpart_sel') then
    create policy gv_rkpart_sel on public."GV_Rack_Particion" for select using (true);
  end if;
end $$;
grant select on public."GV_Rack_Particion" to anon, authenticated;
revoke insert, update on public."GV_Rack_Particion" from anon, authenticated;

-- ── 2) las tres funciones base ─────────────────────────────────────────────────────────
-- en cuántas partes está dividido un rack (1 = entero)
create or replace function public.gv_rack_subs(p text)
returns int language sql stable set search_path to 'public' as $function$
  select greatest(1, coalesce((select l.gv_sub from public."GV_Lugar" l
                                where l.sector = public.gv_rack_sector(p) and l.tipo = 'rack' and l.activo), 1))::int
$function$;

-- la PARTE que pide el texto: «Y25-2» → 2 · «Y25 3» → 3 · «Y25 izq» → 1 · «Y25 der» → 2 · «Y25» → null
-- ⚠ devuelve null si el texto completo YA es un rack (R01AD existe: no es «R01A parte D»)
create or replace function public.gv_rack_lado(p text)
returns int language sql stable set search_path to 'public' as $function$
  with t as (select upper(regexp_replace(coalesce(p,''), '\s+', '', 'g')) k),
       e as (select (select 1 from public."GV_Lugar" l where l.tipo='rack' and l.activo and l.sector = (select k from t)) ex)
  select case
    when (select ex from e) is not null then null
    when public.gv_rack_sector(p) is null then null
    when public.gv_rack_subs(p) <= 1 then null   -- la «parte 2» de un rack ENTERO no existe
    when (select k from t) ~ '[-/._]?(IZQ?|DER?)$'
      then case when (select k from t) ~ '[-/._]?IZQ?$' then 1 else 2 end
    when (select k from t) ~ '[-/._]?(0?[1-9])$'
      then nullif(regexp_replace((select k from t), '^.*?[-/._]?(0?[1-9])$', '\1'), '')::int
    else null
  end
$function$;

-- EL RACK (pela la parte). Firma y semántica de siempre para todo lo que ya existe.
create or replace function public.gv_rack_sector(p text)
returns text language sql stable set search_path to 'public' as $function$
  with t as (select upper(regexp_replace(coalesce(p,''), '\s+', '', 'g')) k)
  select coalesce(
    -- 1) tal cual (R01AD, A1, X22…)
    (select l.sector from public."GV_Lugar" l where l.tipo = 'rack' and l.activo and l.sector = (select k from t)),
    -- 2) con el cero adelante y AD/AT (R1Ad → R01AD, W1 → W01)
    (select l.sector from public."GV_Lugar" l where l.tipo = 'rack' and l.activo
      and l.sector = regexp_replace((select k from t), '^([A-Z]{1,2})(\d)(AD|AT)?$', '\10\2\3')),
    -- 3) v29.78 — sacándole la PARTE: «Y25-2», «Y25/2», «Y25.2», «Y252»? NO: sólo con separador,
    --    o un dígito pegado a un sector de 2 dígitos ya existente (Y25 2 → Y252 sin espacios).
    (select l.sector from public."GV_Lugar" l where l.tipo = 'rack' and l.activo
      and l.sector = regexp_replace((select k from t), '[-/._](0?[1-9])$', '')),
    (select l.sector from public."GV_Lugar" l where l.tipo = 'rack' and l.activo
      and l.sector = regexp_replace((select k from t), '(0?[1-9])$', '')
      and l.gv_sub is not null and l.gv_sub > 1),
    -- 4) alias de entrada: IZQ = 1, DER = 2 (nunca se muestran; sólo por si alguien tipea)
    (select l.sector from public."GV_Lugar" l where l.tipo = 'rack' and l.activo
      and l.sector = regexp_replace((select k from t), '[-/._]?(IZQ?|DER?)$', ''))
  )
$function$;

-- LA DIRECCIÓN canónica, lo que se ESCRIBE en Movimientos_Stock.ubicacion.
-- Nunca falla: si el rack está partido y no vino la parte, devuelve el rack pelado y el
-- GUARD es el que frena (un normalizador que devuelve null terminaría escribiendo «sin ubicar»).
create or replace function public.gv_rack_pos(p text)
returns text language sql stable set search_path to 'public' as $function$
  select case
    when public.gv_rack_sector(p) is null then null
    when public.gv_rack_subs(p) <= 1 then public.gv_rack_sector(p)
    when public.gv_rack_lado(p) is null then public.gv_rack_sector(p)
    else public.gv_rack_sector(p) || '-' || public.gv_rack_lado(p)::text
  end
$function$;

-- ¿falta decir en qué parte? (el rack está partido y el texto no trae parte)
create or replace function public.gv_rack_falta_parte(p text)
returns boolean language sql stable set search_path to 'public' as $function$
  select public.gv_rack_sector(p) is not null
     and public.gv_rack_subs(p) > 1
     and public.gv_rack_lado(p) is null
$function$;

grant execute on function public.gv_rack_subs(text), public.gv_rack_lado(text),
  public.gv_rack_pos(text), public.gv_rack_falta_parte(text) to anon, authenticated;

-- una sola RPC para que el front resuelva una dirección escrita a mano
create or replace function public.gv_rack_dir(p text)
returns jsonb language sql stable set search_path to 'public' as $function$
  select jsonb_build_object(
    'rack',   public.gv_rack_sector(p),
    'pos',    public.gv_rack_pos(p),
    'parte',  public.gv_rack_lado(p),
    'partes', case when public.gv_rack_sector(p) is null then null else public.gv_rack_subs(p) end,
    'falta',  public.gv_rack_falta_parte(p))
$function$;
grant execute on function public.gv_rack_dir(text) to anon, authenticated;

-- ── 3) PARTIR / UNIR un rack ───────────────────────────────────────────────────────────
-- La llama el operario desde Ingreso a racks cuando se topa con un rack ocupado por OTRO
-- código (es lo que pidió Luis: que lo decida en el momento, parado frente al rack), así que
-- NO lleva guard de supervisor — es un cambio de layout, reversible, y queda en GV_Rack_Particion.
-- Lo que ya estaba SIN parte se muda a la parte que diga el operario: si quedara sin parte,
-- nadie sabría de qué lado está.
create or replace function public.gv_rack_partir(p_sector text, p_partes int, p_parte_actual int default null,
                                                 p_motivo text default null, p_legajo text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_rack text := public.gv_rack_sector(p_sector);
  v_n int := p_partes; v_antes int; v_k int := p_parte_actual;
  v_quien text := coalesce(nullif(btrim(coalesce(p_legajo,'')),''), 'sup:' || coalesce(auth.jwt() ->> 'email', session_user::text));
  r record; v_movidos int := 0; v_ocup int;
begin
  if v_rack is null then raise exception 'La posición % no existe como rack.', coalesce(p_sector,'?'); end if;
  if v_n is null or v_n < 1 or v_n > 9 then raise exception 'Las partes van de 1 a 9 (viniste con %).', coalesce(v_n::text,'null'); end if;
  perform pg_advisory_xact_lock(hashtext('gv_rack_pos|' || v_rack));
  -- el guard de «rack partido exige la parte» no aplica a los traslados de ESTA función
  perform set_config('gv.rack_partir', '1', true);
  select greatest(1, coalesce(gv_sub, 1)) into v_antes from public."GV_Lugar" where sector = v_rack;
  if v_antes = v_n then return jsonb_build_object('ok', true, 'sector', v_rack, 'partes', v_n, 'sin_cambios', true); end if;

  -- ¿alguna parte que dejaría de existir tiene stock?
  if v_n < v_antes then
    select count(*) into v_ocup from (
      select 1 from public."Movimientos_Stock" m
       where m.deposito in ('racks','racks_ch') and public.gv_rack_sector(m.ubicacion) = v_rack
         and coalesce(public.gv_rack_lado(m.ubicacion), 0) > v_n
       group by upper(btrim(m.cod_art)), public.gv_rack_lado(m.ubicacion) having sum(m.delta) <> 0) z;
    if v_ocup > 0 then
      raise exception 'No puedo dejar % en % partes: la parte % todavía tiene mercadería. Bajala o movela primero.',
        v_rack, v_n, v_n + 1;
    end if;
  end if;

  -- lo que está SIN parte se muda a la parte que indicó el operario
  if v_n > 1 then
    if v_k is null or v_k < 1 or v_k > v_n then
      if exists (select 1 from public."Movimientos_Stock" m
                  where m.deposito in ('racks','racks_ch') and public.gv_rack_sector(m.ubicacion) = v_rack
                    and public.gv_rack_lado(m.ubicacion) is null
                  group by upper(btrim(m.cod_art)) having sum(m.delta) <> 0) then
        raise exception 'Decime en qué parte (1..%) está lo que ya hay en %.', v_n, v_rack;
      end if;
    else
      for r in select m.deposito dep, upper(btrim(m.cod_art)) cod,
                      case when m.deposito='racks_ch' then 'CH' else upper(coalesce(m.empresa,'LK')) end emp,
                      sum(m.delta) s
                 from public."Movimientos_Stock" m
                where m.deposito in ('racks','racks_ch') and public.gv_rack_sector(m.ubicacion) = v_rack
                  and public.gv_rack_lado(m.ubicacion) is null
                group by 1,2,3 having sum(m.delta) <> 0
      loop
        insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, descripcion, unidad, legajo, empresa, ubicacion) values
          (r.cod, r.dep, -r.s, 'traslado', 'partir rack ' || v_rack, 'Rack partido en ' || v_n || ' partes: lo que había pasa a la parte ' || v_k, 'inner', v_quien, r.emp, v_rack),
          (r.cod, r.dep,  r.s, 'traslado', 'partir rack ' || v_rack, 'Rack partido en ' || v_n || ' partes: lo que había pasa a la parte ' || v_k, 'inner', v_quien, r.emp, v_rack || '-' || v_k);
        v_movidos := v_movidos + 1;
      end loop;
    end if;
  else
    -- volver a rack ENTERO: lo que esté en una parte vuelve a la dirección pelada
    for r in select m.deposito dep, upper(btrim(m.cod_art)) cod,
                    case when m.deposito='racks_ch' then 'CH' else upper(coalesce(m.empresa,'LK')) end emp,
                    public.gv_rack_lado(m.ubicacion) parte, sum(m.delta) s
               from public."Movimientos_Stock" m
              where m.deposito in ('racks','racks_ch') and public.gv_rack_sector(m.ubicacion) = v_rack
                and public.gv_rack_lado(m.ubicacion) is not null
              group by 1,2,3,4 having sum(m.delta) <> 0
    loop
      insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, descripcion, unidad, legajo, empresa, ubicacion) values
        (r.cod, r.dep, -r.s, 'traslado', 'unir rack ' || v_rack, 'Rack vuelve a ser uno solo: la parte ' || r.parte || ' pasa a ' || v_rack, 'inner', v_quien, r.emp, v_rack || '-' || r.parte),
        (r.cod, r.dep,  r.s, 'traslado', 'unir rack ' || v_rack, 'Rack vuelve a ser uno solo: la parte ' || r.parte || ' pasa a ' || v_rack, 'inner', v_quien, r.emp, v_rack);
      v_movidos := v_movidos + 1;
    end loop;
  end if;

  update public."GV_Lugar" set gv_sub = case when v_n <= 1 then null else v_n end, updated_at = now() where sector = v_rack;
  insert into public."GV_Rack_Particion"(sector, partes, partes_antes, por, motivo)
  values (v_rack, v_n, v_antes, v_quien, nullif(btrim(coalesce(p_motivo,'')),''));
  return jsonb_build_object('ok', true, 'sector', v_rack, 'partes', v_n, 'partes_antes', v_antes,
                            'parte_actual', v_k, 'codigos_movidos', v_movidos);
end $function$;
grant execute on function public.gv_rack_partir(text,int,int,text,text) to anon, authenticated;

-- ── 4) las dos vistas del Mapa: una fila por DIRECCIÓN ─────────────────────────────────
-- ⚠ `sector` pasa a ser la DIRECCIÓN (Y25 o Y25-2) y se agregan `rack`, `parte` y `partes`.
--   Es lo que hace que el front siga andando sin tocarlo: los chips de Bajar de racks, las
--   posiciones de Stocks→Ajustar y las celdas del Mapa ya tratan la posición como un string
--   opaco, así que ahora llevan la parte sola. Lo que necesita EL RACK usa la columna `rack`.
-- ⚠ el `id` es un hash de sector|cod|fuente: va con la parte adentro, o dos partes del mismo
--   código en el mismo rack tendrían el MISMO id y PostgREST devolvería una sola.
create or replace view public."Racks_Planimetria" as
with lug as (
  select l.sector, l.empresa, l.uso, l.created_at, greatest(1, coalesce(l.gv_sub, 1)) partes
    from public."GV_Lugar" l where l.tipo = 'rack' and l.activo
), dir as (
  select l.sector rack, l.empresa, l.uso, l.created_at, l.partes,
         case when l.partes > 1 then g.k else null end parte,
         case when l.partes > 1 then l.sector || '-' || g.k else l.sector end sector
    from lug l, lateral generate_series(1, l.partes) g(k)
), st as (
  select public.gv_rack_sector(m.ubicacion) rack, public.gv_rack_lado(m.ubicacion) parte,
         upper(btrim(m.cod_art)) cod,
         case when m.deposito = 'racks_ch' then 'CH' else upper(coalesce(m.empresa, 'LK')) end emp,
         sum(m.delta) cajas, min(m.ts) desde
    from public."Movimientos_Stock" m
   where m.deposito in ('racks','racks_ch') and m.ubicacion is not null
   group by 1,2,3,4 having sum(m.delta) > 0
), rev as (
  select v.id, coalesce(public.gv_rack_sector(v.sector), v.sector) rack, public.gv_rack_lado(v.sector) parte,
         v.cod, v.emp, coalesce(v.cajas_planimetria, v.cajas_stock, 0) cajas,
         v.master_planimetria, v.motivo, v.creado_en
    from public."GV_Rack_Revisar" v where v.resuelto_en is null
), cont as (
  select s.rack, s.parte,
         case when s.parte is not null then s.rack || '-' || s.parte else s.rack end sector,
         s.cod, s.emp, s.cajas, 'stock' fuente, null::bigint revisar_id, null::text motivo, s.desde, null::numeric master_plani
    from st s where s.rack is not null
  union all
  select r.rack, r.parte,
         case when r.parte is not null then r.rack || '-' || r.parte else r.rack end,
         r.cod, r.emp, r.cajas, 'a_contar', r.id, r.motivo, r.creado_en, r.master_planimetria
    from rev r
   where not exists (select 1 from st s where s.rack = r.rack and coalesce(s.parte,0) = coalesce(r.parte,0) and s.cod = r.cod)
), secs as (
  select sector, rack, parte, partes from dir
  union
  select c.sector, c.rack, c.parte, public.gv_rack_subs(c.rack) from cont c
   where not exists (select 1 from dir d where d.sector = c.sector)
)
select abs(hashtextextended(x.sector || '|' || coalesce(c.cod,'') || '|' || coalesce(c.fuente,''), 0::bigint)) as id,
       coalesce(c.emp, l.empresa) as emp,
       x.sector,
       coalesce(c.cod, case l.uso when 'pedidos' then 'Pedidos' when 'cajas' then 'Cajas' else null end) as cod_art,
       case when c.cod is null then 0::numeric
            when c.fuente = 'a_contar' then coalesce(c.master_plani, 0::numeric)
            else coalesce(round(c.cajas / x2.cxm), 0::numeric) end as master_cajas,
       coalesce(c.cajas, 0::numeric) as innercajas,
       case when c.cod is not null or (l.uso = any (array['pedidos','cajas'])) then 'ocupado' else 'libre' end as estado,
       coalesce(c.desde, l.created_at) as created_at,
       c.fuente, c.motivo, c.revisar_id,
       x.rack, x.parte, x.partes
  from secs x
  left join lug l on l.sector = x.rack
  left join cont c on c.sector = x.sector
  left join public."GV_Rack_CxM" x2 on x2.cod = c.cod and x2.emp = c.emp;
alter view public."Racks_Planimetria" set (security_invoker = true);

create or replace view public.gv_rack_celda as
with lug as (
  select upper(btrim(l.sector)) sector, l.empresa, l.orden, l.uso, greatest(1, coalesce(l.gv_sub,1)) partes
    from public."GV_Lugar" l where l.activo and l.tipo = 'rack'
), rp as (
  select r.sector, r.rack, r.parte, r.partes, r.emp, nullif(btrim(r.cod_art), '') cod,
         coalesce(r.master_cajas, 0) master_cajas, coalesce(r.innercajas, 0) innercajas, r.fuente, r.motivo, r.revisar_id
    from public."Racks_Planimetria" r
   where r.estado = 'ocupado' and nullif(btrim(r.cod_art), '') is not null
  union all
  select u.sector, u.sector, null::int, 1, 'IN', u.cod, 0, coalesce(u.cantidad, 0), 'insumo', null::text, null::bigint
    from public.gv_insumo_ubicacion u
   where u.sector is not null
     and not exists (select 1 from public."Racks_Planimetria" r1
                      where r1.sector = u.sector and upper(r1.cod_art) = upper(btrim(u.cod)) and r1.fuente is not null)
), sec as (
  select case when l.partes > 1 then l.sector || '-' || g.k else l.sector end sector,
         l.sector rack, case when l.partes > 1 then g.k else null end parte, l.partes
    from lug l, lateral generate_series(1, l.partes) g(k)
  union
  select p.sector, coalesce(p.rack, p.sector), p.parte, coalesce(p.partes, 1) from rp p
), nom as (
  select public.gv_cod_stock(v.cod) k, min(v.descripcion) descripcion
    from public.vista_nombres_articulos v
   where v.descripcion is not null and btrim(v.descripcion) <> '' group by 1
)
select s.sector,
       substring(s.rack, '^[A-ZÑ]+') as rack,
       l.orden,
       coalesce(l.empresa, r.emp) as empresa,
       l.uso, r.cod,
       coalesce(n.descripcion, (select i.nombre from public."Insumos" i where upper(btrim(i.cod)) = upper(r.cod) limit 1)) as descripcion,
       r.master_cajas, r.innercajas, r.emp as emp_carga,
       case when l.sector is null then 'sin_lugar' when r.cod is null then 'libre' else 'ocupado' end as estado,
       r.fuente, r.motivo, r.revisar_id,
       s.rack as pos_rack, s.parte, s.partes
  from sec s
  left join lug l on l.sector = s.rack
  left join rp r on r.sector = s.sector
  left join nom n on n.k = public.gv_cod_stock(r.cod);
alter view public.gv_rack_celda set (security_invoker = true);

-- ── 5) el guard y las dos lecturas ─────────────────────────────────────────────────────
-- ⚠ EL PUNTO QUE EVITA QUE SE PIERDA UNA CAJA: en un rack PARTIDO, todo movimiento lleva la
--   parte. Sin esto las cajas quedan «en el rack, sin parte»: el Mapa las muestra como una
--   parte fantasma y Bajar de racks no sabe de dónde sacarlas.
create or replace function public.gv_racks_ajuste_sin_posicion()
returns trigger language plpgsql set search_path to 'public' as $function$
begin
  -- marcador: v29.04-racks-pos
  if new.deposito in ('racks','racks_ch') and new.tipo in ('ajuste','inicial') and coalesce(new.legajo,'') = '0'
     and (new.ubicacion is null or public.gv_rack_sector(new.ubicacion) is null) then
    raise exception 'RACKS_SIN_POSICION: un ajuste de racks lleva la posición del rack (ej. X22). No se grabó nada.'
      using errcode = '23514';
  end if;
  -- v29.78-racks-parte: rack partido → la parte es obligatoria
  if new.deposito in ('racks','racks_ch') and coalesce(new.delta,0) <> 0
     and coalesce(current_setting('gv.rack_partir', true), '') <> '1'
     and public.gv_rack_falta_parte(new.ubicacion) then
    raise exception 'RACKS_FALTA_PARTE: % está dividido en % partes: decí en cuál va (ej. %-1). No se grabó nada.',
      public.gv_rack_sector(new.ubicacion), public.gv_rack_subs(new.ubicacion), public.gv_rack_sector(new.ubicacion)
      using errcode = '23514';
  end if;
  return new;
end $function$;

-- el saldo de UNA dirección: si el texto trae parte, mide la parte; si no, el rack entero
create or replace function public.gv_rack_saldo_pos(p_sector text, p_cod text, p_emp text default null)
returns numeric language sql stable set search_path to 'public' as $function$
  select coalesce(sum(m.delta), 0) from public."Movimientos_Stock" m
  where m.deposito in ('racks','racks_ch') and m.ubicacion is not null
  and public.gv_rack_sector(m.ubicacion) = public.gv_rack_sector(p_sector)
  and (public.gv_rack_lado(p_sector) is null
       or coalesce(public.gv_rack_lado(m.ubicacion), -1) = public.gv_rack_lado(p_sector))
  and upper(btrim(m.cod_art)) = upper(btrim(p_cod))
  and (p_emp is null or (case when m.deposito='racks_ch' then 'CH' else upper(coalesce(m.empresa,'LK')) end) = upper(p_emp))
$function$;

-- ¿puedo poner este código en esta dirección?
--   null              → sí
--   'error: …'        → no existe / es un lugar reservado
--   'falta_parte:N'   → el rack está partido en N: hay que decir en cuál
--   'ocupado:<cod>'   → esa DIRECCIÓN la tiene otro código
-- ⚠ sigue devolviendo 'ocupado:' igual que antes, así que los 4 llamadores de siempre
--   (ingreso, nacional, mover, recibir importación) se comportan idéntico. Quien ofrece
--   PARTIR el rack es el front, que sabe que el rack está entero y ocupado por otro.
create or replace function public.gv_rack_pos_chequear(p_sector text, p_cod text)
returns text language plpgsql stable set search_path to 'public' as $function$
declare v_rack text := public.gv_rack_sector(p_sector); v_uso text; v_otro text;
        v_n int; v_k int;
begin
 if v_rack is null then return 'error: la posición ' || coalesce(p_sector,'?') || ' no existe como rack'; end if;
 select uso into v_uso from public."GV_Lugar" where sector = v_rack;
 if v_uso in ('pedidos','cajas') then return 'error: el destino es un lugar reservado'; end if;
 v_n := public.gv_rack_subs(v_rack); v_k := public.gv_rack_lado(p_sector);
 if v_n > 1 and v_k is null then return 'falta_parte:' || v_n; end if;
 select cod_art into v_otro from public."Racks_Planimetria"
  where rack = v_rack and coalesce(parte, 0) = coalesce(v_k, 0)
    and estado = 'ocupado' and fuente is not null and upper(cod_art) <> upper(btrim(p_cod)) limit 1;
 if v_otro is not null then return 'ocupado:' || v_otro; end if;
 return null;
end $function$;

-- ── 6) los 8 ESCRITORES: escriben la DIRECCIÓN, no el rack pelado ──────────────────────
-- Se aplican como PARCHE DE TEXTO sobre pg_get_functiondef (varias sesiones tocan estos
-- objetos y una copia propia pisaría su trabajo), son idempotentes (marcador «v29.78-parte»)
-- y FALLAN con un raise si el texto no matchea. Las reglas de cada función se conservan:
-- gv_imp_imputar_ingreso_racks en racks_plani_ingreso · recepcion_imp/client_id/p_cerrar en
-- gv_imp_recibir · «lo contado de más sale de lo SIN POSICIÓN» en gv_rack_posicion_guardar ·
-- RACKS_SIN_POSICION en el trigger.  (El SQL exacto corrido está en el commit de la v29.78;
--  cada bloque es: d := pg_get_functiondef(...); if d ~ 'v29.78-parte' then return; end if;
--  verificar los trozos; replace(); execute d.)
--
--  racks_plani_ingreso            → declara v_pos := gv_rack_pos(p_sector) y lo escribe en ubicacion
--  racks_plani_ingreso_nacional   → idem
--  racks_plani_mover              → v_o / v_d son DIRECCIONES; el origen filtra por parte y
--                                   frena si el rack partido no la nombra
--  registrar_baja_racks           → v_ubic := gv_rack_pos(v_sec) + raise RACKS_FALTA_PARTE
--  gv_rack_ubicar                 → v_sec := gv_rack_pos(p_sector) + aviso de parte faltante
--  gv_rack_posicion_guardar       → v_sec = la DIRECCIÓN, v_rack = EL RACK; el vaciado pasa a
--                                   gv_rack_pos(m.ubicacion) = v_sec (⚠ el punto peligroso:
--                                   con el criterio por rack, contar una parte borraba la otra)
--  gv_imp_recibir                 → escribe gv_rack_pos(v_sec); los GV_Lugar van por el rack
--  gv_imp_recibir_contexto        → el lateral cuenta el rack entero y devuelve `partes`
--
-- Los reemplazos EXACTOS que se aplicaron (de ← a), para reaplicar o auditar:
--   racks_plani_ingreso
--     ' v_chk text; v_mid bigint;'  →  '... v_pos text := public.gv_rack_pos(p_sector);  -- v29.78-parte: ...'
--     "'ingreso a racks '||v_sec||"  →  "'ingreso a racks '||v_pos||"
--     ", 'inner', nullif(p_legajo,''), v_emp, v_sec)"  →  "..., v_emp, v_pos)"
--   racks_plani_ingreso_nacional
--     ' v_cutoff timestamptz; v_disp numeric; v_chk text;'  →  '... v_pos text := public.gv_rack_pos(p_sector);  -- v29.78-parte'
--     "'nacional a racks '||v_sec"  →  "'nacional a racks '||v_pos"
--     "'nacional desde '||v_orig||' a '||v_sec, 'inner', nullif(p_legajo,''), v_emp, v_sec)"  →  "... v_pos ... v_pos)"
--   registrar_baja_racks
--     'v_ubic := public.gv_rack_sector(v_sec);'  →  'v_ubic := public.gv_rack_pos(v_sec);' + raise RACKS_FALTA_PARTE
--   gv_rack_ubicar
--     'v_sec text := public.gv_rack_sector(p_sector);'  →  'v_sec text := public.gv_rack_pos(p_sector);'
--     + raise '% está dividido en % partes' cuando gv_rack_falta_parte(p_sector)
--   gv_rack_posicion_guardar  (los 6 trozos, todos verificados con position() antes de tocar)
--     'v_sec text := public.gv_rack_sector(p_sector);' → '... gv_rack_pos(...); v_rack text := ... gv_rack_sector(...);'
--     "hashtext('gv_rack_pos|' || v_sec)"                     → '... || v_rack)'
--     '(select empresa from public."GV_Lugar" where sector = v_sec)' → '... = v_rack)'
--     'and m.ubicacion is not null and public.gv_rack_sector(m.ubicacion) = v_sec' → '... gv_rack_pos(m.ubicacion) = v_sec'
--     "where sector = v_sec and (uso in ('pedidos','cajas')"  → 'where sector = v_rack and (...'
--     'coalesce(public.gv_rack_sector(sector), sector) = v_sec' → '... = v_rack'
--     + raise cuando gv_rack_falta_parte(p_sector)
--   gv_imp_recibir  (6 trozos)
--     'l.sector = v_sec and l.empresa not in (v_emp)'         → 'l.sector = public.gv_rack_sector(v_sec) and ...'
--     '(select l.empresa from public."GV_Lugar" l where l.sector = v_sec)' → '... public.gv_rack_sector(v_sec))'
--     "(select 1 from public.\"GV_Lugar\" l where l.sector = v_sec and l.empresa = 'CH')" → '... gv_rack_sector(v_sec) ...'
--     "v_ref || ' → rack ' || v_sec, 'inner', v_por, v_emp, v_sec)" → "... gv_rack_pos(v_sec) ... gv_rack_pos(v_sec))"
--     'public.gv_rack_sector(sector) = v_sec and upper(cod) = v_cod' → '... = public.gv_rack_sector(v_sec) ...'
--     + la línea de 'falta_parte:%' → conflicto 'rack_falta_parte: ...' (al lado de la de 'ocupado:%')
--   gv_imp_recibir_contexto  (2 trozos)
--     "where r.sector = l.sector and r.estado = 'ocupado'"    → 'where public.gv_rack_sector(r.sector) = l.sector ...'
--     "'cod', rp.cod, 'cajas', rp.cajas) order by l.orden)"   → "... , 'partes', greatest(1, coalesce(l.gv_sub, 1))) ..."
--   racks_plani_mover  → reescrita completa (está más abajo, en el bloque de funciones nuevas)
--
-- ⚠ Dos trampas que costaron un intento cada una, para no repetirlas:
--   · en un raise de plpgsql generado DENTRO de un do $$…$$, el placeholder va con UN «%»
--     (escribir «%%» lo deja literal y Postgres dice «too many parameters specified for RAISE»);
--   · un comentario «-- …» al final de la línea de un INSERT se come el «;» del statement.

-- ── 7) los centinelas (16 filas) ───────────────────────────────────────────────────────
-- select * from public.gv_reglas_perdidas;   → vacía = las 16 reglas siguen puestas
-- (el insert está en el commit; objetos: gv_rack_sector, gv_rack_pos, gv_rack_partir ×2,
--  gv_rack_pos_chequear, gv_rack_saldo_pos, gv_racks_ajuste_sin_posicion, racks_plani_ingreso,
--  racks_plani_ingreso_nacional, racks_plani_mover, registrar_baja_racks, gv_rack_ubicar,
--  gv_rack_posicion_guardar, gv_imp_recibir, Racks_Planimetria, gv_rack_celda)

-- ═══ CHEQUEOS ═════════════════════════════════════════════════════════════════════════
-- select * from public.gv_reglas_perdidas;                   -- vacía
-- select * from public.gv_rack_sin_ubicar;                   -- nada quedó sin ubicar
-- select sector, rack, parte, partes, cod_art, innercajas, estado
--   from public."Racks_Planimetria" where partes > 1 order by sector;   -- los racks partidos
-- select * from public."GV_Rack_Particion" order by id desc;  -- quién partió qué y por qué
-- select l.sector, l.gv_sub from public."GV_Lugar" l where l.gv_sub is not null;
--
-- Medido el 13/10, ANTES de que exista ningún rack partido: la huella de gv_rack_sector sobre
-- los 2.645 textos de ubicación reales NO cambió (c82ba953f63ab26f7de76c42abc2f05f), y las dos
-- vistas devolvieron las MISMAS filas y el mismo md5 (259 y 304). O sea: con 0 racks partidos
-- el sistema entero se comporta exactamente como antes.
--
-- La prueba de punta a punta (13 pasos, en transacción abortada sobre AB05/816E) está en
-- tests/rack-subposicion.cjs para el front y en el commit para el SQL: ingreso a un rack
-- ocupado → ocupado:816E · partir en 2 con el 816E a la parte 1 · saldos 208/0/208 · ingreso
-- sin parte → falta_parte:2 · ingreso a la parte libre → ok · ingreso de otro código a la
-- parte ocupada → ocupado:816E · ajuste sin parte → RACKS_FALTA_PARTE · baja desde la parte
-- → saldo 206 y el conteo contra AB05-1 · unir con dos códigos → frena · mover a la parte
-- ocupada → frena · el Mapa muestra las dos celdas · 0 sin ubicar.

-- ═══ ROLLBACK ═════════════════════════════════════════════════════════════════════════
-- 1) volver cada rack partido a entero (mueve el stock de vuelta a la dirección pelada):
--      select public.gv_rack_partir(sector, 1, null, 'rollback v29.78')
--        from public."GV_Lugar" where gv_sub is not null;
-- 2) las vistas y las funciones vuelven con el .sql de su versión anterior:
--      sql/gv_racks_canon_v2277.sql (Racks_Planimetria) · sql/gv_rack_celda_v2267.sql ·
--      sql/gv_rack_conteo_v2468.sql (registrar_baja_racks) · sql/gv_imp_recibir_*.sql
-- 3) la columna y la bitácora quedan sin uso (no hace falta borrarlas):
--      alter table public."GV_Lugar" drop column gv_sub;   -- sólo si se quiere limpiar

-- ── racks_plani_mover: reescrita (es chica y no tiene regla propia) ───────────────────
create or replace function public.racks_plani_mover(p_origen text, p_cod text, p_destino text, p_inner numeric, p_master numeric)
 returns text language plpgsql security definer set search_path to 'public'
as $function$
declare
 -- v29.78-parte: v_o / v_d son la DIRECCIÓN (Y25 o Y25-2); el RACK sale de gv_rack_sector()
 v_o text := public.gv_rack_pos(p_origen); v_d text := public.gv_rack_pos(p_destino);
 v_ko int := public.gv_rack_lado(p_origen);
 v_cod text := upper(replace(btrim(coalesce(p_cod,'')), ' ', ''));
 r record; v_chk text;
begin
 if p_inner is null or p_inner <= 0 or p_inner > 100000 then return 'error: cantidad inválida'; end if;
 if coalesce(btrim(p_origen),'') = '' or coalesce(btrim(p_destino),'') = '' then return 'error: falta ubicación'; end if;
 if v_o is null then return 'error: el origen no es una posición de rack'; end if;
 if v_d is null then return 'error: el destino no existe en la planimetría'; end if;
 if public.gv_rack_falta_parte(p_origen) then
   return 'error: ' || public.gv_rack_sector(p_origen) || ' está dividido en ' || public.gv_rack_subs(p_origen) || ' partes: decí de cuál sacás';
 end if;
 if v_o = v_d then return 'error: mismo lugar'; end if;
 select m.deposito dep, case when m.deposito='racks_ch' then 'CH' else upper(coalesce(m.empresa,'LK')) end emp, sum(m.delta) s
 into r from public."Movimientos_Stock" m
 where m.deposito in ('racks','racks_ch') and m.ubicacion is not null
 and public.gv_rack_sector(m.ubicacion) = public.gv_rack_sector(v_o)
 and (v_ko is null or coalesce(public.gv_rack_lado(m.ubicacion), -1) = v_ko)
 and upper(btrim(m.cod_art)) = v_cod
 group by 1,2 having sum(m.delta) > 0 order by sum(m.delta) desc limit 1;
 if r.s is null then return 'error: el origen no tiene ese artículo'; end if;
 if r.s < p_inner then return 'error: no hay tantas cajas en el origen'; end if;
 v_chk := public.gv_rack_pos_chequear(p_destino, v_cod);
 if v_chk like 'ocupado:%' then return 'error: el destino está ocupado por otro artículo'; end if;
 if v_chk like 'falta_parte:%' then
   return 'error: ' || public.gv_rack_sector(p_destino) || ' está dividido en ' || public.gv_rack_subs(p_destino) || ' partes: decí en cuál lo dejás';
 end if;
 if v_chk is not null then return v_chk; end if;
 insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo, empresa, ubicacion) values
 (v_cod, r.dep, -p_inner, 'traslado', 'mover rack '||v_o||' → '||v_d, 'inner', 'mover', r.emp, v_o),
 (v_cod, r.dep, p_inner, 'traslado', 'mover rack '||v_o||' → '||v_d, 'inner', 'mover', r.emp, v_d);
 perform public.gv_rack_cxm_anotar(v_cod, r.emp, p_inner, p_master);
 return 'ok';
end $function$;
