-- =====================================================================
-- recepcion_excede_oc_telegram.sql — Aviso Telegram (v7.07)
--
-- "📦⚠ RECEPCIÓN POR ENCIMA DE LA ORDEN DE COMPRA": cuando en Recepción de
-- Mercadería entra de un código MÁS DEL +20% de lo que pide la OC vigente de
-- ese tallerista/proveedor (tabla `Ordenes_Compra`, la que llena el generador
-- de OCs desde el PPP).
--
-- CLIENT-EMIT: `recepcion.js` (opEnviar) inserta el evento **ROC** al confirmar
-- la recepción — NO hay pop-up ni aprobación, al operario no se lo interrumpe:
--   opcion    = 'ROC'
--   texto     = 'PROVEEDOR|REMITO|cod:recibidas/pedidas,cod:recibidas/pedidas'
--   legajo    = el que está recibiendo (se resuelve a nombre por `Empleados`)
--   client_id = 'roc_<ts>'  → sirve de dedup_key del outbox
-- Este trigger lo reenvía por Telegram al grupo "Faltantes Virgilio".
--
-- Mecanismo: `tg_enqueue` → `telegram_outbox` → `tg_outbox_flush()` (dedup por
-- `dedup_key`, reintentos, ventana de despacho 07:00–21:00 AR). El bot_token sale
-- del Vault (secreto `telegram_bot_token`); acá no se hardcodea nada.
--
-- Verificado end-to-end (2026-08-04): evento ROC de prueba → outbox → Telegram
-- HTTP **200** (message_id 678). El aviso NUNCA rompe el INSERT del evento
-- (bloque `exception when others then return new`).
-- =====================================================================

create or replace function public.notificar_recepcion_excede_oc_telegram()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  p text[]; it text; kv text[]; nums text[];
  v_nombre text; v_rec numeric; v_ped numeric;
  lineas text := ''; msg text;
begin
  if new.opcion <> 'ROC' then return new; end if;
  p := string_to_array(coalesce(new.texto, ''), '|');
  if coalesce(array_length(p, 1), 0) < 3 then return new; end if;

  select "Empleado" into v_nombre from public."Empleados" where "Legajo" = new.legajo limit 1;

  -- p[3] = 'cod:recibidas/pedidas,cod:recibidas/pedidas' → una línea por código
  foreach it in array string_to_array(p[3], ',') loop
    kv := string_to_array(it, ':');
    if coalesce(array_length(kv, 1), 0) < 2 then continue; end if;
    nums := string_to_array(kv[2], '/');
    if coalesce(array_length(nums, 1), 0) < 2 then continue; end if;
    v_rec := nullif(btrim(nums[1]), '')::numeric;
    v_ped := nullif(btrim(nums[2]), '')::numeric;
    if v_rec is null or v_ped is null or v_ped <= 0 then continue; end if;
    lineas := lineas || E'\n' || '• Art ' || btrim(kv[1]) || ': recibió ' || v_rec ||
              ' vs ' || v_ped || ' pedidas (+' || round((v_rec / v_ped - 1) * 100) || '%)';
  end loop;
  if lineas = '' then return new; end if;

  msg := '📦⚠ RECEPCIÓN POR ENCIMA DE LA ORDEN DE COMPRA — ' ||
         coalesce(nullif(btrim(p[1]), ''), '?') || E'\n' ||
         'Remito ' || coalesce(nullif(btrim(p[2]), ''), 's/remito') || lineas || E'\n' ||
         'Recibió: ' || coalesce(nullif(btrim(coalesce(v_nombre, '')), ''),
                                 'legajo ' || coalesce(new.legajo, '?')) || E'\n' ||
         'Entró más del 20% por encima de lo pedido en la OC vigente.';

  perform public.tg_enqueue(msg, 'roc_' || coalesce(new.client_id, ''));
  perform public.tg_outbox_flush();
  return new;
exception when others then
  return new;   -- blindaje: el aviso jamás rompe el INSERT del evento ROC
end $fn$;

drop trigger if exists trg_recepcion_excede_oc_telegram on public."Registros_Produccion_Virgilio";
create trigger trg_recepcion_excede_oc_telegram
after insert on public."Registros_Produccion_Virgilio"
for each row when (new.opcion = 'ROC')
execute function public.notificar_recepcion_excede_oc_telegram();

-- Prueba manual (manda un mensaje REAL al grupo; borrar el evento después):
--   insert into public."Registros_Produccion_Virgilio"
--     (client_id, legajo, opcion, descripcion, texto, ts_cliente)
--   values ('roc_prueba', '0', 'ROC', 'PRUEBA', 'PRUEBA Lucho|99999|107:150/100', now());
--   select * from public.telegram_outbox where dedup_key = 'roc_roc_prueba';
--   delete from public."Registros_Produccion_Virgilio" where client_id = 'roc_prueba';
