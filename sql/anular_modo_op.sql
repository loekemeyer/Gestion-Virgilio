-- =====================================================================
-- anular_modo_op.sql — ANULAR un envío de Recepción de Mercadería.
--
-- Lo llama recepcion.js con el botón "✕ Anular este envío" que aparece JUSTO
-- DESPUÉS de confirmar una recepción (opEnviar → RPC anular_modo_op(p_id)).
-- NO confundir con anular_toggle_virgilio('RT') (v7.15), que cierra la SESIÓN RT
-- antes de mandar nada; esto revierte un envío YA MANDADO.
--
-- Qué revierte un envío de recepción escribe en tres lados (opEnviar):
--   1. "Entregas Tallerista Virgilio" / "Entregas Prov AT"  (la entrega)
--   2. "Movimientos_Stock"  (a_guardar +cajas por código, tipo='recepcion')
--   3. "Control_Modo_OP"    (un renglón por envío, el checklist de Marianela)
-- y suma al acumulador de cajas del día en localStorage (para cerrar el RT).
--
-- FIX (2026-08-04): hasta ahora anular_modo_op borraba (1) y marcaba (3) como
-- 'anulado', pero NO tocaba (2) → las cajas quedaban vivas para siempre en
-- 'a_guardar' (STOCK FANTASMA). El cliente sí revertía el acumulador localStorage
-- (recpAddCajas(-total)), pero el stock durable no. Auditoría: no hubo daño
-- histórico (las 9 anulaciones existentes son todas anteriores a que recepción
-- empezara a escribir stock, v4.06), pero cualquier anulación de hoy lo corrompía.
--
-- Ahora, además de (1) y (3), inserta un movimiento COMPENSATORIO
-- (a_guardar −cajas, tipo='ajuste', legajo='anula_recep', ref='<remito>|ANULA')
-- por cada código del envío, parseando Control_Modo_OP.detalle
-- ("cod → cajas · cod → cajas") — que es exactamente lo que se sumó. Es:
--   • idempotente: si ya está 'anulado' corta antes de compensar (early-return),
--     y el client_id 'anrec_<id>_<cod>' es único (ON CONFLICT, red de seguridad);
--   • acotado a ESTE envío: no toca otros Control_Modo_OP que compartan remito;
--   • sin colisión con el dedup del pipeline: tipo='ajuste' está fuera del índice
--     mov_stock_pipeline_dedup (picking/separado/facturado).
-- El índice de dedup por client_id es PARCIAL (WHERE client_id IS NOT NULL), por
-- eso el ON CONFLICT lleva su predicado.
--
-- Verificado (transacción + ROLLBACK): envío ZZ1→10/ZZ2→5 con su stock →
-- anular_modo_op() dos veces → r1='ok', r2='ya_anulado'; saldos a_guardar 0/0;
-- 2 compensaciones (no dobla); entrega borrada; estado 'anulado'.
--
-- Devuelve: 'ok' | 'no_existe' | 'ya_anulado' | 'vencido' (>48 h).
-- =====================================================================
create or replace function public.anular_modo_op(p_id bigint)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare r record;
begin
  select * into r from "Control_Modo_OP" where id = p_id;
  if not found then return 'no_existe'; end if;
  if r.estado = 'anulado' then return 'ya_anulado'; end if;
  if r.created_at < now() - interval '48 hours' then return 'vencido'; end if;

  if r.tipo = 'prov_at' then
    delete from "Entregas Prov AT"
      where "Remito" = r.remito and "Proveedor" = r.nombre;
  else
    delete from "Entregas Tallerista Virgilio"
      where "Remito" = r.remito and "Codigo_Tall" = r.codigo_tall;
  end if;

  -- REVERSA DE STOCK: compensa lo que recepcion.js metió en 'a_guardar' por este envío.
  if coalesce(btrim(r.detalle), '') <> '' then
    insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, descripcion, client_id)
    select cod, 'a_guardar', -cajas, 'ajuste',
           coalesce(nullif(btrim(r.remito), ''), 's/remito') || '|ANULA',
           'anula_recep', 'Recepción anulada (Modo OP #' || p_id || ')',
           'anrec_' || p_id || '_' || cod
      from (
        select btrim(split_part(p, '→', 1)) as cod,
               nullif(btrim(split_part(p, '→', 2)), '')::numeric as cajas
          from unnest(string_to_array(r.detalle, '·')) p
      ) x
     where x.cod <> '' and x.cajas is not null and x.cajas > 0
    on conflict (client_id) where (client_id is not null) do nothing;
  end if;

  update "Control_Modo_OP"
    set estado = 'anulado', procesado_at = now()
    where id = p_id;
  return 'ok';
end;
$function$;
