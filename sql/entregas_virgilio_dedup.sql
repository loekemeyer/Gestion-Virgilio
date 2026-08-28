-- idea 3362 — Entregas_Virgilio sin protección de duplicado.
-- Problema: _compSaveEntregas postea sin client_id (a diferencia de Movimientos_Stock,
-- que dedupea desde la idea 5490). Corte de red + reintento desde
-- localStorage.vir_entregas_pend puede duplicar filas; y hay TOCTOU real entre
-- _compTandaYaArmada y el insert final con dos dispositivos en la misma tanda.
-- Fix (backend): BEFORE INSERT trigger que
--   (1) toma un advisory lock transaccional por (np|tanda|cod_art) → serializa a dos
--       dispositivos concurrentes (el segundo espera y ve la fila del primero), y
--   (2) si ya existe una fila EXACTAMENTE igual (np, tanda, cod_art, cajas_entregadas,
--       cajas_falto), descarta la nueva (return null) — el reintento del front recibe
--       201 igual y no duplica.
-- Se dedupea solo el duplicado EXACTO: un insert legítimo con valores distintos
-- (re-armado con otras cajas) pasa. No se agrega unique constraint para no abortar
-- batches parciales del front (PostgREST rechaza el batch entero ante un 23505).
-- ⚠ ANTES DE APLICAR: confirmar columnas reales de Entregas_Virgilio y ajustar la
-- comparación si hay más campos de negocio.
-- (Aplicado como migración `entregas_virgilio_dedup_3362`; copia versionada.)

create or replace function public.entregas_virgilio_dedup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
begin
  v_key := coalesce(new.np,'') || '|' || coalesce(new.tanda,'') || '|' || coalesce(new.cod_art,'');
  perform pg_advisory_xact_lock(hashtextextended('entregas_virgilio:' || v_key, 0));
  if exists (
    select 1 from public."Entregas_Virgilio" e
     where coalesce(e.np,'')    = coalesce(new.np,'')
       and coalesce(e.tanda,'') = coalesce(new.tanda,'')
       and coalesce(e.cod_art,'') = coalesce(new.cod_art,'')
       and coalesce(e.cajas_entregadas, 0) = coalesce(new.cajas_entregadas, 0)
       and coalesce(e.cajas_falto, 0)      = coalesce(new.cajas_falto, 0)
  ) then
    return null;  -- duplicado exacto: descartar sin error (el reintento del front no duplica)
  end if;
  return new;
end;
$$;

revoke execute on function public.entregas_virgilio_dedup() from public, anon, authenticated;

drop trigger if exists trg_entregas_virgilio_dedup on public."Entregas_Virgilio";
create trigger trg_entregas_virgilio_dedup
  before insert on public."Entregas_Virgilio"
  for each row
  execute function public.entregas_virgilio_dedup();
