-- =====================================================================
-- faltante_gondola_telegram.sql — Aviso Telegram URGENTE (idea del usuario)
--
-- "🚨 URGENTE!! FALTÓ EN PICKING PERO HABÍA STOCK EN GÓNDOLA": cuando un operario
-- marca un FALTANTE al pickear (esp>real) pero el sistema dice que la GÓNDOLA
-- (familia del código, disponible a esa tanda) tenía AL MENOS lo pedido. Es una
-- contradicción grave (mercadería mal ubicada / mal contada / no la vio) y hay que
-- ir a mirar YA — por eso el aviso dice URGENTE.
--
-- CLIENT-EMIT: index.html (stockBajaPicking, al TERMINAR el picking = TP) inserta el
-- evento **FGU** cuando detecta la condición:
--   opcion    = 'FGU'
--   texto     = 'TANDA|cod:falto:gond,cod:falto:gond'   (gond = cajas que el sistema tenía en góndola)
--   legajo    = el que pickeó (se resuelve a nombre por `Empleados`)
--   client_id = 'fgu_<legajo>_<tanda>_<YYYY-MM-DD>'  → dedup 1×/tanda/legajo/día
-- Este trigger lo reenvía por Telegram al grupo "Faltantes Virgilio".
--
-- Mecanismo idéntico a los demás avisos: `tg_enqueue` → `telegram_outbox` →
-- `tg_outbox_flush()` (dedup por `dedup_key`, reintentos, ventana de despacho AR).
-- El bot_token sale del Vault; acá no se hardcodea nada. El aviso NUNCA rompe el
-- INSERT del evento (bloque `exception when others then return new`).
-- =====================================================================

create or replace function public.notificar_faltante_gondola_telegram()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  p text[]; it text; kv text[];
  v_nombre text; v_falto numeric; v_gond numeric;
  lineas text := ''; msg text;
begin
  if new.opcion <> 'FGU' then return new; end if;
  p := string_to_array(coalesce(new.texto, ''), '|');
  if coalesce(array_length(p, 1), 0) < 2 then return new; end if;

  select "Empleado" into v_nombre from public."Empleados" where "Legajo" = new.legajo limit 1;

  -- p[2] = 'cod:falto:gond,cod:falto:gond' → una línea por código
  foreach it in array string_to_array(p[2], ',') loop
    kv := string_to_array(it, ':');
    if coalesce(array_length(kv, 1), 0) < 3 then continue; end if;
    v_falto := nullif(btrim(kv[2]), '')::numeric;
    v_gond  := nullif(btrim(kv[3]), '')::numeric;
    if v_falto is null or v_gond is null then continue; end if;
    lineas := lineas || E'\n' || '• Art ' || btrim(kv[1]) || ': faltó ' || v_falto ||
              ' cajas, pero el sistema tenía ' || v_gond || ' en góndola';
  end loop;
  if lineas = '' then return new; end if;

  msg := '🚨 URGENTE!! FALTÓ EN PICKING PERO HABÍA STOCK EN GÓNDOLA — Tanda ' ||
         coalesce(nullif(btrim(p[1]), ''), '?') || lineas || E'\n' ||
         'Pickeó: ' || coalesce(nullif(btrim(coalesce(v_nombre, '')), ''),
                                'legajo ' || coalesce(new.legajo, '?')) || E'\n' ||
         '⚠ Revisar YA: la mercadería figura en góndola. Puede estar mal ubicada, mal contada, o no la vieron.';

  perform public.tg_enqueue(msg, 'fgu_' || coalesce(new.client_id, ''));
  perform public.tg_outbox_flush();
  return new;
exception when others then
  return new;   -- blindaje: el aviso jamás rompe el INSERT del evento FGU
end $fn$;

drop trigger if exists trg_faltante_gondola_telegram on public."Registros_Produccion_Virgilio";
create trigger trg_faltante_gondola_telegram
after insert on public."Registros_Produccion_Virgilio"
for each row when (new.opcion = 'FGU')
execute function public.notificar_faltante_gondola_telegram();

-- Prueba manual (manda un mensaje REAL al grupo; borrar el evento después):
--   insert into public."Registros_Produccion_Virgilio"
--     (client_id, legajo, opcion, descripcion, texto, ts_cliente)
--   values ('fgu_prueba', '0', 'FGU', 'PRUEBA', 'PRUEBA|107:5:40', now());
--   select * from public.telegram_outbox where dedup_key = 'fgu_fgu_prueba';
--   delete from public."Registros_Produccion_Virgilio" where client_id = 'fgu_prueba';
