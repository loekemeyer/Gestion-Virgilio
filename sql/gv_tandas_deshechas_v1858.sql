-- v18.58 (2026-09-15) — gv_tandas_deshechas: las tandas que sacamos NOSOTROS de la
-- programación, para que el monitor no las trate como un error de un operario.
--
-- Por qué existe
-- --------------
-- El monitor muestra «⚠ Tandas trabajadas que NO están en PPP — alguien se equivocó»
-- cuando una tanda tiene TP/TAP de hoy y ya no figura en la programación del día. Esa
-- condición la cumple también una tanda que deshicimos a propósito: el 15/09 se desarmó
-- E01G (sus NPs volvieron a «A Programar» porque el armado mostró códigos que el picking
-- nunca llegó a listar, corte de 1000 filas — problema 268) y el cartel la señaló igual,
-- como si un operario se hubiera equivocado de tanda. Luis: «ese cartel no corresponde en
-- este caso, te pedí yo por acá que lo ajustes».
--
-- La vista une las DOS tablas donde ya queda asentado que algo se deshizo a propósito.
-- No inventa dato nuevo: es la lectura que le faltaba al front.
--   · GV_Desarmes      — lo escribe gv_ppp_np_desarmar (desarme de una NP; guarda su tanda)
--   · GV_Tanda_Anulada — lo escribe anular_armado_virgilio (v18.50), y a mano cuando se
--                        anula un picking viejo que la RPC de 24 h ya no alcanza
--
-- Ojo con el alcance: desarmar UNA NP de una tanda con varias no saca a la tanda de la
-- PPP, así que la alerta no salta y esta exclusión no tiene efecto. Sólo pesa cuando la
-- tanda ya no está en la programación, que es exactamente el caso que se quiso arreglar.
--
-- security_invoker = true (obligatorio: sin eso corre como postgres y saltea la RLS).

-- GV_Tanda_Anulada tenía RLS prendida y CERO policies, o sea que anon veía 0 filas y la
-- mitad de la vista salía vacía. No hay dato sensible ahí (tanda, fase, legajo, motivo).
create policy gv_tanda_anulada_read on public."GV_Tanda_Anulada"
  for select to anon, authenticated using (true);

create or replace view public.gv_tandas_deshechas as
  select upper(btrim(d.tanda)) tanda, 'desarme'::text motivo_tipo,
         d.creado_at ts, coalesce(d.justificativo, '') detalle
    from public."GV_Desarmes" d
   where coalesce(btrim(d.tanda), '') <> ''
  union
  select upper(btrim(a.tanda)), 'anulada'::text,
         a.anulado_en, coalesce(a.motivo, '')
    from public."GV_Tanda_Anulada" a
   where coalesce(btrim(a.tanda), '') <> '';

alter view public.gv_tandas_deshechas set (security_invoker = true);
grant select on public.gv_tandas_deshechas to anon, authenticated;

-- Medición al aplicarlo (15/09):
--   D71A anulada · E01G desarme (x2, una por NP) · E22A desarme
-- Rollback:
--   drop view public.gv_tandas_deshechas;
--   drop policy gv_tanda_anulada_read on public."GV_Tanda_Anulada";
