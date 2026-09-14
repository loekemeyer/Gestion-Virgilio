-- =====================================================================
--  Candado: no se puede GUARDAR más cajas de las que hay en "A guardar" — v17.73 (2026-09-14)
--
--  Cierra el problema
--  "Guardar se puede cargar dos veces: no hay indice anti-duplicado para tipo=guardado".
--
-- ─────────────────────────────────────────────────────────────────────
--  QUÉ PASÓ
-- ─────────────────────────────────────────────────────────────────────
--  El 14/09 el legajo 94 guardó DOS VECES lo mismo:
--    508 → recepción 11/09 (remito 38789) +24 · guardado −24 a las 10:39 · guardado −24 a las 13:29
--    511 → recepción +52                     · guardado −44 a las 11:37 · guardado −52 a las 13:30
--  `client_id` distintos en cada par: son dos ENVÍOS distintos, no el reintento del mismo
--  (ese ya lo frena `mov_stock_clientid_dedup`). Las dos repeticiones caen en la misma ráfaga
--  de 13:29–13:31, junto con 544 y 504 que no se repitieron.
--
--  **Y la mitad que no se ve es la que importa.** Un guardado escribe DOS o TRES patas:
--    `a_guardar −(cargar+exc)` · `terminado +cargar` (góndola) · `excedente +exc` (rack, con
--    ubicación). O sea que el doble no sólo dejó `a_guardar` en −24 y −44: dejó **68 cajas
--    fantasma en góndola**. El negativo en tránsito es el síntoma; el stock inflado es el daño.
--
-- ─────────────────────────────────────────────────────────────────────
--  POR QUÉ SE PODÍA
-- ─────────────────────────────────────────────────────────────────────
--  Los dos índices únicos de `Movimientos_Stock` cubren `tipo in (picking, separado,
--  facturado)` y `tipo = 'aguardar'`, y los dos se apoyan en `ref`. Los movimientos
--  `guardado` tienen **`ref = null` y ningún índice**. `mov_stock_clientid_dedup` sólo frena
--  el REPLAY del mismo envío (cola offline), no un segundo apretar.
--
--  El tope de la pantalla (`it.disponible` en el modal MG) se lee **cuando se abre el modal**;
--  si el borrador queda abierto y se confirma dos horas después, ese tope está viejo.
--
-- ─────────────────────────────────────────────────────────────────────
--  POR QUÉ UN TRIGGER Y NO UN ÍNDICE ÚNICO
-- ─────────────────────────────────────────────────────────────────────
--  Un índice único sobre (cod, depósito, delta, legajo, día) habría agarrado el 508 (−24 y −24
--  idénticos) **pero no el 511** (−44 y después −52: son filas distintas, no un duplicado).
--  Y peor: `stockMove` manda `Prefer: resolution=ignore-duplicates`, así que el choque de
--  índice se traga en silencio — un guardado legítimo repetido (mismo código, misma cantidad,
--  mismo día) se perdería sin que nadie se entere.
--
--  El invariante que de verdad importa es otro y sirve para los dos casos:
--  **no se puede sacar de la pila más de lo que hay.** No molesta al guardado por partes
--  (−61, −27, −5 el mismo día es normal y sigue andando), y **es ciego al destino**: la pata
--  que se controla es la de `a_guardar`, que lleva `cargar + exc` junta, así que cubre igual
--  el guardado a **góndola** y el guardado a **excedente/rack**.
--
--  Cuánto habría molestado: barrido de saldo corrido sobre TODA la historia de `a_guardar`
--  (55.208 movimientos). Sólo **6 códigos** pasaron alguna vez por debajo de cero —
--  511 y 508 el 14/09, 546 (−60, 23/07) y tres de −1 (922 14/08, 960E 29/07, 280 24/07).
--  O sea: 6 rechazos en 3 meses, y los 6 estaban mal.
--
-- ─────────────────────────────────────────────────────────────────────
--  DETALLES QUE NO SON CAPRICHO
-- ─────────────────────────────────────────────────────────────────────
--  • **Se llama `zzz_`** para que corra DESPUÉS de `zz_normalizar_empresa`. Los triggers
--    disparan por orden alfabético y ése es el que pela el sufijo de empresa: si el código
--    entra como `508L` o `508 LK`, antes de ese trigger la clave normalizada sería `508L` y
--    el saldo daría 0. Corriendo último, ve el `cod_art` ya limpio.
--  • **Suma TODAS las empresas del código**, no la partición. La pila es física: el mismo 508
--    entró como `Mixto` a la mañana y como `LK` a la tarde (el front manda `empresa` sólo
--    cuando el renglón la resolvió), así que mirar por empresa habría dado "LK: 0" y dejado
--    pasar el segundo. Por eso `gv_stock_negativos` mostraba `LK: 0.0 · Mixto: -24.0`.
--  • **Sale por el índice `idx_ms_norm_cod`**, que ya existe sobre exactamente esa expresión.
--  • **NO toca `guardado_fuera_lista`**: ése es el ítem cargado a mano, no descuenta de
--    `a_guardar` — y es justamente la salida que le queda al operario si la mercadería está
--    pero el sistema no la tiene.
--
-- ─────────────────────────────────────────────────────────────────────
--  ⚠ LA MITAD DEL FRONT NO ES OPCIONAL
-- ─────────────────────────────────────────────────────────────────────
--  PostgREST devuelve **HTTP 400** ante un `RAISE` de trigger, y `stockMove` mandaba todo
--  4xx no-transitorio a `console.error` y lo DESCARTABA — mientras `mgConfirmar` ya había
--  cerrado el modal, borrado el borrador y mostrado "✅ Guardado". Con el trigger solo, el
--  rechazo habría sido **peor que el doble**: la mercadería se quedaba en la pila, la góndola
--  no la recibía, y el operario se iba convencido de que había guardado.
--  Por eso la v17.73 toca las dos mitades (ver `index.html`, `stockMove` y `mgConfirmar`).
--
-- ─────────────────────────────────────────────────────────────────────
--  VERIFICACIÓN (transacción con ROLLBACK)
-- ─────────────────────────────────────────────────────────────────────
--    A. guardar de un código con pila en 0 .................. RECHAZADO con el mensaje
--    B. guardar 10 de un código con 52 en la pila ........... pasa, pila queda en 42
--    C. guardar otros 42 (por partes, mismo día) ............ pasa, pila queda en 0
--    D. guardar 1 más ....................................... RECHAZADO
--    E. `guardado_fuera_lista` a góndola con la pila en 0 ... pasa (no mira la pila)
--    F. picking / recepción / ajuste ........................ intactos (el trigger no los mira)
--
--  Rollback:
--    drop trigger if exists zzz_guardado_no_negativo on public."Movimientos_Stock";
--    drop function if exists public.trg_guardado_no_negativo();
-- =====================================================================

