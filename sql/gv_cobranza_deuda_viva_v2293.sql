-- v22.93 · Cobranzas: DEUDA VIVA automática + explicación de cada pago (Thomas, 26/09: "que en el módulo de
-- cobranzas figuren todas las deudas que hoy se cargan por Excel… que se carguen de manera automática a través
-- de las facturas y los pagos… y que a la derecha del importe facturado aparezca la explicación de qué pagó").
--
-- CÓMO SE CALCULA LA DEUDA VIVA (GV_Cobranza_Deuda_Viva, una fila por comprobante):
--   1. ANCLA: el último Excel de deuda cargado en Cuarentena (GV_Cuarentena_Deuda_Detalle), por empresa. Es la
--      foto real de ISIS a esa hora; no se reconstruye la historia (no hay saldo de apertura confiable).
--   2. + FACTURAS / ND / NC que ISIS emitió desde la fecha del ancla y que el Excel no tiene → deuda nueva a lista.
--   3. − PAGOS y NC posteriores al ancla, en orden de fecha, de la factura más vieja a la más nueva y a VALOR
--      NOMINAL. Así lo hace ISIS: el cliente paga el 75 % y el 25 % lo cancela una NC "Sin Cotizador" que ISIS
--      emite aparte (medido: la NC 11082 de Torres y Liva = 25 % exacto de 35217+35218). Lo que sobra queda como
--      saldo a favor ("pago a cuenta · banco").
--      ⚠ Un pago es nuevo por su NÚMERO DE RECIBO, no por la fecha: el e-cheque figura en la conciliación con la
--      fecha de COBRO (hasta 01/2027) y su recibo ya estaba en ISIS al sacar el Excel. Recibo nuevo = número mayor
--      que el último recibo emitido hasta el día del ancla (sin los números mal tipeados: > 1,05 × la mediana).
--      Comprobantes de ISIS del mismo día del ancla que el Excel no tiene: la FC/ND entra (se emitió después del
--      Excel), la NC no (casi siempre ya estaba aplicada).
--   Cada vez que se sube un Excel nuevo en Cuarentena, el ancla se mueve sola y la diferencia entre lo que
--   calculó el sistema y lo que dice ISIS se ve en gv_cobranza_control_excel (el control de que el cálculo anda).
--
-- ERROR PROPIO CORREGIDO (v22.89 y v22.92): el cruce factura ↔ Excel usaba 'FC'||letra, y el Excel escribe las
-- facturas de crédito MiPyME como FCP / FCPYM y las de exportación como FCE. Esas facturas —las más grandes—
-- nunca cruzaban y el agente las daba por PAGADAS. Ahora la clave es gv_cobranza_doc_key(clase, pv+número):
-- FCA/FCP/FCPYM/FCE → FC. Medido: 374 de 374 comprobantes del Excel cruzan con ISIS (antes 328).
--
-- Rollback: drop function gv_cobranza_cliente, gv_cobranza_clientes, gv_cobranza_deuda_viva_refrescar;
--           drop view gv_cobranza_control_excel; drop table "GV_Cobranza_Deuda_Viva";
--           y volver gv_cobranza_imputar / gv_cobranza_imputacion_refrescar a sql/gv_cobranza_imputar_v2291.sql.

create or replace function public.gv_cobranza_doc_key(p_clase text, p_digitos text)
returns text language sql immutable set search_path = public, pg_temp as $$
  select case when upper(p_clase) ~ '^(FC|FACT)' then 'FC'
              when upper(p_clase) ~ '^NC' then 'NC'
              when upper(p_clase) ~ '^ND' then 'ND'
              else upper(p_clase) end
         || '-' || right(regexp_replace(coalesce(p_digitos,''), '\D', '', 'g'), 12);
$$;

create table if not exists public."GV_Cobranza_Deuda_Viva" (
  id bigserial primary key, empresa text not null, cod_cliente text not null, razon_social text, cuit text,
  doc_key text not null, comprobante text, fecha date, vence date, condicion text, dto_cond numeric,
  lista numeric,                 -- importe del comprobante en ISIS (con signo: NC negativa)
  pendiente_ancla numeric,       -- lo que decía el Excel (0 si es nuevo)
  cancelado_banco numeric not null default 0,
  pendiente numeric,             -- deuda viva
  origen text,                   -- 'excel' | 'isis nuevo' | 'pago a cuenta (banco)'
  recibos_banco text,            -- recibos posteriores al ancla que lo cancelaron
  ancla timestamptz, calculado_en timestamptz not null default now()
);
create index if not exists gv_cobranza_deuda_viva_cli on public."GV_Cobranza_Deuda_Viva" (empresa, cod_cliente);
create index if not exists gv_cobranza_deuda_viva_key on public."GV_Cobranza_Deuda_Viva" (empresa, doc_key);
alter table public."GV_Cobranza_Deuda_Viva" enable row level security;
drop policy if exists sup_lee on public."GV_Cobranza_Deuda_Viva";
create policy sup_lee on public."GV_Cobranza_Deuda_Viva" for select to authenticated using (public.es_supervisor_virgilio());
revoke all on public."GV_Cobranza_Deuda_Viva" from anon;
revoke insert, update, delete, truncate on public."GV_Cobranza_Deuda_Viva" from authenticated;
grant select on public."GV_Cobranza_Deuda_Viva" to authenticated;

create or replace function public.gv_cobranza_deuda_viva_refrescar()
returns text language plpgsql security definer set search_path = public as $$
declare e text; v_lote text; v_ancla timestamptz; v_dia date; rc record; it record;
        v_rem numeric; v_take numeric; v_nrec bigint; v_med numeric; n_rec int := 0; n_new int := 0;
begin
  delete from "GV_Cobranza_Deuda_Viva";
  foreach e in array array['lk','chef'] loop
    select lote, max(cargado_at) into v_lote, v_ancla from "GV_Cuarentena_Deuda_Detalle"
     where empresa = e group by lote order by max(cargado_at) desc limit 1;
    continue when v_lote is null;
    v_dia := (v_ancla at time zone 'America/Argentina/Buenos_Aires')::date;

    -- 1) ancla: el Excel
    insert into "GV_Cobranza_Deuda_Viva" (empresa, cod_cliente, razon_social, doc_key, comprobante, fecha, vence,
           pendiente_ancla, pendiente, origen, ancla)
    select e, regexp_replace(coalesce(x.cod,''),'^0+',''), x.razon_social,
           gv_cobranza_doc_key(split_part(x.comp_key,'-',1), split_part(x.comp_key,'-',2)), x.comprobante,
           -- el Excel de ISIS trae [0] = VENCIMIENTO y [1] = FECHA de emisión (una FCPYM: 14/10 y 14/09)
           case when x.fila->>1 ~ '^\d+(\.\d+)?$' then date '1899-12-30' + (x.fila->>1)::numeric::int end,
           case when x.fila->>0 ~ '^\d+(\.\d+)?$' then date '1899-12-30' + (x.fila->>0)::numeric::int end,
           x.pendiente, x.pendiente, 'excel', v_ancla
      from "GV_Cuarentena_Deuda_Detalle" x
     where x.empresa = e and x.lote = v_lote and x.pendiente <> 0 and x.comp_key ~ '^[A-Z]';

    -- 2) comprobantes de ISIS desde el día del ancla que el Excel no tiene
    insert into "GV_Cobranza_Deuda_Viva" (empresa, cod_cliente, razon_social, doc_key, comprobante, fecha, vence,
           condicion, lista, pendiente_ancla, pendiente, origen, ancla)
    select e, d.cod, d.nombre, d.k, d.tipo || ' ' || d.punto_venta || '-' || d.numero, d.fecha, d.vto_factura, d.cond,
           d.monto, 0, d.monto, 'isis nuevo', v_ancla
      from (select regexp_replace(coalesce(contraparte_codigo,''),'^0+','') cod, contraparte_nombre nombre,
                   gv_cobranza_doc_key(familia, punto_venta||numero) k, tipo, punto_venta, numero, fecha, vto_factura,
                   condicion_venta cond, case when familia = 'nc_venta' then -abs(total) else abs(total) end monto
              from isis_lk.documentos where e = 'lk' and familia in ('factura_venta','nc_venta','nd_venta')
               and (fecha > v_dia or (fecha = v_dia and familia <> 'nc_venta'))
            union all
            select regexp_replace(coalesce(contraparte_codigo,''),'^0+',''), contraparte_nombre,
                   gv_cobranza_doc_key(familia, punto_venta||numero), tipo, punto_venta, numero, fecha, vto_factura,
                   condicion_venta, case when familia = 'nc_venta' then -abs(total) else abs(total) end
              from isis_ch.documentos where e = 'chef' and familia in ('factura_venta','nc_venta','nd_venta')
               and (fecha > v_dia or (fecha = v_dia and familia <> 'nc_venta'))) d
     where d.monto <> 0
       and not exists (select 1 from "GV_Cobranza_Deuda_Viva" v where v.empresa = e and v.doc_key = d.k);
    get diagnostics n_rec = row_count; n_new := n_new + n_rec;

    -- completar lista, condición y dto de los que vinieron del Excel
    update "GV_Cobranza_Deuda_Viva" v
       set lista = coalesce(v.lista, d.monto), condicion = coalesce(v.condicion, d.cond),
           razon_social = coalesce(v.razon_social, d.nombre), fecha = coalesce(v.fecha, d.fecha)
      from (select gv_cobranza_doc_key(familia, punto_venta||numero) k, condicion_venta cond, contraparte_nombre nombre, fecha,
                   case when familia = 'nc_venta' then -abs(total) else abs(total) end monto
              from isis_lk.documentos where e = 'lk' and familia in ('factura_venta','nc_venta','nd_venta')
            union all
            select gv_cobranza_doc_key(familia, punto_venta||numero), condicion_venta, contraparte_nombre, fecha,
                   case when familia = 'nc_venta' then -abs(total) else abs(total) end
              from isis_ch.documentos where e = 'chef' and familia in ('factura_venta','nc_venta','nd_venta')) d
     where v.empresa = e and v.doc_key = d.k;
    update "GV_Cobranza_Deuda_Viva"
       set dto_cond = coalesce((regexp_match(condicion, '-\s*(\d+)\s*%'))[1]::numeric / 100, 0)
     where empresa = e;
    -- CUIT del cliente (la pantalla no puede leer isis_*) y VENCIMIENTO: el vto del Excel si es posterior a la
    -- factura; si no (contado), fecha + plazo de la condición (contado = 14 días o la coronita del cliente).
    update "GV_Cobranza_Deuda_Viva" v set cuit = c.cuit
      from (select regexp_replace(coalesce(contraparte_codigo,''),'^0+','') cod, max(regexp_replace(coalesce(contraparte_cuit,''),'\D','','g')) cuit
              from isis_lk.documentos where e = 'lk' and familia = 'factura_venta' group by 1
            union all
            select regexp_replace(coalesce(contraparte_codigo,''),'^0+',''), max(regexp_replace(coalesce(contraparte_cuit,''),'\D','','g'))
              from isis_ch.documentos where e = 'chef' and familia = 'factura_venta' group by 1) c
     where v.empresa = e and v.cod_cliente = c.cod;
    update "GV_Cobranza_Deuda_Viva" v
       set vence = case when v.vence > v.fecha then v.vence
                        else v.fecha + case
                          when v.condicion ~* '(\d+)\s*FF' then (regexp_match(v.condicion, '(\d+)\s*FF', 'i'))[1]::int
                          when v.condicion ~* 'e-?cheq\D*(\d+)' then (regexp_match(v.condicion, 'e-?cheq\D*(\d+)', 'i'))[1]::int
                          when v.condicion ~* '\d+\s*a\s*(\d+)\s*d' then (regexp_match(v.condicion, '\d+\s*a\s*(\d+)\s*d', 'i'))[1]::int
                          when v.condicion ~* 'contado' then coalesce((select x.dias from cobranzas_excepciones x
                                  where x.deudor_id = v.cuit and x.escalon = 'contado' and (x.empresa is null or x.empresa = e)
                                  order by x.vigente_desde desc limit 1), 14)
                          else 30 end end
     where v.empresa = e and v.fecha is not null;

    -- 3) créditos posteriores al ancla (recibos nuevos + NC nuevas), en orden de fecha, a valor nominal
    select percentile_cont(0.5) within group (order by r.recibo::bigint) into v_med
      from gv_cobranza_recibos r where r.empresa = e and r.fecha_primer_cobro between v_dia - 30 and v_dia;
    select max(r.recibo::bigint) into v_nrec
      from gv_cobranza_recibos r
     where r.empresa = e and r.fecha_primer_cobro between v_dia - 30 and v_dia and r.recibo::bigint <= 1.05 * v_med;
    for rc in
      select c.cod_cliente, c.ref, c.fecha, c.monto, c.es_nc from (
        select r.cod_cliente, 'Recibo ' || r.recibo ref, r.fecha_primer_cobro fecha, r.pagado monto, false es_nc
          from gv_cobranza_recibos r
         where r.empresa = e and v_nrec is not null and r.recibo::bigint > v_nrec and r.recibo::bigint <= 1.05 * v_nrec
        union all
        select v.cod_cliente, v.comprobante, v.fecha, -v.pendiente, true
          from "GV_Cobranza_Deuda_Viva" v
         where v.empresa = e and v.origen = 'isis nuevo' and v.pendiente < 0) c
       order by c.cod_cliente, c.fecha, c.ref
    loop
      v_rem := rc.monto;
      for it in
        select id, pendiente from "GV_Cobranza_Deuda_Viva"
         where empresa = e and cod_cliente = rc.cod_cliente and pendiente > 0
         order by fecha nulls first, doc_key
      loop
        exit when v_rem <= 0.5;
        v_take := least(v_rem, it.pendiente);
        update "GV_Cobranza_Deuda_Viva"
           set cancelado_banco = cancelado_banco + v_take, pendiente = pendiente - v_take,
               recibos_banco = concat_ws(' + ', recibos_banco, rc.ref || ' (' || to_char(rc.fecha, 'DD/MM') || ')')
         where id = it.id;
        v_rem := v_rem - v_take;
      end loop;
      if rc.es_nc then
        -- la NC queda con lo que no encontró factura que cancelar
        update "GV_Cobranza_Deuda_Viva" set pendiente = -v_rem, cancelado_banco = rc.monto - v_rem
         where empresa = e and cod_cliente = rc.cod_cliente and origen = 'isis nuevo' and comprobante = rc.ref;
      elsif v_rem > 0.5 then
        insert into "GV_Cobranza_Deuda_Viva" (empresa, cod_cliente, doc_key, comprobante, fecha, pendiente_ancla, pendiente,
               origen, recibos_banco, ancla)
        values (e, rc.cod_cliente, 'RC-' || rc.ref, rc.ref || ' (sin factura que cancelar)', rc.fecha,
                0, -v_rem, 'pago a cuenta (banco)', rc.ref, v_ancla);
      end if;
    end loop;
  end loop;
  -- los clientes internos no son deuda a cobrar
  delete from "GV_Cobranza_Deuda_Viva" where (empresa = 'lk' and cod_cliente = '411') or (empresa = 'chef' and cod_cliente = '1434');
  return format('deuda viva: %s comprobantes · %s nuevos de ISIS', (select count(*) from "GV_Cobranza_Deuda_Viva"), n_new);
