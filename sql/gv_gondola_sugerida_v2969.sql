-- ============================================================================================
-- v29.69 (Luis, 13/10/2026) — EL CÓDIGO QUE NO TIENE GÓNDOLA EN EL MAPA + MARCAR TANDAS ANÓMALAS
--
-- Luis: "si el modulo de pickeo los promptea a pickear un codigo para el que no tiene registro de
-- lugar (en que gondola esta) y el que pickea lo agarra, debería preguntarle de que gondola lo
-- agarro y debería aparecerle la sugerencia al admin para ajustar gondolas de la misma forma que
-- le aparece para ajustar stock." · y (D3) "solo en pantalla … que haya algo para marcar los anomalos".
--
-- Medido el 13/10 sobre 60 días: 25 códigos sin celda en el Mapa y 131 líneas de picking
-- (231/232/233, 567, 565, 998E…), unas 2 por día: el aviso no va a ser ruido.
--
-- El flujo, igual al del conteo de góndola (CG, v28.58):
--   app  → evento PKG  "COD|lo que escribió el operario|TANDA"  (sin ts_inicio: no abre tarea)
--   base → gv_gondola_sugerida_pendientes()  los PKG sin resolver, con todo lo que hace falta
--          para decidir: descripción, si esa celda existe, qué código tiene hoy, si el código ya
--          tiene celda, cuántas cajas levantó en esa tanda
--   admin→ gv_gondola_sugerida_resolver(cid, true, sector, cajas_max) = gv_lugar_item_guardar
--          (da de alta la celda en el Mapa) · (cid, false) = se descarta, el Mapa no se toca
--
-- ⚠ La pregunta al operario va DESPUÉS de registrar el pick (el PKC se manda igual): si el celular
--   muere en la pregunta, lo pickeado no se pierde. Y se puede saltear: no frena el picking.
-- ⚠ Lo que el operario escribe NO se inventa: gv_gondola_sector sólo devuelve una celda que existe
--   en GV_Lugar (F9 → F09, m 13 → M13); lo que no matchea queda como «dicho» y lo resuelve el admin.
--
-- Rollback:
--   drop function if exists public.gv_gondola_sugerida_resolver(text, boolean, text, numeric);
--   drop function if exists public.gv_gondola_sugerida_pendientes();
--   drop function if exists public.gv_gondola_sector(text);
--   drop function if exists public.gv_gondola_sugerida_instalar();
--   drop table if exists public."GV_Gondola_Sugerida_Resol";
--   drop function if exists public.gv_analisis_marcas(int, text);
--   drop function if exists public.gv_analisis_marcar(text, text, text, text);
--   drop function if exists public.gv_analisis_marca_instalar();
--   drop table if exists public."GV_Analisis_Marca";
--   delete from public."GV_Reglas_Centinela" where version = 'v29.69';
-- ============================================================================================

-- ─────────────────── 1. la tabla de resueltas (DDL adentro: el MCP se cuelga) ───────────────────
create or replace function public.gv_gondola_sugerida_instalar()
returns text language plpgsql security definer set search_path = public as $$
begin
  create table if not exists public."GV_Gondola_Sugerida_Resol" (
    client_id text primary key,
    estado    text not null,            -- aceptada | rechazada
    cod       text,
    sector    text,
    cajas_max numeric,
    por       text,
    at        timestamptz not null default now(),
    detalle   jsonb
  );
  alter table public."GV_Gondola_Sugerida_Resol" enable row level security;
  revoke all on public."GV_Gondola_Sugerida_Resol" from anon, authenticated;
  return 'ok';
end $$;
revoke all on function public.gv_gondola_sugerida_instalar() from public, anon, authenticated;
select public.gv_gondola_sugerida_instalar();

-- ─────────────────── 2. lo que tipea el operario → una celda del Mapa ───────────────────
create or replace function public.gv_gondola_sector(p text)
returns text language plpgsql stable security definer set search_path = public as $$
declare s text; l text; n text; c text;
begin
  s := upper(btrim(coalesce(p, ''))); s := replace(replace(replace(s, '-', ''), '.', ''), ' ', '');
  if s = '' then return null; end if;
  if exists (select 1 from public."GV_Lugar" g where g.sector = s and g.tipo = 'gondola') then return s; end if;
  l := substring(s from '^([A-ZÑ]+)'); n := substring(s from '([0-9]+)$');
  if l is null or n is null then return null; end if;
  n := regexp_replace(n, '^0+(?=.)', '');
  c := l || lpad(n, 2, '0');
  if exists (select 1 from public."GV_Lugar" g where g.sector = c and g.tipo = 'gondola') then return c; end if;
  c := l || n;
  if exists (select 1 from public."GV_Lugar" g where g.sector = c and g.tipo = 'gondola') then return c; end if;
  return null;   -- v29.69-gond: lo que no es una celda del Mapa NO se inventa
end $$;
grant execute on function public.gv_gondola_sector(text) to anon, authenticated;

