-- v22.96 · Cobranzas: pagos que no pasan por el banco (efectivo, cheque físico) los carga Vivi, y la deducción comercial
-- de cada súper (del parseo de sus OC) entra en la cuenta corriente (Thomas, 26/09).
--
-- 1) GV_Cobranza_Pago_Manual: un pago cargado a mano (efectivo / cheque / otro) con su nº de recibo de ISIS. Entra a la
--    vista gv_conciliacion_bancaria como banco 'manual' (tipo 'ingreso'), así lo ven SOLOS los recibos, el agente, la
--    deuda viva, la cuenta y el control. Anular = anulado_en (no se borra). Escribe sólo gv_cobranza_pago_manual_cargar /
--    _anular (supervisor).
-- 2) GV_Cobranza_Super_Deduccion (ver migración gv_cobranza_super_deduccion_v2296): un peso que paga el súper cancela
--    1 / (1 − deducción) de factura. Se aplica en la cuenta (fila "Deducción súper"), el control de saldos, la deuda viva
--    y el agente (condición NN FF: el dto posible es la deducción, no 0).
--
-- Rollback: volver gv_conciliacion_bancaria a 4 uniones (sql/gv_conciliacion_bancaria_v2287.sql), drop table
--           "GV_Cobranza_Pago_Manual", "GV_Cobranza_Super_Deduccion"; volver gv_cobranza_cuenta / _control_saldos a v2295.
create table if not exists public."GV_Cobranza_Pago_Manual" (
  id bigserial primary key, empresa text not null check (empresa in ('lk','chef')), cod_cliente text not null,
  fecha date not null, monto numeric not null check (monto > 0), medio text not null check (medio in ('efectivo','cheque','otro')),
  nro_recibo text, nota text, cargado_por text, cargado_en timestamptz not null default now(),
  anulado_en timestamptz, anulado_por text);
alter table public."GV_Cobranza_Pago_Manual" enable row level security;
drop policy if exists sup_lee on public."GV_Cobranza_Pago_Manual";
create policy sup_lee on public."GV_Cobranza_Pago_Manual" for select to authenticated using (public.es_supervisor_virgilio());
revoke all on public."GV_Cobranza_Pago_Manual" from anon;
revoke insert, update, delete, truncate on public."GV_Cobranza_Pago_Manual" from authenticated;
grant select on public."GV_Cobranza_Pago_Manual" to authenticated;

