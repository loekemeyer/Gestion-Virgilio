-- ============================================================================
-- PPP Web · numeración de NP y programación · Idea 3717
-- Corre en VIRGILIO (hrxfctzncixxqmpfhskv)
-- ============================================================================
-- Dos cosas que solo existen de este lado:
--   1) el NÚMERO de nota de pedido que se ve en pantalla,
--   2) la DECISIÓN del depósito sobre cada NP (tanda, zona, fecha de entrega).
-- Todo lo demás —cliente, ítems, corte en NP— se lee en vivo de LK y no se copia.
--
-- ----------------------------------------------------------------------------
-- 1 · EL NÚMERO: "LK 1343" · prefijo de empresa + CUATRO dígitos
-- ----------------------------------------------------------------------------
-- Formato pedido por el dueño (2026-09-03): `LK` o `CH`, un espacio, y cuatro
-- dígitos, parecido al id de pedido de la página.
--
-- ⚠ **NO ES EL ID DEL PEDIDO**, aunque arranque pegado a él. Es un CONTADOR
--   PROPIO, igual que las NP de ISIS: cada NP consume un número. Tiene que ser
--   así porque un pedido se parte en varias NP —31% de los casos, medido— y si
--   el pedido 1342 se partiera en LK 1342/1343/1344, mañana el pedido 1343
--   querría el mismo LK 1343 y chocarían. Con contador propio no se repite nunca.
--   La contra es que a partir del primer pedido partido el número deja de
--   coincidir con el id de la página: son dos secuencias distintas.
--
-- ⚠ TECHO DE 4 DÍGITOS. Al ritmo medido —188 pedidos/mes × 1,45 NP por pedido =
--   ~273 NP/mes— desde 1343 hasta 9999 hay unos **31 meses**. Cuando se acerque
--   hay que decidir: reiniciar el contador (y convivir con números repetidos de
--   años distintos, como hace ISIS) o pasar a 5 dígitos.
--
-- La identidad interna de una NP NO es el número: es **(order_id, np_idx)**. El
-- número es una etiqueta que se guarda al lado, así la programación no depende
-- de cómo se numere.
-- ----------------------------------------------------------------------------

create table if not exists public."PPP_Web_NP" (
  empresa   text    not null,
  np        integer not null,
  order_id  bigint  not null,
  np_idx    integer not null,
  creado_at timestamptz not null default now(),
  primary key (empresa, np),
  unique (empresa, order_id, np_idx)
);

-- Desde dónde arranca cada empresa. LK arranca en 1343 = el id de pedido más
-- alto al momento de crearlo (1342) + 1, para que los primeros números se
-- parezcan a los de la página.
create table if not exists public."PPP_Web_NP_Seed" (
  empresa text primary key,
  desde   integer not null
);
insert into public."PPP_Web_NP_Seed" (empresa, desde)
values ('lk', 1343), ('chef', 1)
on conflict (empresa) do nothing;

alter table public."PPP_Web_NP"      enable row level security;
alter table public."PPP_Web_NP_Seed" enable row level security;

drop policy if exists ppp_web_np_select on public."PPP_Web_NP";
create policy ppp_web_np_select on public."PPP_Web_NP"
  for select to anon, authenticated using (true);
drop policy if exists ppp_web_np_seed_select on public."PPP_Web_NP_Seed";
create policy ppp_web_np_seed_select on public."PPP_Web_NP_Seed"
  for select to anon, authenticated using (true);

grant select on public."PPP_Web_NP"      to anon, authenticated;
grant select on public."PPP_Web_NP_Seed" to anon, authenticated;

