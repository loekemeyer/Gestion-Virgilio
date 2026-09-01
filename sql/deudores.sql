-- ══════════════════════════════════════════════════════════════════════════
-- Deudores — deuda por cliente + escalera de descuento por pronto pago
-- ══════════════════════════════════════════════════════════════════════════
-- v12.25 (2026-09-01). Reemplaza al módulo "Deuda a cobrar" (v9.23/v11.68):
-- ese dependía de tickear "Facturar" en el celular (tabla deuda_movimientos,
-- 0 filas en producción — el fire-and-forget fallaba en silencio) y
-- revalorizaba a mano con precios de LK, duplicando vista_facturacion_neto.
-- Se borraron (0 filas, sin backup real que hacer, verificado antes):
--   deuda_movimientos, vista_deuda_saldo,
--   deuda_registrar_facturado(text,text,text,jsonb,text),
--   deuda_registrar_cobrado(text,numeric,text,text), deuda_borrar_facturado(text)
--
-- Este módulo lee isis_lk/isis_ch.documentos — las facturas reales que ya
-- sube el agente local del ISIS (esquemas sin documentar hasta ahora, ver
-- GUIA-PROYECTO.md § "Esquemas isis_lk / isis_ch"). La deuda existe apenas
-- se factura: no hay nada que registrar desde el front.
--
-- Fase 1: deuda BRUTA (cobrado = 0 constante). El enganche para cuando el
-- agente del ISIS empiece a parsear recibos es isis_lk.comprobantes_aplicados
-- (hoy 19 filas) — saldo = importe - cobrado ya está escrito así, no hace
-- falta rehacer nada cuando llegue.
--
-- Objetos:
--   cobranzas_escalones        — la escalera de descuento (pública, config).
--   deudores_condiciones       — condicion_venta (texto ISIS) → días de plazo.
--   cobranzas_excepciones      — plazo pactado por cliente, pisa la escalera.
--   vista_deudores_documentos  — un comprobante = una fila (interna, REVOKE anon).
--   deudores_resumen(...)      — agregado por deudor, paginado (RPC, EXECUTE anon).
--   deudores_detalle(id)       — comprobantes de un deudor (RPC, EXECUTE anon).
--
-- Deudor = CUIT normalizado (11 dígitos), no código de cliente: cruza LK y
-- Chef sin tabla de mapeo (numeraciones independientes por diseño). Fallback
-- empresa|cod_canon si el CUIT no tiene 11 dígitos (no se dio en ningún caso
-- verificado, 2019-2026).
-- ══════════════════════════════════════════════════════════════════════════

-- ── 1. Escalera de descuento por pronto pago ────────────────────────────────
-- Confirmada por el dueño 2026-09-01. Misma que ya cobra el portal
-- (app_settings.wa_descuentos_config de LK) — un solo lugar, Virgilio la lee.
create table public.cobranzas_escalones (
  orden      smallint primary key,
  escalon    text not null unique,
  dias       smallint not null,
  dto        numeric(5,4) not null,
  label      text not null,
  vigente_desde date not null default current_date,
  actualizado_at timestamptz not null default now()
);
comment on table public.cobranzas_escalones is
  'Escalera de descuento por pronto pago de la empresa. Un solo lugar: lo lee '
  'Virgilio (vista_deudores_documentos) y de acá se re-copia a wa_descuentos_config '
  'en LK si algún día se decide unificar del todo (hoy son dos configs iguales '
  'a mano, confirmado 2026-09-01).';

insert into public.cobranzas_escalones (orden, escalon, dias, dto, label) values
  (1, 'contado',       14,  0.25, 'Contado (0-14 días)'),
  (2, 'credito_15_30', 30,  0.20, '15 a 30 días'),
  (3, 'credito_31_45', 45,  0.15, '31 a 45 días'),
  (4, 'credito_46_60', 60,  0.10, '46 a 60 días'),
  (5, 'echeq_90',      90,  0.05, 'E-cheq 90 días (anticipado)'),
  (6, 'echeq_120',     120, 0.00, 'E-cheq 120 días (anticipado)');