end $$;
revoke all on function public.gv_cobranza_deuda_viva_refrescar() from public, anon;
grant execute on function public.gv_cobranza_deuda_viva_refrescar() to authenticated;

-- la imputación (qué pagó cada recibo) lee la deuda viva, con la clave nueva — se aplicó sobre la definición
-- viva con replace() (idempotente, falla si el texto no matchea):
--   'FC'||d.letra||'-'||d.punto_venta||d.numero k            →  gv_cobranza_doc_key('FC', d.punto_venta||d.numero) k
--   dd as (… from "GV_Cuarentena_Deuda_Detalle" …)             →  dd as (… doc_key kk … from "GV_Cobranza_Deuda_Viva" …)
-- y gv_cobranza_imputacion_refrescar hace  perform gv_cobranza_deuda_viva_refrescar()  antes de imputar.

create or replace function public.gv_cob_pesos(x numeric) returns text language sql immutable as $$
  select case when x is null then null else '$' || translate(to_char(round(x), 'FM999,999,999,990'), ',', '.') end $$;

-- lista de clientes para la pantalla de Cobranzas
create or replace function public.gv_cobranza_clientes()
returns table (empresa text, cod_cliente text, cliente text, deuda numeric, vencida numeric, comprobantes_abiertos int,
               dias_mas_vieja int, ultimo_pago date, ultimo_pago_monto numeric, pedidos_mal int, a_reclamar numeric,
               pedidos_tarde int, ret_cliente numeric, agente_retencion boolean, ancla timestamptz, calculado_en timestamptz)
