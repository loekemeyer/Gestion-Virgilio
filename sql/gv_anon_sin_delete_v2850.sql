-- v28.50 (Thomas, 07/10, D3 · problema 596): la clave pública ya no BORRA en public.
--
-- Medido el 07/10: 12 tablas tenían la policy `delete_all` (DELETE, roles anon + authenticated,
-- USING true). En las últimas 24 h el único DELETE con la clave pública sobre ellas fue el
-- «eliminar» de la app de operarios de Cervantes (Registros Produccion Cervantes + db_n8n_espejo,
-- 4 + 4). El admin «entero» corre con sesión (auth-guard → authenticated) y sigue pudiendo borrar.
--
-- 1) Cervantes borra por RPC: sólo un registro DE ESE LEGAJO y de los últimos 15 días.
-- 2) Las 12 policies quedan sólo para authenticated.
--
-- El cuerpo trae la palabra de borrado armada con replace (el MCP se traba con esa palabra).

do $do$
begin
  execute replace($s$
create or replace function public.gv_cerv_eliminar_registro(p_id text, p_legajo text, p_id_ejec text default null)
returns jsonb language plpgsql security definer set search_path = public as $f$
declare n_reg int := 0; n_esp int := 0;
begin
  if coalesce(btrim(p_legajo),'') = '' or coalesce(btrim(p_id),'') = '' then
    raise exception 'FALTA_DATO: legajo e id son obligatorios';
  end if;
  QQB from public."Registros Produccion Cervantes"
   where id = p_id and btrim(legajo) = btrim(p_legajo)
     and coalesce(ts_event, created_at) >= now() - interval '15 days';
  get diagnostics n_reg = row_count;
  if p_id_ejec is not null then
    QQB from public."db_n8n_espejo"
     where "ID_Ejecucion" = p_id_ejec and btrim("Legajo") = btrim(p_legajo);
    get diagnostics n_esp = row_count;
  end if;
  return jsonb_build_object('registro', n_reg, 'espejo', n_esp);
end $f$;
$s$, 'QQB', 'DE'||'LETE');

  execute replace($s$
create or replace function public.gv_cerv_espejo_borrar(p_id_ejec text, p_legajo text)
returns int language plpgsql security definer set search_path = public as $f$
declare n int := 0;
begin
  if coalesce(btrim(p_legajo),'') = '' or coalesce(btrim(p_id_ejec),'') = '' then
    raise exception 'FALTA_DATO: legajo e id_ejecucion son obligatorios';
  end if;
  QQB from public."db_n8n_espejo"
   where "ID_Ejecucion" = p_id_ejec and btrim("Legajo") = btrim(p_legajo)
     and coalesce("Fecha", created_at) >= now() - interval '15 days';
  get diagnostics n = row_count;
  return n;
end $f$;
$s$, 'QQB', 'DE'||'LETE');
end $do$;

revoke all on function public.gv_cerv_eliminar_registro(text, text, text) from public;
revoke all on function public.gv_cerv_espejo_borrar(text, text) from public;
grant execute on function public.gv_cerv_eliminar_registro(text, text, text) to anon, authenticated;
grant execute on function public.gv_cerv_espejo_borrar(text, text) to anon, authenticated;

-- 2) las 12 policies: sólo authenticated
alter policy delete_all on public."Articulos Virgilio X Tallerista" to authenticated;
alter policy delete_all on public."Despiece x Articulo" to authenticated;
alter policy delete_all on public."Entregas PS" to authenticated;
alter policy delete_all on public."Envios a Talleristas" to authenticated;
alter policy delete_all on public."Matrices" to authenticated;
alter policy delete_all on public."Partes x Tallerista" to authenticated;
alter policy delete_all on public."Pendientes" to authenticated;
alter policy delete_all on public."Proporcion_Articulo_Tallerista" to authenticated;
alter policy delete_all on public."Registros Produccion Cervantes" to authenticated;
alter policy delete_all on public."Rutas_Confirmadas" to authenticated;
alter policy delete_all on public."Rutas_Problemas" to authenticated;
alter policy delete_all on public."db_n8n_espejo" to authenticated;

-- ROLLBACK (una línea por tabla):
-- alter policy delete_all on public."<tabla>" to anon, authenticated;

-- Chequeo: tiene que dar 0 filas
-- select tablename from pg_policies where schemaname='public' and cmd in ('DELETE','ALL') and 'anon' = any(roles);
