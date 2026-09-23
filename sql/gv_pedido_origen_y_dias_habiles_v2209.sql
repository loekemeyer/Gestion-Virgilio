-- Luis, 23/09/2026. Aplicado en hrxfctzncixxqmpfhskv el mismo día. La definición viva manda.
--
-- 1) Pedido con artículos "sin stock hasta dd/mm": la página lo confirma como DOS pedidos
--    (dos order_id). El segundo trae pedido_origen. "En nuestro sistema son 2 pedidos pero
--    para el cliente es 1": la deuda de uno NO retiene al otro en cuarentena.
alter table public.lk_pedidos_match add column if not exists pedido_origen bigint;
-- gv_cuarentena_mismo_pedido_lote: el join de hermanas pasó de
--     w.order_id::text = p.order_id
-- a  (w.order_id::text = p.order_id or exists (lk_pedidos_match _mp_m ... pedido_origen ...))
-- Aplicado por reemplazo de texto sobre la definición viva (idempotente, marca _mp_m).
-- Centinela: GV_Reglas_Centinela patron '_mp_m\.pedido_origen'.
-- Probado en transacción abortada con el pedido 1482 (LK 0143 facturada, LK 0144 pendiente):
--   LK 0144 como pedido aparte CON vínculo → exento (deuda_de_otra_NP_del_mismo_pedido)
--   SIN vínculo → no exento (ninguna_NP_facturada) · el de origen → exento igual que antes.

-- 2) Días hábiles para "Tu pedido estará listo antes del dd/mm/aa" de las páginas.
create or replace function public.gv_lk_dias_habiles_feed()
 returns table(fecha date, habil boolean) language sql stable security definer set search_path to 'public'
as $$
  select d::date, public.gv_es_dia_habil(d::date)
    from generate_series(current_date - 2, current_date + 400, interval '1 day') d;
$$;
revoke execute on function public.gv_lk_dias_habiles_feed() from public, anon, authenticated;
grant execute on function public.gv_lk_dias_habiles_feed() to lk_ppp_reader;
create or replace view public.v_lk_dias_habiles with (security_invoker = true) as
  select fecha, habil from public.gv_lk_dias_habiles_feed();
revoke all on public.v_lk_dias_habiles from anon, authenticated;
grant select on public.v_lk_dias_habiles to lk_ppp_reader;
