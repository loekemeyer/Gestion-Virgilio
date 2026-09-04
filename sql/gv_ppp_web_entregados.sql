-- =============================================================================
-- gv_ppp_web_entregados.sql — las NP WEB que ya fueron CONTROLADAS (2026-09-04)
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · objeto NUEVO, prefijo gv_, sólo lectura
-- =============================================================================
-- REGLA DEL DUEÑO (2026-09-04): "Dentro de la PPP, si el pedido ya fue controlado,
-- automáticamente tendría que ir a Pedidos Entregados. No tiene que haber más
-- complejidad que eso."
--
-- CÓMO FUNCIONA HOY PARA LAS NP DE ISIS. Un pedido cuenta como ENTREGADO cuando
-- está "confirmado": tiene un evento CRN (Control Remitos, lo emite el operario
-- al bajarlo del camión, texto "NP|TANDA") o figura en PPP_Entregados_Meta, que
-- es el espejo del Sheet "PPP Pedidos Entregados" de ISIS. El front junta las dos
-- fuentes en _pppConfirmadas(). El CRN lo mira sólo 60 días para atrás; la hoja es
-- la fuente DURABLE.
--
-- EL PROBLEMA PARA LAS NP WEB. PPP_Entregados_Meta se TRUNCA cada 30 minutos con
-- lo que baja del Sheet (sync_ppp_entregados_meta, truncate + insert), así que una
-- NP web —que ISIS nunca vio— no existe ahí ni va a existir. A los 60 días del CRN
-- dejaría de estar confirmada y pasaría a "en viaje" para siempre.
--
-- LA SOLUCIÓN, LA MÁS CHICA QUE HAY: no hace falta tabla nueva. El CRN de una NP
-- web YA se emite con la etiqueta ("LK 01344|GV-02A") y Registros_Produccion_Virgilio
-- conserva todo (CRN desde el 2026-06-24, 821 filas, sin poda). Esta vista es la
-- fuente durable de "web controlada": los CRN cuyo NP es una etiqueta, cruzados con
-- PPP_Web_Programacion (nuestra) para traer cliente, tanda, m³ y fecha. El front la
-- suma a PPP_Entregados_Meta en las dos lecturas (el set de confirmadas y el
-- histórico completo). Nada de lo de ISIS cambia.
--
-- REGLAS QUE CUMPLE: objeto nuevo con prefijo gv_ (grep en Produccion-Virgilio: 0
-- usos), security_invoker = true (corre con los permisos del que consulta, no como
-- postgres), sin triggers, sin tocar tablas compartidas. Excluye los legajos de
-- prueba (0/1) con es_legajo_test, igual que vista_tanda_status.
--
-- MEDIDO AL CREARLA: 0 filas (todavía no hay NP web con CRN — la numeración está
-- apagada). La consulta compila y corre; la prueba de forma está en
-- tests/pweb-entregados.cjs.
--
-- ROLLBACK: drop view public.gv_ppp_web_entregados;
-- =============================================================================

create or replace view public.gv_ppp_web_entregados
with (security_invoker = true) as
with crn as (
  select upper(btrim(split_part(r.texto, '|', 1))) as np_label,
         min(r.ts_cliente)                          as controlado_at,
         count(*)                                   as n_crn
  from public."Registros_Produccion_Virgilio" r
  where r.opcion = 'CRN'
    and r.texto ~* '^\s*(LK|CH)\s+\d+'
    and not public.es_legajo_test(r.legajo)
  group by 1
)
select p.empresa,
       p.np,
       c.np_label,
       p.tanda,
       p.cod_cliente,
       p.razon_social,
       p.m3,
       p.fecha_entrega,
       c.controlado_at,
       c.n_crn
from crn c
join public."PPP_Web_Programacion" p
  on public.gv_ppp_web_np_label(p.empresa, p.np) = c.np_label;

-- Los privilegios por defecto del proyecto le dan TODO a anon sobre cada objeto nuevo
-- (medido: anon_insert = true recién creada). La vista no es actualizable —CTE con
-- GROUP BY— así que un INSERT fallaría igual, pero que el grant diga la verdad.
grant select on public.gv_ppp_web_entregados to anon, authenticated;
revoke insert, update, delete, truncate, references, trigger on public.gv_ppp_web_entregados from anon, authenticated;
