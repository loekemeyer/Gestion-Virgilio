-- ══════════════════════════════════════════════════════════════════════════
-- Movimientos bancarios (extracto) — v12.33 (2026-09-02)
-- ══════════════════════════════════════════════════════════════════════════
-- Primer paso hacia el objetivo real: cobros que se acreditan solos contra
-- Deudores, cruzando por CUIT. Hoy (2026-09-02) el acceso a la API de
-- Interbanking está pedido y no llegó — mientras tanto, el mismo objeto que va
-- a llenar la API en el futuro lo llena a mano un supervisor subiendo el
-- .xlsx que exporta Interbanking (Consultas → Extracto de cuenta → Excel).
-- Cuando la API esté lista, sólo hay que agregar el import automático (mismo
-- shape de fila, columna `origen`='api' en vez de 'manual') — nada de lo de
-- abajo cambia.
--
-- Formato real verificado (Santander Río vía Interbanking, extracto de
-- Tierra Nativa SA, 2026-09-01): cabecera de metadata (cuenta, denominación,
-- fechas, saldo inicial) + tabla con columnas Concepto/Cod.Op. | Fecha |
-- Comprobante | Sucursal | Importe (con signo) | Descripción | Cod.Op.Bco. |
-- CUIT | Denominación | Saldo. El CUIT SOLO viene poblado en los movimientos
-- de Concepto 'CREDITOS' (transferencias recibidas) — todo lo demás
-- (impuestos, comisiones, extracciones) lo trae vacío. Por eso el cruce
-- contra deudores sólo mira CREDITOS con CUIT: el resto es ruido bancario
-- que se guarda para trazabilidad pero no se cruza con nada.
--
-- Verificado con datos reales del extracto de Tierra Nativa: el CUIT
-- 30710305362 matcheó con un cliente REAL de Loekemeyer (cód. 3878, mismo
-- nombre) — confirma que el cruce por CUIT funciona de punta a punta. Como
-- esos movimientos eran transferencias entre cuentas propias de Tierra
-- Nativa (no un cobro real), quedan como ejemplo de por qué existe el botón
-- "Ignorar": aplicar algo que no es un cobro real deja al cliente con saldo
-- negativo (probado: -$2.500.000 en el rollback de prueba).
--
-- Objetos:
--   banco_movimientos                — un movimiento = una fila (interna, REVOKE anon).
--   banco_movimientos_importar(...)  — alta en lote desde el Excel, RPC (supervisor).
--   banco_movimientos_pendientes(...) — CREDITOS con CUIT sin aplicar, RPC (EXECUTE anon).
--   banco_movimiento_aplicar(...)    — acredita el cobro al deudor, RPC (supervisor).
--   banco_movimiento_ignorar(...)    — descarta uno (transferencia propia, etc.), RPC (supervisor).
--
-- Gate de escritura: es_supervisor_virgilio() (definida en sql/deudores.sql,
-- no se redefine acá) — mismo patrón que deuda_cobros/facturable_anticipado_
-- reservas desde v12.32.
-- ══════════════════════════════════════════════════════════════════════════

create table public.banco_movimientos (
  id             bigint generated always as identity primary key,
  cuenta         text not null,             -- tal cual el extracto (ej. "058-0-005714/3")
  banco          text,                      -- 'Santander Rio', etc. — informativo
  fecha          date not null,
  concepto       text not null,             -- 'CREDITOS','DEBITOS','IVA', etc. (Concepto/Cod.Op.)
  comprobante    text not null default '',  -- '' si el extracto lo trae vacío (normalizado para el dedupe)
  sucursal       text,
  importe        numeric not null,          -- con signo: negativo = débito, positivo = crédito
  descripcion    text,
  cod_op_bco     text,
  cuit           text,                      -- crudo, como viene (casi siempre vacío salvo CREDITOS)
  cuit_norm      text generated always as (nullif(regexp_replace(coalesce(cuit,''), '\D', '', 'g'), '')) stored,
  denominacion   text,
  saldo          numeric,                   -- el banco no lo repite en cada fila, puede venir null
  origen         text not null default 'manual',  -- 'manual' (Excel a mano) | 'api' (Interbanking, futuro)
  archivo_nombre text,
  importado_por  text,
  importado_at   timestamptz not null default now(),
  aplicado_a_cobro_id bigint references public.deuda_cobros(id),
  ignorado_at    timestamptz,
  ignorado_por   text,
  ignorado_motivo text
);
comment on table public.banco_movimientos is
  'Movimientos del extracto bancario. Hoy se cargan a mano (Excel de '
  'Interbanking, botón Importar); el día que llegue el acceso a la API de '
  'Interbanking esto se llena solo (origen=''api''), sin tocar el resto del '
  'módulo. Sólo importan para Deudores los CREDITOS con cuit_norm no nulo — '
  'el resto (impuestos, comisiones, extracciones) es ruido bancario que se '
  'guarda para trazabilidad pero no se cruza con nada.';

