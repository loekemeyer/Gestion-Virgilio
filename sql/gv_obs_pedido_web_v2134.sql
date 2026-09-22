-- v21.34 (Thomas, 22/09/2026): "la observación del pedido tendría que figurar sí o sí en Gestión".
-- Antes: 51 de 435 pedidos web de LK (60 días) traían observación en orders.sheets_payload y
-- 0 de 200 filas de PPP_Web_Programacion la tenían. Ej: pedido 1515 "Urgente, hice quiebre de
-- stock art.501". Ahora viaja por el canal que LK ya empuja cada 15 min (lk_pedidos_match).
--
-- ===== Lado GESTIÓN (hrxfctzncixxqmpfhskv) — aplicado =====
alter table public.lk_pedidos_match add column if not exists observaciones text;

-- Al programar un bloque sin observación, se toma la del pedido.
create or replace function public.gv_ppp_web_obs_desde_match()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.observaciones is null then
    select m.observaciones into new.observaciones
      from public.lk_pedidos_match m
     where m.empresa = new.empresa and m.order_id = new.order_id
       and m.observaciones is not null
     limit 1;
  end if;
  return new;
end $$;

-- El otro orden: se programó antes de que LK empujara. Sólo completa vacíos, nunca pisa.
create or replace function public.gv_match_obs_a_programacion()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public."PPP_Web_Programacion" p
     set observaciones = new.observaciones
   where p.empresa = new.empresa and p.order_id = new.order_id
     and p.observaciones is null;
  return null;
end $$;

revoke all on function public.gv_ppp_web_obs_desde_match() from public, anon, authenticated;
revoke all on function public.gv_match_obs_a_programacion() from public, anon, authenticated;

create trigger gv_ppp_web_obs_desde_match before insert on public."PPP_Web_Programacion"
  for each row execute function public.gv_ppp_web_obs_desde_match();
create trigger gv_match_obs_a_programacion after insert or update of observaciones on public.lk_pedidos_match
  for each row when (new.observaciones is not null) execute function public.gv_match_obs_a_programacion();

-- ===== Lado LK (kwkclwhmoygunqmlegrg) — aplicado, backup en
--       zz_backups."LK_Backup_funcdef_gv_np_20260922" =====
-- * alter foreign table virgilio.lk_pedidos_match add column observaciones text;
-- * sync_pedidos_match_virgilio(): inserta observaciones (de orders.sheets_payload) en LK; Chef null.
-- * v_pedidos_web_np: columna nueva `observaciones` al final (sigue security_invoker) → A Programar.
-- * gv_pedidos_web_np_lk / _chef / _chef_fdw: columna nueva `observaciones` al final
--   (DROP + CREATE; resto de la salida idéntico por md5: 344 / 33 filas). _chef_fdw era
--   ejecutable por anon: quedó con los mismos grants que las otras (service_role, gv_reader).
-- * Chef: su portal NO manda observaciones (0 de 86 pedidos), así que sale vacía.
--
-- Medido al aplicar: 23 observaciones empujadas, 26 filas ya programadas completadas por el
-- trigger; insert de prueba (rollback) en 1515 tomó "Urgente, hice quiebre de stock art.501."
--
-- ROLLBACK Gestión:
--   drop trigger gv_ppp_web_obs_desde_match on public."PPP_Web_Programacion";
--   drop trigger gv_match_obs_a_programacion on public.lk_pedidos_match;
--   (la columna puede quedar: LK la deja de llenar al restaurar su función de sync)