create or replace function public.gv_cobranza_pago_manual_cargar(p_emp text, p_cod text, p_fecha date, p_monto numeric,
  p_medio text, p_recibo text default null, p_nota text default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if not public.es_supervisor_virgilio() then raise exception 'solo supervisor'; end if;
  if p_emp not in ('lk','chef') then raise exception 'empresa lk o chef'; end if;
  if coalesce(p_monto, 0) <= 0 then raise exception 'el monto tiene que ser mayor a 0'; end if;
  if p_fecha is null or p_fecha > current_date + 180 then raise exception 'fecha inválida'; end if;
  if nullif(btrim(p_recibo), '') is not null and btrim(p_recibo) !~ '^\d+$' then raise exception 'el recibo va sólo con números'; end if;
  insert into "GV_Cobranza_Pago_Manual" (empresa, cod_cliente, fecha, monto, medio, nro_recibo, nota, cargado_por)
  values (p_emp, regexp_replace(btrim(p_cod), '^0+', ''), p_fecha, round(p_monto, 2), coalesce(p_medio, 'efectivo'),
          nullif(btrim(p_recibo), ''), nullif(btrim(p_nota), ''), coalesce(auth.jwt() ->> 'email', 'supervisor'))
  returning id into v_id;
  return v_id;
end $$;
create or replace function public.gv_cobranza_pago_manual_anular(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.es_supervisor_virgilio() then raise exception 'solo supervisor'; end if;
  update "GV_Cobranza_Pago_Manual" set anulado_en = now(), anulado_por = coalesce(auth.jwt() ->> 'email', 'supervisor')
   where id = p_id and anulado_en is null;
end $$;
revoke all on function public.gv_cobranza_pago_manual_cargar(text,text,date,numeric,text,text,text), public.gv_cobranza_pago_manual_anular(bigint) from public, anon;
grant execute on function public.gv_cobranza_pago_manual_cargar(text,text,date,numeric,text,text,text), public.gv_cobranza_pago_manual_anular(bigint) to authenticated;

create or replace view public.gv_conciliacion_bancaria with (security_invoker = true) as
 SELECT 'credicoop'::text AS banco, 'lk'::text AS empresa, t.id, t.anio, t.fila, t.fecha, t.operacion, t.entrada, t.salida, t.saldo,
        t.detalle, t.det, t.nro_op, t.nro_recibo, t.cod_cliente, t.observacion, t.estado_echeq, t.estado_isis, t.nota, t.tipo, t.carga_id, t.cargado_en
   FROM "GV_Conc_Credicoop_LK" t
UNION ALL
 SELECT 'santander'::text, 'lk'::text, t.id, t.anio, t.fila, t.fecha, t.operacion, t.entrada, t.salida, t.saldo,
        t.detalle, t.det, t.nro_op, t.nro_recibo, t.cod_cliente, t.observacion, t.estado_echeq, t.estado_isis, t.nota, t.tipo, t.carga_id, t.cargado_en
   FROM "GV_Conc_Santander_LK" t
UNION ALL
 SELECT 'credicoop'::text, 'chef'::text, t.id, t.anio, t.fila, t.fecha, t.operacion, t.entrada, t.salida, t.saldo,
        t.detalle, t.det, t.nro_op, t.nro_recibo, t.cod_cliente, t.observacion, t.estado_echeq, t.estado_isis, t.nota, t.tipo, t.carga_id, t.cargado_en
   FROM "GV_Conc_Credicoop_CH" t
UNION ALL
 SELECT 'santander'::text, 'chef'::text, t.id, t.anio, t.fila, t.fecha, t.operacion, t.entrada, t.salida, t.saldo,
        t.detalle, t.det, t.nro_op, t.nro_recibo, t.cod_cliente, t.observacion, t.estado_echeq, t.estado_isis, t.nota, t.tipo, t.carga_id, t.cargado_en
   FROM "GV_Conc_Santander_CH" t
UNION ALL
 -- v22.96: pagos cargados a mano por Cobranzas (efectivo / cheque físico)
 SELECT 'manual'::text, m.empresa, m.id, extract(year from m.fecha)::int, null::int, m.fecha, initcap(m.medio), m.monto::numeric(18,2), 0::numeric(18,2), null::numeric(18,2),
        coalesce(m.nota, 'Cargado a mano'), 'M', null::text, m.nro_recibo, m.cod_cliente, 'Cargado por ' || coalesce(m.cargado_por, '?'),
        null::text, null::text, null::text, 'ingreso'::text, null::bigint, m.cargado_en
   FROM "GV_Cobranza_Pago_Manual" m
  WHERE m.anulado_en IS NULL;

-- ── aplicado además (sobre la definición viva, con replace idempotente) ──
-- GV_Cobranza_Super_Deduccion (migración gv_cobranza_super_deduccion_v2296): 12 cadenas; Alberdi en 0 (medido: paga 98,5 %).
-- gv_cobranza_control_saldos: pago = Σ entrada / (1 − pct) · tolerancia 2 % de f12/12.
-- gv_cobranza_cuenta: fila 'Deducción súper' = entrada × pct / (1 − pct) por cada pago del súper.
-- gv_cobranza_deuda_viva_refrescar: el recibo del súper cancela pagado / (1 − pct).
-- gv_cobranza_imputar: v_sdp = deducción del cliente; condición sin_dto → dtos = [greatest(dc, v_sdp)]; a_reclamar = 0.