alter table public.banco_movimientos enable row level security;
revoke all on public.banco_movimientos from anon, authenticated;

-- Dedupe: re-subir un período superpuesto no duplica filas. comprobante=''
-- normalizado (no null) para que el índice único funcione — Postgres trata
-- NULL como distinto siempre, lo que rompería el dedupe en las filas sin
-- comprobante (la mayoría).
create unique index banco_movimientos_dedupe_idx on public.banco_movimientos
  (cuenta, fecha, concepto, comprobante, importe, coalesce(descripcion, ''), coalesce(cod_op_bco, ''));

create index banco_movimientos_cuit_idx on public.banco_movimientos (cuit_norm)
  where cuit_norm is not null and aplicado_a_cobro_id is null and ignorado_at is null;

-- Alta en lote desde el Excel (front ya lo parseó y limpió: fecha ISO,
-- importe numérico). ON CONFLICT DO NOTHING contra el índice de dedupe.
create function public.banco_movimientos_importar(
  p_cuenta text, p_banco text, p_filas jsonb, p_archivo_nombre text default null, p_creado_por text default null
)
returns table (insertados int, duplicados int)
language plpgsql security definer set search_path = public
as $$
declare
  v_total int; v_ins int;
begin
  if not public.es_supervisor_virgilio() then
    raise exception 'No autorizado: se requiere sesión de supervisor.';
  end if;
  if p_cuenta is null or p_cuenta = '' then
    raise exception 'falta la cuenta';
  end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then
    raise exception 'p_filas debe ser un array jsonb';
  end if;

  select count(*) into v_total from jsonb_array_elements(p_filas);

  with datos as (
    select
      p_cuenta as cuenta, p_banco as banco,
      (f->>'fecha')::date as fecha,
      trim(f->>'concepto') as concepto,
      coalesce(nullif(trim(f->>'comprobante'), ''), '') as comprobante,
      nullif(trim(f->>'sucursal'), '') as sucursal,
      (f->>'importe')::numeric as importe,
      nullif(trim(f->>'descripcion'), '') as descripcion,
      nullif(trim(f->>'cod_op_bco'), '') as cod_op_bco,
      nullif(trim(f->>'cuit'), '') as cuit,
      nullif(trim(f->>'denominacion'), '') as denominacion,
      nullif(f->>'saldo','')::numeric as saldo,
      'manual'::text as origen, p_archivo_nombre as archivo_nombre, p_creado_por as importado_por
    from jsonb_array_elements(p_filas) f
  )
  insert into public.banco_movimientos
    (cuenta, banco, fecha, concepto, comprobante, sucursal, importe, descripcion, cod_op_bco, cuit, denominacion, saldo, origen, archivo_nombre, importado_por)
  select cuenta, banco, fecha, concepto, comprobante, sucursal, importe, descripcion, cod_op_bco, cuit, denominacion, saldo, origen, archivo_nombre, importado_por
  from datos
  on conflict (cuenta, fecha, concepto, comprobante, importe, coalesce(descripcion,''), coalesce(cod_op_bco,'')) do nothing;

  get diagnostics v_ins = row_count;
  return query select v_ins, (v_total - v_ins);
end;
$$;
grant execute on function public.banco_movimientos_importar(text, text, jsonb, text, text) to anon, authenticated;