create or replace function public.trg_guardado_no_negativo()
 returns trigger
 language plpgsql
as $function$
declare v_base text; v_saldo numeric;
begin
  -- Sólo la pata que SACA de la pila. Las patas de destino (terminado = góndola,
  -- excedente = rack) son positivas y no se controlan acá: lo que se guarda a una y a
  -- otra viaja junto en este mismo delta.
  if NEW.tipo <> 'guardado' or NEW.deposito <> 'a_guardar' or coalesce(NEW.delta, 0) >= 0 then
    return NEW;
  end if;

  v_base := regexp_replace(upper(btrim(NEW.cod_art)), '^0+(?=.)', '');

  select coalesce(sum(m.delta), 0) into v_saldo
    from public."Movimientos_Stock" m
   where m.deposito = 'a_guardar'
     and regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', '') = v_base;

  if v_saldo + NEW.delta < 0 then
    raise exception
      'En A guardar del % hay % caja(s) y se quisieron guardar %. Casi seguro ya se guardó antes: abrí Mover a Góndola de nuevo y fijate qué queda de verdad. Si la mercadería está pero el sistema no la tiene, cargala como artículo fuera de lista.',
      v_base, v_saldo::text, (-NEW.delta)::text
      using errcode = '23514';
  end if;

  return NEW;
end;
$function$;

drop trigger if exists zzz_guardado_no_negativo on public."Movimientos_Stock";
create trigger zzz_guardado_no_negativo
  before insert on public."Movimientos_Stock"
  for each row execute function public.trg_guardado_no_negativo();