grant select on public.cobranzas_escalones to anon, authenticated;
-- ⚠ CRÍTICO (encontrado y corregido 2026-09-01, auditor-supabase): el GRANT
-- SELECT de arriba era redundante — toda tabla nueva creada por el rol
-- postgres nace con INSERT/UPDATE/DELETE/TRUNCATE YA abiertos a anon/
-- authenticated por los default privileges del schema public
-- (ALTER DEFAULT PRIVILEGES FOR ROLE postgres ... GRANT ALL ON TABLES).
-- Confirmado con explotación real: un anon podía truncar la escalera de
-- descuento. Toda tabla nueva de este archivo necesita este REVOKE explícito
-- aunque el objetivo final sea "pública de solo lectura" — el default no lo
-- da. La causa raíz (el default privilege del schema) sigue sin tocar,
-- pendiente de una pasada aparte.
revoke insert, update, delete, truncate, references, trigger
  on public.cobranzas_escalones from anon, authenticated;

-- ── 2. condicion_venta (texto del ISIS) → días de plazo ─────────────────────
create table public.deudores_condiciones (
  condicion_venta text primary key,
  dias            smallint,          -- null = sin plazo derivable
  origen          text not null default 'auto',   -- auto | manual
  nota            text,
  actualizado_at  timestamptz not null default now()
);
comment on table public.deudores_condiciones is
  'Mapa condicion_venta (isis_lk/isis_ch.documentos) → días de plazo. Fuente '
  'única para derivar vto_factura cuando el PDF no lo trae (96% de los casos). '
  'Sembrada 2026-09-01 desde las condiciones reales de 2019 a la fecha.';

insert into public.deudores_condiciones (condicion_venta, dias, origen, nota)
select condicion_venta, dias, 'auto', null
from (
  select distinct condicion_venta,
    case
      when condicion_venta ~ '^\s*(\d+)\s*FF'                    then (regexp_match(condicion_venta,'^\s*(\d+)'))[1]::int
      when condicion_venta ~* 'contado'                          then 14
      when condicion_venta ~* 'a vista'                          then 0
      when condicion_venta ~* 'e[- ]?cheq' and condicion_venta ~ '120' then 120
      when condicion_venta ~* 'e[- ]?cheq' and condicion_venta ~ '90'  then 90
      when condicion_venta ~* 'e[- ]?cheq' and condicion_venta ~ '60'  then 60
      when condicion_venta ~* 'e[- ]?cheq' and condicion_venta ~ '45'  then 45
      when condicion_venta ~* 'e[- ]?cheq' and condicion_venta ~ '30'  then 30
      when condicion_venta ~* 'e[- ]?cheq' and condicion_venta ~ '15'  then 15
      when condicion_venta ~ '46' and condicion_venta ~ '60'      then 60
      when condicion_venta ~ '31' and condicion_venta ~ '45'      then 45
      when condicion_venta ~ '30[- ]?45'                          then 45
      when condicion_venta ~ '15' and condicion_venta ~ '30'      then 30
      when condicion_venta ~* '^\s*0?6?0\s*-\s*0?6?0\s*DIAS'      then 60
      when condicion_venta ~* '^\s*0?7?5\s*-\s*0?7?5\s*DIAS'      then 75
      when condicion_venta ~* '30\s*d.?as'                        then 30
      when condicion_venta ~* '现金支付'                            then 14  -- "pago en efectivo, 25% dto" (chino, mismo caso que Contado)
      else null
    end as dias
  from (
    select condicion_venta from isis_lk.documentos where familia in ('factura_venta','nc_venta','nd_venta')
    union
    select condicion_venta from isis_ch.documentos where familia in ('factura_venta','nc_venta','nd_venta')
  ) t
  where condicion_venta is not null and condicion_venta <> ''
) d
on conflict (condicion_venta) do nothing;

update public.deudores_condiciones set dias = null, origen = 'manual',
  nota = 'Sin plazo declarado en el comprobante — factura por confirmar cotizador/condición.'
  where condicion_venta in ('Sin Cotizador', 'IMPORTADOR', 'Prefiero no decidir ahora',
    'REGULAR', 'TEST', 'FOB', ':', 'Sin especificar');
update public.deudores_condiciones set dias = null, origen = 'manual',
  nota = 'Bonificación puntual de una expo, no es un plazo de pago.'
  where condicion_venta ilike 'Expo 2023%';
update public.deudores_condiciones set origen = 'manual',
  nota = 'Descuento distinto al vigente, pero el plazo (días) sigue valiendo para vencimiento.'
  where condicion_venta in ('Pago Contado -24%','Pago E-Cheq 30 dias -13%','Pago E-Cheq 45 dias -8%',
    'Pago E-Cheq 15 dias -18%','Pago E-Cheq 60 dias 0%');

