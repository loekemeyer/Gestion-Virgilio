-- v22.91 (2026-09-26) — 📒 CUENTA CORRIENTE POR PROVEEDOR (China)
-- Proyecto Supabase: hrxfctzncixxqmpfhskv
--
-- Thomas, 26/09: "Debería estar la cta corriente de: Hugo Wong; Becky Chen; Ownland" · sobre el
-- formato: "la que creas mejor, formato que sea entendible y analizable".
--
-- QUÉ HABÍA (medido el 26/09):
--   · la plata se veía POR PEDIDO (💵 Plata de 🚢 En curso: gv_imp_cuenta_corriente, la planilla de
--     deudas del 11/09) y la cuenta de NTL por EMPRESA (💱 NTL). Nadie juntaba, por fábrica, cuánto
--     le debemos, cuánto le giramos y por dónde.
--   · GV_Imp_Prov_Mov (las hojas por proveedor del Excel Cuenta_Corriente_NTL.xlsx) tiene SÓLO
--     Ownland (21 movs) y Frontier (7): la hoja Becky que traía el Excel nunca se importó y Hugo Wong
--     no tenía hoja. Y ninguna pantalla mostraba esa tabla.
--   · GV_Imp_CC_Deuda ("formato papá", real / banco / futuro, 17 filas del 16/09) nació el 25/09 en la
--     base, con 6 RPC, sin pantalla y sin commit en el repo.
--
-- QUÉ HACE ESTE SCRIPT: NO crea tablas ni toca datos. Una vista + dos RPC de LECTURA que juntan, por
-- proveedor canónico (gv_imp_prov_canon), lo que ya está cargado, cada fila con su FUENTE:
--   · 'pedido'  = un PI en curso con su FOB (gv_imp_cuenta_corriente: pagado, a girar por banco, falta)
--   · 'giro'    = cada giro cargado (GV_Imp_Pagos)
--   · 'hoja'    = la hoja del proveedor del Excel, tal cual, con SU saldo (GV_Imp_Prov_Mov)
--   · 'ntl'     = lo que el extracto de NTL giró a esa fábrica y lo que recuperó (gv_imp_ntl_cuenta)
-- El SALDO CORRIDO se calcula SÓLO sobre 'pedido' y 'giro' (FOB − giros = lo que le debemos por los
-- pedidos en curso). La hoja y el extracto se muestran con sus propios números, sin volver a sumarlos:
-- la hoja de Thomas mezcla giros por NTL y por banco contra facturas viejas (lo explica
-- docs/IMPORTACIONES-PAGOS-ARGENTINA.md §2 y §4) y rehacer ese saldo era inventar una regla.
--
-- Patrón del módulo (v18.63): la vista cruda NO la lee anon; la app llama a las RPC SECURITY DEFINER.
--
-- ROLLBACK:
--   drop function if exists public.gv_imp_prov_cc_libro(text);
--   drop function if exists public.gv_imp_prov_cc_resumen();
--   drop view if exists public.gv_imp_prov_libro;

-- ---------- 1) la vista: un renglón por movimiento, con su fuente ----------
create or replace view public.gv_imp_prov_libro
with (security_invoker = true) as
with cc as (
  select c.*, pc.creado
    from public.gv_imp_cuenta_corriente c
    left join public.gv_importados_pedidos_curso pc
      on pc.pedido_ref = c.pedido_ref and pc.proveedor = c.proveedor
)
select public.gv_imp_prov_canon(c.proveedor)              as prov,
       'pedido'::text                                     as fuente,
       coalesce(c.fecha_pago_30, c.creado::date)          as fecha,
       0::int                                             as orden,
       case when c.pedido_ref ~* '^\s*pi\b' then c.pedido_ref else 'Pedido ' || c.pedido_ref end as concepto,
       c.pedido_ref                                       as carga,
       null::text                                         as a_traves_de,
       c.a_nombre_de                                      as canal,
       c.fob                                              as fob,
       null::numeric                                      as pago,
       null::numeric                                      as recupero,
       null::numeric                                      as saldo_excel,
       c.pagado                                           as pagado,
       c.pend_giro_directo                                as pend_giro,
       c.falta                                            as falta,
       c.fecha_embarque                                   as embarque,
       c.fecha_llegada                                    as llegada,
       c.unidades                                         as unidades,
       c.m3                                               as m3,
       c.fob_difiere                                      as fob_difiere,
       c.n_lineas || ' línea(s) · ' || c.unidades || ' u · ' || coalesce(c.m3::text, '0') || ' m³'
         || case when c.fob_difiere then ' · ⚠ FOB del PI distinto al calculado por el motor (' || c.fob_calculado || ')' else '' end
         || coalesce(' · ' || c.nota, '')                 as detalle,
       null::text                                         as empresa
  from cc c
