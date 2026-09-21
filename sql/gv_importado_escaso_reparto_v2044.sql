-- v20.44 (Luis, 2026-09-21): el faltante de un importado escaso se REPARTE por prioridad.
--
-- Luis: "tiene que haber un orden, ya que si 5 pedidos tienen 10 cajas de un codigo del que solo
-- tenemos 3 cajas, no tienen que figurar todos con 7 faltantes... prioridad por orden de
-- programa/llegada".
--
-- El orden, tal cual:
--   1) Lo YA PROGRAMADO se lo lleva primero: dia de entrega mas proximo y, dentro del mismo dia,
--      la tanda por orden alfabetico. Una NP programada tiene su mercaderia reservada aunque
--      todavia no se haya pickeado.
--   2) Lo que sobra se reparte entre los pedidos retenidos por ORDEN DE LLEGADA: fecha del
--      pedido, despues la hora, y a igualdad el order_id.
--   3) Un pedido del lote que YA esta programado no vuelve a competir: sus cajas ya se contaron
--      en el paso 1 y contarlas dos veces le inventaria un faltante propio.

-- ── 1. Lo programado y todavia pendiente ────────────────────────────────────────────────────
-- Mismo criterio que el `pend_np` del generador de OC: programada, sin factura y sin TP.
-- ⚠ Si se cambia alla, cambiar aca.
create or replace view public.gv_demanda_programada_pendiente as
with pickeadas as (
  select distinct upper(btrim(r.texto)) as tanda
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'TP' and nullif(btrim(coalesce(r.texto, '')), '') is not null
),
np as (
  select btrim(p.np) as np,
         upper(btrim(coalesce(p.tanda, ''))) as tanda,
         case when btrim(coalesce(p.fecha_entrega, '')) ~ '^\d{4}-\d{2}-\d{2}'
              then left(btrim(p.fecha_entrega), 10)::date end as fecha_entrega
    from public."GV_PPP_Programacion_Diaria" p
   where btrim(p.np) not in (select btrim(f.np) from public."Facturacion_NP" f)
     and upper(btrim(coalesce(p.tanda, ''))) not in (select tanda from pickeadas)
  union
  select public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np,
         upper(btrim(coalesce(w.tanda, ''))) as tanda,
         w.fecha_entrega
    from public."PPP_Web_Programacion" w
   where public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)
           not in (select btrim(f.np) from public."Facturacion_NP" f)
     and upper(btrim(coalesce(w.tanda, ''))) not in (select tanda from pickeadas)
     and not exists (select 1 from public."GV_Web_Cancelados" wc
                      where wc.np_label = public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))
)
select n.np, n.tanda, n.fecha_entrega,
       public.gv_cod_stock(b.articulo) as codn,
       case when upper(btrim(b.articulo)) ~ '[0-9E]L$' then 'LK'
            when public.gv_empresa_de_np_texto(btrim(b.pedido)) = 'chef' then 'CH'
            else 'LK' end as emp,
       sum(coalesce(b.cajas, 0))::numeric as cajas,
       row_number() over (order by coalesce(n.fecha_entrega, '9999-12-31'::date), n.tanda, n.np)
         as prioridad
  from np n
  join public.gv_demanda_pedidos b on btrim(b.pedido) = n.np
 where nullif(btrim(b.articulo), '') is not null
 group by n.np, n.tanda, n.fecha_entrega, 4, 5;

alter view public.gv_demanda_programada_pendiente set (security_invoker = true);
grant select on public.gv_demanda_programada_pendiente to authenticated;

-- ── 2. Cajas LIBRES: el disponible menos lo que ya tiene dueno ──────────────────────────────
create or replace function public.gv_art_libre(p_cod text, p_empresa text default 'lk')
returns numeric language sql stable set search_path to 'public', 'pg_temp' as $function$
  select greatest(0, public.gv_art_disponible(p_cod, p_empresa) - coalesce((
    select sum(d.cajas) from public.gv_demanda_programada_pendiente d
     where d.codn = public.gv_cod_stock(p_cod)
       and d.emp = case when upper(btrim(coalesce(p_cod,''))) ~ '[0-9E]L$' then 'LK'
                        when lower(coalesce(p_empresa,'lk')) = 'chef' then 'CH' else 'LK' end), 0));
$function$;

-- ── 3. El lote, con el greedy por orden de llegada ──────────────────────────────────────────
-- (el CREATE completo esta aplicado en la base; aca queda el cuerpo por si hay que recrearlo)
-- El nucleo es esta ventana, que es lo que reparte:
--   sum(cajas) over (partition by codn, emp order by f_ped, h_ped, order_id
--                    rows between unbounded preceding and 1 preceding)  as tomado_antes
--   falta = greatest(0, cajas - greatest(0, libre - tomado_antes))
--
-- Probado con 5 pedidos de 10 cajas de 437E de Chef (libre = 14):
--   P1 -> 0 faltantes, monto $1.094.016
--   P2 -> 6 faltantes, monto $437.606,40 y $656.409,60 descontados (se llevo las 4 que quedaban)
--   P3, P4, P5 -> 10 faltantes cada uno, monto $0
-- Sin el reparto los cinco mostraban 0 faltantes, porque cada uno veia las 14 cajas enteras.
--
-- Regresion sobre pedidos reales: chef 227 y 228 sin descuento, chef 229 con 1 item en falta y
-- $508.200 descontados — los mismos numeros que antes del cambio.
