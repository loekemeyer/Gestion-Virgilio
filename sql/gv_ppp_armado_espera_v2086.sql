-- ═══════════════════════════════════════════════════════════════════════════════
-- v20.86 (Thomas, 2026-09-21) — EL ARMADO QUE ESPERA CAMION ENTRA AL BADGE DE LA PPP
--
-- Thomas, textual: *"deberia aparecer discriminado en el badge del icono de PPP en la
-- pagina principal del admin (un numero rojo con los pendientes)"*.
--
-- QUE PASO. Iro Iro (4223), NP 98626/98627, tandas E39A/E40A, 0,483 m3: pickeadas el
-- 14/09, armadas el 15/09, FACTURADAS el 16/09, y el 18/09 alguien las cargo en
-- GV_PPP_Armados_Espera. gv_ppp_programacion_diaria le vacia la fecha_entrega a
-- cualquier NP que este en esa tabla (es el sentido del modulo: armado sin dia), asi que
-- las dos NP desaparecieron de TODOS los dias de la Programacion. No estaban en ninguna
-- pantalla, no podian figurar como "Salio", y nada avisaba.
--
-- No es un bug del modulo: esta haciendo lo que dice. El agujero es que **no habia forma
-- de enterarse** — un pedido ya facturado podia quedarse ahi para siempre. Lo encontro
-- Thomas mirando, no el sistema. Es el mismo criterio de la regla de Elias (v20.58): el
-- tapon va junto con la forma nueva de enterarse; y el de la v20.72 con Albalandia, que
-- tambien era un bulto armado que no aparecia en ninguna pantalla.
--
-- ⚠ Y no se cuenta "cuantas filas hay" sino CUANTOS PEDIDOS: igual que el resto de
-- gv_ppp_avisos, una cosa = un renglon. Iro Iro son 2 NP de UN pedido y cuenta 1.
--
-- ⚠ La fila NO guarda quien ni por que (`por` y `motivo` vienen NULL en las dos que hay):
-- el detalle lo dice con todas las letras en vez de inventarlo.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── 1. La vista base ──────────────────────────────────────────────────────────
-- Resuelve el cliente, la zona y los m3 contra las DOS programaciones (ISIS y web), que
-- es de donde sale el dato segun de donde venga la NP.
create or replace view public.gv_ppp_armado_espera
with (security_invoker = true) as
with ae as (
  select btrim(e.np)                      as np,
         btrim(e.tanda)                   as tanda,
         lower(coalesce(e.empresa, 'lk')) as empresa,
         e.m3                             as m3_fila,
         nullif(btrim(coalesce(e.por, '')), '')    as por,
         nullif(btrim(coalesce(e.motivo, '')), '') as motivo,
         e.creado_en
    from public."GV_PPP_Armados_Espera" e
), i as (   -- NP de ISIS
  select regexp_replace(btrim(p.np), '\.0+$', '') as np,
         p.cod, p.razon_social, p.zona, p.m3::numeric as m3
    from public.gv_ppp_programacion_diaria p
), w as (   -- NP web
  select public.gv_ppp_web_np_label(x.empresa, x.np, x.np_idx) as np,
         x.cod_cliente as cod, x.razon_social, x.zona, x.m3
    from public."PPP_Web_Programacion" x
)
select a.np,
       a.tanda,
       a.empresa,
       coalesce(i.cod, w.cod)                   as cod,
       coalesce(i.razon_social, w.razon_social)  as razon_social,
       coalesce(i.zona, w.zona)                  as zona,
       round(coalesce(a.m3_fila, i.m3, w.m3), 3) as m3,
       a.creado_en::date                         as desde,
       (current_date - a.creado_en::date)        as dias,
       -- facturado sin salir es lo que apura: el cliente tiene la factura y no la caja
       exists (select 1 from public."Facturacion_NP" f where f.np = a.np) as facturado,
       a.por,
       a.motivo
  from ae a
  left join i on i.np = a.np
  left join w on w.np = a.np;

alter view public.gv_ppp_armado_espera set (security_invoker = true);
grant select on public.gv_ppp_armado_espera to anon, authenticated;

-- ── 2. El conteo que alimenta el numero rojo ──────────────────────────────────
-- Se agrega el tipo `armado_espera` en orden 4 (un pedido armado y facturado sin salir
-- pesa mas que una alerta web sin revisar) y se corren los dos de abajo.
create or replace view public.gv_ppp_avisos
with (security_invoker = true) as
 SELECT 'super_mezclado'::text AS tipo,
    1 AS orden,
    'Súper mezclado con clientes en el mismo camión'::text AS titulo,
    count(DISTINCT (gv_ppp_super_mezclado.dia || '|'::text) || gv_ppp_super_mezclado.cam)::integer AS n
   FROM gv_ppp_super_mezclado
