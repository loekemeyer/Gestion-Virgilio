-- v22.91 · Agente de cobranzas: IMPUTACIÓN recibo ↔ facturas (Thomas, 26/09: "tenés que aprender cómo
-- analizar la conciliación bancaria contra las facturas, para que sepas quién pagó bien").
--
-- EL MÉTODO, en el orden en que se aplica:
--   1. El COBRO es el RECIBO, no el movimiento del banco. La conciliación anota el nº de recibo de ISIS en
--      cada ingreso; un recibo puede ser varios depósitos o e-cheques en días distintos (LK: 592 de 2.742
--      recibos tienen más de un movimiento; 406 caen en más de un día). Se suma todo lo del recibo.
--      Fecha de pago = fecha del último cobro del recibo (el e-cheque cuenta cuando se cobra: Thomas).
--   2. La FACTURA sale a precio de LISTA y el cliente descuenta al pagar el % de su condición
--      ("Pago Contado -25%" → paga el 75 %). Las NC del mismo pedido se descuentan con el MISMO %.
--   3. Qué facturas están PAGADAS lo dice la DEUDA (el Excel de Cuarentena, GV_Cuarentena_Deuda_Detalle):
--      lo que no figura ahí está pagado; si figura con pendiente parcial, se pagó la diferencia.
--   4. Las facturas se agrupan por DÍA (un pedido = las facturas de ese día). Los recibos van en ORDEN
--      (por número de recibo, que es el orden en que ISIS los emitió) y los pedidos en orden de fecha:
--      el cliente paga lo más viejo primero. La imputación es la ALINEACIÓN de las dos secuencias que
--      cuesta menos (programación dinámica): cada tramo junta 1 a 3 recibos con 1 a 3 pedidos y 0 a 2
--      NC/ND, y tiene que cumplir  pagado ≈ (lista − NC) × (1 − dto)  con residuo entre −1,2 % y +5 %.
--      Un recibo puede quedar 'sin imputar' (pago a cuenta, cheque rechazado repuesto) y un pedido
--      'pagada sin recibo' (efectivo sin identificar): cada salto cuesta 3,5 %. Cada pieza de más
--      (2.º recibo, 2.º pedido, NC) cuesta 0,8 %; usar un dto distinto al de la condición, 3 %.
--   5. La RETENCIÓN del cliente se aprende de sus propios pagos: en una primera pasada se miran los pares
--      recibo↔pedido simples y, si más de la mitad cae en el mismo residuo (mediana ± 0,5 %), ése es su
--      `ret_cliente` (Torres y Liva: 2,2 %). En la alineación un residuo igual a la retención del
--      cliente cuesta lo mismo que un residuo cero. Sin ese prior, la búsqueda prefería sumar NC viejas
--      para llegar a 0,0 % antes que aceptar el 2,2 % que el cliente se descuenta en TODOS sus pagos.
--   6. Con la imputación hecha: días = fecha de pago − fecha de factura; tramo real (14 días o la coronita
--      del cliente en cobranzas_excepciones → 25 %, ≤30 → 20 %, ≤45 → 15 %, ≤60 → 10 %, más → 0 %);
--      a reclamar = lista × (dto que se tomó − dto que ganó), si es positivo.
--   7. Cliente muy grande (recibos × pedidos × NC > 150.000 estados): las NC se netean contra el pedido
--      anterior más cercano y la alineación va sin la dimensión NC. Es el fallback, y lo dice `calidad`.
--   8. La CONDICIÓN de la factura decide qué descuentos puede haber tomado el cliente:
--        · escalón ("Pago Contado -25%", "Pago 15 a 30 dias -20%"…): se prueba el de la condición primero
--          y los otros escalones con castigo (3 %). Plazo = 14 (o coronita) / 30 / 45 / 60 / 90 / 120.
--        · "NN FF" (súper: Coto 90 FF, Cencosud 107 FF) e IMPORTADOR / FOB / A vista: SIN descuento,
--          sólo dto 0. Lo que falte es retención o deducción del súper. Plazo = NN. a_reclamar = 0.
--        · "Sin Cotizador" / "Prefiero no decidir ahora" / "Contado" a secas: el cliente no eligió;
--          cualquier escalón vale sin castigo y se reclama contra el tramo real.
--      `atraso` = días − plazo (si es positivo, pagó tarde), para los que no tienen descuento que reclamar.
--   9. Quedan afuera los clientes internos (LK 411 = Chef SRL · Chef 1434 = Loekemeyer Hnos).
--
-- Objetos:
--   gv_cobranza_recibos(emp, cod)         — los recibos del cliente, sumados (vista)
--   gv_cobranza_imputar(emp, cod, desde)  — la imputación del cliente, una fila por pedido (o por recibo suelto)
--   gv_cobranza_imputacion                — la misma para todos los clientes con facturas en 450 días (vista)
--   gv_cobranza_pago_mal                  — resumen por cliente (reemplaza a la v22.89, que deducía FIFO)
--
-- Rollback: drop view gv_cobranza_pago_mal, gv_cobranza_imputacion, gv_cobranza_recibos;
--           drop function gv_cobranza_imputar(text,text,date); (la v22.89 queda en gv_cobranza_facturas_pago)

create or replace view public.gv_cobranza_recibos with (security_invoker = true) as
select empresa, cod_cliente, nro_recibo as recibo,
       max(fecha) as fecha_pago, min(fecha) as fecha_primer_cobro,
       sum(entrada) as pagado, count(*) as movimientos,
       case when bool_and(tipo = 'a_depositar') then 'e-cheque'
            when bool_or(tipo = 'a_depositar') then 'mixto'
            when bool_and(operacion ~* 'transf') then 'transferencia'
            when bool_and(detalle ~* 'no identificado') then 'efectivo'
            else 'deposito' end as medio,
       min(case when estado_echeq ~ '\d{1,2}/\d{1,2}' then
             to_date(substring(estado_echeq from '(\d{1,2}/\d{1,2})') || '/' || extract(year from fecha)::text, 'DD/MM/YYYY') end) as echeq_entregado,
       string_agg(distinct banco, '+') as banco,
       bool_or(observacion ~* 'rechaz') as cheque_rechazado
  from public.gv_conciliacion_bancaria
 where tipo in ('ingreso','a_depositar') and entrada > 0 and cod_cliente ~ '^\d+$' and nro_recibo ~ '^\d+$'
 group by empresa, cod_cliente, nro_recibo;

drop view if exists public.gv_cobranza_pago_mal;
drop view if exists public.gv_cobranza_imputacion;
drop function if exists public.gv_cobranza_imputar(text, text, date);
create or replace function public.gv_cobranza_imputar(p_emp text, p_cod text, p_desde date default current_date - 450)
returns table (recibo text, fecha_pago date, medio text, pagado numeric, dto_tomado numeric, retencion numeric,
               pedido date, facturas text, lista numeric, nc text, lista_nc numeric,
               dias int, dias_contado int, dto_ganado numeric, a_reclamar numeric, calidad text,
               grupo int, ret_cliente numeric, plazo int, atraso int)
language plpgsql stable set search_path = public as $$
declare
  -- pedidos (facturas por día y condición), ordenados por fecha asc
  pd date[] := '{}'; pk text[] := '{}'; pl float8[] := '{}'; pdc float8[] := '{}'; pf text[] := '{}'; pz int[] := '{}';
  -- NC / ND (monto con signo), por fecha asc
  nd date[] := '{}'; nk text[] := '{}'; nl float8[] := '{}';
  -- recibos por número asc
  rr text[] := '{}'; rd date[] := '{}'; rp float8[] := '{}'; rm text[] := '{}';
  pls float8[]; nls float8[]; rps float8[];
  v_cuit text; nr int; np int; nn int; s_tot int; fallback boolean := false;
  rec record; i int; j int; a int; r int; p int; n int; d int; q float8; f float8; s float8; s_l float8; pag float8;
  dmax date; dmin date; oldest date; newest date; dc float8; dtos float8[]; dto float8; resid float8; base float8; c float8;
  cost float8[]; act int[]; mr int[]; mp int[]; mn int[]; mdto float8[]; mres float8[];
  idx int; best float8; bact int; br int; bp int; bn int; bdto float8; bres float8;
  v_ret float8 := 0; rets float8[] := '{}'; med float8; ok int;
  g int := 0; v_dias_contado int; v_dias int; v_ganado numeric; v_fecha date; v_calidad text; v_recibos text; v_medio text;
  v_pag numeric; v_fp date; v_nc text; v_ncm numeric; pen_dto float8; v_plazo int;
  SKIP_R constant float8 := 0.035; SKIP_P constant float8 := 0.035;
begin
  select regexp_replace(coalesce(contraparte_cuit,''),'\D','','g') into v_cuit
    from (select contraparte_cuit from isis_lk.documentos where p_emp = 'lk' and regexp_replace(coalesce(contraparte_codigo,''),'^0+','') = p_cod
          union all
          select contraparte_cuit from isis_ch.documentos where p_emp = 'chef' and regexp_replace(coalesce(contraparte_codigo,''),'^0+','') = p_cod
          limit 1) c;

  -- 1) pedidos pagados (facturas por día, menos lo que sigue pendiente en la deuda), 200 días antes de la ventana
  for rec in
    with doc as (
      select d.fecha, d.punto_venta, d.numero, d.total, d.condicion_venta cond, 'FC'||d.letra||'-'||d.punto_venta||d.numero k
        from (select fecha, letra, punto_venta, numero, total, condicion_venta, contraparte_codigo, familia
                from isis_lk.documentos where p_emp = 'lk'
              union all
              select fecha, letra, punto_venta, numero, total, condicion_venta, contraparte_codigo, familia
                from isis_ch.documentos where p_emp = 'chef') d
       where d.familia = 'factura_venta' and d.fecha >= p_desde - 200 and d.total > 0
         and regexp_replace(coalesce(d.contraparte_codigo,''),'^0+','') = p_cod),
    dd as (select comp_key kk, sum(pendiente) pend from "GV_Cuarentena_Deuda_Detalle" where empresa = p_emp group by 1)
    select doc.fecha,
           coalesce((regexp_match(doc.cond, '-\s*(\d+)\s*%'))[1]::float8 / 100, 0) dcond,
           case when doc.cond ~ '-\s*\d+\s*%' then 'esc'
                when doc.cond ~* '\d+\s*FF' or doc.cond ~* 'importador|fob|a vista|0\s*%' then 'sin_dto'
                else 'libre' end tipo,
           case when doc.cond ~* '(\d+)\s*FF' then (regexp_match(doc.cond, '(\d+)\s*FF', 'i'))[1]::int
                when doc.cond ~* 'e-?cheq\D*(\d+)' then (regexp_match(doc.cond, 'e-?cheq\D*(\d+)', 'i'))[1]::int
                when doc.cond ~* '\d+\s*a\s*(\d+)\s*d' then (regexp_match(doc.cond, '\d+\s*a\s*(\d+)\s*d', 'i'))[1]::int
                when doc.cond ~* 'contado' then -1            -- el plazo de contado lo da la coronita del cliente
                else null end plazo,
           string_agg(ltrim(doc.numero, '0'), '+' order by doc.numero) ks,
           sum(greatest(doc.total - coalesce(dd.pend, 0), 0))::float8 pagado_lista
      from doc left join dd on dd.kk = doc.k
     group by 1, 2, 3, 4 having sum(greatest(doc.total - coalesce(dd.pend, 0), 0)) > 0.03 * sum(doc.total)
     order by 1, 2
  loop
    pd := pd || rec.fecha; pk := pk || rec.ks; pl := pl || rec.pagado_lista; pdc := pdc || rec.dcond;
    pf := pf || rec.tipo; pz := pz || rec.plazo;
  end loop;
  np := coalesce(array_length(pd, 1), 0);

  -- 2) NC / ND del cliente (la NC baja lo que hay que pagar; la ND lo sube)
  for rec in
    select d.fecha, ltrim(d.numero, '0') k, case when d.familia = 'nc_venta' then -abs(d.total) else abs(d.total) end::float8 monto
      from (select fecha, numero, total, contraparte_codigo, familia from isis_lk.documentos where p_emp = 'lk'
            union all
            select fecha, numero, total, contraparte_codigo, familia from isis_ch.documentos where p_emp = 'chef') d
     where d.familia in ('nc_venta','nd_venta') and d.fecha >= p_desde - 200 and d.total <> 0
       and regexp_replace(coalesce(d.contraparte_codigo,''),'^0+','') = p_cod
     order by d.fecha, d.numero
  loop
    nd := nd || rec.fecha; nk := nk || rec.k; nl := nl || rec.monto;
  end loop;
  nn := coalesce(array_length(nd, 1), 0);

  -- 3) recibos, por número (el orden en que ISIS los emitió)
  for rec in
    select r.recibo, r.fecha_pago, r.medio, r.pagado::float8 pagado
      from gv_cobranza_recibos r
     where r.empresa = p_emp and r.cod_cliente = p_cod and r.fecha_pago >= p_desde
     order by r.recibo::bigint
  loop
    rr := rr || rec.recibo; rd := rd || rec.fecha_pago; rp := rp || rec.pagado; rm := rm || rec.medio;
  end loop;
  nr := coalesce(array_length(rr, 1), 0);

  -- 4) fallback para clientes enormes: NC neteadas contra el pedido anterior, sin dimensión NC
  if nr * np * (nn + 1) > 150000 then
    fallback := true;
    for a in 1..nn loop
      for j in reverse np..1 loop
        if pd[j] <= nd[a] then pl[j] := pl[j] + nl[a]; exit; end if;
      end loop;
    end loop;
    nd := '{}'; nk := '{}'; nl := '{}'; nn := 0;
  end if;

  -- 5) retención típica del cliente: pares simples recibo↔pedido con el dto de la condición
  for i in 1..nr loop
    for j in 1..np loop
      continue when pd[j] > rd[i] + 5 or pd[j] < rd[i] - 200 or pl[j] <= 0;
      resid := 1 - rp[i] / (pl[j] * (1 - pdc[j]));
      if resid between 0.005 and 0.05 then rets := rets || resid; end if;
    end loop;
  end loop;
  if coalesce(array_length(rets, 1), 0) >= 3 then
    select percentile_cont(0.5) within group (order by x) into med from unnest(rets) x;
    select count(*) into ok from unnest(rets) x where abs(x - med) <= 0.005;
    if ok::float8 / array_length(rets, 1) >= 0.6 then v_ret := med; end if;
  end if;

  -- prefijos
  rps := array_fill(0::float8, array[nr + 1]); pls := array_fill(0::float8, array[np + 1]); nls := array_fill(0::float8, array[nn + 1]);
  for i in 1..nr loop rps[i + 1] := rps[i] + rp[i]; end loop;
  for j in 1..np loop pls[j + 1] := pls[j] + pl[j]; end loop;
  for a in 1..nn loop nls[a + 1] := nls[a] + nl[a]; end loop;

  -- 6) alineación (programación dinámica, de atrás hacia adelante)
  s_tot := (nr + 1) * (np + 1) * (nn + 1);
  cost := array_fill(0::float8, array[s_tot]); act := array_fill(0, array[s_tot]);
  mr := array_fill(0, array[s_tot]); mp := array_fill(0, array[s_tot]); mn := array_fill(0, array[s_tot]);
  mdto := array_fill(0::float8, array[s_tot]); mres := array_fill(0::float8, array[s_tot]);
  for i in reverse nr..0 loop
    for j in reverse np..0 loop
      for a in reverse nn..0 loop
        idx := ((i * (np + 1)) + j) * (nn + 1) + a + 1;
        if i = nr and j = np then cost[idx] := 0; act[idx] := 0; continue; end if;
        best := 1e9; bact := 0;
        if i < nr then c := cost[idx + (np + 1) * (nn + 1)] + SKIP_R; if c < best then best := c; bact := 1; end if; end if;
        if j < np then c := cost[idx + (nn + 1)] + SKIP_P;            if c < best then best := c; bact := 2; end if; end if;
        if a < nn then c := cost[idx + 1];                            if c < best then best := c; bact := 3; end if; end if;
        for r in 1..3 loop
          exit when i + r > nr;
          dmax := rd[i + 1]; dmin := rd[i + 1];
          for d in 2..r loop dmax := greatest(dmax, rd[i + d]); dmin := least(dmin, rd[i + d]); end loop;
          exit when dmax - dmin > 35;                       -- un pedido se paga en cuotas de hasta un mes
          pag := rps[i + r + 1] - rps[i + 1];
          for p in 1..3 loop
            exit when j + p > np;
            oldest := pd[j + 1]; newest := pd[j + p];
            exit when newest > dmax + 5 or oldest < dmin - 200;
            s_l := pls[j + p + 1] - pls[j + 1]; dc := pdc[j + 1];
            dtos := case when pf[j + 1] = 'sin_dto' then array[dc] else array[dc, 0.25, 0.20, 0.15, 0.10, 0.05, 0] end;
            pen_dto := case when pf[j + 1] = 'esc' then 0.03 else 0 end;
            for n in 0..2 loop
              exit when a + n > nn;
              if n > 0 then exit when nd[a + n] > dmax + 5 or nd[a + 1] < oldest - 10; end if;
              s := s_l + nls[a + n + 1] - nls[a + 1];
              continue when s <= 0;
              q := pag / s;
              for d in 1..array_length(dtos, 1) loop
                dto := dtos[d];
                continue when d > 1 and dto = dc;
                f := 1 - dto;
                continue when q > f * 1.012 or q < f * 0.95;
                resid := 1 - q / f;
                base := least(case when resid >= 0 then resid else -2 * resid end, abs(resid - v_ret));
                c := cost[(((i + r) * (np + 1)) + j + p) * (nn + 1) + a + n + 1]
                     + base + 0.008 * (r - 1) + 0.008 * (p - 1) + 0.008 * n + case when d > 1 then pen_dto else 0 end;
                if c < best then best := c; bact := 4; br := r; bp := p; bn := n; bdto := dto; bres := resid; end if;
              end loop;
            end loop;
          end loop;
        end loop;
        cost[idx] := best; act[idx] := bact;
        if bact = 4 then mr[idx] := br; mp[idx] := bp; mn[idx] := bn; mdto[idx] := bdto; mres[idx] := bres; end if;
      end loop;
    end loop;
  end loop;

  -- 7) reconstruir el camino y emitir
  i := 0; j := 0; a := 0;
  loop
    idx := ((i * (np + 1)) + j) * (nn + 1) + a + 1;
    exit when act[idx] = 0;
    if act[idx] = 1 then
      recibo := rr[i + 1]; fecha_pago := rd[i + 1]; medio := rm[i + 1]; pagado := round(rp[i + 1]::numeric, 2);
      dto_tomado := null; retencion := null; pedido := null; facturas := null; lista := null; nc := null; lista_nc := null;
      dias := null; dias_contado := null; dto_ganado := null; a_reclamar := null; calidad := 'sin imputar';
      grupo := null; ret_cliente := round(v_ret::numeric, 4); plazo := null; atraso := null;
      return next; i := i + 1; continue;
    elsif act[idx] = 2 then
      if pd[j + 1] >= p_desde then
        recibo := null; fecha_pago := null; medio := null; pagado := null; dto_tomado := null; retencion := null;
        pedido := pd[j + 1]; facturas := pk[j + 1]; lista := round(pl[j + 1]::numeric, 2); nc := null; lista_nc := null;
        dias := null; dias_contado := null; dto_ganado := null; a_reclamar := null; calidad := 'pagada sin recibo';
        grupo := null; ret_cliente := round(v_ret::numeric, 4); plazo := null; atraso := null;
        return next;
      end if;
      j := j + 1; continue;
    elsif act[idx] = 3 then
      a := a + 1; continue;
    end if;
    -- tramo imputado
    g := g + 1; r := mr[idx]; p := mp[idx]; n := mn[idx]; dto := mdto[idx]; resid := mres[idx];
    v_recibos := rr[i + 1]; v_fp := rd[i + 1]; v_medio := rm[i + 1]; v_pag := 0;
    for d in 1..r loop
      v_pag := v_pag + rp[i + d]; v_fp := greatest(v_fp, rd[i + d]);
      if d > 1 then v_recibos := v_recibos || '+' || rr[i + d]; if rm[i + d] <> v_medio then v_medio := 'varios'; end if; end if;
    end loop;
    v_nc := null; v_ncm := 0;
    for d in 1..n loop v_nc := concat_ws('+', v_nc, nk[a + d]); v_ncm := v_ncm + nl[a + d]; end loop;
    v_calidad := case when abs(resid) <= 0.005 then 'exacta'
                      when v_ret > 0 and abs(resid - v_ret) <= 0.005 then 'con retencion'
                      when resid > 0 then 'con retencion' else 'pago de mas' end
                 || case when fallback then ' (nc neteadas)' else '' end;
    for d in 1..p loop
      v_fecha := pd[j + d];
      select coalesce((select e.dias from cobranzas_excepciones e
                        where e.deudor_id = v_cuit and e.escalon = 'contado' and (e.empresa is null or e.empresa = p_emp)
                          and v_fecha >= e.vigente_desde and (e.vigente_hasta is null or v_fecha <= e.vigente_hasta)
                        order by e.vigente_desde desc limit 1), 14) into v_dias_contado;
      v_dias := v_fp - v_fecha;
      v_ganado := case when v_dias <= v_dias_contado then 0.25 when v_dias <= 30 then 0.20
                       when v_dias <= 45 then 0.15 when v_dias <= 60 then 0.10 else 0 end;
      recibo := v_recibos; fecha_pago := v_fp; medio := v_medio; pagado := round(v_pag::numeric, 2);
      dto_tomado := dto::numeric; retencion := round(resid::numeric, 4);
      pedido := v_fecha; facturas := pk[j + d]; lista := round(pl[j + d]::numeric, 2);
      nc := v_nc; lista_nc := round(v_ncm::numeric, 2);
      dias := v_dias; dias_contado := v_dias_contado; dto_ganado := v_ganado;
      a_reclamar := round((pl[j + d] * greatest(dto - v_ganado, 0))::numeric, 2);
      calidad := v_calidad; grupo := g; ret_cliente := round(v_ret::numeric, 4);
      -- plazo: el de la condición; con escalón, el del dto que se TOMÓ (14/coronita · 30 · 45 · 60)
      v_plazo := case when pf[j + d] = 'esc' or (pf[j + d] = 'libre' and dto > 0) then
                        case when dto >= 0.25 then v_dias_contado when dto >= 0.20 then 30 when dto >= 0.15 then 45
                             when dto >= 0.10 then 60 when dto >= 0.05 then 90 else 120 end
                      when pz[j + d] = -1 then v_dias_contado else pz[j + d] end;
      plazo := v_plazo; atraso := case when v_plazo is null then null else greatest(v_dias - v_plazo, 0) end;
      return next;
    end loop;
    i := i + r; j := j + p; a := a + n;
  end loop;