union all
select public.gv_imp_prov_canon(p.proveedor), 'giro', p.fecha, p.id::int,
       case p.tipo when 'anticipo30' then 'Anticipo' when 'giro_directo' then 'Giro directo' else 'Saldo' end
         || ' → ' || coalesce(p.beneficiario, p.proveedor),
       p.pedido_ref, p.factura_ref,
       case when p.beneficiario ilike 'ntl' then 'NTL' else 'Bco' end,
       null, p.monto_usd, null, null,
       null, null, null, null, null, null, null, null,
       coalesce(p.nota, '') || coalesce(' · despacho ' || p.despacho_ref, ''),
       null
  from public."GV_Imp_Pagos" p
union all
select public.gv_imp_prov_canon(pm.proveedor), 'hoja',
       -- las filas de factura vienen sin fecha en el Excel ("China 47"): heredan la última fecha de arriba
       coalesce(pm.fecha, (select max(x.fecha) from public."GV_Imp_Prov_Mov" x
                            where x.proveedor = pm.proveedor and x.fila <= pm.fila)),
       pm.fila,
       case when coalesce(pm.credito, 0) > 0
            then 'Factura / carga ' || coalesce(nullif(btrim(pm.fecha_txt), ''), pm.fue_a, '')
            else 'Giro ' || coalesce(pm.salido_por, '') end,
       pm.fue_a, pm.a_traves_de, pm.salido_por,
       pm.credito, pm.debito, null, pm.saldo,
       null, null, null, null, null, null, null, null,
       'Hoja ' || pm.proveedor || ' · fila ' || pm.fila || coalesce(' · ' || pm.nota, ''),
       null
  from public."GV_Imp_Prov_Mov" pm
union all
select public.gv_imp_prov_canon(n.proveedor), 'ntl', n.fecha, n.fila,
       n.descripcion, null, null, 'NTL',
       null,
       case when n.clase = 'giro' then n.debito end,
       case when n.clase = 'recupero' then n.credito end,
       null,
       null, null, null, null, null, null, null, null,
       'Extracto NTL · fila ' || n.fila || coalesce(' · ' || n.origen_destino, ''),
       n.empresa
  from public.gv_imp_ntl_cuenta n
 where n.hoja = 'NTL' and n.clase in ('giro', 'recupero') and n.proveedor is not null
   and not exists (select 1 from public."GV_Imp_Prov_Alias" a
                    where lower(a.alias) = lower(n.proveedor) and a.es_empresa);

revoke select on public.gv_imp_prov_libro from anon, authenticated;

-- ---------- 2) el libro de UN proveedor, con saldo corrido sobre pedido + giro ----------
create or replace function public.gv_imp_prov_cc_libro(p_proveedor text)
returns table (fuente text, fecha date, orden int, concepto text, carga text, a_traves_de text, canal text,
               fob numeric, pago numeric, recupero numeric, saldo numeric, saldo_excel numeric,
               pagado numeric, pend_giro numeric, falta numeric, embarque date, llegada date,
               unidades int, m3 numeric, fob_difiere boolean, detalle text, empresa text)
