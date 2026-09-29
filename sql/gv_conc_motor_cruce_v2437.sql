-- v24.37 — MOTOR DE CONCILIACION BANCARIA: carga de extractos por dia + cruce + preguntas al humano
--
-- Luis (29/09): "el modulo deberia resolver automaticamente todo lo que pueda con la carga de los
-- extractos de movimientos por dia y consultarle al humano por las cosas que no puede cuadrar.
-- quiero un buen motor de cruce en este, esmerate".
--
-- ============================================================================================
-- COMO DECIDE, en orden (cada paso medido contra lo que la persona ya concilio a mano)
-- ============================================================================================
--  1. REGLA (GV_Conc_Regla + gv_conc_parse): operacion y codigo del Manual N 39 para el 100 % de
--     los movimientos (189/189 Credicoop LK, 203/203 Santander Chef).
--  2. CUIT del extracto -> codigo del cliente EN LA EMPRESA DE LA CUENTA (la cuenta define la
--     empresa, Luis 29/09). Santander Chef, septiembre: 24 de 27 igual que la persona; las otras 3
--     son pagos de terceros o de otra empresa del grupo -> van a pregunta.
--  3. APAREO CONTRA LA PLANILLA: el Manual pide proyectar los cheques (A DEPOSITAR), transferencias,
--     sueldos y cargas sociales ANTES de que el banco los muestre. Un movimiento del extracto con el
--     MISMO importe y sentido que una fila de la planilla (ventana -150/+10 dias) toma de ahi el
--     cliente/proveedor, el Nro OP y el recibo. Asignacion 1 a 1, por cercania de fecha.
--     Importes de cheques unicos en 90 dias: Santander Chef 126/140, Credicoop LK 637/1019.
--  4. CRUCE POR IMPORTE contra facturas IMPAGAS (gv_conc_candidatos_importe) y contra facturas
--     pagadas en varias entradas junto con los otros cobros del cliente en la semana
--     (gv_conc_candidatos_complemento). Backtest, 120 depositos identificados de Chef (jun-sep):
--     cliente correcto en 1er lugar 57/120; cuando el motor se juega (score < 0,0025 y 0,003 de
--     ventaja sobre el siguiente cliente) acierta 27 de 28. => eso sale como PROPUESTO (un click),
--     nunca automatico.
--  5. Lo demas -> PREGUNTA, con los candidatos y el telefono de cada uno (gv_cliente_nuevo_wpp_lote).
--
-- ESTADOS de GV_Conc_Mov:  auto · propuesto · pregunta · confirmado · no_identificado
--   auto        el motor lo resolvio con certeza (CUIT, apareo unico, gastos/impuestos/sueldos)
--   propuesto   cruce por importe con ventaja clara: se confirma con un click
--   pregunta    no cuadra solo: lo resuelve una persona
--   confirmado  lo resolvio o confirmo una persona (gv_conc_resolver)
--   no_identificado  una persona decidio que queda como "No Identificado" (det 1 del Manual)
--
-- Nro de recibo: lo genera ISIS (Luis). El motor NO lo inventa; solo lo copia si la fila apareada
-- de la planilla ya lo tiene.

-- ---------------------------------------------------------------- tablas
create table if not exists public."GV_Conc_Carga_Extracto" (
  id bigserial primary key,
  banco text not null, empresa text not null, cuenta text, archivo text,
  movimientos int, nuevos int, cargado_por text, cargado_en timestamptz not null default now()
);
alter table public."GV_Conc_Carga_Extracto" enable row level security;
revoke all on public."GV_Conc_Carga_Extracto" from anon, authenticated;

