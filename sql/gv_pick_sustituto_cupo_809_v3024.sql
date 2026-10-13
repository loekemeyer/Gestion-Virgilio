-- v30.24 (Luis, 13/10/2026): las próximas 9 cajas de 809E de CHEF que entren en pedidos web
-- se pickean del 809 nacional (góndola M16). Cupo de una vez: al llegar a 9 se apaga solo.
--
-- Cómo: al aparecer la línea 809E (empresa chef, SIN L) con su NP (np_label) en PPP_Web_Base,
-- si entra entera en lo que queda del cupo se escribe Correcciones_Pedido (np, 809E → 809).
-- El picking ya aplica Correcciones_Pedido (corrArt) y la etapa 2 del armado también
-- (gv_entregas_norm). Una línea más grande que el resto del cupo NO se parte: se saltea y
-- el cupo espera la próxima que entre (Correcciones reemplaza la línea entera).
-- La NP y la factura siguen diciendo 809E.

create table if not exists public."GV_Pick_Sustituto_Cupo" (
  id           bigserial primary key,
  empresa      text    not null,            -- 'chef' | 'lk' (como PPP_Web_Base)
  cod_pedido   text    not null,            -- lo que pide la NP
  cod_pick     text    not null,            -- lo que se pickea
  cajas_cupo   numeric not null,
  cajas_usadas numeric not null default 0,
  activo       boolean not null default true,
  notas        text,
  creado       timestamptz not null default now()
);
alter table public."GV_Pick_Sustituto_Cupo" enable row level security;
create policy gv_pick_sust_cupo_sel on public."GV_Pick_Sustituto_Cupo" for select using (true);

create table if not exists public."GV_Pick_Sustituto_Uso" (
  cupo_id   bigint  not null references public."GV_Pick_Sustituto_Cupo"(id),
  np_label  text    not null,
  order_id  bigint,
  np_idx    integer,
  cajas     numeric not null,
  creado    timestamptz not null default now(),
  primary key (cupo_id, np_label)
);
alter table public."GV_Pick_Sustituto_Uso" enable row level security;
create policy gv_pick_sust_uso_sel on public."GV_Pick_Sustituto_Uso" for select using (true);

create or replace function public.gv_pick_sustituto_cupo_trg()
returns trigger language plpgsql security definer set search_path to 'public' as $$
-- v30.24-cupo-sustituto
declare
  _c   record;
  _cod text := upper(btrim(coalesce(new.articulo, '')));
  _emp text := lower(btrim(coalesce(new.empresa, '')));
begin
  if new.np_label is null or btrim(new.np_label) = '' or coalesce(new.cajas, 0) <= 0 then return new; end if;
  for _c in
    select * from "GV_Pick_Sustituto_Cupo"
     where activo and cod_pedido = _cod
       and (empresa = _emp or (empresa = 'chef' and _emp = 'ch'))
     order by id
     for update
  loop
    continue when exists (select 1 from "GV_Pick_Sustituto_Uso" u where u.cupo_id = _c.id and u.np_label = new.np_label);
    continue when _c.cajas_usadas + new.cajas > _c.cajas_cupo;   -- no se parte una línea
    insert into "Correcciones_Pedido" (np, cod_secundario, cod_principal, cajas, confirmado_por, origen)
    values (btrim(new.np_label), _cod, _c.cod_pick, new.cajas, 'cupo ' || _c.id || ' · ' || coalesce(_c.notas, ''), 'cupo')
    on conflict (np, cod_secundario) do nothing;
    if not found then continue; end if;
    insert into "GV_Pick_Sustituto_Uso" (cupo_id, np_label, order_id, np_idx, cajas)
    values (_c.id, btrim(new.np_label), new.order_id, new.np_idx, new.cajas);
    update "GV_Pick_Sustituto_Cupo"
       set cajas_usadas = cajas_usadas + new.cajas,
           activo = (cajas_usadas + new.cajas) < cajas_cupo
     where id = _c.id;
    exit;
  end loop;
  return new;
exception when others then
  raise warning 'gv_pick_sustituto_cupo_trg: %', sqlerrm;   -- nunca frena la carga del pedido
  return new;
end $$;

create or replace trigger zz_gv_pick_sustituto_cupo
  after insert or update of np_label on public."PPP_Web_Base"
  for each row execute function public.gv_pick_sustituto_cupo_trg();

insert into public."GV_Pick_Sustituto_Cupo" (empresa, cod_pedido, cod_pick, cajas_cupo, notas)
select 'chef', '809E', '809', 9, 'Luis 13/10: 9 cajas de 809 nacional en M16'
 where not exists (select 1 from public."GV_Pick_Sustituto_Cupo" where cod_pedido = '809E' and cod_pick = '809');

-- Chequeo: select * from public."GV_Pick_Sustituto_Cupo"; select * from public."GV_Pick_Sustituto_Uso";
-- Rollback: drop trigger zz_gv_pick_sustituto_cupo on public."PPP_Web_Base";
--           (y borrar de Correcciones_Pedido las filas origen = 'cupo' que no se hayan pickeado)