language sql stable security definer set search_path = public as $$
  select l.fuente, l.fecha, l.orden, l.concepto, l.carga, l.a_traves_de, l.canal, l.fob, l.pago, l.recupero,
         case when l.fuente in ('pedido', 'giro') then
           sum(case when l.fuente in ('pedido', 'giro') then coalesce(l.fob, 0) - coalesce(l.pago, 0) else 0 end)
             over (order by l.fecha nulls first,
                            case l.fuente when 'pedido' then 0 when 'giro' then 1 when 'hoja' then 2 else 3 end,
                            l.orden rows unbounded preceding)
         end as saldo,
         l.saldo_excel, l.pagado, l.pend_giro, l.falta, l.embarque, l.llegada, l.unidades, l.m3, l.fob_difiere,
         l.detalle, l.empresa
    from public.gv_imp_prov_libro l
   where lower(l.prov) = lower(public.gv_imp_prov_canon(p_proveedor))
   order by l.fecha nulls first,
            case l.fuente when 'pedido' then 0 when 'giro' then 1 when 'hoja' then 2 else 3 end,
            l.orden;
$$;

-- ---------- 3) el resumen: una fila por proveedor, con las cuatro fuentes al lado ----------
create or replace function public.gv_imp_prov_cc_resumen()
returns table (prov text, empresa text,
               pedidos int, fob numeric, pagado numeric, pend_giro_directo numeric, falta numeric, saldo numeric,
               prox_embarque date, prox_llegada date, unidades int, m3 numeric, fob_difiere boolean,
               giros int, ultimo_giro date,
               hoja_movs int, hoja_desde date, hoja_hasta date, hoja_saldo numeric,
               ntl_movs int, ntl_girado numeric, ntl_recuperado numeric, ntl_ultimo date,
               papa_real numeric, papa_banco numeric, papa_banco_factura text, papa_banco_bl date,
               papa_futuro numeric, papa_fecha date)
