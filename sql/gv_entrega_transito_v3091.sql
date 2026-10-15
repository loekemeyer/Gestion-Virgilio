-- v30.91 (Luis, 15/10, D5 «si»): una ENTREGA de insumo descuenta PRIMERO de Tránsito.
-- BEFORE INSERT en Movimientos_Stock (corre después de gv_insumo_unidad_base, así compara en la unidad base):
--   · tránsito ≥ lo que sale  → la fila entera sale de TRANSITO;
--   · 0 < tránsito < lo que sale → se parte: una fila extra por lo que hay en TRANSITO (client_id + '·tr')
--     y la original queda por el resto, en la posición que traía.
create or replace function public.gv_insumo_entrega_transito()
returns trigger language plpgsql set search_path to 'public' as $f$
-- marcador v30.91-entrega-transito
declare v_hay numeric; v_sale numeric;
begin
  if new.deposito <> 'insumos' or new.tipo <> 'entrega_insumo' or coalesce(new.delta, 0) >= 0
     or upper(btrim(coalesce(new.ubicacion, ''))) = 'TRANSITO' then
    return new;
  end if;
  select coalesce(sum(m.delta), 0) into v_hay from public."Movimientos_Stock" m
   where m.deposito = 'insumos' and upper(btrim(m.ubicacion)) = 'TRANSITO'
     and upper(btrim(m.cod_art)) = upper(btrim(new.cod_art)) and m.unidad is not distinct from new.unidad;
  if v_hay <= 0 then return new; end if;
  v_sale := -new.delta;
  if v_hay >= v_sale then
    new.ubicacion := 'TRANSITO';
    return new;
  end if;
  insert into public."Movimientos_Stock"(ts, cod_art, descripcion, deposito, delta, tipo, ref, legajo, unidad, ubicacion, client_id, empresa, gv_doc)
  values (new.ts, new.cod_art, new.descripcion, 'insumos', -v_hay, 'entrega_insumo', new.ref, new.legajo, new.unidad, 'TRANSITO',
          case when new.client_id is null then null else new.client_id || '·tr' end, new.empresa, new.gv_doc);
  new.delta := -(v_sale - v_hay);
  return new;
end $f$;
create or replace trigger zy_gv_insumo_entrega_transito
  before insert on public."Movimientos_Stock"
  for each row when (new.deposito = 'insumos' and new.tipo = 'entrega_insumo')
  execute function public.gv_insumo_entrega_transito();

insert into public."GV_Reglas_Centinela"(objeto, clase, patron, regla, quien_pidio, version, activo) values
  ('gv_insumo_entrega_transito', 'funcion', 'TRANSITO', 'La entrega de un insumo descuenta primero de Tránsito', 'Luis 15/10 (D5)', 'v30.91', true);
