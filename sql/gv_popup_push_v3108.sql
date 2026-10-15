-- v31.08 (Luis, 15/10/2026): pop-ups de sistema (C2/C4/C5) por WEB PUSH al ÚLTIMO dispositivo activo de Luis.
--
--   Luis: "se debería considerar el último dispositivo que registra actividad del usuario" y
--   (D6) "que no le salten mis avisos a 9a59c479".
--
--   1) GV_Popup_Disp: un renglón por dispositivo con rol «luis». La app manda la ACTIVIDAD (un click o
--      una tecla, como mucho una vez por minuto, y al abrir la app a la vista) y la suscripción de push.
--   2) Destino de un aviso = el dispositivo no bloqueado con la última actividad (gv_popup_destino).
--      El pop-up de la app sale SÓLO ahí; en los demás se cierra solo.
--   3) Al entrar un aviso, trigger → Edge Function gv-popup-push → Web Push al destino: suena y aparece
--      el aviso de Windows aunque la app esté CERRADA (con Chrome corriendo). Tocarlo abre la app.
--   4) La clave VAPID privada está en Vault ('gv_popup_vapid_priv'); la lee la función con service_role.
--
--   Review: select * from public.gv_popup_review order by creado_at desc;
--           select * from public."GV_Popup_Disp" order by ultima_actividad desc nulls last;

create table if not exists public."GV_Popup_Disp" (
  dispositivo      text primary key,
  persona          text not null,
  ultima_actividad timestamptz,
  bloqueado        boolean not null default false,
  push_sub         jsonb,
  push_alta        timestamptz,
  push_ult_envio   timestamptz,
  push_ult_estado  text
);
alter table public."GV_Popup_Disp" enable row level security;
revoke all on public."GV_Popup_Disp" from anon, authenticated;

alter table public."GV_Popup_Aviso" add column if not exists push_destino text;
alter table public."GV_Popup_Aviso" add column if not exists push_estado  text;

-- D6: 9a59c479 no recibe los avisos de Luis.
insert into public."GV_Popup_Disp"(dispositivo, persona, bloqueado)
values ('9a59c479-d125-4f4b-b453-066777e1193c', 'luis', true)
on conflict (dispositivo) do update set bloqueado = true;

create or replace function public.gv_popup_destino(p_persona text)
returns text language sql stable security definer set search_path = public, pg_temp as $f$
  select d.dispositivo from public."GV_Popup_Disp" d
   where d.persona = lower(p_persona) and not d.bloqueado and d.ultima_actividad is not null
   order by d.ultima_actividad desc limit 1;   -- ultimo-activo-v3108
$f$;

-- Actividad y suscripción (la app la llama con la sesión de supervisor).
create or replace function public.gv_popup_actividad(p_persona text, p_dispositivo text, p_push_sub jsonb default null, p_solo_push boolean default false)
returns void language plpgsql security definer set search_path = public, pg_temp as $f$
begin
  perform public.gv_rpc_guard('gv_popup_actividad');
  insert into public."GV_Popup_Disp"(dispositivo, persona, ultima_actividad, push_sub, push_alta)
  values (p_dispositivo, lower(p_persona), case when p_solo_push then null else now() end,
          p_push_sub, case when p_push_sub is not null then now() end)
  on conflict (dispositivo) do update set
    persona          = excluded.persona,
    ultima_actividad = case when p_solo_push then "GV_Popup_Disp".ultima_actividad else now() end,
    push_sub         = coalesce(excluded.push_sub, "GV_Popup_Disp".push_sub),
    push_alta        = coalesce(excluded.push_alta, "GV_Popup_Disp".push_alta);
end $f$;