end $$;

revoke all on function public.gv_cobranza_imputar(text,text,date) from public, anon;
grant execute on function public.gv_cobranza_imputar(text,text,date) to authenticated;

-- ───────────────────────────────────────────────────────────────────────────────────────────────
-- La imputación de TODOS los clientes cuesta 35 s (LK 31 s · 629 clientes · Chef 3,5 s · 125), así que
-- NO se lee en vivo desde el front (timeout 8 s): vive en la tabla GV_Cobranza_Imputacion, que el cron
-- gv-cobranza-imputacion (minuto 49 de cada hora) rehace SÓLO si cambió algo desde el último cálculo
-- (una carga de conciliación, un Excel de deuda, una factura nueva de ISIS). gv_cobranza_imputacion y
-- gv_cobranza_pago_mal leen la tabla; gv_cobranza_imputar(emp, cod) sigue siendo la versión viva por
-- cliente (Torres y Liva: 846 ms).
-- Rollback: select cron.unschedule('gv-cobranza-imputacion'); drop table GV_Cobranza_Imputacion, GV_Cobranza_Imputacion_Meta cascade;

create table if not exists public."GV_Cobranza_Imputacion" (
  empresa text not null, cod_cliente text not null, nombre text,
  recibo text, fecha_pago date, medio text, pagado numeric, dto_tomado numeric, retencion numeric,
  pedido date, facturas text, lista numeric, nc text, lista_nc numeric,
  dias int, dias_contado int, dto_ganado numeric, a_reclamar numeric, calidad text,
  grupo int, ret_cliente numeric, calculado_en timestamptz not null default now(), plazo int, atraso int
);
alter table public."GV_Cobranza_Imputacion" add column if not exists plazo int, add column if not exists atraso int;
create index if not exists gv_cobranza_imputacion_cli on public."GV_Cobranza_Imputacion" (empresa, cod_cliente);
alter table public."GV_Cobranza_Imputacion" enable row level security;
drop policy if exists sup_lee on public."GV_Cobranza_Imputacion";
create policy sup_lee on public."GV_Cobranza_Imputacion" for select to authenticated using (public.es_supervisor_virgilio());
revoke all on public."GV_Cobranza_Imputacion" from anon;
revoke insert, update, delete, truncate on public."GV_Cobranza_Imputacion" from authenticated;
grant select on public."GV_Cobranza_Imputacion" to authenticated;