language sql stable security invoker set search_path = public as $$
  with dv as (
    select empresa, cod_cliente, max(razon_social) rs, max(cuit) cuit, sum(pendiente) deuda,
           sum(pendiente) filter (where pendiente > 0 and vence < current_date) vencida,
           count(*) filter (where pendiente > 0) abiertas,
           current_date - min(fecha) filter (where pendiente > 0) dias_vieja, max(ancla) ancla
      from "GV_Cobranza_Deuda_Viva" group by 1, 2),
  im as (
    select empresa, cod_cliente, max(nombre) nombre,
           count(*) filter (where a_reclamar > 0) mal, sum(a_reclamar) reclamar,
           count(*) filter (where atraso > 0 and coalesce(a_reclamar, 0) = 0) tarde,
           max(ret_cliente) ret, max(fecha_pago) ult, max(calculado_en) calc
      from "GV_Cobranza_Imputacion" group by 1, 2),
  ult as (
    select distinct on (empresa, cod_cliente) empresa, cod_cliente, pagado
      from "GV_Cobranza_Imputacion" where fecha_pago is not null order by empresa, cod_cliente, fecha_pago desc)
  select coalesce(dv.empresa, im.empresa), coalesce(dv.cod_cliente, im.cod_cliente), coalesce(dv.rs, im.nombre),
         round(coalesce(dv.deuda, 0), 2), round(coalesce(dv.vencida, 0), 2), coalesce(dv.abiertas, 0)::int, dv.dias_vieja,
         im.ult, ult.pagado, coalesce(im.mal, 0)::int, round(coalesce(im.reclamar, 0), 2), coalesce(im.tarde, 0)::int,
         im.ret,
         ag.cuit is not null,
         dv.ancla, im.calc
    from dv full join im on im.empresa = dv.empresa and im.cod_cliente = dv.cod_cliente
    left join ult on ult.empresa = coalesce(dv.empresa, im.empresa) and ult.cod_cliente = coalesce(dv.cod_cliente, im.cod_cliente)
    left join "GV_Clientes_Agente_Retencion" ag on ag.cuit = dv.cuit
   where coalesce(dv.deuda, 0) <> 0 or coalesce(im.reclamar, 0) > 0 or coalesce(im.tarde, 0) > 0
