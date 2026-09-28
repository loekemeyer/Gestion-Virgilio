-- v23.35 (Luis, 28/09): "pedido de super siempre en su propia tanda. Ni siquiera en una tanda del
-- mismo super, el mismo dia, con misma condicion de entrega".
-- El armado automatico ya no juntaba supers (los saca de _sin_tanda; la fusion los excluye); lo que
-- quedaba abierto era lo MANUAL ("Cambiar de dia" -> meter en otra tanda, reusar, fusion), que no
-- miraba si la tanda era de super. Este trigger lo cierra para todos los caminos a la vez.
-- Probado en transaccion abortada: comun -> tanda de super FRENA · super -> tanda comun FRENA ·
-- otro super (Chef 231) -> tanda de super (F23A, LK 1504) FRENA · renombrar la tanda del super PASA ·
-- renombrar una tanda comun de varios clientes PASA.
-- Solo PPP_Web_Programacion (pedidos web). Las NP de ISIS ya no entran nuevas (Luis, 24/09).
create or replace function public.gv_ppp_web_super_tanda_sola()
returns trigger language plpgsql set search_path = public as $$
declare v_otro record;
begin
  if coalesce(btrim(new.tanda), '') = '' then return new; end if;
  if tg_op = 'UPDATE' and new.tanda is not distinct from old.tanda then return new; end if;
  select w.empresa, w.order_id, w.razon_social,
         public.gv_es_super(w.empresa, w.cod_cliente) as es_sup
    into v_otro
    from public."PPP_Web_Programacion" w
   where w.empresa in ('lk', 'chef') and w.tanda = new.tanda
     and not (w.empresa = new.empresa and w.order_id = new.order_id)
     and (public.gv_es_super(new.empresa, new.cod_cliente) or public.gv_es_super(w.empresa, w.cod_cliente))
   limit 1;
  if found then
    raise exception 'SUPER_TANDA_SOLA: la tanda % ya tiene el pedido % (%). Un pedido de súper va siempre en su propia tanda, sin ningún otro pedido — ni siquiera del mismo súper.',
      new.tanda, upper(v_otro.empresa) || ' ' || v_otro.order_id, coalesce(v_otro.razon_social, '')
      using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists gv_ppp_web_super_tanda_sola on public."PPP_Web_Programacion";
create trigger gv_ppp_web_super_tanda_sola before insert or update of tanda on public."PPP_Web_Programacion"
  for each row execute function public.gv_ppp_web_super_tanda_sola();
-- Rollback: drop trigger gv_ppp_web_super_tanda_sola on public."PPP_Web_Programacion";