create table if not exists public."GV_Cobranza_Imputacion_Meta" (
  id int primary key default 1 check (id = 1),
  calculado_en timestamptz, huella timestamptz, clientes int, filas int, ms int, motivo text
);
alter table public."GV_Cobranza_Imputacion_Meta" enable row level security;
drop policy if exists sup_lee on public."GV_Cobranza_Imputacion_Meta";
create policy sup_lee on public."GV_Cobranza_Imputacion_Meta" for select to authenticated using (public.es_supervisor_virgilio());
revoke all on public."GV_Cobranza_Imputacion_Meta" from anon;
revoke insert, update, delete, truncate on public."GV_Cobranza_Imputacion_Meta" from authenticated;
grant select on public."GV_Cobranza_Imputacion_Meta" to authenticated;
insert into public."GV_Cobranza_Imputacion_Meta" (id) values (1) on conflict do nothing;

create or replace function public.gv_cobranza_imputacion_refrescar(p_forzar boolean default false)
returns text language plpgsql security definer set search_path = public as $$
declare v_huella timestamptz; v_prev timestamptz; t0 timestamptz := clock_timestamp(); n int; m int;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'solo supervisor';
  end if;
  -- ¿cambió algo desde el último cálculo? conciliación · deuda · facturas de ISIS
  select greatest(
           (select max(cargado_en) from public."GV_Conc_Cargas"),
           (select max(cargado_at) from public."GV_Cuarentena_Deuda_Detalle"),
           (select max(created_at) from isis_lk.documentos),
           (select max(created_at) from isis_ch.documentos)) into v_huella;
  select huella into v_prev from public."GV_Cobranza_Imputacion_Meta" where id = 1;
  if not p_forzar and v_prev is not null and v_huella is not null and v_huella <= v_prev then
    return 'sin cambios desde ' || to_char(v_prev at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI');
  end if;
  if not pg_try_advisory_xact_lock(hashtext('gv_cobranza_imputacion')) then return 'ocupado'; end if;
  delete from public."GV_Cobranza_Imputacion";
  insert into public."GV_Cobranza_Imputacion"
        (empresa, cod_cliente, nombre, recibo, fecha_pago, medio, pagado, dto_tomado, retencion, pedido, facturas, lista, nc, lista_nc,
         dias, dias_contado, dto_ganado, a_reclamar, calidad, grupo, ret_cliente, plazo, atraso)
  with cli as (
    select 'lk'::text emp, regexp_replace(coalesce(contraparte_codigo,''),'^0+','') cod, max(contraparte_nombre) nombre
      from isis_lk.documentos where familia = 'factura_venta' and fecha >= current_date - 450
       and regexp_replace(coalesce(contraparte_codigo,''),'^0+','') <> '411' group by 2        -- 411 = Chef SRL (interno)
    union all
    select 'chef', regexp_replace(coalesce(contraparte_codigo,''),'^0+',''), max(contraparte_nombre)
      from isis_ch.documentos where familia = 'factura_venta' and fecha >= current_date - 450
       and regexp_replace(coalesce(contraparte_codigo,''),'^0+','') <> '1434' group by 2)      -- 1434 = Loekemeyer Hnos (interno)
  select cli.emp, cli.cod, cli.nombre, x.recibo, x.fecha_pago, x.medio, x.pagado, x.dto_tomado, x.retencion, x.pedido, x.facturas,
         x.lista, x.nc, x.lista_nc, x.dias, x.dias_contado, x.dto_ganado, x.a_reclamar, x.calidad, x.grupo, x.ret_cliente, x.plazo, x.atraso
    from cli cross join lateral public.gv_cobranza_imputar(cli.emp, cli.cod) x;
  get diagnostics n = row_count;
  select count(distinct (empresa, cod_cliente)) into m from public."GV_Cobranza_Imputacion";
  update public."GV_Cobranza_Imputacion_Meta"
     set calculado_en = now(), huella = v_huella, clientes = m, filas = n,
         ms = round(extract(epoch from clock_timestamp() - t0) * 1000), motivo = case when p_forzar then 'forzado' else 'cambio' end
   where id = 1;
  return format('%s clientes · %s filas · %s ms', m, n, round(extract(epoch from clock_timestamp() - t0) * 1000));
end $$;
revoke all on function public.gv_cobranza_imputacion_refrescar(boolean) from public, anon;
grant execute on function public.gv_cobranza_imputacion_refrescar(boolean) to authenticated;

-- las vistas pasan a leer la tabla (la viva por cliente sigue en gv_cobranza_imputar)
drop view if exists public.gv_cobranza_pago_mal;
drop view if exists public.gv_cobranza_imputacion;
create view public.gv_cobranza_imputacion with (security_invoker = true) as
select empresa, cod_cliente, nombre, recibo, fecha_pago, medio, pagado, dto_tomado, retencion, pedido, facturas, lista, nc, lista_nc,
       dias, dias_contado, dto_ganado, a_reclamar, calidad, grupo, ret_cliente, plazo, atraso, calculado_en
  from public."GV_Cobranza_Imputacion";
create view public.gv_cobranza_pago_mal with (security_invoker = true) as
select empresa, cod_cliente, max(nombre) as cliente,
       count(*) filter (where a_reclamar > 0) as pedidos_mal,
       count(*) filter (where grupo is not null) as pedidos_imputados,
       count(*) filter (where atraso > 0) as pedidos_atrasados,
       round(avg(dias) filter (where a_reclamar > 0 or atraso > 0)) as dias_prom, max(dias) as dias_max, max(atraso) as atraso_max,
       max(ret_cliente) as ret_cliente,
       round(sum(a_reclamar), 2) as a_reclamar,
       count(*) filter (where calidad = 'sin imputar') as recibos_sin_imputar,
       count(*) filter (where calidad = 'pagada sin recibo') as pedidos_sin_recibo,
       min(pedido) filter (where a_reclamar > 0 or atraso > 0) as desde, max(pedido) filter (where a_reclamar > 0 or atraso > 0) as hasta,
       max(calculado_en) as calculado_en
  from public."GV_Cobranza_Imputacion"
 group by empresa, cod_cliente;
revoke all on public.gv_cobranza_imputacion, public.gv_cobranza_pago_mal from anon;
grant select on public.gv_cobranza_imputacion, public.gv_cobranza_pago_mal to authenticated;

-- cron: minuto 49 (impar, libre: no choca con 55/57/68/92/94/102)
select cron.unschedule(jobid) from cron.job where jobname = 'gv-cobranza-imputacion';
select cron.schedule('gv-cobranza-imputacion', '49 * * * *', 'select public.gv_cobranza_imputacion_refrescar();');