-- ─────────────────── 3. lo que el supervisor tiene pendiente de dar de alta ───────────────────
create or replace function public.gv_gondola_sugerida_pendientes()
returns table(client_id text, ts timestamptz, legajo text, nombre text, tanda text,
              cod text, cod_base text, descripcion text, sector_dicho text, sector text,
              sector_ok boolean, ocupada_por text, tiene_gondola boolean, veces int, cajas numeric)
language sql stable security definer set search_path = public as $$
  with e as (
    select r.client_id, r.ts_cliente ts, r.legajo,
           upper(btrim(split_part(r.texto, '|', 1))) cod,
           btrim(split_part(r.texto, '|', 2)) dicho,
           upper(btrim(split_part(r.texto, '|', 3))) tanda
      from public."Registros_Produccion_Virgilio" r
     where r.opcion = 'PKG' and not public.es_legajo_test(r.legajo)
       and r.ts_cliente > now() - interval '120 days'
       and not exists (select 1 from public."GV_Gondola_Sugerida_Resol" z where z.client_id = r.client_id)
  ), x as (
    select e.*, regexp_replace(regexp_replace(regexp_replace(e.cod, '\s+(LK|CH)$', ''), '([0-9E])L$', '\1'), '^0+(?=.)', '') ck,
           public.gv_gondola_sector(e.dicho) sec
      from e
  )
  select x.client_id, x.ts, x.legajo,
         (select max(p."Empleado") from public."Empleados" p where p."Legajo"::text = x.legajo),
         nullif(x.tanda, ''), x.cod, x.ck,
         (select max(n.descripcion) from public.vista_nombres_articulos n
           where regexp_replace(upper(btrim(n.cod)), '^0+(?=.)', '') = x.ck),
         x.dicho, x.sec, x.sec is not null,
         (select string_agg(distinct i.cod, ' · ') from public."GV_Lugar_Item" i
           where i.sector = x.sec and coalesce(i.activo, true)
             and regexp_replace(upper(btrim(i.cod)), '^0+(?=.)', '') <> x.ck),
         exists (select 1 from public."GV_Lugar_Item" i join public."GV_Lugar" l on l.sector = i.sector
                  where regexp_replace(upper(btrim(i.cod)), '^0+(?=.)', '') = x.ck and coalesce(i.activo, true)
                    and l.tipo = 'gondola' and coalesce(l.activo, true)),
         (select count(*)::int from x y where y.ck = x.ck and y.sec is not distinct from x.sec),
         (select coalesce(sum(case when split_part(r2.texto, '|', 4) ~ '^[0-9.]+$' then split_part(r2.texto, '|', 4)::numeric else 0 end), 0)
            from public."Registros_Produccion_Virgilio" r2
           where r2.opcion = 'PKC' and upper(btrim(split_part(r2.texto, '|', 1))) = x.tanda
             and regexp_replace(regexp_replace(regexp_replace(upper(btrim(split_part(r2.texto, '|', 2))), '\s+(LK|CH)$', ''), '([0-9E])L$', '\1'), '^0+(?=.)', '') = x.ck)
    from x order by x.ts desc;
$$;
revoke all on function public.gv_gondola_sugerida_pendientes() from public, anon;
grant execute on function public.gv_gondola_sugerida_pendientes() to authenticated;

