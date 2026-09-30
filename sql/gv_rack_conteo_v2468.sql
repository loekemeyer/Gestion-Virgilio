-- v24.68 (Thomas, 30/09/2026 · D23/D24) — BAJAR DE RACKS: posición obligatoria, sobrante a
-- excedente y CONTEO A CIEGAS de lo que quedó en el rack y en la góndola. Si el conteo no
-- coincide con el sistema, queda PENDIENTE y lo aprueba un SUPERVISOR (recién ahí se ajusta).

-- 1) la tabla de conteos
create table if not exists public."GV_Rack_Conteo" (
  id          bigserial primary key,
  creado      timestamptz not null default now(),
  legajo      text,
  cod_art     text not null,
  empresa     text,
  tipo        text not null check (tipo in ('rack','gondola')),
  lugar       text,
  sistema     numeric not null,
  contado     numeric not null,
  diferencia  numeric generated always as (contado - sistema) stored,
  estado      text not null default 'pendiente' check (estado in ('ok','pendiente','aprobado','rechazado')),
  resuelto_por text,
  resuelto_at timestamptz,
  nota        text,
  ref         text,
  client_id   text unique
);
alter table public."GV_Rack_Conteo" enable row level security;
revoke insert, update, delete, truncate on public."GV_Rack_Conteo" from anon, authenticated;