-- Lista lo pendiente de revisar: CREDITOS con CUIT, sin aplicar ni ignorar
-- todavía, con el deudor que matchea (si existe) al frente.
create function public.banco_movimientos_pendientes(
  p_q text default null, p_limit int default 100, p_offset int default 0
)
returns table (
  id bigint, cuenta text, banco text, fecha date, comprobante text, importe numeric,
  descripcion text, cuit text, cuit_norm text, denominacion text,
  deudor_id text, deudor_razon_social text, deudor_saldo numeric,
  total_count bigint
)
language sql security definer set search_path = public
as $$
  with cand as (
    select bm.*
    from public.banco_movimientos bm
    where bm.concepto = 'CREDITOS'
      and bm.cuit_norm is not null
      and bm.aplicado_a_cobro_id is null
      and bm.ignorado_at is null
  ),
  deu as (
    select deudor_id, max(razon_social) as razon_social, sum(saldo) as saldo
    from public.vista_deudores_documentos
    group by deudor_id
  )
  select c.id, c.cuenta, c.banco, c.fecha, c.comprobante, c.importe, c.descripcion,
         c.cuit, c.cuit_norm, c.denominacion,
         d.deudor_id, d.razon_social, d.saldo,
         count(*) over ()::bigint
  from cand c
  left join deu d on d.deudor_id = c.cuit_norm
  where (p_q is null or p_q = ''
         or c.denominacion ilike '%'||p_q||'%' or c.cuit ilike '%'||p_q||'%'
         or d.razon_social ilike '%'||p_q||'%')
  order by (d.deudor_id is null), c.fecha desc
  limit greatest(p_limit,1) offset greatest(p_offset,0)
$$;
grant execute on function public.banco_movimientos_pendientes(text, int, int) to anon, authenticated;

-- Acredita el movimiento como cobro (deuda_cobros) y marca el movimiento como
-- aplicado para que no se pueda volver a usar dos veces. p_documento_id es
-- opcional desde el diseño original (v12.33); a partir de v12.34 el front lo
-- usa de verdad: al "Aplicar" un movimiento, si el deudor tiene facturas
-- abiertas ofrece elegir a cuál imputarlo (mejor precisión de tramo) — sin
-- elegir ninguna, sigue siendo un cobro general como antes.
create function public.banco_movimiento_aplicar(
  p_movimiento_id bigint, p_empresa text default null, p_documento_id bigint default null, p_creado_por text default null
)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_mov record;
  v_cobro_id bigint;
begin
  if not public.es_supervisor_virgilio() then
    raise exception 'No autorizado: se requiere sesión de supervisor.';
  end if;

  select * into v_mov from public.banco_movimientos where id = p_movimiento_id;
  if v_mov is null then
    raise exception 'Movimiento % no existe', p_movimiento_id;
  end if;
  if v_mov.aplicado_a_cobro_id is not null then
    raise exception 'Ese movimiento ya se aplicó (cobro %)', v_mov.aplicado_a_cobro_id;
  end if;
  if v_mov.cuit_norm is null then
    raise exception 'Ese movimiento no tiene CUIT, no se puede aplicar a un deudor';
  end if;

  insert into public.deuda_cobros (deudor_id, empresa, documento_id, monto, fecha, medio, nota, creado_por)
  values (v_mov.cuit_norm, p_empresa, p_documento_id, v_mov.importe, v_mov.fecha, 'transferencia',
          'Extracto bancario: ' || coalesce(v_mov.descripcion,'') || ' (mov #' || v_mov.id || ')', p_creado_por)
  returning id into v_cobro_id;

  update public.banco_movimientos set aplicado_a_cobro_id = v_cobro_id where id = p_movimiento_id;

  return v_cobro_id;
end;
$$;
grant execute on function public.banco_movimiento_aplicar(bigint, text, bigint, text) to anon, authenticated;

-- Descarta un movimiento sin aplicarlo (ej. transferencia entre cuentas
-- propias, como los dos "TRANSF RECIBIDA MISMO TIT" del extracto de prueba).
create function public.banco_movimiento_ignorar(p_movimiento_id bigint, p_motivo text default null, p_por text default null)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.es_supervisor_virgilio() then
    raise exception 'No autorizado: se requiere sesión de supervisor.';
  end if;
  update public.banco_movimientos
  set ignorado_at = now(), ignorado_por = p_por, ignorado_motivo = p_motivo
  where id = p_movimiento_id and aplicado_a_cobro_id is null and ignorado_at is null;
end;
$$;
grant execute on function public.banco_movimiento_ignorar(bigint, text, text) to anon, authenticated;