create table if not exists public."GV_Conc_Mov" (
  id bigserial primary key,
  banco text not null, empresa text not null, cuenta text,
  fecha date not null, concepto text not null, codop text, sucursal text, referencia text,
  debito numeric not null default 0, credito numeric not null default 0, saldo numeric,
  huella text not null unique,
  carga_id bigint references public."GV_Conc_Carga_Extracto"(id),
  -- lo que decide el motor
  operacion text, det text, es_cobranza boolean, cuit text, nombre_banco text, cbu text,
  cod_cliente text, detalle text, nro_op text, nro_recibo text, cancela text,
  metodo text, confianza numeric, candidatos jsonb, alerta text, proy_key text,
  estado text not null default 'nuevo'
    check (estado in ('nuevo','auto','propuesto','pregunta','confirmado','no_identificado')),
  resuelto_en timestamptz,
  -- lo que decide una persona
  confirmado_por text, confirmado_en timestamptz, nota text,
  creado_en timestamptz not null default now()
);
create index if not exists gv_conc_mov_cuenta_fecha on public."GV_Conc_Mov" (banco, empresa, fecha);
create index if not exists gv_conc_mov_estado on public."GV_Conc_Mov" (estado);
create unique index if not exists gv_conc_mov_proy on public."GV_Conc_Mov" (proy_key) where proy_key is not null;
alter table public."GV_Conc_Mov" enable row level security;
revoke all on public."GV_Conc_Mov" from anon, authenticated;

-- ---------------------------------------------------------------- carga del extracto (idempotente)
-- p_movs: [{"fecha":"2026-09-28","concepto":"...","codop":"1874","sucursal":"...","referencia":"80009",
--           "debito":0,"credito":472524.71,"saldo":42560851.62}, ...]
-- La HUELLA evita duplicar cuando dos extractos se pisan (el de ayer y el de hoy repiten dias, y
-- Santander trae el mismo movimiento en "Movimientos del Dia" y en "Ultimos Movimientos"). En
-- Santander la referencia es unica por movimiento y el saldo del bloque del dia viene vacio, asi que
-- el saldo NO entra en su huella; en Credicoop si (varios gastos del dia comparten concepto e importe).
create or replace function public.gv_conc_extracto_cargar(p_banco text, p_empresa text, p_cuenta text,
                                                          p_archivo text, p_movs jsonb)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $fn$
declare v_carga bigint; v_ids bigint[]; v_n int; v_b text := lower(btrim(p_banco)); v_e text := lower(btrim(p_empresa));
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then raise exception 'sin permiso'; end if;
  if v_b not in ('credicoop','santander') or v_e not in ('lk','chef') then raise exception 'cuenta desconocida: % %', p_banco, p_empresa; end if;
  v_n := jsonb_array_length(coalesce(p_movs,'[]'::jsonb));
  insert into public."GV_Conc_Carga_Extracto" (banco, empresa, cuenta, archivo, movimientos, cargado_por)
  values (v_b, v_e, p_cuenta, p_archivo, v_n, coalesce(auth.jwt()->>'email', current_user)) returning id into v_carga;
  with ins as (
    insert into public."GV_Conc_Mov" (banco, empresa, cuenta, fecha, concepto, codop, sucursal, referencia,
                                      debito, credito, saldo, huella, carga_id)
    select v_b, v_e, p_cuenta, (x->>'fecha')::date, btrim(regexp_replace(x->>'concepto','\s+',' ','g')),
           nullif(btrim(x->>'codop'),''), nullif(btrim(x->>'sucursal'),''), nullif(btrim(x->>'referencia'),''),
           abs(coalesce((x->>'debito')::numeric,0)), abs(coalesce((x->>'credito')::numeric,0)), (x->>'saldo')::numeric,
           md5(concat_ws('|', v_b, v_e, x->>'fecha', coalesce(nullif(btrim(x->>'referencia'),''),''),
                         abs(coalesce((x->>'debito')::numeric,0))::text, abs(coalesce((x->>'credito')::numeric,0))::text,
                         btrim(regexp_replace(x->>'concepto','\s+',' ','g')),
                         case when v_b = 'credicoop' then coalesce((x->>'saldo')::numeric::text,'') else '' end)),
           v_carga
      from jsonb_array_elements(coalesce(p_movs,'[]'::jsonb)) x
     where nullif(x->>'fecha','') is not null
    on conflict (huella) do nothing
    returning id)
  select array_agg(id order by id) into v_ids from ins;
  update public."GV_Conc_Carga_Extracto" set nuevos = coalesce(array_length(v_ids,1),0) where id = v_carga;
  return jsonb_build_object('carga_id', v_carga, 'movimientos', v_n, 'nuevos', coalesce(array_length(v_ids,1),0),
                            'ids', coalesce(to_jsonb(v_ids),'[]'::jsonb));
