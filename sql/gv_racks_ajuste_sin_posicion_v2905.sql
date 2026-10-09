-- v29.05 (Luis, 09/10/2026): un AJUSTE / STOCK INICIAL de racks desde el panel (legajo '0') tiene que llevar la
-- POSICIÓN del rack. Caso 606 (09/10): Marianela corrigió un ingreso a X22 que era 606E con −10 desde
-- Stock → Ajustar y quedó «bajado de racks sin decir de qué posición» (X22 siguió con +10). Pasó 6 veces desde el 25/09.
-- El front (index.html, _stkRackPosElegir) ya pide la posición; esto lo frena también en la base
-- (celulares / pestañas con el index viejo cacheado). Sólo legajo '0' (panel): los demás caminos ya mandan la posición.
create or replace function public.gv_racks_ajuste_sin_posicion() returns trigger
language plpgsql set search_path = public as $fn$
begin
  -- marcador: v29.05-racks-pos
  if new.deposito in ('racks','racks_ch') and new.tipo in ('ajuste','inicial') and coalesce(new.legajo,'') = '0'
     and (new.ubicacion is null or public.gv_rack_sector(new.ubicacion) is null) then
    raise exception 'RACKS_SIN_POSICION: un ajuste de racks lleva la posición del rack (ej. X22). No se grabó nada.'
      using errcode = '23514';
  end if;
  return new;
end $fn$;

create or replace trigger aa_gv_racks_ajuste_sin_posicion
  before insert on public."Movimientos_Stock"
  for each row when (new.deposito in ('racks','racks_ch') and new.tipo in ('ajuste','inicial') and new.legajo = '0')
  execute function public.gv_racks_ajuste_sin_posicion();

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_racks_ajuste_sin_posicion','funcion','RACKS_SIN_POSICION',
        'Un ajuste de racks desde el panel (legajo 0) sin posición de rack del Mapa no se graba','Luis','v29.05');

-- Rollback:
--   alter table public."Movimientos_Stock" disable trigger aa_gv_racks_ajuste_sin_posicion;