$$;

-- el detalle de un cliente: cada factura con el importe facturado y, a la derecha, la explicación de qué pagó
create or replace function public.gv_cobranza_cliente(p_emp text, p_cod text)
returns table (orden date, fecha date, comprobantes text, facturado numeric, pendiente numeric, estado text,
               pago_recibo text, pago_fecha date, pago_monto numeric, dias int, dto_tomado numeric, dto_ganado numeric,
               retencion numeric, a_reclamar numeric, explicacion text)
language sql stable security invoker set search_path = public as $$
  -- 1) pedidos que el agente imputó a un recibo (pagados)
  select i.pedido, i.pedido, i.facturas, i.lista,
         (select round(sum(v.pendiente), 2) from "GV_Cobranza_Deuda_Viva" v
           where v.empresa = p_emp and v.cod_cliente = p_cod and v.pendiente > 0
             and ltrim(right(v.doc_key, 8), '0') = any (string_to_array(i.facturas, '+'))),
         case when i.a_reclamar > 0 then 'mal' when i.atraso > 0 then 'tarde' else 'bien' end,
         i.recibo, i.fecha_pago, i.pagado, i.dias, i.dto_tomado, i.dto_ganado, i.retencion, i.a_reclamar,
         'Recibo ' || i.recibo || ' del ' || to_char(i.fecha_pago, 'DD/MM/YY') || ': ' || gv_cob_pesos(i.pagado)
         || case when i.dto_tomado > 0 then ' = ' || round((1 - i.dto_tomado) * 100) || ' % de la lista' else ' = lista completa' end
         || case when i.lista_nc < 0 then ' (menos NC ' || i.nc || ')' else '' end
         || case when i.retencion > 0.005 then ', menos ' || replace(to_char(i.retencion * 100, 'FM90.0'), '.', ',') || ' % de retención'
                 when i.retencion < -0.005 then ', pagó ' || replace(to_char(-i.retencion * 100, 'FM90.0'), '.', ',') || ' % de más' else '' end
         || case when i.recibo like '%+%' then ' (varios recibos juntos)' else '' end
         || '. Pagó a los ' || i.dias || ' días'
         || case when i.a_reclamar > 0 then ': le correspondía ' || round(i.dto_ganado * 100) || ' % y se tomó ' || round(i.dto_tomado * 100)
                                            || ' % → reclamar ' || gv_cob_pesos(i.a_reclamar) || '.'
                 when i.atraso > 0 then ': ' || i.atraso || ' días después del plazo de ' || i.plazo || ' días.'
                 else ' ✔ dentro del plazo.' end
    from "GV_Cobranza_Imputacion" i
   where i.empresa = p_emp and i.cod_cliente = p_cod and i.grupo is not null
  union all
  -- 2) pedidos pagados sin recibo en la conciliación
  select i.pedido, i.pedido, i.facturas, i.lista, 0, 'sin recibo', null, null, null, null, null, null, null, null,
         'ISIS la da por pagada pero en la conciliación no hay un recibo que cierre con este importe (efectivo sin identificar, pago de otra cuenta o un recibo a cuenta).'
    from "GV_Cobranza_Imputacion" i
   where i.empresa = p_emp and i.cod_cliente = p_cod and i.calidad = 'pagada sin recibo'
  union all
  -- 3) recibos que no cierran con ninguna factura
  select i.fecha_pago, i.fecha_pago, null, null, null, 'recibo suelto', i.recibo, i.fecha_pago, i.pagado, null, null, null, null, null,
         'Recibo ' || i.recibo || ' del ' || to_char(i.fecha_pago, 'DD/MM/YY') || ' por ' || gv_cob_pesos(i.pagado)
         || ': no cierra con ninguna combinación de facturas (pago a cuenta, parcial o de otra cosa).'
    from "GV_Cobranza_Imputacion" i
   where i.empresa = p_emp and i.cod_cliente = p_cod and i.calidad = 'sin imputar'
  union all
  -- 4) lo que se debe hoy (deuda viva) y el agente no imputó a un pago
  select v.fecha, v.fecha, v.comprobante, v.lista, round(v.pendiente, 2),
         case when v.pendiente < 0 then 'a favor' else 'debe' end,
         v.recibos_banco, null, null, current_date - v.fecha, null, null, null, null,
         case when v.pendiente < 0 then 'Saldo a favor del cliente ' || gv_cob_pesos(-v.pendiente) || ' (' || v.origen || ').'
              when v.cancelado_banco > 0 then 'Debe ' || gv_cob_pesos(v.pendiente) || '. Pagó en parte ' || gv_cob_pesos(v.cancelado_banco)
                                             || ' con ' || v.recibos_banco || '.'
              else 'Debe ' || gv_cob_pesos(v.pendiente) || ' · facturada hace ' || (current_date - v.fecha) || case when current_date - v.fecha = 1 then ' día' else ' días' end
                   || case when v.vence is not null and v.vence < current_date then ' · venció el ' || to_char(v.vence, 'DD/MM')
                        when v.vence is not null then ' · vence el ' || to_char(v.vence, 'DD/MM') else '' end
                   || case when v.origen = 'isis nuevo' then ' · factura nueva (posterior al último Excel)' else '' end || '.'
         end
    from "GV_Cobranza_Deuda_Viva" v
   where v.empresa = p_emp and v.cod_cliente = p_cod and v.pendiente <> 0
     and not exists (select 1 from "GV_Cobranza_Imputacion" i
                      where i.empresa = p_emp and i.cod_cliente = p_cod and i.grupo is not null
                        and ltrim(right(v.doc_key, 8), '0') = any (string_to_array(i.facturas, '+')))
  order by 1 desc nulls last
$$;

-- control: cuando se sube un Excel nuevo, lo que calculó el sistema contra lo que dice ISIS (por cliente)
create or replace view public.gv_cobranza_control_excel with (security_invoker = true) as
select v.empresa, v.cod_cliente, max(v.razon_social) cliente, round(sum(v.pendiente), 2) deuda_viva,
       round(sum(v.pendiente_ancla), 2) deuda_excel, round(sum(v.cancelado_banco), 2) pagos_banco,
       count(*) filter (where v.origen = 'isis nuevo') comprobantes_nuevos, max(v.ancla) ancla
  from public."GV_Cobranza_Deuda_Viva" v group by 1, 2;

revoke all on function public.gv_cobranza_clientes(), public.gv_cobranza_cliente(text, text) from public, anon;
grant execute on function public.gv_cobranza_clientes(), public.gv_cobranza_cliente(text, text) to authenticated;
revoke all on public.gv_cobranza_control_excel from anon;
grant select on public.gv_cobranza_control_excel to authenticated;
