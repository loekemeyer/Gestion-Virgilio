-- v22.93 · Agente de cobranzas — pantalla en Cobranzas + aviso diario por Telegram (Thomas, 26/09)
--
-- DOS PARTES:
--   A) el motor de imputación recibo↔pedido vive en sql/gv_cobranza_imputar_v2291.sql (v22.92).
--   B) NUEVO (v22.93): las RPC que lee la pantalla, la tabla de avisados y el aviso diario.
--
-- Rollback de B:
--   select cron.unschedule('gv-cobranza-aviso');
--   drop function if exists public.gv_cobranza_aviso_telegram(), public.gv_cobranza_aviso_texto(),
--        public.gv_cobranza_aviso_nuevos(), public.gv_cobranza_agente_resumen(),
--        public.gv_cobranza_agente_cliente(text,text), public.gv_cobranza_cliente_cuit(text),
--        public.gv_cobranza_bancos(text,text,text,date,date,text,int,int), public.gv_cobranza_bancos_cargas();
--   drop table if exists public."GV_Cobranza_Avisadas";
--   delete from public."GV_Reglas_Centinela" where version = 'v22.93';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- A) EL MOTOR: sql/gv_cobranza_imputar_v2291.sql (v22.92, misma sesión anterior, que siguió viva y lo
--    commiteó 20 min después de que esta sesión lo recuperara de la base). Ahí están gv_cobranza_imputar,
--    gv_cobranza_recibos, GV_Cobranza_Imputacion (+ Meta), gv_cobranza_imputacion_refrescar y el cron 103.
--    Acá NO se repite nada de eso.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- B) NUEVO v22.93
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ─── B.1 · RPC de la pantalla (SECURITY DEFINER + chequeo de supervisor adentro, patrón v22.91) ──

-- Resumen por cliente (lo que dibuja la solapa 🕵 Agente) + cuándo se calculó.
create or replace function public.gv_cobranza_agente_resumen()
returns table (empresa text, cod_cliente text, cliente text, pedidos_mal bigint, pedidos_imputados bigint,
               pedidos_atrasados bigint, dias_prom numeric, dias_max int, atraso_max int, ret_cliente numeric,
               a_reclamar numeric, recibos_sin_imputar bigint, pedidos_sin_recibo bigint,
               desde date, hasta date, calculado_en timestamptz)