UNION ALL
 SELECT 'tanda_dos_camiones'::text AS tipo,
    2 AS orden,
    'Tanda con paradas de dos recorridos'::text AS titulo,
    count(DISTINCT gv_ppp_tanda_camion_mezclado.tanda)::integer AS n
   FROM gv_ppp_tanda_camion_mezclado
UNION ALL
 SELECT 'tanda_dos_dias'::text AS tipo,
    3 AS orden,
    'Tanda con el mismo código en dos días'::text AS titulo,
    count(DISTINCT gv_ppp_tanda_dos_dias.tanda)::integer AS n
   FROM gv_ppp_tanda_dos_dias
UNION ALL
 -- v20.86 — armado que espera camion. Cuenta PEDIDOS (cliente), no NP.
 SELECT 'armado_espera'::text AS tipo,
    4 AS orden,
    'Pedidos armados esperando camión (sin día)'::text AS titulo,
    count(DISTINCT (a.empresa || '|'::text) || coalesce(a.cod, a.np))::integer AS n
   FROM gv_ppp_armado_espera a
UNION ALL
 SELECT 'retenido_sin_fecha'::text AS tipo,
    5 AS orden,
    'Pedidos sacados a mano, esperando fecha'::text AS titulo,
    count(DISTINCT ("GV_PPP_Web_Retenido".empresa || '|'::text) || "GV_PPP_Web_Retenido".order_id::text)::integer AS n
   FROM "GV_PPP_Web_Retenido"
UNION ALL
 SELECT 'alerta_web'::text AS tipo,
    6 AS orden,
    'Pedidos web anómalos sin revisar'::text AS titulo,
    count(*)::integer AS n
   FROM "Alertas_Pedidos_Web"
  WHERE "Alertas_Pedidos_Web".estado = 'pendiente'::text;

alter view public.gv_ppp_avisos set (security_invoker = true);

-- ── 3. El desglose que abre el badge al tocarlo ───────────────────────────────
create or replace view public.gv_ppp_avisos_detalle
with (security_invoker = true) as
 SELECT 'super_mezclado'::text AS tipo,
    1 AS orden,
    'Súper mezclado con clientes en el mismo camión'::text AS titulo,
    s.dia::date AS fecha,
    'Camión '::text || s.cam AS que,
    (((count(*) FILTER (WHERE s.que_es = 'super'::text) || ' súper + '::text) || count(*) FILTER (WHERE s.que_es <> 'super'::text)) || ' cliente(s): '::text) || string_agg(DISTINCT COALESCE(NULLIF(btrim(s.razon_social), ''::text), s.cod), ', '::text) AS detalle,
    'El súper no comparte camión con clientes comunes. Mover las NP comunes a otro camión.'::text AS accion
   FROM gv_ppp_super_mezclado s
  GROUP BY s.dia, s.cam
UNION ALL
 SELECT 'tanda_dos_camiones'::text AS tipo,
    2 AS orden,
    'Tanda con paradas de dos recorridos'::text AS titulo,
    t.fecha,
    'Tanda '::text || t.tanda AS que,
    ((((((t.nps || ' NP · '::text) || t.clientes) || ' cliente(s) · '::text) || t.camiones) || ' ('::text) || t.zonas) || ')'::text AS detalle,
    'La tanda se parte por camión. Mover a otra tanda las NP del camión que no corresponde.'::text AS accion
   FROM gv_ppp_tanda_camion_mezclado t
UNION ALL
 SELECT 'tanda_dos_dias'::text AS tipo,
    3 AS orden,
    'Tanda con el mismo código en dos días'::text AS titulo,
    min(d.fecha) AS fecha,
    'Tanda '::text || d.tanda AS que,
    ((('sale el '::text || string_agg(DISTINCT to_char(d.fecha::timestamp with time zone, 'DD/MM'::text), ' y el '::text)) || ' · '::text) || count(*)) || ' NP'::text AS detalle,
    'Una tanda no puede salir en dos días: cae en dos camiones. Renombrar una de las dos.'::text AS accion
   FROM gv_ppp_tanda_dos_dias d
  GROUP BY d.tanda
