-- v31.87 (Luis, 16/10/2026): sacar articulos de una NP YA PICKEADA sin interrumpir el armado.
-- Caso: NP LK 0392 (Carrefour, tanda F73A) — se sacaron 521, 575, 500, 229 y 594 (95 cj) del pedido
-- LK 1654 y de PPP_Web_Base, y volvieron de separar_pedidos a a_guardar (tipo 'desarme', ref F73A).
-- El armado ya estaba abierto: el celular puede terminarlo con la foto vieja (14 articulos, en
-- localStorage). Esta red descarta esos renglones al entrar a Entregas_Virgilio, asi no van al
-- remito ni a la factura (Excel ISIS sale de Entregas) ni la reconciliacion mueve stock por ellos.
-- Cubre tambien gv_entregas_reconstruir (inserta en la misma tabla).

create table if not exists public."GV_NP_Art_Quitado" (
  np text not null, cod_art text not null, cajas numeric, motivo text not null, por text,
  creado_at timestamptz not null default now(), primary key (np, cod_art));
alter table public."GV_NP_Art_Quitado" enable row level security;
revoke all on public."GV_NP_Art_Quitado" from anon, authenticated;

create or replace function public.gv_np_art_quitado_trg() returns trigger
language plpgsql security definer set search_path to 'public','pg_temp' as $f$
begin
  if exists (select 1 from public."GV_NP_Art_Quitado" q
              where upper(btrim(q.np)) = upper(btrim(coalesce(new.np,'')))
                and public.canon_cod(q.cod_art) = public.canon_cod(coalesce(new.cod_art,''))) then
    return null;
  end if;
  return new;
end $f$;
create or replace trigger aa_gv_np_art_quitado before insert on public."Entregas_Virgilio"
  for each row execute function public.gv_np_art_quitado_trg();

-- Prueba (transaccion abortada, 16/10): insert de 521 y 248 para LK 0392 -> 521=0, 248=1.
-- Rollback: drop trigger aa_gv_np_art_quitado on public."Entregas_Virgilio";
--           drop function public.gv_np_art_quitado_trg(); drop table public."GV_NP_Art_Quitado";
-- Backups del caso LK 0392: zz_backups.ppp_web_base_lk0392_20261016, ppp_web_prog_lk0392_20261016,
-- armado_avance_f73a_20261016 (Gestion) y zz_backups.order_items_o1654_20261016 / orders_o1654_20261016 (LK).
