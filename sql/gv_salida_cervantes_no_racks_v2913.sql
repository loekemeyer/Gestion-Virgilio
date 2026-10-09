-- v29.13 (Luis, 09/10/2026): la salida a Cervantes NO sale de racks. Para mandar una MC de racks:
-- «BR · Bajar de racks» la baja a A guardar y se manda desde la pestaña A guardar.
-- Rollback: alter table public."Movimientos_Stock" disable trigger aa_gv_salida_cervantes_no_racks;
create or replace function public.gv_salida_cervantes_no_racks() returns trigger language plpgsql set search_path = public as $f$
begin
  -- marcador: v29.13-sc-no-racks (Luis, 09/10): a Cervantes se manda de góndola o A guardar; de racks primero se baja con BR
  if new.tipo = 'salida_cervantes' and new.deposito in ('racks','racks_ch') and coalesce(new.delta,0) < 0 then
    raise exception 'SC_DESDE_RACKS: a Cervantes no se manda desde racks. Primero bajalo a A guardar con «BR · Bajar de racks» y mandalo desde ahí. No se grabó nada.' using errcode = '23514';
  end if;
  return new;
end $f$;
create or replace trigger aa_gv_salida_cervantes_no_racks before insert on public."Movimientos_Stock" for each row execute function public.gv_salida_cervantes_no_racks();
insert into public."GV_Reglas_Centinela"(objeto, clase, patron, regla, quien_pidio, version)
values ('gv_salida_cervantes_no_racks','funcion','SC_DESDE_RACKS','La salida a Cervantes no sale de racks: se baja con BR a A guardar y se manda desde ahí','Luis','v29.13');
-- Datos del 09/10 (958E, AD10): salida a Cervantes −13 (id 132561171) anulada con +13 (id 132585332);
-- GV_Rack_CxM 958E 13 → 12; ingreso 260 corregido a 240 = 20 MC × 12 (id 132585364).
