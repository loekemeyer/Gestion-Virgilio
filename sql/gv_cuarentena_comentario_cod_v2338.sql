-- v23.38 (Luis, 28/09): un comentario de cuarentena sin COD de cliente no aparece en
-- «🕘 Antes, con este cliente» (gv_clin_comentarios_cliente filtra por cod). Caso Capo SA (LK 4286):
-- 10 comentarios de los pedidos 1548/1549 cargados sin cod.
-- Datos (con el sí de Luis): se completó el cod de 35 comentarios (Capo + 20 de otros clientes + 5 de
-- Capo escritos en el medio), sacándolo del pedido (lk_pedidos_match) o del log de cuarentena.
-- Queda 1 sin cod (id 5, NP 98635): no hay de dónde sacarlo.
create or replace function public.gv_cuarentena_comentario_cod()
returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce(btrim(new.cod), '') = '' then
    new.cod := coalesce(
      (select min(m.cod_cliente) from public.lk_pedidos_match m
        where m.empresa = new.empresa and m.order_id::text = public.gv_cuarentena_clave(new.order_id)),
      (select min(l.cod::text) from public."GV_Cuarentena_Log" l
        where l.empresa = new.empresa and public.gv_cuarentena_clave(l.clave) = public.gv_cuarentena_clave(new.order_id)));
  end if;
  return new;
end $$;
drop trigger if exists gv_cuarentena_comentario_cod on public."GV_Cuarentena_Comentarios";
create trigger gv_cuarentena_comentario_cod before insert on public."GV_Cuarentena_Comentarios"
  for each row execute function public.gv_cuarentena_comentario_cod();
-- Probado: insert sin cod en el pedido 1548 (transacción abortada) → cod = 4286.
-- Rollback: drop trigger gv_cuarentena_comentario_cod on public."GV_Cuarentena_Comentarios";
