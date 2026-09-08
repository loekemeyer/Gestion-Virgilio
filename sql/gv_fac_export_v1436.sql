-- ═══════════════════════════════════════════════════════════════════════════════════════
-- GV_Fac_Export — historial de lo que Facturación descargó (Excel para ISIS)
-- v14.36 (2026-09-08) · migración gv_fac_export_v1436 · Virgilio (hrxfctzncixxqmpfhskv)
--
-- Dueño (08/09): *"una vez que descargo el excel no puedo ver el detalle más; necesito poder
-- verlo para chequear la información"*. Hoy el archivo se arma en el navegador y se descarga:
-- no queda NADA. Si el archivo se pierde o hay que auditar qué se mandó a ISIS, no hay forma.
--
-- Guarda, por descarga: el nombre del archivo, la empresa, las NP que fueron, y el DETALLE
-- (las mismas filas que se escribieron en el Excel, en `detalle`). Con eso la ventana de
-- Facturación lo muestra en pantalla y lo puede volver a bajar sin rehacer el cálculo —
-- importante, porque `PPP_Base_Pedidos` es amnésica y las líneas de una NP vieja se pierden.
--
-- Tabla NUEVA con prefijo GV_ (no toca nada compartido con Producción). La escritura va por
-- RPC con gate de supervisor: `anon` NO puede insertar (docs/RIESGO-ESTRUCTURAL-CANON.md).
--
-- ROLLBACK:
--   drop function public.gv_fac_export_detalle(bigint);
--   drop function public.gv_fac_export_lista(integer);
--   drop function public.gv_fac_export_registrar(text, text, text, text, text[], integer, jsonb, text);
--   drop table public."GV_Fac_Export";
-- ═══════════════════════════════════════════════════════════════════════════════════════

create table if not exists public."GV_Fac_Export" (
  id         bigserial primary key,
  tipo       text        not null default 'excel_isis',
  archivo    text        not null,
  empresa    text,
  formato    text,
  nps        text[]      not null default '{}',
  n_filas    integer     not null default 0,
  detalle    jsonb       not null default '[]'::jsonb,
  creado_por text,
  creado_at  timestamptz not null default now()
);
create index if not exists gv_fac_export_creado_idx on public."GV_Fac_Export" (creado_at desc);

alter table public."GV_Fac_Export" enable row level security;
-- Sin policy de select para anon: todo pasa por las RPC (SECURITY DEFINER con gate).
grant all on public."GV_Fac_Export" to service_role;
grant usage, select on sequence public."GV_Fac_Export_id_seq" to service_role;

-- ── registrar una descarga ─────────────────────────────────────────────────────────────
create or replace function public.gv_fac_export_registrar(
  p_archivo text,
  p_tipo    text default 'excel_isis',
  p_empresa text default null,
  p_formato text default null,
  p_nps     text[] default '{}',
  p_n_filas integer default 0,
  p_detalle jsonb default '[]'::jsonb,
  p_por     text default null
) returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_id bigint;
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Sólo supervisores pueden registrar una descarga de Facturación.';
  end if;
  if nullif(btrim(coalesce(p_archivo, '')), '') is null then
    raise exception 'Falta el nombre del archivo.';
  end if;
  insert into public."GV_Fac_Export" (tipo, archivo, empresa, formato, nps, n_filas, detalle, creado_por)
  values (coalesce(nullif(btrim(p_tipo), ''), 'excel_isis'), btrim(p_archivo),
          nullif(btrim(coalesce(p_empresa, '')), ''), nullif(btrim(coalesce(p_formato, '')), ''),
          coalesce(p_nps, '{}'), coalesce(p_n_filas, 0), coalesce(p_detalle, '[]'::jsonb),
          nullif(btrim(coalesce(p_por, '')), ''))
  returning id into v_id;
  return v_id;
end $function$;

-- ── listar (liviano: sin el detalle, que puede ser grande) ─────────────────────────────
create or replace function public.gv_fac_export_lista(p_limit integer default 200)
returns table (id bigint, tipo text, archivo text, empresa text, formato text,
               n_nps integer, n_filas integer, creado_por text, creado_at timestamptz, nps text[])
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  select e.id, e.tipo, e.archivo, e.empresa, e.formato,
         coalesce(array_length(e.nps, 1), 0), e.n_filas, e.creado_por, e.creado_at, e.nps
    from public."GV_Fac_Export" e
   where public.gv_es_supervisor_o_servicio()
   order by e.creado_at desc
   limit greatest(1, least(coalesce(p_limit, 200), 1000));
$function$;

-- ── el detalle de una descarga (las filas que fueron al Excel) ─────────────────────────
create or replace function public.gv_fac_export_detalle(p_id bigint)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  select case when public.gv_es_supervisor_o_servicio()
              then (select e.detalle from public."GV_Fac_Export" e where e.id = p_id)
         end;
$function$;

revoke execute on function public.gv_fac_export_registrar(text, text, text, text, text[], integer, jsonb, text) from public;
revoke execute on function public.gv_fac_export_lista(integer) from public;
revoke execute on function public.gv_fac_export_detalle(bigint) from public;
grant execute on function public.gv_fac_export_registrar(text, text, text, text, text[], integer, jsonb, text) to anon, authenticated, service_role;
grant execute on function public.gv_fac_export_lista(integer) to anon, authenticated, service_role;
grant execute on function public.gv_fac_export_detalle(bigint) to anon, authenticated, service_role;
