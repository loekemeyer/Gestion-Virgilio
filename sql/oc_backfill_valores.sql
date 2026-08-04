-- =====================================================================
-- oc_backfill_valores.sql — rellenar los valores del impreso de OC (uso one-shot).
--
-- El impreso de la OC (v7.39/v7.40/v7.42) muestra Falta Pedidos, Uni x Caja, Caja N°
-- y % Lleno a partir de columnas guardadas en cada línea: oc_max / oc_pedidos /
-- oc_stock / oc_uni_caja / oc_ncaja. Las OCs generadas por el generador ya las traen;
-- pero las creadas ANTES de v7.39 (o a mano) no → el impreso mostraba "—" en esas
-- columnas (reportado por el usuario en la OC de Oscar del 29/07).
--
-- `oc_backfill_valores(p_solo_null)` calcula esos valores con la MISMA fórmula del
-- generador (Máximo = proy×índice topado a capacidad; Pedidos = demanda neteada por
-- picking terminado; Stock = góndola+a_guardar+racks+excedente; Uni x Caja =
-- OC_Maximos.uni_x_caja; Caja N° = N_Caja más frecuente de Articulos_Cajas) y los
-- escribe en las OCs que matchean por código normalizado.
--   • p_solo_null = true  → sólo las filas SIN valores (oc_max is null): uso one-shot,
--                           no pisa lo que ya guardó el generador NI los valores
--                           congelados de las OCs viejas.
--   • p_solo_null = false → recalcula TODAS (menos las 'recibida').
-- NUNCA toca `cantidad` (las cajas a pedir son fijas). No refresca OCs 'recibida'.
-- Devuelve la cantidad de filas actualizadas.
--
-- ⚠ CONGELADO (v7.42): Falta Pedidos y % Lleno se llenan AL MOMENTO DE GENERAR y
-- quedan fijos (reflejan el estado del día de la OC, como pidió el usuario). Por eso
-- se ELIMINÓ el cron diario 'oc-backfill-diario' que los refrescaba con datos de hoy.
-- Esta función queda como herramienta MANUAL de reparación (rellenar una OC vieja o
-- cargada a mano). El default seguro es p_solo_null=true, que sólo toca filas nunca
-- rellenadas y no pisa nada congelado.
--
-- One-shot ejecutado 2026-08-04: 101 OCs rellenadas (oc_max/pedidos/stock/uni_caja).
-- One-shot v7.42 (2026-08-04): oc_ncaja rellenado en las OCs existentes con un UPDATE
--   dirigido SÓLO a esa columna (92/101 con dato; el resto sin match en Articulos_Cajas),
--   sin tocar los valores dinámicos ya congelados.
--
-- ⚠ La definición VIVA está en la migración de Supabase; esta es la copia del repo.
-- =====================================================================
create or replace function public.oc_backfill_valores(p_solo_null boolean default true)
returns integer language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_n integer;
begin
  with norm as (
    select regexp_replace(upper(btrim(m.cod)), '^0+(?=.)', '') as codn,
           coalesce(m.max_cajas, 0)::numeric as max_excel,
           case when coalesce(m.indice, 0) > 0 then m.indice::numeric else 1.5 end as indice,
           coalesce(m.uni_x_caja, 0)::numeric as uni_caja
      from public."OC_Maximos" m
     where m.activo and nullif(btrim(m.cod), '') is not null
  ),
  stk as (
    select regexp_replace(upper(btrim(cod_art)), '^0+(?=.)', '') as codn,
           sum(coalesce(terminado,0)+coalesce(a_guardar,0)+coalesce(racks,0)+coalesce(excedente,0)) as stock
      from public.vista_saldos_stock group by 1
  ),
  pickeadas as (
    select distinct upper(btrim(texto)) as tanda from public."Registros_Produccion_Virgilio"
     where opcion = 'TP' and nullif(btrim(coalesce(texto,'')),'') is not null
  ),
  pend_np as (
    select distinct btrim(p.np) as np from public."PPP_Programacion_Diaria" p
     where btrim(p.np) not in (select btrim(np) from public."Facturacion_NP")
       and upper(btrim(coalesce(p.tanda,''))) not in (select tanda from pickeadas)
  ),
  dem as (
    select regexp_replace(upper(btrim(b.articulo)),'^0+(?=.)','') as codn, sum(coalesce(b.cajas,0)) as pedidos
      from public."PPP_Base_Pedidos" b join pend_np n on btrim(b.pedido)=n.np
     where nullif(btrim(b.articulo),'') is not null group by 1
  ),
  proy as (
    select regexp_replace(upper(btrim(cod)),'^0+(?=.)','') as codn, max(coalesce(proy_cajas_mes,0))::numeric as proy
      from public.proyeccion_madre group by 1
  ),
  cap as (
    select regexp_replace(upper(btrim(cod)),'^0+(?=.)','') as codn, sum(coalesce(cajas_max,0))::numeric as cap
      from public."Capacidad_Sector" group by 1
  ),
  ncaja as (   -- v7.42: N_Caja más frecuente por código (desempate: la más chica)
    select distinct on (codn) codn, n_caja from (
      select regexp_replace(upper(btrim("Cod_Art")),'^0+(?=.)','') as codn, "N_Caja" as n_caja, count(*) as c
        from public."Articulos_Cajas" where "N_Caja" is not null group by 1,2
    ) t order by codn, c desc, n_caja
  ),
  val as (
    select n.codn, n.uni_caja, nc.n_caja, coalesce(d.pedidos,0) as pedidos, coalesce(s.stock,0) as stock,
           least(ceil(case when p.proy is not null and p.proy>0 then p.proy*n.indice else n.max_excel end),
                 coalesce(nullif(c.cap,0),1e9)) as maximo
      from norm n
      left join stk s on s.codn=n.codn left join dem d on d.codn=n.codn
      left join proy p on p.codn=n.codn left join cap c on c.codn=n.codn
      left join ncaja nc on nc.codn=n.codn
  )
  update public."Ordenes_Compra" oc
     set oc_max = v.maximo, oc_pedidos = v.pedidos, oc_stock = v.stock,
         oc_uni_caja = v.uni_caja, oc_ncaja = v.n_caja
    from val v
   where regexp_replace(upper(btrim(oc.codigo)),'^0+(?=.)','') = v.codn
     and coalesce(oc.estado,'') <> 'recibida'
     and (not p_solo_null or oc.oc_max is null);
  get diagnostics v_n = row_count;
  return v_n;
end $fn$;

revoke all on function public.oc_backfill_valores(boolean) from public;
grant execute on function public.oc_backfill_valores(boolean) to authenticated;

-- ⚠ El cron diario 'oc-backfill-diario' fue ELIMINADO en v7.42 (valores congelados).
-- Si quedara alguno colgado, esto lo saca:
select cron.unschedule(jobid) from cron.job where jobname = 'oc-backfill-diario';