UNION ALL
 -- v20.86 — un renglon por PEDIDO, con los dias que lleva y si ya se facturo.
 SELECT 'armado_espera'::text AS tipo,
    4 AS orden,
    'Pedidos armados esperando camión (sin día)'::text AS titulo,
    min(a.desde) AS fecha,
    COALESCE(NULLIF(btrim(a.razon_social), ''::text), 'Cliente ' || COALESCE(a.cod, a.np)) AS que,
    count(*) || ' NP (' || string_agg(DISTINCT a.np, ', '::text) || ') · tanda ' ||
      string_agg(DISTINCT a.tanda, ', '::text) || ' · ' ||
      to_char(sum(a.m3), 'FM990.000') || ' m³ · ' ||
      COALESCE(NULLIF(btrim(min(a.zona)), ''::text), 'sin zona') || ' · espera hace ' ||
      max(a.dias) || ' día(s)' ||
      CASE WHEN bool_or(a.facturado) THEN ' · ⚠ YA FACTURADO sin salir' ELSE '' END ||
      CASE WHEN count(*) FILTER (WHERE a.por IS NOT NULL) > 0
           THEN ' · lo dejó ' || string_agg(DISTINCT a.por, ', '::text)
           ELSE ' · no quedó registrado quién ni por qué' END AS detalle,
    'Está armado en el pallet sin día de entrega. Darle día con camión a su zona, o fundar uno.'::text AS accion
   FROM gv_ppp_armado_espera a
  GROUP BY a.empresa, COALESCE(a.cod, a.np), a.razon_social
UNION ALL
 SELECT 'retenido_sin_fecha'::text AS tipo,
    5 AS orden,
    'Pedidos sacados a mano, esperando fecha'::text AS titulo,
    min(r.fecha_previa) AS fecha,
    (upper(
        CASE
            WHEN r.empresa = 'chef'::text THEN 'CH'::text
            ELSE 'LK'::text
        END) || ' pedido '::text) || r.order_id AS que,
    ((((count(*) || ' NP · salió de la tanda '::text) || string_agg(DISTINCT r.tanda_previa, ', '::text)) ||
        CASE
            WHEN bool_or(r.tanda_estado = ANY (ARRAY['pickeada'::text, 'armada'::text, 'facturada'::text, 'salio'::text])) THEN (' · ⚠ esa tanda '::text || string_agg(DISTINCT r.tanda_estado, ', '::text) FILTER (WHERE r.tanda_estado = ANY (ARRAY['pickeada'::text, 'armada'::text, 'facturada'::text, 'salio'::text]))) || ' SIN este pedido: NO vuelve ahí, va a una tanda nueva'::text
            WHEN bool_or(r.tanda_viva) THEN (' · esa tanda sale el '::text || to_char(min(r.tanda_fecha)::timestamp with time zone, 'DD/MM'::text)) || ' y no se empezó: vuelve ahí'::text
            ELSE ' · esa tanda ya no existe: el código queda libre'::text
        END) || ' · lo sacó '::text) || string_agg(DISTINCT r.por, ', '::text) AS detalle,
    'Está en A Programar esperando día. Si su tanda ya avanzó, va a una tanda nueva y se pickea normal.'::text AS accion
   FROM gv_ppp_web_retenido r
  GROUP BY r.empresa, r.order_id
UNION ALL
 SELECT 'alerta_web'::text AS tipo,
    6 AS orden,
    'Pedidos web anómalos sin revisar'::text AS titulo,
    a.creado_en::date AS fecha,
    'Pedido '::text || a.order_id AS que,
    ((COALESCE(NULLIF(btrim(a.cliente), ''::text), a.cod_cliente) || ' · score '::text) || a.score) || COALESCE(' · '::text || NULLIF(btrim(a.motivo), ''::text), ''::text) AS detalle,
    'Mirarlo en la PPP y marcarlo Revisado o Descartar.'::text AS accion
   FROM "Alertas_Pedidos_Web" a
  WHERE a.estado = 'pendiente'::text;

alter view public.gv_ppp_avisos_detalle set (security_invoker = true);

-- ── 4. Centinela: que nadie se lleve el tipo nuevo por delante ────────────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values
 ('gv_ppp_avisos', 'vista', 'armado_espera',
  'El badge de la PPP tiene que contar los armados que esperan camion (GV_PPP_Armados_Espera): sin eso un pedido facturado queda invisible, como Iro Iro 98626/98627.',
  'Thomas', 'v20.86'),
 ('gv_ppp_avisos_detalle', 'vista', 'armado_espera',
  'El desglose del badge tiene que decir que pedido esta armado esperando camion, hace cuantos dias y si ya se facturo.',
  'Thomas', 'v20.86')
on conflict do nothing;
