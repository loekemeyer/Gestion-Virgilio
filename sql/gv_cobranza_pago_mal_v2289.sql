-- v22.89 · Agente de cobranzas: ¿el cliente pagó en el plazo del descuento que se tomó? (Thomas, 26/09)
--
-- Reglas (Thomas):
--   * La factura sale a PRECIO DE LISTA con la condición elegida ("Pago Contado -25%", "Pago 15 a 30
--     dias -20%"…). El cliente DESCUENTA ese % al pagar.
--   * Contado = hasta 14 días de la factura (o lo que diga la coronita del cliente en
--     cobranzas_excepciones, escalón 'contado'). 15-30 → 20 %, 31-45 → 15 %, 46-60 → 10 %,
--     más de 60 → SIN descuento.
--   * Pagó mal = pagó en un tramo peor que el descuento que se tomó. A reclamar =
--     lista × (dto de la condición − dto del tramo real).
--   * El e-cheque cuenta por su FECHA DE COBRO (un cheque a 60 días no es contado).
--
-- Cómo sabe qué factura pagó cada cobro (no hay imputación de recibos en la base):
--   * PAGADA = no figura en la deuda cargada (GV_Cuarentena_Deuda_Detalle, el último Excel).
--   * Fecha de pago: se cuenta HACIA ATRÁS desde hoy, anclado en la deuda real. Los cobros más nuevos
--     pagaron las facturas pagadas más nuevas (lista × (1 − dto de la condición)). Así no hace falta
--     saber la deuda de hace un año. Tolerancia 1,5 % (retenciones). Las NC no entran: la deuda del
--     Excel ya las tiene aplicadas. Los recibos a cuenta sin imputar se descuentan de los cobros.
--     La primera versión (hacia adelante) daba días negativos: la deuda vieja corría todo.
--   * Sin cobro que alcance → 'pagada sin rastro en bancos' (efectivo sin identificar, etc.).
--
-- Rollback: drop view public.gv_cobranza_pago_mal; drop view public.gv_cobranza_facturas_pago;

create or replace view public.gv_cobranza_facturas_pago with (security_invoker = true) as
with doc as (
  select 'lk'::text emp, regexp_replace(coalesce(contraparte_codigo,''),'^0+','') cod,
         regexp_replace(coalesce(contraparte_cuit,''),'\D','','g') cuit, contraparte_nombre nombre,
         fecha, numero, condicion_venta cond, total, 'FC'||letra||'-'||punto_venta||numero k
    from isis_lk.documentos
   where familia = 'factura_venta' and fecha >= current_date - 450 and total > 0
  union all
  select 'chef', regexp_replace(coalesce(contraparte_codigo,''),'^0+',''),
         regexp_replace(coalesce(contraparte_cuit,''),'\D','','g'), contraparte_nombre,
         fecha, numero, condicion_venta, total, 'FC'||letra||'-'||punto_venta||numero
    from isis_ch.documentos
   where familia = 'factura_venta' and fecha >= current_date - 450 and total > 0
),
deuda as (select empresa emp, cod, comp_key k, pendiente from public."GV_Cuarentena_Deuda_Detalle"),
dd as (select emp, k, sum(pendiente) pend from deuda group by 1, 2),
-- recibos/pagos a cuenta todavía sin imputar (pendiente negativo que no es factura): son los cobros
-- más recientes y no pagaron ninguna factura de las que ya figuran pagadas.
cred as (select emp, cod, -sum(pendiente) credito from deuda where pendiente < 0 and k !~ '^(FC|NC|ND)' group by 1, 2),
f as (
  select d.*, coalesce(x.pend, 0) pend,
         coalesce((regexp_match(d.cond, '-\s*(\d+)\s*%'))[1]::numeric / 100, 0) dcond,
         greatest(d.total - coalesce(x.pend, 0), 0) pagado_lista
    from doc d left join dd x on x.emp = d.emp and x.k = d.k
),
-- lo que el cliente tenía que pagar por las facturas MÁS NUEVAS que ésta (ya pagadas):
-- se cuenta hacia atrás desde hoy, anclado en la deuda real.
s as (
  select f.*, coalesce(sum(pagado_lista * (1 - dcond)) over (partition by emp, cod order by fecha desc, numero desc
                rows between unbounded preceding and 1 preceding), 0) debe_despues
    from f
),
cob as (
  select empresa emp, cod_cliente cod, fecha,
         coalesce(sum(entrada) over (partition by empresa, cod_cliente order by fecha desc, fila desc
                  rows between unbounded preceding and 1 preceding), 0) cobrado_despues
    from public.gv_conciliacion_bancaria
   where tipo in ('ingreso','a_depositar') and cod_cliente ~ '^\d+$' and entrada > 0
     and fecha >= current_date - 450
),
fac as (
  select s.*,
         coalesce((select e.dias from public.cobranzas_excepciones e
                    where e.deudor_id = s.cuit and e.escalon = 'contado'
                      and (e.empresa is null or e.empresa = s.emp)
                      and s.fecha >= e.vigente_desde and (e.vigente_hasta is null or s.fecha <= e.vigente_hasta)
                    order by e.vigente_desde desc limit 1), 14) dias_contado,
         case when s.pagado_lista <= s.total * 0.03 then null
              else (select min(c.fecha) from cob c
                     where c.emp = s.emp and c.cod = s.cod
                       and c.cobrado_despues <= (s.debe_despues + coalesce(cr.credito, 0)) * 0.985) end fp
    from s left join cred cr on cr.emp = s.emp and cr.cod = s.cod
),
pago as (select fac.*, case when fp < fecha then fecha else fp end fecha_pago from fac)
select emp as empresa, cod as cod_cliente, cuit, nombre, k as factura, fecha, cond as condicion, dcond as dto_condicion,
       round(total, 2) as lista, round(pend, 2) as pendiente,
       case when pagado_lista <= total * 0.03 then 'impaga'
            when fecha_pago is null then 'pagada sin rastro en bancos'
            else 'pagada' end as estado,
       fecha_pago, fecha_pago - fecha as dias, dias_contado,
       case when fecha_pago is null then null
            when fecha_pago - fecha <= dias_contado then 0.25
            when fecha_pago - fecha <= 30 then 0.20
            when fecha_pago - fecha <= 45 then 0.15
            when fecha_pago - fecha <= 60 then 0.10
            else 0 end as dto_ganado,
       case when fecha_pago is null or dcond not in (0.25, 0.20, 0.15, 0.10) then null
            else round(pagado_lista * greatest(dcond -
                   case when fecha_pago - fecha <= dias_contado then 0.25
                        when fecha_pago - fecha <= 30 then 0.20
                        when fecha_pago - fecha <= 45 then 0.15
                        when fecha_pago - fecha <= 60 then 0.10 else 0 end, 0), 2) end as a_reclamar
  from pago;

comment on view public.gv_cobranza_facturas_pago is
  'Agente de cobranzas (v22.89): una fila por factura de los últimos 450 días, con fecha de pago deducida '
  'de los bancos, días, descuento ganado según el tramo real y lo que corresponde reclamar. Reglas en '
  'sql/gv_cobranza_pago_mal_v2289.sql.';

create or replace view public.gv_cobranza_pago_mal with (security_invoker = true) as
select empresa, cod_cliente, max(nombre) as cliente,
       count(*) as facturas_mal, round(avg(dias)) as dias_prom, max(dias) as dias_max,
       round(sum(a_reclamar), 2) as a_reclamar,
       min(fecha) as desde, max(fecha) as hasta
  from public.gv_cobranza_facturas_pago
 where a_reclamar > 0
 group by empresa, cod_cliente;

revoke all on public.gv_cobranza_facturas_pago, public.gv_cobranza_pago_mal from anon;
revoke insert, update, delete, truncate on public.gv_cobranza_facturas_pago, public.gv_cobranza_pago_mal from authenticated;
grant select on public.gv_cobranza_facturas_pago, public.gv_cobranza_pago_mal to authenticated;
