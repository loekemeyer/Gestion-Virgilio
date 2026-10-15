-- v31.01 (Luis, 15/10/2026): avisos de sistema C2 / C4 / C5 → pop-up en la app para Luis.
--
--   C2 = la clave pública intentó escribir en una tabla cerrada   (dedup_key 'anon-bloqueo:…')
--   C4 = celular nuevo / un celular con 2 operarios               (dedup_key 'gv_disp…' y 'gt-disp…')
--   C5 = login de operario rechazado por red / ISIS sin facturas  (dedup_key 'login_op…' y 'gv_ingesta…')
--
-- Siguen saliendo por Telegram igual que antes: el pop-up se SUMA (trigger sobre telegram_outbox,
-- no se tocó ninguna de las funciones que los generan).
--
-- "Logueado como Luis": el mail de Google es compartido (loekemeyer.n8n@ en 23 dispositivos), así
-- que el login no dice quién es. Vale la sesión de supervisor (Google) + «Luis» elegido en el
-- selector de rol del panel (localStorage gv_sup_quien = 'luis'). Lo decide el front (index.html,
-- gvPopupPersona); las RPC exigen sesión de supervisor (gv_rpc_guard).
--
-- Review a futuro:
--   select * from public.gv_popup_review order by creado_at desc;
--   (cuándo llegó, en qué dispositivo saltó, quién apretó Aceptar y cuándo)

-- 1) Tablas -------------------------------------------------------------------------------
create table if not exists public."GV_Popup_Aviso" (
  id            bigserial primary key,
  persona       text not null default 'luis',
  codigo        text not null,                     -- C2 | C4 | C5
  texto         text not null,
  dedup_key     text unique,
  outbox_id     bigint,
  creado_at     timestamptz not null default now(),
  aceptado_at   timestamptz,
  aceptado_email text,
  aceptado_dispositivo text,
  aceptado_quien text
);
create index if not exists gv_popup_aviso_pend_idx on public."GV_Popup_Aviso"(persona) where aceptado_at is null;

create table if not exists public."GV_Popup_Log" (
  id          bigserial primary key,
  aviso_id    bigint not null references public."GV_Popup_Aviso"(id),
  quien       text,                              -- rol elegido en el panel ('luis')
  evento      text not null check (evento in ('mostrado','aceptado')),
  dispositivo text,
  email       text,
  app_version text,
  at          timestamptz not null default now()
);
create index if not exists gv_popup_log_aviso_idx on public."GV_Popup_Log"(aviso_id);

alter table public."GV_Popup_Aviso"       enable row level security;
alter table public."GV_Popup_Log"         enable row level security;
revoke all on public."GV_Popup_Aviso", public."GV_Popup_Log" from anon, authenticated;

-- 2) Trigger: cada aviso C2/C4/C5 que entra al outbox de Telegram también va al pop-up ---------
create or replace function public.gv_popup_desde_outbox()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $f$
declare v_cod text;
begin
  v_cod := case
    when new.dedup_key ~ '^anon-bloqueo'          then 'C2'
    when new.dedup_key ~ '^(gv_disp|gt-disp)'     then 'C4'
    when new.dedup_key ~ '^(login_op|gv_ingesta)' then 'C5'
  end;
  if v_cod is null then return new; end if;
  begin
    insert into public."GV_Popup_Aviso"(persona, codigo, texto, dedup_key, outbox_id)
    values ('luis', v_cod, new.text, new.dedup_key, new.id)
    on conflict (dedup_key) do nothing;
  exception when others then
    raise warning 'popup-c2c4c5-v3101 gv_popup_desde_outbox: %', sqlerrm;   -- el pop-up nunca frena el Telegram
  end;
  return new;
end $f$;

create or replace trigger trg_gv_popup_desde_outbox
  after insert on public.telegram_outbox
  for each row execute function public.gv_popup_desde_outbox();