end $fn$;
revoke all on function public.gv_conc_extracto_cargar(text,text,text,text,jsonb) from public;
grant execute on function public.gv_conc_extracto_cargar(text,text,text,text,jsonb) to anon, authenticated, service_role;

-- ---------------------------------------------------------------- la linea amarilla
-- La macro del Excel saltea la fila "Conciliacion al" y deja un HUECO en fila. La ultima fila conciliada es
-- la ultima antes de un hueco que no sea proyeccion ni A Depositar (esas quedan debajo aunque tengan fecha vieja).
create or replace view public.gv_conc_linea with (security_invoker = true) as
with a as (select banco, empresa, max(anio) anio from public.gv_conciliacion_bancaria group by 1,2),
f as (select g.banco, g.empresa, g.anio, g.fila, g.fecha, g.operacion, g.saldo,
             lead(g.fila) over (partition by g.banco, g.empresa, g.anio order by g.fila) nx
        from public.gv_conciliacion_bancaria g join a using (banco, empresa, anio))
select distinct on (banco, empresa) banco, empresa, anio, fila, fecha as conciliado_al, saldo
  from f
 where nx - fila > 1 and fecha is not null and coalesce(operacion,'') !~* '^(a depositar|proyecc)'
 order by banco, empresa, fila desc;
revoke all on public.gv_conc_linea from anon, authenticated;