language sql stable security definer set search_path = public as $$
  select m.empresa, m.cod_cliente, m.cliente, m.pedidos_mal, m.pedidos_imputados, m.pedidos_atrasados,
         m.dias_prom, m.dias_max, m.atraso_max, m.ret_cliente, m.a_reclamar, m.recibos_sin_imputar,
         m.pedidos_sin_recibo, m.desde, m.hasta, m.calculado_en
    from public.gv_cobranza_pago_mal m
   where (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
   order by coalesce(m.a_reclamar, 0) desc, m.pedidos_atrasados desc, m.cliente;
$$;

-- El detalle de UN cliente: cada recibo con el pedido que pagó, o suelto.
create or replace function public.gv_cobranza_agente_cliente(p_empresa text, p_cod text)
returns setof public.gv_cobranza_imputacion
language sql stable security definer set search_path = public as $$
  select i.* from public.gv_cobranza_imputacion i
   where (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
     and i.empresa = p_empresa and i.cod_cliente = p_cod
   order by coalesce(i.pedido, i.fecha_pago) desc, i.grupo desc nulls last, i.fecha_pago desc;
$$;

-- Lo mismo por CUIT (la pantalla Deuda a cobrar identifica al cliente por CUIT, no por código).
-- Un CUIT puede ser cliente en las dos empresas con dos códigos: salen los dos.
create or replace function public.gv_cobranza_cliente_cuit(p_cuit text)
returns setof public.gv_cobranza_imputacion
language sql stable security definer set search_path = public as $$
  with cli as (
    select distinct 'lk'::text emp, regexp_replace(coalesce(contraparte_codigo,''),'^0+','') cod
      from isis_lk.documentos
     where fecha >= current_date - 450 and regexp_replace(coalesce(contraparte_cuit,''),'\D','','g') = regexp_replace(coalesce(p_cuit,''),'\D','','g')
    union
    select distinct 'chef', regexp_replace(coalesce(contraparte_codigo,''),'^0+','')
      from isis_ch.documentos
     where fecha >= current_date - 450 and regexp_replace(coalesce(contraparte_cuit,''),'\D','','g') = regexp_replace(coalesce(p_cuit,''),'\D','','g'))
  select i.* from public.gv_cobranza_imputacion i join cli on cli.emp = i.empresa and cli.cod = i.cod_cliente
   where (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
   order by coalesce(i.pedido, i.fecha_pago) desc, i.grupo desc nulls last, i.fecha_pago desc;
$$;

-- La conciliación bancaria (los 4 Excel) paginada y filtrada para la solapa 🏦 Bancos.
-- 35.579 filas al 26/09: NUNCA se lee entera desde el navegador (regla v20.45: PostgREST corta en 1.000).
create or replace function public.gv_cobranza_bancos(p_banco text default null, p_empresa text default null,
                                                     p_q text default null, p_desde date default null,
                                                     p_hasta date default null, p_tipo text default null,
                                                     p_limit int default 300, p_offset int default 0)
returns table (banco text, empresa text, anio int, fila int, fecha date, operacion text, entrada numeric,
               salida numeric, saldo numeric, detalle text, det text, nro_op text, nro_recibo text,
               cod_cliente text, observacion text, estado_echeq text, estado_isis text, nota text,
               tipo text, total_count bigint, suma_entrada numeric, suma_salida numeric)
language sql stable security definer set search_path = public as $$
  with f as (
    select c.* from public.gv_conciliacion_bancaria c
     where (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
       and (p_banco   is null or p_banco   = '' or c.banco = p_banco)
       and (p_empresa is null or p_empresa = '' or c.empresa = p_empresa)
       and (p_tipo    is null or p_tipo    = '' or c.tipo = p_tipo)
       and (p_desde   is null or c.fecha >= p_desde)
       and (p_hasta   is null or c.fecha <= p_hasta)
       and (p_q is null or btrim(p_q) = ''
            or c.cod_cliente = btrim(p_q) or c.nro_recibo = btrim(p_q) or c.nro_op = btrim(p_q)
            or c.detalle ilike '%' || btrim(p_q) || '%' or c.observacion ilike '%' || btrim(p_q) || '%'
            or c.nota ilike '%' || btrim(p_q) || '%'))
  select f.banco, f.empresa, f.anio, f.fila, f.fecha, f.operacion, f.entrada, f.salida, f.saldo, f.detalle, f.det,
         f.nro_op, f.nro_recibo, f.cod_cliente, f.observacion, f.estado_echeq, f.estado_isis, f.nota, f.tipo,
         count(*) over () as total_count,
         sum(f.entrada) over () as suma_entrada,
         sum(f.salida)  over () as suma_salida
    from f
   order by f.fecha desc, f.anio desc, f.fila desc
   limit greatest(coalesce(p_limit, 300), 1) offset greatest(coalesce(p_offset, 0), 0);
$$;

-- Última carga de cada banco (para que la pantalla diga hasta cuándo está al día el Excel).
create or replace function public.gv_cobranza_bancos_cargas()
returns table (banco text, anio int, movimientos int, cargado_en timestamptz, archivo text, ultima_fecha date)
language sql stable security definer set search_path = public as $$
  with u as (
    select distinct on (g.banco) g.banco, g.anio, g.filas as movimientos, g.cargado_en, g.archivo
      from public."GV_Conc_Cargas" g order by g.banco, g.cargado_en desc),
  ult as (
    select c.banco || '_' || case c.empresa when 'lk' then 'lk' else 'ch' end k, max(c.fecha) filter (where c.tipo <> 'proyeccion' and c.fecha <= current_date + 1) f
      from public.gv_conciliacion_bancaria c group by 1)
  select u.banco, u.anio, u.movimientos, u.cargado_en, u.archivo, ult.f
    from u left join ult on ult.k = u.banco
   where (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
   order by u.banco;
$$;

revoke all on function public.gv_cobranza_agente_resumen(), public.gv_cobranza_agente_cliente(text,text),
  public.gv_cobranza_cliente_cuit(text), public.gv_cobranza_bancos(text,text,text,date,date,text,int,int),
  public.gv_cobranza_bancos_cargas() from public, anon;
grant execute on function public.gv_cobranza_agente_resumen(), public.gv_cobranza_agente_cliente(text,text),
  public.gv_cobranza_cliente_cuit(text), public.gv_cobranza_bancos(text,text,text,date,date,text,int,int),
  public.gv_cobranza_bancos_cargas() to authenticated, service_role;

-- las vistas nacieron con grants de escritura a authenticated (default de CREATE VIEW); no escriben nada
-- (la tabla de abajo no tiene INSERT para nadie), pero se cierran igual.
revoke insert, update, delete, truncate on public.gv_cobranza_imputacion, public.gv_cobranza_pago_mal from authenticated;

-- ─── B.2 · Aviso diario por Telegram: lo NUEVO que el agente detectó ─────────────────────────────
-- Un pedido se avisa UNA sola vez (misma idea que GV_Cruce_Avisadas): la clave es el tramo imputado
-- (empresa, cliente, recibo, pedido). Si se recalcula y el tramo cambia (otro recibo), vuelve a avisar,
-- porque es otra conclusión.

create table if not exists public."GV_Cobranza_Avisadas" (
  empresa      text not null,
  cod_cliente  text not null,
  recibo       text not null,
  pedido       date not null,
  facturas     text,
  a_reclamar   numeric,
  atraso       int,
  avisado_at   timestamptz not null default now(),
  primary key (empresa, cod_cliente, recibo, pedido)
);
alter table public."GV_Cobranza_Avisadas" enable row level security;
revoke all on public."GV_Cobranza_Avisadas" from anon, authenticated;
grant select on public."GV_Cobranza_Avisadas" to authenticated;
drop policy if exists sup_lee on public."GV_Cobranza_Avisadas";
create policy sup_lee on public."GV_Cobranza_Avisadas" for select using (public.es_supervisor_virgilio());

-- lo detectado que todavía no se avisó (tramos imputados con reclamo o con atraso)
create or replace function public.gv_cobranza_aviso_nuevos()
returns table (empresa text, cod_cliente text, nombre text, recibo text, pedido date, facturas text,
               fecha_pago date, dias int, plazo int, atraso int, dto_tomado numeric, dto_ganado numeric,
               a_reclamar numeric, calidad text)
language sql stable security definer set search_path = public as $$
  select i.empresa, i.cod_cliente, i.nombre, i.recibo, i.pedido, i.facturas, i.fecha_pago, i.dias, i.plazo,
         i.atraso, i.dto_tomado, i.dto_ganado, i.a_reclamar, i.calidad
    from public."GV_Cobranza_Imputacion" i
   where (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
     and i.grupo is not null and i.recibo is not null and i.pedido is not null
     and (coalesce(i.a_reclamar, 0) > 0 or coalesce(i.atraso, 0) > 0)
     and not exists (select 1 from public."GV_Cobranza_Avisadas" a
                      where a.empresa = i.empresa and a.cod_cliente = i.cod_cliente
                        and a.recibo = i.recibo and a.pedido = i.pedido)
   order by coalesce(i.a_reclamar, 0) desc, coalesce(i.atraso, 0) desc;
$$;

-- el texto del aviso (NULL si no hay nada nuevo). Separado para poder PROBARLO sin mandar nada.
create or replace function public.gv_cobranza_aviso_texto()
returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_n int; v_cli int; v_suma numeric; v_atraso_solo int; v_lineas text := ''; v_i int := 0; r record;
begin
  select count(*), count(distinct (empresa, cod_cliente)), coalesce(sum(a_reclamar), 0),
         count(*) filter (where coalesce(a_reclamar, 0) = 0)
    into v_n, v_cli, v_suma, v_atraso_solo
    from public.gv_cobranza_aviso_nuevos();
  if coalesce(v_n, 0) = 0 then return null; end if;

  for r in select * from public.gv_cobranza_aviso_nuevos() limit 12 loop
    v_i := v_i + 1;
    v_lineas := v_lineas || E'\n' ||
      '• ' || coalesce(left(r.nombre, 26), '') || ' (' || upper(left(r.empresa, 2)) || ' ' || r.cod_cliente || ')' ||
      ' · pedido ' || to_char(r.pedido, 'DD/MM') || ' · pagó ' || to_char(r.fecha_pago, 'DD/MM') ||
      ' (' || r.dias || ' d, tomó ' || round(coalesce(r.dto_tomado, 0) * 100) || ' %)' ||
      case when coalesce(r.a_reclamar, 0) > 0
           then ' · a reclamar $ ' || replace(to_char(r.a_reclamar, 'FM999G999G999G990'), ',', '.')
           else ' · atraso ' || r.atraso || ' d' end;
  end loop;

  return '🕵 AGENTE DE COBRANZAS · ' || to_char(v_hoy, 'DD/MM') || E'\n' ||
    'Pagos fuera del plazo del descuento que tomó el cliente, nuevos desde el último aviso: ' ||
    v_n || ' pedido(s) de ' || v_cli || ' cliente(s) · a reclamar $ ' || replace(to_char(v_suma, 'FM999G999G999G990'), ',', '.') ||
    case when v_atraso_solo > 0 then ' (' || v_atraso_solo || ' con atraso pero sin reclamo)' else '' end ||
    v_lineas ||
    case when v_n > 12 then E'\n… y ' || (v_n - 12) || ' más' else '' end ||
    E'\n\nDetalle en Cobranzas → 🕵 Agente. Cada pedido se avisa una sola vez.';
end $$;

create or replace function public.gv_cobranza_aviso_telegram()
returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_txt text; v_n int;
begin
  if not public.gv_es_dia_habil(v_hoy) then return 0; end if;
  v_txt := public.gv_cobranza_aviso_texto();
  if v_txt is null then return 0; end if;
  perform public.tg_enqueue(v_txt, 'gv_cobranza_aviso_' || v_hoy::text);
  insert into public."GV_Cobranza_Avisadas" (empresa, cod_cliente, recibo, pedido, facturas, a_reclamar, atraso)
  select n.empresa, n.cod_cliente, n.recibo, n.pedido, n.facturas, n.a_reclamar, n.atraso
    from public.gv_cobranza_aviso_nuevos() n
  on conflict do nothing;
  get diagnostics v_n = row_count;
  perform public.tg_outbox_flush();
  return v_n;
end $$;

revoke all on function public.gv_cobranza_aviso_nuevos(), public.gv_cobranza_aviso_texto(),
  public.gv_cobranza_aviso_telegram() from public, anon;
grant execute on function public.gv_cobranza_aviso_nuevos(), public.gv_cobranza_aviso_texto() to authenticated, service_role;
grant execute on function public.gv_cobranza_aviso_telegram() to service_role;

-- lun-vie 08:45 ART (11:45 UTC), después de que el cron 103 (:49) haya recalculado con la carga de la mañana
select cron.schedule('gv-cobranza-aviso', '45 11 * * 1-5', 'select public.gv_cobranza_aviso_telegram();');

-- ─── B.3 · centinelas ────────────────────────────────────────────────────────────────────────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values
 ('gv_cobranza_imputacion_refrescar', 'funcion', 'gv_cobranza_imputar\(cli\.emp, cli\.cod\)',
  'El refresco de la imputación recorre TODOS los clientes con gv_cobranza_imputar (recibo↔pedido); sin esto el agente se queda con la foto vieja', 'Thomas', 'v22.93'),
 ('gv_cobranza_aviso_telegram', 'funcion', 'GV_Cobranza_Avisadas',
  'Cada pedido detectado se avisa UNA sola vez: el aviso escribe en GV_Cobranza_Avisadas', 'Thomas', 'v22.93')
on conflict do nothing;