language sql stable security definer set search_path = public as $$
  with cc as (
    select public.gv_imp_prov_canon(c.proveedor) prov,
           count(*)::int pedidos, sum(c.fob) fob, sum(c.pagado) pagado,
           sum(c.pend_giro_directo) pend_giro_directo, sum(c.falta) falta,
           min(c.fecha_embarque) filter (where c.fecha_embarque >= current_date) prox_embarque,
           min(c.fecha_llegada)  filter (where c.fecha_llegada  >= current_date) prox_llegada,
           sum(c.unidades)::int unidades, sum(c.m3) m3, bool_or(c.fob_difiere) fob_difiere
      from public.gv_imp_cuenta_corriente c group by 1),
  gi as (
    select public.gv_imp_prov_canon(p.proveedor) prov, count(*)::int giros, max(p.fecha) ultimo_giro
      from public."GV_Imp_Pagos" p group by 1),
  ho as (
    select public.gv_imp_prov_canon(pm.proveedor) prov, count(*)::int hoja_movs,
           min(pm.fecha) hoja_desde, max(pm.fecha) hoja_hasta,
           (array_agg(pm.saldo order by pm.fila desc))[1] hoja_saldo
      from public."GV_Imp_Prov_Mov" pm group by 1),
  nt as (
    select public.gv_imp_prov_canon(n.proveedor) prov, count(*)::int ntl_movs,
           sum(n.debito)  filter (where n.clase = 'giro')     ntl_girado,
           sum(n.credito) filter (where n.clase = 'recupero') ntl_recuperado,
           max(n.fecha) ntl_ultimo,
           mode() within group (order by n.empresa) filter (where n.empresa in ('TN', 'CH')) empresa
      from public.gv_imp_ntl_cuenta n
     where n.hoja = 'NTL' and n.clase in ('giro', 'recupero') and n.proveedor is not null
       and not exists (select 1 from public."GV_Imp_Prov_Alias" a
                        where lower(a.alias) = lower(n.proveedor) and a.es_empresa)
     group by 1),
  pa0 as (
    select public.gv_imp_prov_canon(d.proveedor) prov, d.*
      from public."GV_Imp_CC_Deuda" d),
  provs as (
    select prov from cc union select prov from gi union select prov from ho union select prov from nt),
  -- "formato papá" escribe 'Hugo' donde el módulo dice 'Hugo Wong': se casa por nombre canónico o por
  -- primera palabra (sin alias en GV_Imp_Prov_Alias, que es dato y lo carga Thomas).
  pa as (
    select p.prov,
           sum(d.fob - d.pagado) filter (where d.estado = 'real')   papa_real,
           sum(d.fob - d.pagado) filter (where d.estado = 'banco')  papa_banco,
           string_agg(d.factura, ' / ') filter (where d.estado = 'banco' and d.factura is not null) papa_banco_factura,
           max(d.bl) filter (where d.estado = 'banco') papa_banco_bl,
           sum(d.fob - d.pagado) filter (where d.estado = 'futuro') papa_futuro,
           max(d.snapshot_fecha) papa_fecha,
           max(d.empresa) empresa
      from provs p
      join pa0 d on lower(d.prov) = lower(p.prov)
                 or lower(p.prov) like lower(d.prov) || ' %'
     group by p.prov)
  select p.prov, coalesce(pa.empresa, nt.empresa) empresa,
         coalesce(cc.pedidos, 0), round(coalesce(cc.fob, 0), 2), round(coalesce(cc.pagado, 0), 2),
         round(coalesce(cc.pend_giro_directo, 0), 2), round(coalesce(cc.falta, 0), 2),
         round(coalesce(cc.fob, 0) - coalesce(cc.pagado, 0), 2) saldo,
         cc.prox_embarque, cc.prox_llegada, coalesce(cc.unidades, 0), round(coalesce(cc.m3, 0), 3),
         coalesce(cc.fob_difiere, false),
         coalesce(gi.giros, 0), gi.ultimo_giro,
         coalesce(ho.hoja_movs, 0), ho.hoja_desde, ho.hoja_hasta, ho.hoja_saldo,
         coalesce(nt.ntl_movs, 0), round(coalesce(nt.ntl_girado, 0), 2), round(coalesce(nt.ntl_recuperado, 0), 2), nt.ntl_ultimo,
         round(pa.papa_real, 2), round(pa.papa_banco, 2), pa.papa_banco_factura, pa.papa_banco_bl,
         round(pa.papa_futuro, 2), pa.papa_fecha
    from provs p
    left join cc on cc.prov = p.prov
    left join gi on gi.prov = p.prov
    left join ho on ho.prov = p.prov
    left join nt on nt.prov = p.prov
    left join pa on pa.prov = p.prov
   order by (coalesce(cc.fob, 0) - coalesce(cc.pagado, 0)) desc, coalesce(nt.ntl_girado, 0) desc, p.prov;
$$;

grant execute on function public.gv_imp_prov_cc_libro(text) to anon, authenticated;
grant execute on function public.gv_imp_prov_cc_resumen() to anon, authenticated;

-- ---------- chequeo (correr como anon, que es la identidad del navegador) ----------
-- set role anon;
-- select prov, empresa, pedidos, fob, pagado, pend_giro_directo, falta, saldo, hoja_movs, ntl_movs
--   from public.gv_imp_prov_cc_resumen();
-- select fuente, fecha, concepto, carga, canal, fob, pago, saldo, saldo_excel
--   from public.gv_imp_prov_cc_libro('Hugo Wong');
-- reset role;
--
-- Al 26/09 (medido): Hugo Wong → 2 PI (38.640 + 600) · pagado 17.041 · saldo 22.199 · 0 filas de hoja ·
-- 24 movs NTL. Ownland → 1 PI 49.291,44 · pagado 14.000 · saldo 35.291,44 · 21 filas de hoja (saldo hoja
-- 34.956,08 al 03/06). Becky → 2 PI · 1 giro de 7.359 · 0 filas de hoja (la hoja Becky del Excel no se
-- importó) · 17 movs NTL.