-- ---------------------------------------------------------------- el motor
-- Se llama con los ids de un lote (de a 15-20 desde la pantalla: el rol authenticated corta a los 8 s).
-- Reprocesa todo lo que no haya confirmado una persona.
create or replace function public.gv_conc_motor(p_ids bigint[])
returns table(estado text, n bigint)
language plpgsql volatile security definer set search_path to 'public' as $fn$
declare
  m record; p record; j jsonb; ap jsonb; v_cod text; v_cli text; v_est text; v_cand jsonb; v_top jsonb;
  v_sc1 numeric; v_sc2 numeric; v_vec jsonb; v_canc text; v_ciego boolean; v_prov text;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then raise exception 'sin permiso'; end if;

  -- 0) lo que no confirmo una persona se recalcula desde cero
  update public."GV_Conc_Mov" x set operacion = null, det = null, es_cobranza = null, cuit = null, nombre_banco = null,
         cbu = null, cod_cliente = null, detalle = null, nro_op = null, nro_recibo = null, cancela = null, metodo = null,
         confianza = null, candidatos = null, alerta = null, proy_key = null, estado = 'nuevo', resuelto_en = null
   where x.id = any(p_ids) and x.estado not in ('confirmado','no_identificado');

  -- 1) REGLA: operacion + codigo del Manual + CUIT/nombre/CBU del concepto
  for m in select * from public."GV_Conc_Mov" x where x.id = any(p_ids) and x.estado = 'nuevo' loop
    j := public.gv_conc_parse(m.banco, m.concepto, m.debito, m.credito, m.codop);
    update public."GV_Conc_Mov" set operacion = j->>'operacion', det = coalesce(j->>'det','?'),
           es_cobranza = coalesce((j->>'es_cobranza')::boolean,false), cuit = j->>'cuit',
           nombre_banco = j->>'nombre', cbu = j->>'cbu',
           alerta = case when j->>'propio' is not null
                         then 'vino de ' || (j->>'propio') || ' (empresa del grupo): cobro por cuenta de un cliente' end
     where id = m.id;
  end loop;

  -- 2) APAREO 1 a 1 contra la planilla: mismo importe y sentido, -150/+10 dias, por cercania de fecha
  -- La LINEA AMARILLA (gv_conc_linea) parte la planilla: arriba lo conciliado, abajo lo proyectado.
  --   * movimiento de un dia que la persona YA concilio -> se aparea con la fila conciliada (+-3 dias):
  --     es la respuesta de la persona, y el motor la toma.
  --   * movimiento posterior a la linea -> SOLO contra lo proyectado. Contra lo conciliado no: esa fila
  --     ya es de otro movimiento del banco (gastos fijos, cuotas y transferencias repiten importe).
  --   gv.conc_ciego = '1' (solo para medir) ignora lo conciliado y mide el motor sin la respuesta.
  create temp table if not exists _cbz_par (mov_id bigint, pkey text, dist int, cod text, det_pl text,
                                            nro_op text, nro_rec text, op text, conciliada boolean) on commit drop;
  delete from _cbz_par;
  v_ciego := coalesce(current_setting('gv.conc_ciego', true), '') = '1';
  insert into _cbz_par
  with lin as (select * from public.gv_conc_linea)
  select mv.id, g.banco || '|' || g.empresa || '|' || g.anio || '|' || g.fila, abs(mv.fecha - g.fecha),
         nullif(regexp_replace(coalesce(g.cod_cliente,''),'^0+',''),''), g.detalle, g.nro_op, g.nro_recibo, g.operacion,
         (l.anio is not null and (g.anio, g.fila) <= (l.anio, l.fila))
    from public."GV_Conc_Mov" mv
    left join lin l on l.banco = mv.banco and l.empresa = mv.empresa
    join public.gv_conciliacion_bancaria g
      on g.banco = mv.banco and g.empresa = mv.empresa
     and ((mv.credito > 0 and g.entrada = mv.credito) or (mv.debito > 0 and g.salida = mv.debito))
     and g.fecha between mv.fecha - 150 and mv.fecha + 10
   where mv.id = any(p_ids) and mv.estado = 'nuevo'
     and ( (not v_ciego and l.anio is not null and mv.fecha <= l.conciliado_al
            and (g.anio, g.fila) <= (l.anio, l.fila) and abs(mv.fecha - g.fecha) <= 3)
        or ((v_ciego or l.anio is null or mv.fecha > l.conciliado_al)
            and (l.anio is null or (g.anio, g.fila) > (l.anio, l.fila))) )
     and not exists (select 1 from public."GV_Conc_Mov" o
                      where o.proy_key = g.banco || '|' || g.empresa || '|' || g.anio || '|' || g.fila and o.id <> mv.id);
  for p in select * from _cbz_par order by dist, mov_id loop
    continue when exists (select 1 from public."GV_Conc_Mov" x where x.id = p.mov_id and x.proy_key is not null);
    continue when exists (select 1 from public."GV_Conc_Mov" x where x.proy_key = p.pkey);
    update public."GV_Conc_Mov" set proy_key = p.pkey,
           candidatos = jsonb_build_object('apareo', jsonb_build_object(
             'cod', p.cod, 'detalle', p.det_pl, 'nro_op', p.nro_op, 'recibo', p.nro_rec, 'operacion', p.op, 'dias', p.dist,
             'conciliada', p.conciliada,
             'otros_clientes', (select count(distinct q.cod) from _cbz_par q where q.mov_id = p.mov_id and q.cod is distinct from p.cod)))
     where id = p.mov_id;
  end loop;

  -- 3) DECISION (todo menos el cruce por importe)
  for m in select * from public."GV_Conc_Mov" x where x.id = any(p_ids) and x.estado = 'nuevo' order by x.fecha, x.id loop
    ap := m.candidatos->'apareo';
    if m.credito > 0 and m.es_cobranza then
      v_cod := null; v_cli := null; v_est := null;
      if m.cuit is not null and m.alerta is null then
        select c.cod_cliente, c.cliente, c.estado into v_cod, v_cli, v_est
          from public.gv_conc_cliente_por_cuit(m.cuit, m.empresa) c limit 1;
      end if;
      if v_cod is not null then
        -- que factura cancela: la que el cruce por importe encuentra DENTRO de ese cliente
        select x.facturas into v_canc from public.gv_conc_candidatos_importe(m.empresa, m.fecha, m.credito, 1, m.banco, v_cod) x
         where x.score < 0.004;
        update public."GV_Conc_Mov" set estado = 'auto', metodo = 'cuit', confianza = 1, cod_cliente = v_cod,
               detalle = v_cli, cancela = v_canc, det = case when det = '3' then '3' else 'D' end,
               nro_op = ap->>'nro_op', nro_recibo = ap->>'recibo',
               alerta = case when ap is not null and ap->>'cod' is not null and ap->>'cod' <> v_cod
                             then 'la planilla tenia ese importe proyectado para el cliente ' || (ap->>'cod') end,
               resuelto_en = now()
         where id = m.id;
      elsif ap is not null and ap->>'cod' is not null and m.alerta is null then
        update public."GV_Conc_Mov" set
               estado = case when (ap->>'otros_clientes')::int = 0 then 'auto' else 'propuesto' end,
               metodo = case when (ap->>'conciliada')::boolean then 'conciliado' else 'planilla' end,
               confianza = case when (ap->>'otros_clientes')::int = 0 then 0.97 else 0.7 end,
               cod_cliente = ap->>'cod', detalle = ap->>'detalle', nro_op = ap->>'nro_op', nro_recibo = ap->>'recibo',
               det = case when det = '3' or ap->>'operacion' ilike 'a depositar%' then '3' else 'D' end,
               alerta = case when (ap->>'otros_clientes')::int > 0
                             then 'el mismo importe estaba proyectado para ' || ((ap->>'otros_clientes')::int + 1) || ' clientes' end,
               resuelto_en = now()
         where id = m.id;
      end if;   -- el resto sigue al paso 4
    elsif m.credito > 0 then
      update public."GV_Conc_Mov" set estado = case when operacion is null then 'pregunta' else 'auto' end,
             metodo = 'regla', confianza = 1, detalle = coalesce(ap->>'detalle', nombre_banco, operacion),
             alerta = case when operacion is null then 'entrada sin regla: no se que es' end, resuelto_en = now()
       where id = m.id;
    else
      update public."GV_Conc_Mov" set estado = case when operacion is null then 'pregunta' else 'auto' end,
             metodo = case when ap is null then 'regla' when (ap->>'conciliada')::boolean then 'conciliado' else 'planilla' end, confianza = 1,
             cod_cliente = ap->>'cod', detalle = coalesce(ap->>'detalle', nombre_banco, operacion), nro_op = ap->>'nro_op',
             alerta = case when operacion is null then 'salida sin regla: no se que es'
                           when operacion in ('Transf','Sueldos') and ap is null
                           then 'no estaba proyectada en la planilla (el Manual pide proyectar transferencias y sueldos)' end,
             resuelto_en = now()
       where id = m.id;
    end if;
  end loop;

  -- 4) CRUCE POR IMPORTE para los cobros que siguen sin cliente
  for m in select * from public."GV_Conc_Mov" x where x.id = any(p_ids) and x.estado = 'nuevo' and x.credito > 0 order by x.fecha, x.id loop
    select jsonb_agg(jsonb_build_object('cod_cliente', o.cod_cliente, 'importe', o.credito, 'fecha', o.fecha)) into v_vec
      from public."GV_Conc_Mov" o
     where o.empresa = m.empresa and o.id <> m.id and o.credito > 0 and o.cod_cliente is not null
       and o.estado in ('auto','propuesto','confirmado') and o.fecha between m.fecha - 7 and m.fecha + 3;
    select jsonb_agg(z order by (z->>'score')::numeric) into v_cand from (
      select distinct on (z->>'cod') z from (
        select jsonb_build_object('cod', x.cod_cliente, 'cliente', x.cliente, 'facturas', x.facturas, 'dias', x.dias,
                                  'lista', x.lista, 'dto', x.dto, 'retencion', x.retencion, 'score', x.score,
                                  'via', 'importe', 'tipo', x.tipo) z
          from public.gv_conc_candidatos_importe(m.empresa, m.fecha, m.credito, 5, m.banco) x
        union all
        select jsonb_build_object('cod', y.cod_cliente, 'cliente', y.cliente, 'facturas', y.facturas, 'dias', y.dias,
                                  'lista', y.lista, 'dto', y.dto, 'retencion', y.retencion, 'score', y.score,
                                  'via', 'junto', 'junto_con', y.junto_con, 'total', y.total_cruzado)
          from public.gv_conc_candidatos_complemento(m.empresa, m.fecha, m.credito, v_vec, m.banco, 3) y) u
       order by z->>'cod', (z->>'score')::numeric) d;
    -- la SUCURSAL del deposito es pista: un efectivo en Rosario es de un cliente de Santa Fe
    -- (medido: los 2 efectivos del 25/09 que la persona dejo "No identificado" -> Sarali, Santa Fe,
    -- en Rosario; Elbantonio, Cordoba, en Rio Cuarto). Mismo lugar: -0,0015 · otro lugar: +0,004.
    v_prov := public.gv_conc_sucursal_provincia(coalesce(m.sucursal, substring(m.concepto from '[Ff]ilial:\s*[0-9]*-?\s*(.*)$')));  -- Credicoop la trae en el concepto
    if v_prov is not null and v_cand is not null then
      select jsonb_agg(c2 order by (c2->>'score')::numeric) into v_cand from (
        select c || jsonb_build_object('provincia', to_jsonb(pv.provs),
                 'geo', case when pv.provs is null then 'sin dato' when v_prov = any(pv.provs) then 'misma' else 'otra' end,
                 'score', round(greatest(0, (c->>'score')::numeric
                            + case when pv.provs is null then 0 when v_prov = any(pv.provs) then -0.0015 else 0.004 end), 5)) c2
          from jsonb_array_elements(v_cand) c
          left join lateral (select array_agg(distinct d.provincia) provs from public."GV_Clientes_Direcciones" d
                              where d.empresa = m.empresa and d.cod = c->>'cod' and d.provincia is not null) pv on true) q;
    end if;
    v_top := v_cand->0; v_sc1 := (v_top->>'score')::numeric; v_sc2 := (v_cand->1->>'score')::numeric;
    if v_top is not null and v_sc1 < 0.0025 and coalesce(v_sc2, 1) - v_sc1 > 0.003 and m.alerta is null then
      update public."GV_Conc_Mov" set estado = 'propuesto', metodo = 'importe', confianza = round(1 - v_sc1 * 10, 3),
             cod_cliente = v_top->>'cod', detalle = v_top->>'cliente', cancela = v_top->>'facturas',
             det = case when det = '3' then '3' else 'D' end,
             candidatos = coalesce(candidatos,'{}'::jsonb) || jsonb_build_object('lista', v_cand),
             alerta = case when m.cuit is not null then 'el CUIT ' || m.cuit || ' no tiene codigo en ' || upper(m.empresa)
                                                        || ': lo propongo por importe' end,
             resuelto_en = now()
       where id = m.id;
    else
      update public."GV_Conc_Mov" set estado = 'pregunta', metodo = null, det = case when det = '3' then '3' else '1' end,
             candidatos = coalesce(candidatos,'{}'::jsonb) || jsonb_build_object('lista', coalesce((
               select jsonb_agg(e) from (select e from jsonb_array_elements(coalesce(v_cand,'[]'::jsonb)) e limit 3) q),'[]'::jsonb)),
             alerta = coalesce(m.alerta,
                        case when m.cuit is not null then 'el CUIT ' || m.cuit || ' no tiene codigo en ' || upper(m.empresa) || ': paga un tercero o falta el alta'
                             when m.det = '3' then 'cheque que no estaba proyectado como A DEPOSITAR'
                             when v_cand is null then 'sin CUIT y ningun importe de factura impaga lo explica'
                             else 'sin CUIT: hay candidatos pero ninguno con ventaja clara' end),
             resuelto_en = now()
       where id = m.id;
    end if;
  end loop;

  return query select x.estado, count(*) from public."GV_Conc_Mov" x where x.id = any(p_ids) group by 1 order by 1;