-- 3) RPC (sólo con sesión de supervisor: gv_rpc_guard) -------------------------------------
create or replace function public.gv_popup_pendientes(p_persona text)
returns table(id bigint, codigo text, texto text, creado_at timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $f$
begin
  perform public.gv_rpc_guard('gv_popup_pendientes');
  return query
    select a.id, a.codigo, a.texto, a.creado_at
      from public."GV_Popup_Aviso" a
     where a.persona = lower(p_persona) and a.aceptado_at is null
     order by a.creado_at
     limit 20;
end $f$;

-- 'mostrado' cada vez que salta en una página; 'aceptado' cierra el aviso en todas.
create or replace function public.gv_popup_evento(p_id bigint, p_evento text, p_quien text, p_dispositivo text, p_app_version text)
returns void language plpgsql security definer set search_path = public, pg_temp as $f$
declare v_em text := auth.jwt() ->> 'email';
begin
  perform public.gv_rpc_guard('gv_popup_evento');
  insert into public."GV_Popup_Log"(aviso_id, evento, quien, dispositivo, email, app_version)
  values (p_id, p_evento, p_quien, p_dispositivo, v_em, p_app_version);
  if p_evento = 'aceptado' then
    update public."GV_Popup_Aviso"
       set aceptado_at = now(), aceptado_quien = p_quien, aceptado_email = v_em, aceptado_dispositivo = p_dispositivo
     where id = p_id and aceptado_at is null;
  end if;
end $f$;

revoke all on function public.gv_popup_pendientes(text), public.gv_popup_evento(bigint,text,text,text,text),
  public.gv_popup_desde_outbox() from public, anon;
grant execute on function public.gv_popup_pendientes(text), public.gv_popup_evento(bigint,text,text,text,text) to authenticated;

insert into public."GV_RPC_Guard"(fn, activo, desde, version) values
  ('gv_popup_pendientes', true, now(), 'v31.01'),
  ('gv_popup_evento',     true, now(), 'v31.01')
on conflict (fn) do nothing;

-- 4) Vista de review ------------------------------------------------------------------------
create or replace view public.gv_popup_review with (security_invoker = true) as
select a.id, a.codigo, a.persona, a.creado_at,
       (select min(l.at) from public."GV_Popup_Log" l where l.aviso_id = a.id and l.evento = 'mostrado') as primer_mostrado_at,
       (select count(*) from public."GV_Popup_Log" l where l.aviso_id = a.id and l.evento = 'mostrado') as veces_mostrado,
       (select string_agg(distinct left(l.dispositivo, 8), ', ') from public."GV_Popup_Log" l where l.aviso_id = a.id and l.evento = 'mostrado') as dispositivos,
       a.aceptado_at, a.aceptado_email, left(a.aceptado_dispositivo, 8) as aceptado_disp,
       left(regexp_replace(a.texto, '\s+', ' ', 'g'), 160) as texto,
       a.aceptado_quien
  from public."GV_Popup_Aviso" a;
revoke all on public.gv_popup_review from anon, authenticated;

-- 5) Centinela: que el trigger no se pierda en un CREATE OR REPLACE ---------------------------
insert into public."GV_Reglas_Centinela"(objeto, clase, patron, regla, quien_pidio, version, activo)
select v.* from (values
  ('gv_popup_desde_outbox', 'funcion', 'popup-c2c4c5-v3101',   -- el marcador vive en el raise warning (código, no comentario)
   'Los avisos C2/C4/C5 del outbox de Telegram también van al pop-up de Luis', 'Luis', 'v31.01', true),
  ('trg_gv_popup_desde_outbox', 'trigger', 'gv_popup_desde_outbox',
   'El trigger del outbox que alimenta el pop-up de Luis sigue existiendo', 'Luis', 'v31.01', true)
) v(objeto, clase, patron, regla, quien_pidio, version, activo)
where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto = v.objeto);
