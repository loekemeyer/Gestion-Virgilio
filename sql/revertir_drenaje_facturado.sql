-- idea 9082 — Revertir en Facturación debe DESHACER el drenaje de stock.
-- Problema: facTickNP drena "a_facturar" (Movimientos_Stock tipo='facturado',
-- ref = TANDA|NP por stockSalidaFacturadoNP y ref = NP|CP por stockDrenarCPFacturado),
-- pero facRevertir solo hace DELETE en Facturacion_NP: el stock quedaba drenado para
-- siempre y, peor, el dedup del front (busca tipo=facturado&ref=...) veía las filas
-- viejas y un re-tick posterior NUNCA volvía a drenar.
-- Fix (backend, fuente de verdad): trigger AFTER DELETE en Facturacion_NP que BORRA
-- las filas de drenaje de ESA NP. Borrar (y no compensar con +N) es deliberado:
-- restaura el saldo Y deja pasar el dedup del front, así el próximo tick re-drena.
-- Solo aplica a NPs sin cierre (cierre_id IS NULL = lo único que borra el botón
-- Revertir); filas de cierres pasados borradas a mano NO disparan la reversa.
-- Limitación conocida: el barrido del 100% de tanda (ref = TANDA solo) es compartido
-- entre NPs y no se puede atribuir → no se revierte (igual que hoy).
-- (Aplicado como migración `revertir_drenaje_facturado_9082`; copia versionada.)

create or replace function public.revertir_drenaje_facturado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_np    text;
  v_tanda text;
begin
  -- NPs ya cerradas: no tocar (el botón Revertir no las borra; un delete manual
  -- de historia vieja no debe resucitar stock).
  if old.cierre_id is not null then
    return old;
  end if;
  v_np    := regexp_replace(trim(coalesce(old.np, '')), '\.0+$', '');
  v_tanda := upper(trim(coalesce(old.tanda, '')));
  if v_np = '' then
    return old;
  end if;
  delete from public."Movimientos_Stock"
   where tipo = 'facturado'
     and deposito = 'a_facturar'
     and (
       (v_tanda <> '' and ref = v_tanda || '|' || v_np)  -- drenaje por NP (v5.95)
       or ref = v_np || '|CP'                            -- drenaje del completado (v6.27)
     );
  return old;
end;
$$;

revoke execute on function public.revertir_drenaje_facturado() from public, anon, authenticated;

drop trigger if exists trg_revertir_drenaje_facturado on public."Facturacion_NP";
create trigger trg_revertir_drenaje_facturado
  after delete on public."Facturacion_NP"
  for each row
  execute function public.revertir_drenaje_facturado();