end $fn$;
revoke all on function public.gv_conc_motor(bigint[]) from public;
grant execute on function public.gv_conc_motor(bigint[]) to anon, authenticated, service_role;

-- ---------------------------------------------------------------- lo que ve y decide la persona
-- Lista de una cuenta entre dos fechas. Devuelve UN jsonb (no filas): un mes de Santander son ~200
-- movimientos y PostgREST corta en 1.000 filas sin avisar.
create or replace function public.gv_conc_movs(p_banco text, p_empresa text, p_desde date, p_hasta date)
returns jsonb language sql stable security definer set search_path to 'public' as $fn$
  select case when not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then null else
  coalesce((select jsonb_agg(to_jsonb(x) - 'huella' order by x.fecha, x.id) from public."GV_Conc_Mov" x
             where x.banco = lower(p_banco) and x.empresa = lower(p_empresa)
               and x.fecha between p_desde and p_hasta), '[]'::jsonb) end
$fn$;
revoke all on function public.gv_conc_movs(text,text,date,date) from public;
grant execute on function public.gv_conc_movs(text,text,date,date) to anon, authenticated, service_role;

-- Resolver un movimiento a mano.
--   p_cod con valor  -> confirmado para ese cliente (el nombre sale del padron de ESA empresa)
--   p_cod null       -> no_identificado (det 1 del Manual)
--   p_recordar       -> el CUIT que pago queda atado a ese cliente (GV_Conc_Alias_Pagador): la proxima vez
--                       el motor lo resuelve solo. Lo decide la persona en pantalla, nunca el motor.
create or replace function public.gv_conc_resolver(p_id bigint, p_cod text, p_nota text default null,
                                                   p_recordar boolean default false)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $fn$
