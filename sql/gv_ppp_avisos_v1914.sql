/* ============================================================================
   gv_ppp_avisos — lo que alimenta el badge rojo del botón PPP.  (v19.14, pedido
   de Luis 2026-09-16: *"badge rojo con número arriba a la izquierda del icono de
   la PPP como con los demás"*)

   ── Por qué no había badge, si ya existía ───────────────────────────────────
   El badge estaba en la pantalla desde la **v8.82** y no se vio nunca. Dos cosas,
   las dos silenciosas:

   1. Contaba sólo `Alertas_Pedidos_Web` con estado `pendiente`. Hoy hay **0** (la
      tabla tiene 2 filas en total, las dos ya revisadas), así que el badge quedaba
      escondido para siempre.
   2. El botón de PPP era el **único** de la fila sin `position:relative`. El badge
      es `position:absolute`, así que se posicionaba contra otro ancestro y, aunque
      hubiera aparecido, no caía sobre la tarjeta.

   ── Qué cuenta ahora ────────────────────────────────────────────────────────
   Una fila por tipo de aviso, y el front suma. **Se agrupa por COSA, no por fila**:
   un camión mezclado cuenta 1 aunque tenga 4 pedidos adentro, y un pedido de dos
   bloques cuenta 1 aunque sean dos NP.

   | tipo | qué es | al 16/09 |
   |---|---|---|
   | `super_mezclado` | un camión con un súper y clientes comunes | 1 (E11) |
   | `tanda_dos_camiones` | una tanda con paradas de dos recorridos | 1 (D69F) |
   | `tanda_dos_dias` | el mismo código de tanda en dos fechas | 1 (D69C) |
   | `retenido_sin_fecha` | pedidos sacados a mano de una tanda, esperando fecha | 7 |
   | `alerta_web` | pedidos web anómalos sin revisar | 0 |

   Total: **10**.

   ⚠ `retenido_sin_fecha` es el que más importa que esté acá. El retenido es a
   propósito —lo que se saca a mano de una tanda no lo vuelve a agarrar el
   automático (v17.85)— pero la contracara es que un pedido puede quedarse quieto
   **para siempre sin que nada avise**. Al 16/09 el más viejo lleva 10 días
   (Gifel S.R.L., entró el 06/09). Hasta ahora la única forma de enterarse era
   abrir la pantalla y mirar.

   ── Costo ──────────────────────────────────────────────────────────────────
   **177 ms** medidos, contra un tope de 8 s. El front la pide cada 2 minutos
   mientras el panel de supervisor está a la vista, o sea que no es camino caliente.

   ── Permisos ───────────────────────────────────────────────────────────────
   `security_invoker = true` y probada **con el rol `anon`**, que es el que usa la
   app: devuelve los mismos números. Sin ese chequeo, una tabla con RLS habría
   dado 0 en silencio y el badge volvería a no mostrarse nunca — que es
   exactamente el bug que se está arreglando.
   ============================================================================ */

create or replace view public.gv_ppp_avisos
with (security_invoker = true) as
select 'super_mezclado'::text as tipo, 1 as orden,
       'Súper mezclado con clientes en el mismo camión'::text as titulo,
       count(distinct dia || '|' || cam)::int as n
  from public.gv_ppp_super_mezclado
union all
select 'tanda_dos_camiones', 2, 'Tanda con paradas de dos recorridos',
       count(distinct tanda)::int from public.gv_ppp_tanda_camion_mezclado
union all
select 'tanda_dos_dias', 3, 'Tanda con el mismo código en dos días',
       count(distinct tanda)::int from public.gv_ppp_tanda_dos_dias
union all
select 'retenido_sin_fecha', 4, 'Pedidos sacados a mano, esperando fecha',
       count(distinct empresa || '|' || order_id::text)::int from public."GV_PPP_Web_Retenido"
union all
select 'alerta_web', 5, 'Pedidos web anómalos sin revisar',
       count(*)::int from public."Alertas_Pedidos_Web" where estado = 'pendiente';

grant select on public.gv_ppp_avisos to anon, authenticated, service_role;

comment on view public.gv_ppp_avisos is
  'Una fila por tipo de aviso de la PPP con su conteo (v19.14, Luis). Alimenta el badge rojo del '
  'boton PPP del panel supervisor. n = 0 significa que ese aviso no tiene nada.';

/* Chequeo:
     select * from public.gv_ppp_avisos order by orden;   -- todos en 0 = todo bien
   Y el que no hay que saltearse, porque es el bug que esto arregla:
     set local role anon; select tipo, n from public.gv_ppp_avisos order by orden;

   Del lado del front (`index.html`): `pppFetchAvisos` la lee, `pppAlertBadgeUpdate` suma y llama
   a `supSetBadge`, el mismo que usan Facturación, Stock y Recepción Remitos — número rojo si hay
   algo, ✓ verde si no. El badge va arriba a la DERECHA, igual que los demás
   (Luis lo pidió a la izquierda y lo corrigió a la derecha el mismo día; `dp-badge` ya es
   `right:2px`, así que no lleva estilo propio de posición).

   Rollback: `drop view public.gv_ppp_avisos;` y volver el botón de PPP a como estaba
   (sin `position:relative`, con la clase `ppp-alert-badge`). Test: `tests/ppp-badge.cjs`.       */