-- Reparte números a las NP que todavía no tienen. Es IDEMPOTENTE: una NP ya
-- numerada conserva su número para siempre, así que la pantalla la puede llamar
-- en cada carga sin consumir numeración.
create or replace function public.ppp_web_np_asignar(p_empresa text, p_pares jsonb)
returns table (r_order_id bigint, r_np_idx integer, r_np integer)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_next integer;
begin
  if auth.uid() is null then
    raise exception 'Se necesita sesión para asignar números de NP.';
  end if;

  -- Sin este lock, dos pantallas abiertas a la vez leen el mismo max(np) y sacan
  -- el mismo número. Es por empresa y se libera solo al cerrar la transacción.
  perform pg_advisory_xact_lock(hashtext('ppp_web_np:' || p_empresa));

  select greatest(
           coalesce((select max(n.np) from public."PPP_Web_NP" n where n.empresa = p_empresa), 0) + 1,
           coalesce((select s.desde from public."PPP_Web_NP_Seed" s where s.empresa = p_empresa), 1)
         )
    into v_next;

  with pedir as (
    select (x->>'order_id')::bigint as oid, (x->>'np_idx')::int as idx
    from jsonb_array_elements(p_pares) x
  ),
  nuevos as (
    select p.oid, p.idx,
           row_number() over (order by p.oid, p.idx) - 1 as offset_rn
    from pedir p
    where not exists (
      select 1 from public."PPP_Web_NP" n
       where n.empresa = p_empresa and n.order_id = p.oid and n.np_idx = p.idx)
  )
  insert into public."PPP_Web_NP" (empresa, np, order_id, np_idx)
  select p_empresa, v_next + nu.offset_rn::int, nu.oid, nu.idx
  from nuevos nu
  on conflict (empresa, order_id, np_idx) do nothing;

  return query
    with pedir as (
      select (x->>'order_id')::bigint as oid, (x->>'np_idx')::int as idx
      from jsonb_array_elements(p_pares) x
    )
    select n.order_id, n.np_idx, n.np
      from public."PPP_Web_NP" n
      join pedir p on p.oid = n.order_id and p.idx = n.np_idx
     where n.empresa = p_empresa;
end
$function$;

revoke all on function public.ppp_web_np_asignar(text, jsonb) from public, anon;
grant execute on function public.ppp_web_np_asignar(text, jsonb) to authenticated;


-- ----------------------------------------------------------------------------
-- 2 · LA PROGRAMACIÓN: tanda, zona, fecha de entrega
-- ----------------------------------------------------------------------------
-- ⚠ TABLA APARTE DE `PPP_Programacion_Diaria`, NO la misma. Esa es la que están
--   usando los operarios de Producción —misma base, 61 tandas vivas, entregas
--   hasta octubre— y escribir ahí mezclaría dos circuitos que todavía no están
--   unificados. Conviven sin tocarse.
--
-- `m3` y `m3_parcial` se guardan como FOTO del momento de programar, no como
--   cálculo vivo: la tanda se armó con ese número y el volumen de un artículo
--   puede cambiar después. `m3_parcial = true` = a esa NP le faltaban artículos
--   sin medir, o sea que el m³ guardado es un PISO.
-- ----------------------------------------------------------------------------

create table if not exists public."PPP_Web_Programacion" (
  empresa        text    not null default 'lk',
  order_id       bigint  not null,
  np_idx         integer not null,
  np             integer,              -- etiqueta visible, no la clave
  cod_cliente    text,
  razon_social   text,
  direccion      text,
  barrio         text,
  tanda          text,
  zona           text,
  fecha_entrega  date,
  op             text,
  observaciones  text,
  m3             numeric,
  m3_parcial     boolean not null default false,
  lineas         integer,
  cajas          numeric,
  creado_por     text,
  creado_at      timestamptz not null default now(),
  actualizado_at timestamptz not null default now(),
  primary key (empresa, order_id, np_idx)
);

create index if not exists ppp_web_prog_tanda_idx   on public."PPP_Web_Programacion" (empresa, tanda);
create index if not exists ppp_web_prog_entrega_idx on public."PPP_Web_Programacion" (fecha_entrega);
create index if not exists ppp_web_prog_np_idx      on public."PPP_Web_Programacion" (empresa, np);

alter table public."PPP_Web_Programacion" enable row level security;

-- Misma reja que `PPP_Programacion_Diaria`: los tres mails de supervisor,
-- chequeados por RLS del lado del servidor. Las dos listas están duplicadas a
-- mano — al sumar un supervisor hay que tocar las DOS policies.
drop policy if exists ppp_web_prog_select on public."PPP_Web_Programacion";
create policy ppp_web_prog_select on public."PPP_Web_Programacion"
  for select to anon, authenticated using (true);

drop policy if exists ppp_web_prog_write_sup on public."PPP_Web_Programacion";
create policy ppp_web_prog_write_sup on public."PPP_Web_Programacion"
  for all to authenticated
  using      ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']))
  with check ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']));

grant select on public."PPP_Web_Programacion" to anon, authenticated;
grant insert, update, delete on public."PPP_Web_Programacion" to authenticated;

-- Auditoría del lado del servidor: el front no decide quién firmó ni cuándo.
-- `creado_at` se preserva en el UPDATE para que reprogramar no borre cuándo se
-- programó por primera vez.
create or replace function public.ppp_web_prog_touch()
returns trigger language plpgsql as $$
begin
  new.actualizado_at := now();
  if new.creado_por is null or new.creado_por = '' then
    new.creado_por := coalesce(auth.jwt() ->> 'email', 'sistema');
  end if;
  if tg_op = 'UPDATE' then new.creado_at := old.creado_at; end if;
  return new;
