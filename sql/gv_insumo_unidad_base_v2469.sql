-- v24.69 (Thomas, 30/09/2026, D11) — un insumo se mueve en MC (lo mínimo es 1 MC, a Cervantes o
-- bajado de racks) pero el stock queda en su unidad BASE. Repone la conversión en el backend
-- (el trigger normalizar_unidad_insumo del v11.77 ya no existía) y deja escrito lo cargado.
-- Los 5 movimientos viejos en MC NO se tocan: la pantalla de insumos ya los suma con el factor.
create or replace function public.gv_insumo_unidad_base()
returns trigger language plpgsql set search_path = public as $$
declare f numeric; b text;
begin
  if new.deposito <> 'insumos' or new.unidad is null then return new; end if;
  select x.factor into f from public."Insumos_Factores" x
   where upper(btrim(x.cod_art)) = upper(btrim(new.cod_art)) and lower(btrim(x.unidad)) = lower(btrim(new.unidad)) and not x.es_base limit 1;
  if f is null or f <= 0 then return new; end if;
  select x.unidad into b from public."Insumos_Factores" x
   where upper(btrim(x.cod_art)) = upper(btrim(new.cod_art)) and x.es_base limit 1;
  if b is null then return new; end if;
  new.descripcion := btrim(coalesce(new.descripcion, '') || ' · cargado ' || abs(new.delta) || ' ' || new.unidad || ' × ' || f);
  new.delta := new.delta * f;
  new.unidad := b;
  return new;
end $$;
drop trigger if exists gv_insumo_unidad_base on public."Movimientos_Stock";
create trigger gv_insumo_unidad_base before insert on public."Movimientos_Stock"
  for each row when (new.deposito = 'insumos') execute function public.gv_insumo_unidad_base();
-- Probado: insert 505C −2 MC → −8000 Uni «· cargado 2 MC × 4000» (transacción abortada).
-- Rollback: drop trigger gv_insumo_unidad_base on public."Movimientos_Stock"; drop function public.gv_insumo_unidad_base();
