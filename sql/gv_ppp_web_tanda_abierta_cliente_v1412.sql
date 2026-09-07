-- gv_ppp_web_tanda_abierta_cliente — v14.12 (2026-09-07) · Virgilio (hrxfctzncixxqmpfhskv)
--
-- QUÉ CAMBIA Y POR QUÉ
-- ====================
-- Regla del dueño, 07/09, zanjada después de dos vueltas y de que dos sesiones se pisaran el
-- mismo pedido. Textual:
--
--     "solo va en tanda nueva si mezcla lo que es pedido isis y pedido web"
--
-- **El corte es el ORIGEN, no "¿ya se tocó?".** La v14.05 lo había leído al revés: su propio
-- comentario decía *"el corte es ¿ya se tocó?, NO ¿es de ISIS o es web?"*. Con esa lectura la
-- función tomaba como candidatas también las tandas de ISIS y metía pedidos de la página adentro
-- de ellas.
--
-- Cómo se llegó acá (para que no se vuelva a dar vuelta):
--   1. El dueño explicó el caso Osa: *"la primera de osa es pedido de isis y el agregado, del nuevo
--      formato"* — y agregó que si la tanda no se pickeó, el agregado va adentro.
--   2. Eso se leyó como "el corte es si se pickeó" (v14.05) y el 1354 se fusionó con la tanda ISIS.
--   3. El dueño lo vio y frenó: *"osa no puede quedar en D66B el pedidito chiquito del agregado.
--      tiene que ir en una nueva tanda"*.
--   4. Preguntado si eso era sólo para Osa o cambiaba la regla, respondió la frase de arriba.
--
-- REGLA QUE QUEDA
--   · agregado web + tanda WEB del mismo cliente y día, sin empezar  → se junta
--   · agregado web + tanda de ISIS                                    → SIEMPRE tanda nueva
--   · el guard de "sin empezar" se mantiene: sumarle algo a una tanda ya pickeada rompe el picking
--
-- EL CAMBIO CONCRETO: la CTE `cand` hacía un UNION de dos ramas; **se sacó la segunda**, la que
-- traía las tandas de `gv_ppp_programacion_diaria` (ISIS). Ahora sólo mira `PPP_Web_Programacion`.
-- Si el cliente sólo tiene tanda de ISIS, devuelve NULL y el armado abre tanda nueva.
--
-- MEDIDO DESPUÉS DEL CAMBIO
--   gv_ppp_web_tanda_abierta_cliente('lk','2533','2026-09-09') → 'E09B'   (su tanda WEB)
--     con la versión vieja daba 'E09A', que es la de ISIS → era el bug
--   ('lk','45'  ,'2026-09-15') → 'E03A'   (tanda web sin empezar: se junta, correcto)
--   ('lk','3843','2026-09-14') → 'E01E'   (idem)
--   ('lk','9999','2026-09-14') → NULL     (sin nada ese día: tanda nueva, correcto)
--
-- QUIÉN LA USA: el bloque (a1) de `gv_ppp_web_armar_pendientes`, que corre en el job de las 00:01
-- (cron 71) y en el intradía (cron 73). No la usa Producción.
--
-- BACKUP de la definición anterior: public."GV_Backup_Func_20260907_tanda_abierta"
-- ROLLBACK:  select def from public."GV_Backup_Func_20260907_tanda_abierta";  -- y ejecutarlo

create or replace function public.gv_ppp_web_tanda_abierta_cliente(p_empresa text, p_cod text, p_fecha date)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  -- v14.12 — ¿el cliente ya tiene ese día una tanda WEB a la que se pueda sumar el agregado?
  --
  -- REGLA DEL DUEÑO (07/09): "solo va en tanda nueva si mezcla lo que es pedido isis y pedido web".
  -- El corte es el ORIGEN, no "¿ya se tocó?". Por eso acá SOLO se miran las tandas de
  -- PPP_Web_Programacion: las de ISIS ya no son candidatas, así que un agregado web sobre un
  -- cliente que sólo tiene tanda de ISIS abre tanda nueva (caso Osa: E09A es de ISIS, el agregado
  -- va en E09B, mismo camión y misma dirección, picking separado).
  --
  -- Se mantiene el guard de "sin empezar": sumarle algo a una tanda ya pickeada rompe el picking.
  with cand as (
    select upper(btrim(w.tanda)) as tanda
      from public."PPP_Web_Programacion" w
     where w.empresa = p_empresa
       and btrim(coalesce(w.cod_cliente, '')) = btrim(coalesce(p_cod, ''))
       and w.fecha_entrega = p_fecha
       and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
       and coalesce(w.zona, '') ~ '^\s*Zona\s*[0-9]+'
  )
  select min(c.tanda) from cand c
   where not exists (
     select 1 from public."Registros_Produccion_Virgilio" r
      where r.opcion in ('EP','TP','AP','TAP')
        and (   upper(btrim(split_part(r.texto, '|', 1))) = c.tanda
             or upper(btrim(split_part(r.texto, '|', 2))) = c.tanda
             or upper(btrim(split_part(r.texto, '|', 3))) = c.tanda)
   );
$function$;