revoke all on public.deudores_condiciones from anon, authenticated;

-- ── 3. Excepciones comerciales por cliente ──────────────────────────────────
-- Grano cliente × escalón, no "cliente tiene N días" — así una excepción
-- puede correr un solo escalón sin tocar los demás. Vacía a propósito.
create table public.cobranzas_excepciones (
  id              bigint generated always as identity primary key,
  deudor_id       text not null,              -- CUIT normalizado, igual que vista_deudores_documentos
  cod_cliente     text,                        -- referencia legible, no es la clave
  empresa         text,                        -- 'lk' | 'chef' | null = aplica a ambas
  escalon         text not null references public.cobranzas_escalones(escalon),
  dias            smallint not null,           -- los días pactados para ESE escalón
  dto             numeric(5,4),                -- null = hereda el % general del escalón
  vigente_desde   date not null default current_date,
  vigente_hasta   date,                        -- null = sigue vigente. No se borra al caducar, se cierra.
  autorizado_por  text not null,
  motivo          text,
  creado_por      text,
  creado_at       timestamptz not null default now()
);
comment on table public.cobranzas_excepciones is
  'Plazo/descuento pactado con un cliente puntual, distinto de cobranzas_escalones. '
  'Prioridad 1 en vista_deudores_documentos: si hay excepción vigente para la fecha '
  'de la factura, pisa a deudores_condiciones. LK lee esta tabla por FDW de solo '
  'lectura (mismo patrón que sincronizar_ppp) para que BotWA-LK conteste "hasta '
  'cuándo tengo" — pendiente el grant al rol lk_ppp_reader, no se hace sin permiso '
  'explícito porque toca RLS de una tabla ya en uso.';

alter table public.cobranzas_excepciones enable row level security;
revoke all on public.cobranzas_excepciones from anon, authenticated;

create index cobranzas_excepciones_deudor_idx on public.cobranzas_excepciones (deudor_id, escalon);

