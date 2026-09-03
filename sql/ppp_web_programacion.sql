-- ============================================================================
-- PPP_Web_Programacion · la decisión del depósito sobre un pedido web
-- Idea 3717 · corre en VIRGILIO (hrxfctzncixxqmpfhskv)
-- ============================================================================
-- QUÉ GUARDA: tanda, zona y fecha de entrega de cada NP que salió de un pedido
--   web. Es lo ÚNICO del circuito que no puede venir de LK: no es un dato del
--   pedido, es una decisión de acá. Todo lo demás (cliente, ítems, corte en NP)
--   se lee en vivo de LK y no se copia.
--
-- ⚠ TABLA NUEVA Y APARTE, NO `PPP_Programacion_Diaria`. Esa es la que están
--   usando los operarios de Producción —misma base, 61 tandas vivas, entregas
--   hasta octubre— y escribir ahí mezclaría dos circuitos que todavía no están
--   unificados. Cuando el flujo nuevo reemplace al viejo habrá que decidir si se
--   fusionan; hasta entonces conviven sin tocarse.
--
-- CLAVE: `np_prov`, la NP provisoria de 9 dígitos que arma `v_pedidos_web_np`
--   en LK (`<empresa><order_id 6><parte 2>`). Es estable porque sale del pedido
--   y del número de parte. **No usar el N° Pedido del Excel del mail**: ese es un
--   contador de la tanda y el mismo pedido saca distinto número según con qué
--   otros salga.
--
-- ESCRITURA: misma reja que `PPP_Programacion_Diaria` — los tres mails de
--   supervisor, chequeados por RLS del lado del servidor. Un operario no puede
--   escribir acá ni con la consola abierta. Si mañana hay otro supervisor, se
--   agrega en las DOS policies (esta y la de la PPP), que hoy están duplicadas a
--   mano.
--
-- `m3` y `m3_parcial` se guardan como FOTO del momento en que se programó, no
--   como cálculo vivo: la tanda se armó con ese número y el volumen de un
--   artículo puede cambiar después. `m3_parcial = true` significa que a esa NP le
--   faltaban artículos sin medir, o sea que el m³ guardado es un PISO.
-- ============================================================================

create table if not exists public."PPP_Web_Programacion" (
  empresa        text not null default 'lk',
  np_prov        text not null,
  order_id       bigint,
  np_idx         integer,
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
  primary key (empresa, np_prov)
);

create index if not exists ppp_web_prog_tanda_idx   on public."PPP_Web_Programacion" (empresa, tanda);
create index if not exists ppp_web_prog_entrega_idx on public."PPP_Web_Programacion" (fecha_entrega);

alter table public."PPP_Web_Programacion" enable row level security;

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
-- `creado_at` se preserva en el UPDATE para que un reprogramado no borre cuándo
-- se programó por primera vez.
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
--   -- Lo programado, por tanda:
--   select tanda, count(*) as np, sum(cajas) as cajas, round(sum(m3),3) as m3,
--          bool_or(m3_parcial) as algun_m3_incompleto, min(fecha_entrega) as entrega
--     from public."PPP_Web_Programacion" where empresa='lk' and tanda is not null
--    group by tanda order by tanda;
--
--   -- Que no se haya escrito en la PPP de Producción (tiene que dar 161 o más,
--   -- nunca menos, y ninguna fila con np de 9 dígitos):
--   select count(*) from public."PPP_Programacion_Diaria";
--   select count(*) from public."PPP_Programacion_Diaria" where length(np) = 9;
-- ----------------------------------------------------------------------------
