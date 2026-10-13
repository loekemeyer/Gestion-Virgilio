-- v29.50 (Luis, 13/10/2026): prueba de punta a punta del módulo de operarios, como celular (rol anon).
-- El PKC de la tablet disparaba trg_pkc_reconciliar_rt, que era SECURITY INVOKER: con la clave
-- pública fallaba con «permission denied for table Movimientos_Stock», el error se tragaba y la
-- góndola recién se movía con el cron 68 (hasta 10 min). docs/SEGURIDAD-MATRIZ-FUNCIONES.md ya lo pedía.
-- Medido en vivo después del cambio: PKC 09:04:28 → movimiento de picking 09:04:28. ~290 ms por PKC.
alter function public.trg_pkc_reconciliar_rt() security definer set search_path = public;
-- ROLLBACK: alter function public.trg_pkc_reconciliar_rt() security invoker reset search_path;