-- 2) registrar_baja_racks: acepta por ítem `excedente` (cajas que no entran en góndola) y
--    `conteo_rack` / `conteo_gondola` (cajas contadas a ciegas). Parche sobre la definición VIVA.
do $patch$
declare d text; n text;
begin
  d := pg_get_functiondef('public.registrar_baja_racks(jsonb)'::regprocedure);
  if d like '%v24.68-conteo%' then raise notice 'ya aplicado'; return; end if;
  n := d;
  n := replace(n, 'v_nombre text;',
    'v_nombre text; v_exc numeric; v_cr numeric; v_cg numeric; v_sis numeric; v_dual boolean; -- v24.68-conteo');
  n := replace(n, 'v_emp := nullif(btrim(it->>''emp''),'''');',
    'v_emp := nullif(btrim(it->>''emp''),'''');' || chr(10) ||
    ' v_exc := least(greatest(coalesce(nullif(it->>''excedente'','''')::numeric, 0), 0), v_caj);' || chr(10) ||
    ' v_cr := nullif(it->>''conteo_rack'','''')::numeric; v_cg := nullif(it->>''conteo_gondola'','''')::numeric;');
  n := replace(n, 'values (v_cod, v_desc, ''terminado'', v_caj, ''baja_racks''',
                  'values (v_cod, v_desc, ''terminado'', v_caj - v_exc, ''baja_racks''');
  n := replace(n, 'v_cid || ''-t'', v_emp) on conflict do nothing;',
    'v_cid || ''-t'', v_emp) on conflict do nothing;' || chr(10) ||
    ' if v_exc > 0 then' || chr(10) ||
    '  insert into public."Movimientos_Stock" (cod_art, descripcion, deposito, delta, tipo, ref, legajo, client_id, empresa)' || chr(10) ||
    '  values (v_cod, v_desc, ''excedente'', v_exc, ''baja_racks'', v_ref || '' · no entró en góndola'', v_leg, v_cid || ''-x'', v_emp) on conflict do nothing;' || chr(10) ||
    ' end if;' || chr(10) ||
    ' if v_ins > 0 and v_cr is not null and v_ubic is not null then' || chr(10) ||
    '  v_sis := public.gv_rack_saldo_pos(v_ubic, v_cod);' || chr(10) ||
    '  insert into public."GV_Rack_Conteo" (legajo, cod_art, empresa, tipo, lugar, sistema, contado, estado, ref, client_id)' || chr(10) ||
    '  values (v_leg, v_cod, v_emp, ''rack'', v_ubic, v_sis, v_cr, case when v_cr = v_sis then ''ok'' else ''pendiente'' end, v_ref, v_cid || ''-cr'') on conflict do nothing;' || chr(10) ||
    '  if v_cr <> v_sis then perform tg_enqueue(''🔎 CONTEO DE RACK distinto — '' || v_cod || coalesce('' · '' || v_desc, '''') || '' en '' || v_ubic || '': sistema '' || v_sis || '' cj, contó '' || v_cr || '' cj (legajo '' || v_leg || ''). Lo aprueba un supervisor en Gestión.'', ''rkconteo|'' || v_cid || ''|r''); end if;' || chr(10) ||
    ' end if;' || chr(10) ||
    ' if v_ins > 0 and v_cg is not null then' || chr(10) ||
    '  v_dual := exists (select 1 from public.codigos_duales cd where upper(btrim(cd.cod)) = upper(btrim(v_cod)));' || chr(10) ||
    '  select coalesce(sum(m.delta), 0) into v_sis from public."Movimientos_Stock" m' || chr(10) ||
    '   where m.deposito = ''terminado'' and upper(btrim(m.cod_art)) = upper(btrim(v_cod))' || chr(10) ||
    '     and (not v_dual or v_emp is null or upper(coalesce(m.empresa, '''')) = upper(v_emp));' || chr(10) ||
    '  insert into public."GV_Rack_Conteo" (legajo, cod_art, empresa, tipo, lugar, sistema, contado, estado, ref, client_id)' || chr(10) ||
    '  values (v_leg, v_cod, v_emp, ''gondola'', null, v_sis, v_cg, case when v_cg = v_sis then ''ok'' else ''pendiente'' end, v_ref, v_cid || ''-cg'') on conflict do nothing;' || chr(10) ||
    '  if v_cg <> v_sis then perform tg_enqueue(''🔎 CONTEO DE GÓNDOLA distinto — '' || v_cod || coalesce('' · '' || v_desc, '''') || '': sistema '' || v_sis || '' cj, contó '' || v_cg || '' cj (legajo '' || v_leg || ''). Lo aprueba un supervisor en Gestión.'', ''rkconteo|'' || v_cid || ''|g''); end if;' || chr(10) ||
    ' end if;');
  if n = d or n not like '%v_caj - v_exc%' or n not like '%GV_Rack_Conteo%' or n not like '%v_exc := least%' then
    raise exception 'registrar_baja_racks: el texto vivo no matchea, no se aplicó nada';
  end if;
  execute n;
end $patch$;

-- 3) lo que espera aprobación (sólo supervisor)
create or replace function public.gv_rack_conteo_pendientes()
returns table (id bigint, creado timestamptz, legajo text, cod_art text, descripcion text, empresa text,
               tipo text, lugar text, sistema numeric, contado numeric, diferencia numeric)
language sql stable security definer set search_path = public as $$
  select c.id, c.creado, c.legajo, c.cod_art,
         (select max(m.descripcion) from public."Movimientos_Stock" m where m.client_id = replace(replace(c.client_id,'-cr','-r'),'-cg','-r')),
         c.empresa, c.tipo, c.lugar, c.sistema, c.contado, c.diferencia
    from public."GV_Rack_Conteo" c
   where c.estado = 'pendiente' and (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
   order by c.creado;
$$;

-- 4) aprobar (ajusta el stock por la diferencia contada) o rechazar (no toca nada)
create or replace function public.gv_rack_conteo_resolver(p_id bigint, p_aprobar boolean, p_nota text default null)
returns text language plpgsql security definer set search_path = public as $$
declare c record; v_por text;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede aprobar conteos';
  end if;
  v_por := coalesce(nullif(auth.jwt()->>'email',''), 'servicio');
  select * into c from public."GV_Rack_Conteo" where id = p_id for update;
  if not found then raise exception 'Conteo % no existe', p_id; end if;
  if c.estado <> 'pendiente' then return 'ya estaba ' || c.estado; end if;
  if p_aprobar and c.diferencia <> 0 then
    insert into public."Movimientos_Stock" (cod_art, descripcion, deposito, delta, tipo, ref, legajo, client_id, empresa, ubicacion)
    values (c.cod_art, 'Conteo ' || c.tipo || ' aprobado (' || c.sistema || ' → ' || c.contado || ')',
            case when c.tipo = 'rack' then 'racks' else 'terminado' end, c.diferencia, 'ajuste',
            'conteo ' || c.tipo || ' #' || c.id, 'sup:' || v_por, 'rkconteo_' || c.id, c.empresa,
            case when c.tipo = 'rack' then c.lugar end)
    on conflict do nothing;
  end if;
  update public."GV_Rack_Conteo"
     set estado = case when p_aprobar then 'aprobado' else 'rechazado' end,
         resuelto_por = v_por, resuelto_at = now(), nota = p_nota
   where id = p_id;
  return case when p_aprobar then 'aprobado' else 'rechazado' end;
end $$;
revoke all on function public.gv_rack_conteo_resolver(bigint, boolean, text) from public;
grant execute on function public.gv_rack_conteo_resolver(bigint, boolean, text) to anon, authenticated;
grant execute on function public.gv_rack_conteo_pendientes() to anon, authenticated;

-- Rollback: drop function gv_rack_conteo_resolver(bigint,boolean,text); drop function gv_rack_conteo_pendientes();
--           registrar_baja_racks: quitar el bloque marcado v24.68-conteo (la definición anterior está en
--           el historial de la sesión; el cambio sólo agrega y con items viejos se comporta igual).
