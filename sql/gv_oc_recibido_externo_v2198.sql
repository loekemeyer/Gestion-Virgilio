-- v21.98 — OC: la mercadería que entrega un EXTERNO (proveedor sin OC de ese código
-- en esa ventana) descuenta de la OC del/los ASIGNADO(S) — los que tienen la OC vigente.
-- Si hay varios asignados, se reparte en cajas ENTERAS, proporcional al SPLIT asignado a cada
-- proveedor (OC_Maximos.prop_prov1/2), método de restos mayores: 3 cajas 50/50 → 2 y 1; 10 con 70/30 → 7 y 3.
-- Además: con p_cod, se recalculan TODAS las OC del código (no sólo las del proveedor que
-- entregó), porque la entrega de un externo mueve la OC de otro.
-- FORWARD-FACING (pedido 23/09): sólo cuentan entregas externas con fecha >= 2026-09-23;
-- las OC viejas no se completan con entregas viejas.
-- Base: pg_get_functiondef viva del 23/09 (incluye GV_OC_Fabrica_Para, v21.22).
CREATE OR REPLACE FUNCTION public.gv_oc_recompute_recibido(p_nombre text DEFAULT NULL::text, p_cod text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  n_updated int := 0;
  k_filtro text[];
  cod_filtro text;
begin
  cod_filtro := case when p_cod is not null then norm_cod(p_cod) end;
  -- v21.98: con código, todas las OC del código (la entrega externa mueve la OC del asignado)
  k_filtro   := case when p_nombre is not null and cod_filtro is null then gv_norm_prov_keys(p_nombre) end;

  with entregas as (
    select 'T'||id as eid, norm_cod("Cod") as cod, gv_norm_prov_keys("Nombre_Tall") as pk,
           coalesce("Fecha_RTO",
             case when "Fecha" ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then "Fecha"::date end) as f,
           coalesce("Cajas",0) as caj
    from "Entregas Tallerista Virgilio"
    union all
    select 'P'||id, norm_cod("Cod_Art"), gv_norm_prov_keys("Proveedor"),
           coalesce("Fecha_RTO",
             case
               when "Dia_mes" ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2}$'  then to_date("Dia_mes",'DD/MM/YY')
               when "Dia_mes" ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$'  then to_date("Dia_mes",'DD/MM/YYYY')
               when "Dia_mes" ~ '^[0-9]{1,2}-[0-9]{1,2}$'          then to_date("Dia_mes"||'-'||extract(year from current_date)::text,'DD-MM-YYYY')
             end),
           coalesce("Cantidad",0)
    from "Entregas Prov AT"
  ),
  oc as (
    select o.id, o.cantidad, o.estado, o.fecha,
           norm_cod(o.codigo) as cod_n,
           gv_norm_prov_key(o.proveedor) as pkey,
           gv_norm_prov_keys(o.proveedor)
             || coalesce((select array_agg(gv_norm_prov_key(f.fabricante))
                            from "GV_OC_Fabrica_Para" f
                           where gv_norm_prov_key(f.recibe_la_oc) = gv_norm_prov_key(o.proveedor)),
                          '{}'::text[]) as pkeys
    from "Ordenes_Compra" o
    where nullif(trim(o.codigo),'') is not null and o.fecha is not null
      and (cod_filtro is null or norm_cod(o.codigo) = cod_filtro)
  ),
  oc_win as (
    select oc.*,
           least(
             coalesce(lead(oc.fecha) over (partition by oc.cod_n, oc.pkey order by oc.fecha, oc.id),
                      date '9999-12-31'),
             oc.fecha + 120
           ) as tope,
           (row_number() over (
              partition by oc.cod_n, oc.pkey order by (lower(coalesce(oc.estado,'')) in ('cerrada','anulada')), oc.fecha desc, oc.id desc
            ) = 1
            and lower(coalesce(oc.estado,'')) not in ('cerrada','anulada')) as es_ultima
    from oc
  ),
  propio as (
    select w.*,
           coalesce((
             select sum(e.caj)::int
             from entregas e
             where e.cod = w.cod_n and e.f is not null
               and e.f >= w.fecha and e.f < w.tope
               and gv_prov_match(w.pkeys, e.pk)
           ),0) as rec_propio
    from oc_win w
  ),
  -- v21.98: entrega EXTERNA = ninguna OC de ese código, en esa fecha, es de quien entregó
  ext as (
    select e.* from entregas e
    where e.f is not null and e.caj > 0
      and e.f >= date '2026-09-23'   -- FORWARD-FACING: sólo entregas desde el 23/09; lo viejo no completa OC
      and (cod_filtro is null or e.cod = cod_filtro)
      and not exists (select 1 from oc_win w
                       where w.cod_n = e.cod and e.f >= w.fecha and e.f < w.tope
                         and gv_prov_match(w.pkeys, e.pk))
  ),
  -- los ASIGNADOS: OC vigente del código cuya ventana cubre la fecha de la entrega
  cand as (
    select x.eid, x.caj, p.id,
           greatest(p.cantidad - p.rec_propio, 0) as falta, p.cantidad,
           -- el SPLIT asignado en ⚙ Configuraciones (OC_Maximos: prop_prov1 / prop_prov2)
           (select case when gv_prov_match(p.pkeys, gv_norm_prov_keys(m.proveedor))  then m.prop_prov1
                        when gv_prov_match(p.pkeys, gv_norm_prov_keys(m.proveedor2)) then m.prop_prov2 end
              from "OC_Maximos" m where norm_cod(m.cod) = p.cod_n limit 1)::numeric as pct
    from ext x
    join propio p on p.cod_n = x.cod and p.es_ultima and x.f >= p.fecha and x.f < p.tope
  ),
  -- peso = el split del proveedor. Si a algún asignado no se le encuentra el split (o suman 0),
  -- se reparte por lo que le falta recibir a cada OC; y si eso también es 0, por la cantidad de la OC.
  peso as (
    select c.*,
           case when bool_and(c.pct is not null) over (partition by c.eid)
                 and sum(c.pct) over (partition by c.eid) > 0 then c.pct
                when sum(c.falta) over (partition by c.eid) > 0 then c.falta
                else c.cantidad end::numeric as w
    from cand c
  ),
  cuota as (
    select p.*,
           p.caj * p.w / nullif(sum(p.w) over (partition by p.eid),0) as exacta
    from peso p
  ),
  base as (
    select q.*, floor(coalesce(q.exacta,0))::int as piso,
           q.caj - sum(floor(coalesce(q.exacta,0))::int) over (partition by q.eid) as sobra,
           row_number() over (partition by q.eid
                              order by coalesce(q.exacta,0) - floor(coalesce(q.exacta,0)) desc, q.w desc, q.id) as rn_resto
    from cuota q
  ),
  ext_asig as (
    select b.id, sum(b.piso + case when b.rn_resto <= b.sobra then 1 else 0 end)::int as rec_ext
    from base b group by b.id
  ),
  recibido as (
    select p.id,
           least(p.cantidad, p.rec_propio + coalesce(a.rec_ext,0)) as rec_cap,
           p.cantidad, p.estado, p.es_ultima
    from propio p
    left join ext_asig a on a.id = p.id
    where (k_filtro is null or gv_prov_match(p.pkeys, k_filtro))
  ),
  upd as (
    update "Ordenes_Compra" o
      set cantidad_recibida = r.rec_cap,
          estado = case
                     when lower(coalesce(o.estado,'')) = 'cerrada' then o.estado
                     when r.es_ultima and r.rec_cap >= r.cantidad then 'recibida'
                     when not r.es_ultima then 'anulada'
                     else 'pendiente'
                   end,
          fecha_entrega_real = case when r.rec_cap > 0 then coalesce(o.fecha_entrega_real, current_date)
                                    else o.fecha_entrega_real end
      from recibido r
      where o.id = r.id
        and (o.cantidad_recibida is distinct from r.rec_cap
             or o.estado is distinct from (case
                     when lower(coalesce(o.estado,'')) = 'cerrada' then o.estado
                     when r.es_ultima and r.rec_cap >= r.cantidad then 'recibida'
                     when not r.es_ultima then 'anulada'
                     else 'pendiente' end))
      returning 1
  )
  select count(*) into n_updated from upd;
  return n_updated;
end;
$function$;

-- APLICADO 23/09 (Luis). Nota: en la base el cuerpo dice "v21.96" en los comentarios (mismo código).
-- Backups: zz_backups."GV_Backup_fn_oc_recompute_20260923" (def anterior) y
--          zz_backups."GV_Backup_OrdenesCompra_20260923" (872 filas).
-- Verificado: recompute total cambia 0 OC · split 70/30 con 10 caj → 7/3, +3 caj → 9/4 ·
-- entrega propia sigue imputando · botón del celular (anon) muestra el pendiente descontado.
-- Rollback: execute (select def from zz_backups."GV_Backup_fn_oc_recompute_20260923");
-- Centinela: GV_Reglas_Centinela (gv_oc_recompute_recibido, patrón prop_prov2).
