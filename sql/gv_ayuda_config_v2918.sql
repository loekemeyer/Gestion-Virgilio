-- v29.18 (Luis, 09/10/2026): las API keys y el modelo del asistente de ayuda se cargan desde el ADMIN
-- (⚙️ Configuración → Asistente IA operarios). La clave va al Vault de Supabase y NUNCA vuelve al navegador:
-- la pantalla sólo ve «tiene clave · termina en XXXX». La Edge Function gv-ayuda la lee con service_role.
create table if not exists public."GV_Ayuda_Config" (
  proveedor   text primary key check (proveedor in ('gemini','groq','openrouter')),
  modelo      text,
  activo      boolean not null default true,
  orden       int not null default 9,
  secret_id   uuid,
  clave_fin   text,
  updated_at  timestamptz not null default now(),
  updated_by  text
);
alter table public."GV_Ayuda_Config" enable row level security;
revoke all on public."GV_Ayuda_Config" from anon, authenticated;
insert into public."GV_Ayuda_Config"(proveedor, modelo, orden) values
  ('gemini','gemini-2.5-flash',1), ('groq','llama-3.3-70b-versatile',2),
  ('openrouter','meta-llama/llama-3.3-70b-instruct:free',3)
on conflict (proveedor) do nothing;

-- lo que ve la pantalla (sin la clave)
create or replace function public.gv_ayuda_config_leer()
returns table(proveedor text, modelo text, activo boolean, orden int, tiene_clave boolean, clave_fin text,
              updated_at timestamptz, updated_by text)
language plpgsql security definer set search_path = public as $$
begin
  if not public.es_supervisor_virgilio() then raise exception 'SUPERVISOR: hace falta la sesión de supervisor'; end if;
  return query select c.proveedor, c.modelo, c.activo, c.orden, c.secret_id is not null, c.clave_fin, c.updated_at, c.updated_by
    from public."GV_Ayuda_Config" c order by c.orden, c.proveedor;
end $$;

-- guardar: clave vacía = no la toca; p_principal = este va primero (los otros quedan de respaldo)
create or replace function public.gv_ayuda_config_guardar(p_proveedor text, p_api_key text default null,
  p_modelo text default null, p_activo boolean default null, p_principal boolean default false,
  p_borrar_clave boolean default false)
returns jsonb language plpgsql security definer set search_path = public, vault as $$
declare v_id uuid; v_quien text := coalesce(auth.jwt()->>'email', 'sup');
begin
  if not public.es_supervisor_virgilio() then raise exception 'SUPERVISOR: hace falta la sesión de supervisor'; end if;
  if p_proveedor not in ('gemini','groq','openrouter') then raise exception 'proveedor inválido'; end if;
  select secret_id into v_id from public."GV_Ayuda_Config" where proveedor = p_proveedor;
  if p_borrar_clave then
    if v_id is not null then perform vault.update_secret(v_id, ''); end if;
    update public."GV_Ayuda_Config" set secret_id = null, clave_fin = null where proveedor = p_proveedor;
  elsif nullif(btrim(p_api_key),'') is not null then
    if length(btrim(p_api_key)) < 20 or btrim(p_api_key) ~ '\s' then raise exception 'La clave no parece válida'; end if;
    if v_id is null then
      v_id := vault.create_secret(btrim(p_api_key), 'gv_ayuda_'||p_proveedor||'_'||extract(epoch from now())::bigint,
                                  'API key del asistente de ayuda ('||p_proveedor||')');
    else
      perform vault.update_secret(v_id, btrim(p_api_key));
    end if;
    update public."GV_Ayuda_Config" set secret_id = v_id, clave_fin = right(btrim(p_api_key),4) where proveedor = p_proveedor;
  end if;
  update public."GV_Ayuda_Config" set
    modelo = coalesce(nullif(btrim(p_modelo),''), modelo),
    activo = coalesce(p_activo, activo),
    updated_at = now(), updated_by = v_quien
   where proveedor = p_proveedor;
  if p_principal then
    update public."GV_Ayuda_Config" set orden = case when proveedor = p_proveedor then 1 else orden + 1 end
     where proveedor = p_proveedor or orden >= 1;
    update public."GV_Ayuda_Config" c set orden = x.rn
      from (select proveedor, row_number() over (order by orden, proveedor) rn from public."GV_Ayuda_Config") x
     where x.proveedor = c.proveedor;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- lo que lee la Edge Function (sólo service_role)
create or replace function public.gv_ayuda_proveedores_server()
returns table(proveedor text, modelo text, api_key text)
language sql security definer set search_path = public, vault as $$
  select c.proveedor, c.modelo, s.decrypted_secret
    from public."GV_Ayuda_Config" c join vault.decrypted_secrets s on s.id = c.secret_id
   where c.activo and coalesce(s.decrypted_secret,'') <> ''
   order by c.orden, c.proveedor;
$$;
revoke all on function public.gv_ayuda_config_leer() from public, anon;
grant execute on function public.gv_ayuda_config_leer() to authenticated;
revoke all on function public.gv_ayuda_config_guardar(text,text,text,boolean,boolean,boolean) from public, anon;
grant execute on function public.gv_ayuda_config_guardar(text,text,text,boolean,boolean,boolean) to authenticated;
revoke all on function public.gv_ayuda_proveedores_server() from public, anon, authenticated;
grant execute on function public.gv_ayuda_proveedores_server() to service_role;
-- Rollback: revocar las tres funciones y limpiar GV_Ayuda_Config (las claves quedan en vault.secrets con nombre gv_ayuda_*).
