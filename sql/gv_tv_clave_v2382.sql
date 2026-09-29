-- v23.82 (Luis, 29/09): CLAVE DE LA TV para entrar como operario.
-- La TV del depósito (monitor/tv.html) muestra chiquito una clave de 4 dígitos que cambia cada
-- 15 minutos. El operario la tipea en el celular, elige su nombre de la lista (o «+» y su legajo).
-- Sirve para que se entre estando EN el depósito: no es un candado de seguridad (la TV lee con la
-- clave pública), es presencia.
--
-- ⚠ Sin tabla y sin secreto en el repo (el repo es público): la clave sale de un md5 del
-- system_identifier del cluster + el tramo de 15 min. pg_control_system() sólo lo lee postgres,
-- por eso las funciones son SECURITY DEFINER.
-- Vale la clave del tramo actual y la del anterior (hasta 30 min).

create or replace function public.gv_tv_clave_de(p_tramo bigint)
returns text language sql stable security definer set search_path = public, pg_catalog as $$
  select lpad(((('x' || substr(md5((select system_identifier from pg_control_system())::text
                 || ':gv-tv-clave:' || p_tramo::text), 1, 8))::bit(32)::bigint) % 10000)::text, 4, '0');
$$;
revoke all on function public.gv_tv_clave_de(bigint) from public, anon, authenticated;

create or replace function public.gv_tv_clave_actual()
returns jsonb language sql stable security definer set search_path = public, pg_catalog as $$
  select jsonb_build_object(
    'clave', public.gv_tv_clave_de(floor(extract(epoch from now()) / 900)::bigint),
    'cambia_en_s', 900 - (floor(extract(epoch from now()))::bigint % 900));
$$;
grant execute on function public.gv_tv_clave_actual() to anon, authenticated;

-- Valida la clave y devuelve los operarios para elegir: Empleados activos de Virgilio (sede V o sin
-- sede). El resto entra con «+» y su legajo.
create or replace function public.gv_tv_clave_validar(p_clave text)
returns jsonb language plpgsql stable security definer set search_path = public, pg_catalog as $$
declare
  v_t bigint := floor(extract(epoch from now()) / 900)::bigint;
  v_c text := regexp_replace(coalesce(p_clave, ''), '\D', '', 'g');
begin
  if v_c = '' or (v_c <> public.gv_tv_clave_de(v_t) and v_c <> public.gv_tv_clave_de(v_t - 1)) then
    return jsonb_build_object('ok', false);
  end if;
  return jsonb_build_object('ok', true, 'operarios', coalesce((
    select jsonb_agg(jsonb_build_object('legajo', btrim(e."Legajo"), 'nombre', btrim(e."Empleado"))
                     order by btrim(e."Empleado"))
      from public."Empleados" e
     where upper(btrim(coalesce(e."Activo", ''))) = 'SI'
       and upper(btrim(coalesce(e."Sede", ''))) in ('V', '')
       and btrim(coalesce(e."Legajo", '')) not in ('', '0', '1')
       and btrim(coalesce(e."Empleado", '')) <> ''), '[]'::jsonb));
end $$;
grant execute on function public.gv_tv_clave_validar(text) to anon, authenticated;

-- Rollback:
-- drop function public.gv_tv_clave_validar(text); drop function public.gv_tv_clave_actual();
-- drop function public.gv_tv_clave_de(bigint);
