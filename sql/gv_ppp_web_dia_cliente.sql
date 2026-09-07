-- =============================================================================
-- gv_ppp_web_dia_cliente.sql — "si el cliente YA tiene camión, engancharlo ahí"
-- v13.93 · 2026-09-07 · Proyecto Virgilio (hrxfctzncixxqmpfhskv)
-- =============================================================================
-- EL CASO QUE LO MOTIVÓ (medido el 07/09). Osa Distribuidora (cod 2533, Villa
--   Lugano, Zona 1) tenía camión el miércoles 9 — tanda D66B, 4,04 m³ en dos NP.
--   Entró un pedido web del mismo cliente, de 0,026 m³, y el automático lo programó
--   para el martes 15, en camión aparte: 26 litros, seis días después, mismo cliente
--   y mismo barrio.
--
-- DOS CAUSAS, las dos de diseño:
--   1) El colchón de 4 días hábiles (`dias_anticipacion_min`) tapaba el 9: un lunes 7
--      el mínimo era el 11, así que los días 8, 9 y 10 ni se miraban.
--   2) El automático NUNCA miraba si el cliente ya tenía camión ese día. Sólo mira
--      cupo por día y cercanía entre las tandas que arma en esa misma corrida; la
--      D66B es de ISIS y queda entera fuera de su universo.
--   El cupo tampoco lo hubiera dejado entrar: el 9 estaba en 7,03 m³ contra un cupo
--   de 6.
--
-- LAS DOS DEFINICIONES DEL DUEÑO (07/09), textuales:
--   · **Pisa el colchón Y el cupo.** Es el único modo que resuelve el caso, porque el
--     9 estaba a la vez dentro del colchón y pasado de cupo. El cupo mide PICKING, y
--     sumarle 26 litros a un cliente que ya tiene 4 m³ armándose ese día es casi
--     gratis y ahorra un camión entero.
--   · **"Tiene que buscar para atrás, no para adelante."** Entre mañana y el día que
--     el automático elegiría por su cuenta, se toma el día en que el cliente ya tiene
--     entrega. La regla ADELANTA el pedido, nunca lo demora.
--
-- CÓMO PISA CADA COSA — sin código nuevo, reusando lo que ya existía:
--   · el colchón lo aplica el LLAMADOR (`gv_ppp_web_dia_minimo`), no
--     `ppp_web_armar_tandas`; pasarle una fecha explícita ya lo saltea;
--   · el cupo se saltea pasando el cod en `p_forzar_cods`: eso lo marca `prioritario`,
--     que es la rama del filtro de selección que entra siempre;
--   · con `p_incluir_manuales = true` vale para TODAS las zonas.
--   La v13.47 ya hacía esto pero por ZONA (`gv_ppp_web_dia_camion`, bloque (c) de
--   `gv_ppp_web_armar_pendientes`). Ésta es la versión por CLIENTE.
--
-- DÓNDE SE ENGANCHA: bloque (a2) de `gv_ppp_web_armar_pendientes`, ANTES de la
--   cascada (b) a propósito — lo que se programa ahí queda con tanda, y la cascada
--   lo saltea sola por su filtro de "no programado".
--
-- PROBADO el 2026-09-07 en transacción revertida (3 casos):
--   · cod 2533 (Osa, con camión el 09) → tanda D66G, 09/09   ← adelantado, correcto
--   · cod 3872 (A L S.A, con entrega el 14) → E01A, 14/09    ← adelantado del 15 al 14
--   · cod 4999 (sin ninguna entrega) → E03A, 15/09           ← camino normal, sin tocar
--   Rollback verificado: 0 filas de prueba, `PPP_Web_Programacion` quedó en 28.
--
-- NO TOCA PRODUCCIÓN: sólo lee. `gv_ppp_web_dia_cliente` es objeto nuevo con prefijo
--   `gv_`; `gv_ppp_web_armar_pendientes` ya era nuestra.
-- ROLLBACK: sql/backups/gv_ppp_web_armar_pendientes_20260907_pre_a2.sql
-- =============================================================================

create or replace function public.gv_ppp_web_dia_cliente(
  p_empresa text, p_cod text, p_desde date, p_hasta date)
returns date
language sql
stable
set search_path to 'public'
as $fn$
  -- ¿El cliente ya tiene entrega programada entre p_desde y p_hasta? Devuelve el día
  -- MÁS TEMPRANO ("para atrás, no para adelante"). Mira las dos fuentes, igual que
  -- gv_ppp_web_dia_camion: lo web y el espejo de ISIS. Sólo días con camión de
  -- reparto: exige "Zona N" (Retira/Súper/Expo no son camión) y saltea KRIKOS (el
  -- súper va en camión propio, una tanda por cliente).
  select min(dia) from (
    select w.fecha_entrega as dia
      from public."PPP_Web_Programacion" w
     where w.empresa = p_empresa
       and btrim(coalesce(w.cod_cliente, '')) = btrim(coalesce(p_cod, ''))
       and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
       and coalesce(w.zona, '') ~ '^\s*Zona\s*[0-9]+'
       and w.fecha_entrega between p_desde and p_hasta
    union all
    select left(btrim(i.fecha_entrega::text), 10)::date
      from public.gv_ppp_programacion_diaria i
     where btrim(coalesce(i.cod, '')) = btrim(coalesce(p_cod, ''))
       and coalesce(nullif(btrim(i.tanda), ''), '') <> ''
       and coalesce(i.tipo, '') <> 'KRIKOS'
       and coalesce(i.zona, '') ~ '^\s*Zona\s*[0-9]+'
       and btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
       and left(btrim(i.fecha_entrega::text), 10)::date between p_desde and p_hasta
       -- el cod de cliente es POR EMPRESA: LK 2533 no es el mismo que Chef 2533
       and ((p_empresa = 'lk'   and btrim(i.np) ~ '^9')
         or (p_empresa = 'chef' and btrim(i.np) ~ '^4'))
  ) d;
$fn$;

revoke all on function public.gv_ppp_web_dia_cliente(text,text,date,date) from public, anon;
grant execute on function public.gv_ppp_web_dia_cliente(text,text,date,date) to authenticated, service_role;

-- El bloque (a2) que la usa vive dentro de gv_ppp_web_armar_pendientes; el cuerpo
-- completo y vigente de esa función se saca con:
--   select pg_get_functiondef(oid) from pg_proc where proname = 'gv_ppp_web_armar_pendientes';

-- ----------------------------------------------------------------------------
-- Controles (correr a mano)
-- ----------------------------------------------------------------------------
--   -- El techo (día que elegiría el automático) y el día del cliente:
--   select public.gv_ppp_web_proximo_dia_con_cupo(public.gv_ppp_web_dia_minimo()) as techo,
--          public.gv_ppp_web_dia_cliente('lk','2533', current_date + 1,
--            public.gv_ppp_web_proximo_dia_con_cupo(public.gv_ppp_web_dia_minimo()) - 1) as dia_cliente;
--
--   -- Prueba sin escribir (dentro de begin … rollback):
--   begin;
--     select * from public.gv_ppp_web_armar_pendientes('lk', null,
--       '[{"order_id":999901,"np_idx":1,"cod":"2533","zona":"Zona 1 - CABA Sur",
--          "barrio":"Villa Lugano","m3":0.03,"lineas":1,"cajas":5,"fecha_recep":"2026-09-07"}]'::jsonb,
--       '[]'::jsonb);
--     select order_id, tanda, fecha_entrega from public."PPP_Web_Programacion" where order_id = 999901;
--   rollback;
-- ----------------------------------------------------------------------------
