-- v23.30 (Luis, 2026-09-28) — el código de cliente corregido en la página llega a lo ya programado.
-- En LK, trg_cliente_recodificar_pedidos (customers) recodifica los pedidos cuando cambia el número
-- del cliente o la ficha se recrea (casos Capo 4318→4286 y Chaverim 4317→4285). El código nuevo viaja
-- a lk_pedidos_match con sync_pedidos_match_virgilio (cada 15 min, delete+insert). Esto lo lleva a
-- PPP_Web_Programacion y GV_NP_Sucursal, SÓLO en NP no facturadas (una factura hecha lleva su código).
-- Mismo patrón que gv_match_obs_a_programacion. Medido al aplicar: 0 NP con código distinto.
create or replace function public.gv_match_cod_a_programacion()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public."PPP_Web_Programacion" w
     set cod_cliente = btrim(new.cod_cliente), actualizado_at = now()
   where w.empresa = new.empresa and w.order_id = new.order_id
     and btrim(coalesce(w.cod_cliente, '')) <> btrim(new.cod_cliente)
     and not exists (select 1 from public."Facturacion_NP" f
                      where btrim(f.np) = public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx));
  update public."GV_NP_Sucursal" s
     set cod = btrim(new.cod_cliente), updated_at = now()
    from public."PPP_Web_Programacion" w
   where w.empresa = new.empresa and w.order_id = new.order_id
     and s.empresa = w.empresa and s.np = public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)
     and btrim(coalesce(s.cod, '')) <> btrim(new.cod_cliente)
     and not exists (select 1 from public."Facturacion_NP" f where btrim(f.np) = s.np);
  return null;
end $$;

drop trigger if exists gv_match_cod_a_programacion on public.lk_pedidos_match;
create trigger gv_match_cod_a_programacion
  after insert or update of cod_cliente on public.lk_pedidos_match
  for each row when (nullif(btrim(new.cod_cliente), '') is not null)
  execute function public.gv_match_cod_a_programacion();

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_match_cod_a_programacion', 'funcion', 'Facturacion_NP',
        'el código corregido del cliente llega a la programación sólo en NP no facturadas', 'Luis', 'v23.30')
on conflict do nothing;
-- Rollback: drop trigger gv_match_cod_a_programacion on public.lk_pedidos_match;
--           drop function public.gv_match_cod_a_programacion();
