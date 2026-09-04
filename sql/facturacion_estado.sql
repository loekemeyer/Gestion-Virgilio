-- ══════════════════════════════════════════════════════════════════════════
-- vista_facturacion_estado — en qué punto del circuito está cada NP tildada
-- Corre en VIRGILIO (hrxfctzncixxqmpfhskv) · 2026-09-04
-- ══════════════════════════════════════════════════════════════════════════
-- QUÉ RESUELVE
-- ──────────────────────────────────────────────────────────────────────────
-- El módulo de Facturación pasa a tener TRES sublistas en vez de una sola:
--   1. armados PENDIENTES de facturar   → NP armada, todavía sin tildar
--   2. armados ESPERANDO CONFIRMACIÓN   → tildada y mandada a ISIS, sin factura
--   3. armados FACTURADOS               → ya apareció el comprobante
--
-- Esta vista resuelve el corte **2↔3**, que es el nuevo. La lista 1 la sigue
-- armando el front, que es el único que sabe si una NP está armada: cruza
-- `Entregas_Virgilio` con el fallback de eventos TAL/TAP (`facEstaArmada`, v12.18).
--
-- ── CÓMO SE SABE QUE SE FACTURÓ ───────────────────────────────────────────
-- Hay DOS caminos y se aceptan los dos, porque son independientes y ninguno
-- alcanza solo:
--
--   (a) EL ACUSE DE ISIS. `isis_export_pedidos` es la cola de salida al ERP
--       (`sql/isis_api.sql`). Cuando ISIS procesa el pedido acusa por la API con
--       resultado 'ok' + nro_comprobante + CAE. Es el camino rápido y explícito,
--       pero depende de que ISIS efectivamente use la API.
--
--   (b) EL PARSEO DE COMPROBANTES. `vista_cruce_facturacion` matchea la NP contra
--       el comprobante real de `isis_lk`/`isis_ch.documentos` por cliente + fecha
--       (±3 días) + cajas con tolerancia. Es el que YA funciona hoy sin que ISIS
--       toque nada.
--
-- Con cualquiera de los dos la NP pasa a "facturado". La columna `via` dice por
-- cuál entró — sirve para saber si el circuito de la API está andando de verdad.
--
-- ── LO QUE NO DA (medido el 2026-09-04, no supuesto) ──────────────────────
-- Sobre las 1.181 NP tildadas: 735 facturadas (todas por parseo, 0 por acuse —
-- ISIS todavía no usa la API) y 446 esperando. Repartidas por antigüedad:
--
--   última semana        102 facturado ·  29 esperando   (78%)
--   8 a 30 días          298 facturado ·  57 esperando   (84%)
--   junio a hace 30 d    335 facturado · 306 esperando   (52%)
--   anterior a junio       0 facturado ·  54 esperando   (el parseo arranca en junio)
--
-- O sea: para lo reciente el corte sirve; hacia atrás hay una cola de NP viejas
-- que nunca van a confirmar. **La sublista 2 conviene mostrarla con ventana de
-- fecha**, o se convierte en un cementerio.
--
-- ⚠ Falso negativo conocido, documentado en `sql/cruce_facturacion.sql`: si una
--   factura consolida varias NP del mismo cliente y día, sus cajas son la SUMA y
--   no matchea 1:1 contra ninguna. Esa NP se queda en "esperando_confirmacion"
--   sin estar mal. Por eso se expone `candidatos_cercanos`: es la pista para
--   resolverlo a ojo.
--
-- ⚠ Las NP web (LK 1343 / CH 7) todavía NO llegan acá: `Facturacion_NP` sólo
--   tiene NP de ISIS (de 44361 para arriba). Cuando la facturación de NP web se
--   conecte entran solas — la vista no las distingue.
--
-- `security_invoker = true`: la RLS de las tablas de abajo es la que decide.
-- ══════════════════════════════════════════════════════════════════════════

create or replace view public.vista_facturacion_estado
with (security_invoker = true) as
select
  f.np,
  f.tanda,
  f.fecha_salida,
  f.cod_cliente,
  f.razon_social,
  f.m3,
  f.facturado_at        as tildado_at,     -- cuándo la tildó la operadora
  f.cierre_id,
  -- salida hacia ISIS (cola de la API)
  e.estado              as isis_estado,    -- pendiente|entregado|procesado|error|anulado
  e.entregado_en        as isis_bajado_en, -- cuándo ISIS se lo llevó (GET)
  e.procesado_en        as isis_acuse_en,  -- cuándo acusó (POST)
  e.error_detalle       as isis_error,
  -- el comprobante, venga por donde venga
  coalesce(e.nro_comprobante, c.comprobante_id::text) as nro_comprobante,
  coalesce(e.cae, c.cae)                              as cae,
  c.doc_fecha           as factura_fecha,
  c.factura_total,
  c.diff_pct            as diff_pct_vs_calculado,
  c.candidatos_cercanos,
  case
    when e.resultado = 'ok' and coalesce(e.nro_comprobante,'') <> '' then 'acuse_isis'
    when c.comprobante_id is not null                                then 'parseo'
  end as via,
  case
    when (e.resultado = 'ok' and coalesce(e.nro_comprobante,'') <> '')
      or c.comprobante_id is not null then 'facturado'
    else 'esperando_confirmacion'
  end as estado
from public."Facturacion_NP" f
left join public.isis_export_pedidos e
       on e.np = f.np::text and e.estado <> 'anulado'
left join public.vista_cruce_facturacion c
       on c.np = f.np::text;

comment on view public.vista_facturacion_estado is
  'Una fila por NP tildada para facturar, con su estado: esperando_confirmacion o facturado. El corte 2-3 de las tres sublistas del módulo Facturación. Ver sql/facturacion_estado.sql.';

grant select on public.vista_facturacion_estado to anon, authenticated;

-- ──────────────────────────────────────────────────────────────────────────
-- Controles
-- ──────────────────────────────────────────────────────────────────────────
--   -- El reparto, y por qué vía se confirma cada una:
--   select estado, via, count(*) from public.vista_facturacion_estado
--    group by 1,2 order by 1,2;
--
--   -- Las que esperan hace demasiado (candidatas a revisar a mano):
--   select np, tanda, fecha_salida, razon_social, candidatos_cercanos
--     from public.vista_facturacion_estado
--    where estado = 'esperando_confirmacion'
--      and fecha_salida::date < current_date - 7
--    order by fecha_salida;
--
--   -- ¿Empezó a andar el acuse de la API? (hoy da 0)
--   select count(*) from public.vista_facturacion_estado where via = 'acuse_isis';
-- ══════════════════════════════════════════════════════════════════════════