-- La firma vieja (sin dispositivo, apps v31.03–v31.07) ya no muestra nada: no sabe a qué dispositivo va.
create or replace function public.gv_popup_pendientes(p_persona text)
returns table(id bigint, codigo text, texto text, creado_at timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $f$
begin
  perform public.gv_rpc_guard('gv_popup_pendientes');
  return;
end $f$;

-- Pendientes: sólo para el dispositivo destino (sin destino registrado todavía, para cualquiera no bloqueado).
create or replace function public.gv_popup_pendientes_disp(p_persona text, p_dispositivo text)
returns table(id bigint, codigo text, texto text, creado_at timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $f$
declare v_dest text := public.gv_popup_destino(p_persona);
begin
  perform public.gv_rpc_guard('gv_popup_pendientes_disp');
  if p_dispositivo is null then return; end if;
  if exists (select 1 from public."GV_Popup_Disp" d where d.dispositivo = p_dispositivo and d.bloqueado) then return; end if;
  if v_dest is not null and v_dest <> p_dispositivo then return; end if;
  return query
    select a.id, a.codigo, a.texto, a.creado_at
      from public."GV_Popup_Aviso" a
     where a.persona = lower(p_persona) and a.aceptado_at is null
     order by a.creado_at
     limit 20;
end $f$;

-- Para la Edge Function (sólo service_role): la clave privada y el registro del envío.
create or replace function public.gv_popup_vapid_priv()
returns text language sql stable security definer set search_path = public, pg_temp as $f$
  select decrypted_secret from vault.decrypted_secrets where name = 'gv_popup_vapid_priv' limit 1;
$f$;
create or replace function public.gv_popup_push_resultado(p_aviso bigint, p_dispositivo text, p_estado text)
returns void language sql security definer set search_path = public, pg_temp as $f$
  update public."GV_Popup_Aviso" set push_estado = p_estado where id = p_aviso;
  update public."GV_Popup_Disp" set push_ult_envio = now(), push_ult_estado = p_estado,
         push_sub = case when p_estado in ('410','404') then null else push_sub end   -- suscripción vencida: se descarta
   where dispositivo = p_dispositivo;
$f$;

-- Trigger: al entrar un aviso, push al destino (si tiene suscripción). Nunca frena el alta del aviso.
create or replace function public.gv_popup_push_disparar()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $f$
declare v_dest text; v_sub jsonb; v_key text;
begin
  begin
    v_dest := public.gv_popup_destino(new.persona);
    select d.push_sub into v_sub from public."GV_Popup_Disp" d where d.dispositivo = v_dest;
    if v_sub is null then
      update public."GV_Popup_Aviso" set push_destino = v_dest, push_estado = 'sin-suscripcion' where id = new.id;
      return new;
    end if;
    select v into v_key from lecturacvs.app_secrets where k = 'SUPABASE_SERVICE_ROLE_KEY';
    perform net.http_post(
      url     := 'https://hrxfctzncixxqmpfhskv.supabase.co/functions/v1/gv-popup-push',
      body    := jsonb_build_object('aviso_id', new.id, 'dispositivo', v_dest, 'sub', v_sub,
                   'titulo', 'Aviso de sistema · ' || new.codigo,
                   'texto', left(new.texto, 240)),
      headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key, 'apikey', v_key));
    update public."GV_Popup_Aviso" set push_destino = v_dest, push_estado = 'enviando' where id = new.id;
  exception when others then
    raise warning 'push-popup-v3108 gv_popup_push_disparar: %', sqlerrm;
  end;
  return new;
end $f$;

create or replace trigger trg_gv_popup_push
  after insert on public."GV_Popup_Aviso"
  for each row execute function public.gv_popup_push_disparar();

revoke all on function public.gv_popup_destino(text), public.gv_popup_actividad(text,text,jsonb,boolean),
  public.gv_popup_pendientes_disp(text,text), public.gv_popup_vapid_priv(), public.gv_popup_push_resultado(bigint,text,text),
  public.gv_popup_push_disparar() from public, anon, authenticated;
grant execute on function public.gv_popup_actividad(text,text,jsonb,boolean), public.gv_popup_pendientes_disp(text,text) to authenticated;
grant execute on function public.gv_popup_vapid_priv(), public.gv_popup_push_resultado(bigint,text,text) to service_role;

insert into public."GV_RPC_Guard"(fn, activo, desde, version) values ('gv_popup_actividad', true, now(), 'v31.08'), ('gv_popup_pendientes_disp', true, now(), 'v31.08')
on conflict (fn) do nothing;

insert into public."GV_Reglas_Centinela"(objeto, clase, patron, regla, quien_pidio, version, activo)
select v.* from (values
  ('gv_popup_destino', 'funcion', 'order by d.ultima_actividad desc limit 1',
   'El pop-up/push de Luis va al ÚLTIMO dispositivo activo no bloqueado', 'Luis', 'v31.08', true),
  ('gv_popup_pendientes_disp', 'funcion', 'd.bloqueado',
   'Un dispositivo bloqueado (9a59c479, D6) no recibe los pop-ups de Luis', 'Luis', 'v31.08', true),
  ('trg_gv_popup_push', 'trigger', 'gv_popup_push_disparar',
   'Cada aviso de pop-up se manda por Web Push al dispositivo destino', 'Luis', 'v31.08', true)
) v(objeto, clase, patron, regla, quien_pidio, version, activo)
where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto = v.objeto);