-- ── 4. Un comprobante = una fila ─────────────────────────────────────────────
create or replace view public.vista_deudores_documentos as
with base as (
  select
    'lk'::text as empresa,
    d.id, d.familia, d.fecha, d.vto_factura, d.condicion_venta,
    d.contraparte_cuit, d.contraparte_codigo, d.contraparte_nombre,
    d.total, d.comprobante_id, d.storage_path, d.cae
  from isis_lk.documentos d
  where d.familia in ('factura_venta','nc_venta','nd_venta')
  union all
  select
    'chef'::text as empresa,
    d.id, d.familia, d.fecha, d.vto_factura, d.condicion_venta,
    d.contraparte_cuit, d.contraparte_codigo, d.contraparte_nombre,
    d.total, d.comprobante_id, d.storage_path, d.cae
  from isis_ch.documentos d
  where d.familia in ('factura_venta','nc_venta','nd_venta')
),
enriq as (
  select
    b.*,
    regexp_replace(coalesce(b.contraparte_cuit,''), '\D', '', 'g') as cuit_norm,
    public.canon_cod(b.contraparte_codigo) as cod_canon,
    case when b.familia = 'nc_venta' then -1 else 1 end as signo,
    exc.dias  as exc_dias,
    exc.dto   as exc_dto,
    exc.escalon as exc_escalon,
    dc.dias   as cond_dias
  from base b
  left join lateral (
    select e.dias, e.dto, e.escalon
    from public.cobranzas_excepciones e
    where e.deudor_id = regexp_replace(coalesce(b.contraparte_cuit,''), '\D', '', 'g')
      and (e.empresa is null or e.empresa = b.empresa)
      and b.fecha >= e.vigente_desde
      and (e.vigente_hasta is null or b.fecha <= e.vigente_hasta)
    order by e.creado_at desc
    limit 1
  ) exc on true
  left join public.deudores_condiciones dc on dc.condicion_venta = b.condicion_venta
),
resuelto as (
  select
    e.*,
    -- deudor_id: CUIT si tiene 11 dígitos (siempre, verificado); si no, fallback
    -- empresa|código canónico para no perder la fila.
    case when length(e.cuit_norm) = 11 then e.cuit_norm
         else e.empresa || '|' || e.cod_canon end as deudor_id,
    coalesce(e.exc_dias, e.cond_dias) as dias_plazo,
    (e.exc_dias is not null) as tiene_excepcion
  from enriq e
)
select
  r.empresa, r.familia, r.id as documento_id, r.comprobante_id, r.cae, r.storage_path,
  r.deudor_id, r.cuit_norm as cuit, r.contraparte_nombre as razon_social,
  r.cod_canon as cod_cliente,
  r.fecha, r.condicion_venta, r.tiene_excepcion,
  r.signo * r.total as importe,
  0::numeric as cobrado,          -- fase 1: deuda bruta. Se llena cuando isis_lk.comprobantes_aplicados tenga datos.
  r.signo * r.total as saldo,     -- saldo = importe - cobrado
  coalesce(r.vto_factura, r.fecha + r.dias_plazo) as vence,
  (r.vto_factura is null and r.dias_plazo is not null) as plazo_estimado,
  (r.dias_plazo is null) as sin_plazo,
  case when r.dias_plazo is null then null
       else (current_date - coalesce(r.vto_factura, r.fecha + r.dias_plazo))
  end as dias_vencido,
  case
    when r.dias_plazo is null then 'sin_plazo'
    when (current_date - coalesce(r.vto_factura, r.fecha + r.dias_plazo)) < 0 then 'por_vencer'
    when (current_date - coalesce(r.vto_factura, r.fecha + r.dias_plazo)) <= 30 then '1_30'
    when (current_date - coalesce(r.vto_factura, r.fecha + r.dias_plazo)) <= 60 then '31_60'
    when (current_date - coalesce(r.vto_factura, r.fecha + r.dias_plazo)) <= 90 then '61_90'
    else 'mas_90'
  end as tramo,
  -- Próximo escalón de descuento vigente (o el que fija la excepción): el
  -- primero, contando desde la fecha de factura, que todavía no venció.
  -- OJO: un solo LATERAL autocontenido con su propio LIMIT 1 (una versión
  -- previa con dos LATERAL separados multiplicaba hasta 6x las filas —
  -- 235.638 contra 39.273 esperadas, detectado y corregido antes de publicar).
  esc.escalon as escalon_vigente, esc.label as escalon_label,
  esc.dto as escalon_dto, (r.fecha + esc.dias) as escalon_vence
from resuelto r
left join lateral (
  select ce.escalon, ce.label,
         coalesce(r.exc_dto, ce.dto) as dto,
         case when r.tiene_excepcion and ce.escalon = r.exc_escalon then r.exc_dias else ce.dias end as dias
  from public.cobranzas_escalones ce
  where (not r.tiene_excepcion or ce.escalon = r.exc_escalon)
    and (r.fecha + (case when r.tiene_excepcion and ce.escalon = r.exc_escalon then r.exc_dias else ce.dias end)) >= current_date
  order by (case when r.tiene_excepcion and ce.escalon = r.exc_escalon then r.exc_dias else ce.dias end) asc
  limit 1
) esc on true;

revoke all on public.vista_deudores_documentos from anon, authenticated;