declare m public."GV_Conc_Mov"; v_cod text := nullif(regexp_replace(btrim(coalesce(p_cod,'')),'^0+',''),''); v_cli text;
  v_quien text := coalesce(auth.jwt()->>'email', current_user); v_alias boolean := false;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then raise exception 'sin permiso'; end if;
  select * into m from public."GV_Conc_Mov" where id = p_id for update;
  if not found then raise exception 'movimiento % no existe', p_id; end if;
  if v_cod is not null then
    select d.razon_social into v_cli from public."GV_Clientes_Direcciones" d
     where d.empresa = m.empresa and d.cod = v_cod and d.razon_social is not null limit 1;
    if v_cli is null then raise exception 'el cliente % no existe en %', v_cod, upper(m.empresa); end if;
  end if;
  update public."GV_Conc_Mov" set
         estado = case when v_cod is null then 'no_identificado' else 'confirmado' end,
         cod_cliente = v_cod, detalle = case when v_cod is null then 'No Identificado' else v_cli end,
         det = case when v_cod is null then (case when det = '3' then '3' else '1' end)
                    when det in ('1','?') or det is null then 'D' else det end,
         metodo = coalesce(metodo, 'persona'), confirmado_por = v_quien, confirmado_en = now(),
         nota = coalesce(nullif(btrim(p_nota),''), nota)
   where id = p_id;
  if p_recordar and v_cod is not null and m.cuit is not null
     and not exists (select 1 from public."GV_Conc_Alias_Pagador" a where a.empresa = m.empresa and a.cuit_pagador = m.cuit) then
    insert into public."GV_Conc_Alias_Pagador" (empresa, cuit_pagador, cod_cliente, nota, cargado_por)
    values (m.empresa, m.cuit, v_cod, coalesce(nullif(btrim(p_nota),''), 'confirmado en conciliacion: ' || coalesce(m.nombre_banco,'')), v_quien);
    v_alias := true;
  end if;
  return jsonb_build_object('id', p_id, 'estado', case when v_cod is null then 'no_identificado' else 'confirmado' end,
                            'cliente', v_cli, 'alias', v_alias);
end $fn$;
revoke all on function public.gv_conc_resolver(bigint,text,text,boolean) from public;
grant execute on function public.gv_conc_resolver(bigint,text,text,boolean) to anon, authenticated, service_role;

-- Confirmar de un click lo que el motor propuso (y lo auto, si la persona quiere cerrarlo todo).
create or replace function public.gv_conc_confirmar(p_ids bigint[])
returns int language plpgsql volatile security definer set search_path to 'public' as $fn$
declare n int;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then raise exception 'sin permiso'; end if;
  update public."GV_Conc_Mov" set estado = 'confirmado', confirmado_por = coalesce(auth.jwt()->>'email', current_user),
         confirmado_en = now()
   where id = any(p_ids) and estado in ('auto','propuesto') and (credito = 0 or cod_cliente is not null or not es_cobranza);
  get diagnostics n = row_count;
  return n;
end $fn$;
revoke all on function public.gv_conc_confirmar(bigint[]) from public;
grant execute on function public.gv_conc_confirmar(bigint[]) to anon, authenticated, service_role;