end $$;

drop trigger if exists trg_ppp_web_prog_touch on public."PPP_Web_Programacion";
create trigger trg_ppp_web_prog_touch
  before insert or update on public."PPP_Web_Programacion"
  for each row execute function public.ppp_web_prog_touch();


-- ----------------------------------------------------------------------------
-- Controles
-- ----------------------------------------------------------------------------
--   -- Numeración entregada, y cuánto queda antes del techo de 4 dígitos:
--   select empresa, min(np) as desde, max(np) as hasta, count(*) as np,
--          9999 - max(np) as quedan
--     from public."PPP_Web_NP" group by empresa;
--
--   -- Lo programado, por tanda:
--   select tanda, count(*) as np, sum(cajas) as cajas, round(sum(m3),3) as m3,
--          bool_or(m3_parcial) as algun_m3_incompleto, min(fecha_entrega) as entrega
--     from public."PPP_Web_Programacion" where empresa='lk' and tanda is not null
--    group by tanda order by tanda;
--
--   -- Que un pedido partido tenga números correlativos:
--   select order_id, np_idx, np from public."PPP_Web_NP"
--    where empresa='lk' and order_id in (select order_id from public."PPP_Web_NP"
--                                         group by order_id having count(*) > 1)
--    order by order_id, np_idx;
--
--   -- Que no se haya escrito en la PPP de Producción (161 o más, nunca menos):
--   select count(*) from public."PPP_Programacion_Diaria";
-- ----------------------------------------------------------------------------


-- ============================================================================
-- 3 · PPP_Web_Base · los artículos que ve el operario
-- ============================================================================
-- FOTO de las líneas de cada NP, tomada AL PROGRAMAR. Acá la copia sí
-- corresponde, y por dos motivos:
--   · el operario pickea lo que se programó — el pedido no puede cambiarle abajo
--     de la mano mientras lo levanta;
--   · el operario no tiene, ni tiene por qué tener, sesión contra el proyecto LK.
-- Es lo mismo que hace `PPP_Base_Pedidos` con los pedidos de ISIS.
--
-- `np_label` es la etiqueta ("LK 1343"), que es la que viaja como NP por todo el
-- circuito de picking. **No es cosmética**: `empresaDeNp` del front resuelve la
-- empresa por el número (>90000 = LK) y una NP web de 4 dígitos caería en Chef,
-- mandando a buscar un pedido de Loekemeyer al sector equivocado. Con la etiqueta
-- la empresa la dice el prefijo.
-- ============================================================================

create table if not exists public."PPP_Web_Base" (
  empresa   text    not null default 'lk',
  order_id  bigint  not null,
  np_idx    integer not null,
  np_label  text    not null,
  articulo  text    not null,
  cajas     numeric not null default 0,
  creado_at timestamptz not null default now(),
  primary key (empresa, order_id, np_idx, articulo)
);
create index if not exists ppp_web_base_np_idx on public."PPP_Web_Base" (np_label);

alter table public."PPP_Web_Base" enable row level security;

drop policy if exists ppp_web_base_select on public."PPP_Web_Base";
create policy ppp_web_base_select on public."PPP_Web_Base"
  for select to anon, authenticated using (true);

drop policy if exists ppp_web_base_write_sup on public."PPP_Web_Base";
create policy ppp_web_base_write_sup on public."PPP_Web_Base"
  for all to authenticated
  using      ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']))
  with check ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']));

grant select on public."PPP_Web_Base" to anon, authenticated;
grant insert, update, delete on public."PPP_Web_Base" to authenticated;

--   -- Que ninguna tanda web haya quedado sin artículos (llegaría vacía al celular):
--   select p.tanda, p.np, count(b.articulo) as lineas
--     from public."PPP_Web_Programacion" p
--     left join public."PPP_Web_Base" b
--       on b.empresa = p.empresa and b.order_id = p.order_id and b.np_idx = p.np_idx
--    where p.tanda is not null
--    group by p.tanda, p.np having count(b.articulo) = 0;

-- v12.67 · `fecha_recep`: la fecha en que el pedido entró por la página.
-- La necesita el Excel para ISIS. Para una NP de ISIS esa fecha sale de
-- `PPP_Base_Pedidos`, donde una NP web no está, así que se guarda al programar.
alter table public."PPP_Web_Programacion" add column if not exists fecha_recep date;