-- ── 5. RPC de pantalla ───────────────────────────────────────────────────────
-- p_desde por defecto = últimos 12 meses: sumar TODO desde 2019 sin cobros
-- restados da un "saldo" de miles de millones que no significa nada (una
-- factura pagada hace años sigue sumando). Es la fase 1: bruto de un período
-- razonable, no la deuda desde el origen.
create or replace function public.deudores_resumen(
  p_empresa text default null,
  p_desde   date default (current_date - interval '12 months')::date,
  p_q       text default null,
  p_tramo   text default null,
  p_limit   int  default 50,
  p_offset  int  default 0
)
returns table (
  deudor_id text, cod_cliente text, razon_social text, empresas text[],
  saldo numeric, cant_documentos int,
  por_vencer numeric, tramo_1_30 numeric, tramo_31_60 numeric, tramo_61_90 numeric, tramo_mas_90 numeric, sin_plazo numeric,
  ultima_factura date,
  escalon_vigente text, escalon_label text, escalon_vence date, escalon_dto numeric,
  total_count bigint
)
language sql security definer set search_path = public
as $$
  with base as (
    select *
    from public.vista_deudores_documentos
    where (p_empresa is null or empresa = p_empresa)
      and (p_desde is null or fecha >= p_desde)
  ),
  agg as (
    select
      deudor_id,
      max(cod_cliente) filter (where empresa = 'lk')   as cod_cliente_lk,
      max(cod_cliente) filter (where empresa = 'chef') as cod_cliente_chef,
      (array_agg(razon_social order by fecha desc))[1] as razon_social,
      array_agg(distinct empresa)                      as empresas,
      sum(saldo)                                        as saldo,
      count(*)                                          as cant_documentos,
      sum(saldo) filter (where tramo = 'por_vencer')    as por_vencer,
      sum(saldo) filter (where tramo = '1_30')          as tramo_1_30,
      sum(saldo) filter (where tramo = '31_60')         as tramo_31_60,
      sum(saldo) filter (where tramo = '61_90')         as tramo_61_90,
      sum(saldo) filter (where tramo = 'mas_90')        as tramo_mas_90,
      sum(saldo) filter (where tramo = 'sin_plazo')     as sin_plazo,
      max(fecha) filter (where familia = 'factura_venta') as ultima_factura
    from base
    group by deudor_id
  ),
  prox as (
    select distinct on (deudor_id)
      deudor_id, escalon_vigente, escalon_label, escalon_vence, escalon_dto
    from base
    where escalon_vence is not null and escalon_vence >= current_date
    order by deudor_id, escalon_vence asc
  )
  select
    a.deudor_id,
    coalesce(a.cod_cliente_lk, a.cod_cliente_chef),
    a.razon_social, a.empresas,
    a.saldo, a.cant_documentos::int,
    coalesce(a.por_vencer,0), coalesce(a.tramo_1_30,0), coalesce(a.tramo_31_60,0),
    coalesce(a.tramo_61_90,0), coalesce(a.tramo_mas_90,0), coalesce(a.sin_plazo,0),
    a.ultima_factura,
    p.escalon_vigente, p.escalon_label, p.escalon_vence, p.escalon_dto,
    count(*) over ()::bigint
  from agg a
  left join prox p on p.deudor_id = a.deudor_id
  where (p_q is null or p_q = ''
         or a.razon_social ilike '%'||p_q||'%' or a.deudor_id ilike '%'||p_q||'%'
         or a.cod_cliente_lk ilike '%'||p_q||'%' or a.cod_cliente_chef ilike '%'||p_q||'%')
    and (p_tramo is null or p_tramo = '' or
         (p_tramo = 'por_vencer' and coalesce(a.por_vencer,0) <> 0) or
         (p_tramo = '1_30'       and coalesce(a.tramo_1_30,0) <> 0) or
         (p_tramo = '31_60'      and coalesce(a.tramo_31_60,0) <> 0) or
         (p_tramo = '61_90'      and coalesce(a.tramo_61_90,0) <> 0) or
         (p_tramo = 'mas_90'     and coalesce(a.tramo_mas_90,0) <> 0) or
         (p_tramo = 'sin_plazo'  and coalesce(a.sin_plazo,0) <> 0))
  order by a.saldo desc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0)
$$;
grant execute on function public.deudores_resumen(text, date, text, text, int, int) to anon, authenticated;

-- deudores_detalle: comprobantes de un deudor, sin ventana (el detalle sí
-- muestra todo el historial). Incluye storage_path para poder abrir el PDF
-- (bucket privado — hoy no hay UI para eso, pendiente signed URL).
create or replace function public.deudores_detalle(p_deudor_id text)
returns table (
  empresa text, familia text, documento_id bigint, comprobante_id text, cae text, storage_path text,
  fecha date, condicion_venta text, tiene_excepcion boolean,
  importe numeric, saldo numeric,
  vence date, plazo_estimado boolean, sin_plazo boolean, dias_vencido int, tramo text,
  escalon_vigente text, escalon_label text, escalon_dto numeric, escalon_vence date
)
language sql security definer set search_path = public
as $$
  select empresa, familia, documento_id, comprobante_id, cae, storage_path,
         fecha, condicion_venta, tiene_excepcion,
         importe, saldo, vence, plazo_estimado, sin_plazo, dias_vencido, tramo,
         escalon_vigente, escalon_label, escalon_dto, escalon_vence
  from public.vista_deudores_documentos
  where deudor_id = p_deudor_id
  order by fecha desc
$$;
grant execute on function public.deudores_detalle(text) to anon, authenticated;