-- ─────────────────── 4. el ✓ del supervisor: da de alta la celda en el Mapa ───────────────────
create or replace function public.gv_gondola_sugerida_resolver(p_cid text, p_aceptar boolean,
                                                               p_sector text default null, p_cajas_max numeric default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; v_sec text; v_por text; v_res record;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'SUPERVISOR: la gondola la da de alta un supervisor';
  end if;
  if exists (select 1 from public."GV_Gondola_Sugerida_Resol" z where z.client_id = p_cid) then
    return jsonb_build_object('ok', false, 'motivo', 'ya_resuelto');
  end if;
  select * into r from public.gv_gondola_sugerida_pendientes() q where q.client_id = p_cid;
  if r.client_id is null then return jsonb_build_object('ok', false, 'motivo', 'no_esta_pendiente'); end if;
  v_por := coalesce(nullif(current_setting('request.jwt.claims', true)::jsonb->>'email', ''), session_user);

  if not coalesce(p_aceptar, false) then
    insert into public."GV_Gondola_Sugerida_Resol" (client_id, estado, cod, sector, por, detalle)
    values (p_cid, 'rechazada', r.cod, coalesce(public.gv_gondola_sector(p_sector), r.sector), v_por,
            jsonb_build_object('dicho', r.sector_dicho, 'tanda', r.tanda, 'legajo', r.legajo));
    return jsonb_build_object('ok', true, 'estado', 'rechazada');
  end if;

  v_sec := coalesce(public.gv_gondola_sector(p_sector), r.sector);
  if v_sec is null then
    return jsonb_build_object('ok', false, 'motivo', 'sector_no_existe',
                              'dicho', r.sector_dicho);
  end if;
  select * into v_res from public.gv_lugar_item_guardar(v_sec, r.cod_base, 'articulo', p_cajas_max);
  insert into public."GV_Gondola_Sugerida_Resol" (client_id, estado, cod, sector, cajas_max, por, detalle)
  values (p_cid, 'aceptada', r.cod, v_sec, p_cajas_max, v_por,
          jsonb_build_object('dicho', r.sector_dicho, 'tanda', r.tanda, 'legajo', r.legajo,
                             'guardado', to_jsonb(v_res)));
  return jsonb_build_object('ok', true, 'estado', 'aceptada', 'sector', v_sec, 'cod', r.cod_base);
end $$;
revoke all on function public.gv_gondola_sugerida_resolver(text, boolean, text, numeric) from public, anon;
grant execute on function public.gv_gondola_sugerida_resolver(text, boolean, text, numeric) to authenticated;

-- ─────────────────── 5. D3: marcar una tanda como ANÓMALA o revisada ───────────────────
-- Sólo pantalla (Luis: "solo en pantalla"), sin Telegram. La marca es de la TANDA, no de la fase.
create or replace function public.gv_analisis_marca_instalar()
returns text language plpgsql security definer set search_path = public as $$
begin
  create table if not exists public."GV_Analisis_Marca" (
    tanda   text primary key,
    estado  text not null,              -- anomala | revisada | sin
    nota    text,
    por     text,
    legajo  text,
    at      timestamptz not null default now()
  );
  alter table public."GV_Analisis_Marca" enable row level security;
  revoke all on public."GV_Analisis_Marca" from anon, authenticated;
  return 'ok';
end $$;
revoke all on function public.gv_analisis_marca_instalar() from public, anon, authenticated;
select public.gv_analisis_marca_instalar();

create or replace function public.gv_analisis_marcar(p_tanda text, p_estado text, p_nota text default null,
                                                    p_legajo text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_t text := upper(btrim(coalesce(p_tanda, ''))); v_e text := lower(btrim(coalesce(p_estado, '')));
        v_por text; v_n text := nullif(btrim(coalesce(p_nota, '')), '');
begin
  if not public.gv_analisis_acceso_ok(p_legajo) then
    raise exception 'ACCESO: el Analisis Productivo es para el supervisor y los legajos habilitados';
  end if;
  if v_t = '' then raise exception 'Falta la tanda'; end if;
  v_por := coalesce(nullif(current_setting('request.jwt.claims', true)::jsonb->>'email', ''),
                    nullif(btrim(coalesce(p_legajo, '')), ''), session_user);
  if v_e in ('', 'sin', 'ninguna') then
    update public."GV_Analisis_Marca" set estado = 'sin', nota = v_n, por = v_por, legajo = p_legajo, at = now()
     where tanda = v_t;
    return jsonb_build_object('ok', true, 'tanda', v_t, 'estado', 'sin');
  end if;
  if v_e not in ('anomala', 'revisada') then raise exception 'Estado invalido: %', p_estado; end if;
  insert into public."GV_Analisis_Marca" (tanda, estado, nota, por, legajo)
  values (v_t, v_e, v_n, v_por, nullif(btrim(coalesce(p_legajo, '')), ''))
  on conflict (tanda) do update set estado = excluded.estado, nota = excluded.nota,
    por = excluded.por, legajo = excluded.legajo, at = now();
  return jsonb_build_object('ok', true, 'tanda', v_t, 'estado', v_e, 'por', v_por);
end $$;
revoke all on function public.gv_analisis_marcar(text, text, text, text) from public;
grant execute on function public.gv_analisis_marcar(text, text, text, text) to anon, authenticated;

create or replace function public.gv_analisis_marcas(p_dias int default 30, p_legajo text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_out jsonb;
begin
  if not public.gv_analisis_acceso_ok(p_legajo) then
    raise exception 'ACCESO: el Analisis Productivo es para el supervisor y los legajos habilitados';
  end if;
  select coalesce(jsonb_object_agg(m.tanda, jsonb_build_object('estado', m.estado, 'nota', m.nota,
                                                               'por', m.por, 'at', m.at)), '{}'::jsonb)
    into v_out from public."GV_Analisis_Marca" m
   where m.at > now() - make_interval(days => greatest(coalesce(p_dias, 30), 1) + 120)
     and m.estado <> 'sin';
  return v_out;
end $$;
revoke all on function public.gv_analisis_marcas(int, text) from public;
grant execute on function public.gv_analisis_marcas(int, text) to anon, authenticated;

-- ─────────────────── 6. centinela ───────────────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
 ('gv_gondola_sugerida_resolver', 'funcion', 'gv_lugar_item_guardar',
  'El si del supervisor a una gondola informada en el picking DA DE ALTA la celda en el Mapa.',
  'Luis 13/10/2026', 'v29.69')) v(o, c, p, r, q, ver)
 where not exists (select 1 from public."GV_Reglas_Centinela" z where z.objeto = v.o and z.patron = v.p);

-- Chequeo:
--   select * from public.gv_gondola_sugerida_pendientes();
--   select public.gv_gondola_sector('f9');            -- F09
--   select public.gv_analisis_marcas(30, '8');
--   select * from public.gv_reglas_perdidas;          -- vacía = todo bien
