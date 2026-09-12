-- ============================================================================
-- v16.04 — el stock del módulo de importados sale del DEPÓSITO REAL
-- Dueño, 12/09: "que lea el stock real".
--
-- Antes: v_importados_ordenes.stock_actual salía de Importados_Mov_Stock, un libro
-- propio (seed del Excel + un sync manual del 11/09) del que sólo se descontaban las
-- cajas de Entregas_Virgilio. Ajustes, facturado, racks, envasado y recepciones nunca
-- le llegaban → empataba el día del sync y se despegaba un poco por día.
--
-- Ahora: sale de vista_saldos_stock, la misma fuente que la pantalla de Stock.
-- v_importados_ordenes NO se toca (queda como rollback); el módulo pasa a leer
-- gv_importados_ordenes.
-- ============================================================================

-- 1) El stock real por código normalizado y empresa, en CAJAS.
--    Los 8 depósitos que suma la pantalla de Stock (vista_stock_procesada.stock_total):
--    terminado + excedente + separar_pedidos + a_facturar + a_guardar + racks +
--    racks_ch + para_envasar. `insumos` va aparte (lo usa gv_importados_stock_insumos).
create or replace view public.gv_importados_stock_dep
with (security_invoker = true) as
select public.gv_cod_stock(s.cod_art)                         as cod_norm,
       upper(coalesce(s.empresa, 'Mixto'))                    as empresa,
       sum(coalesce(s.terminado,0) + coalesce(s.excedente,0)
         + coalesce(s.separar_pedidos,0) + coalesce(s.a_facturar,0)
         + coalesce(s.a_guardar,0) + coalesce(s.racks,0)
         + coalesce(s.racks_ch,0) + coalesce(s.para_envasar,0))as cajas,
       sum(coalesce(s.insumos,0))                             as cajas_insumos
  from public.vista_saldos_stock s
 group by 1, 2;

comment on view public.gv_importados_stock_dep is
  'v16.04 — stock real del depósito por código normalizado (gv_cod_stock) y empresa, en cajas. Misma suma de depósitos que vista_stock_procesada.stock_total. Fuente del stock del módulo de importados.';

-- 2) La vista del motor de importados, con stock_actual = depósito real.
--    Copia de v_importados_ordenes salvo el bloque `mov`/`ventas`, que desaparece.
create or replace view public.gv_importados_ordenes
with (security_invoker = true) as
with cfg as (
  select meses_objetivo from public."Importados_Config" where id = 1
), fam as (
  select public.gv_cod_stock(cod_principal) as ppal,
         public.gv_cod_stock(cod_secundario) as sec
    from public."Equivalencias_Familia"
   where nullif(btrim(cod_principal),'') is not null
     and nullif(btrim(cod_secundario),'') is not null
), pe_raw as (
  select public.gv_cod_stock(cod) as cod_norm, empresa, proy_cajas_mes
    from public."GV_Proyeccion_Emp"
), pe as (
  select k.cod_norm, r.empresa, sum(r.proy_cajas_mes) as proy_cajas_mes
    from (select distinct cod_norm from pe_raw union select ppal from fam) k
    join pe_raw r on r.cod_norm = k.cod_norm
                  or r.cod_norm in (select f.sec from fam f where f.ppal = k.cod_norm)
   group by k.cod_norm, r.empresa
), partes as (
  select distinct upper(parte) as cod from public."Importados_Partes_Map"
), ch_rows as (
  select distinct upper(cod_art) as cod from public."Importados"
   where principal and activo and upper(coalesce(marca,'')) = 'CH'
), -- (a) ¿el código normalizado lo comparten DOS filas de Importados? Siempre es una LK
   --     y una CH (437E/437EL, 438E/438EL, 439E/439EL, 809E). Ahí el stock se parte por
   --     empresa; si la fila es única, se lleva todo (LK + CH + Mixto).
dup as (
  select public.gv_cod_stock(cod_art) as cod_norm
    from public."Importados" where principal and activo
   group by 1 having count(*) > 1
), stk as (
  select i.id,
         coalesce(sum(d.cajas), 0) as cajas
    from public."Importados" i
    left join public.gv_importados_stock_dep d
           on d.cod_norm = public.gv_cod_stock(i.cod_art)
          and (
                not exists (select 1 from dup where dup.cod_norm = public.gv_cod_stock(i.cod_art))
             or (upper(coalesce(i.marca,'')) = 'CH' and d.empresa = 'CH')
             or (upper(coalesce(i.marca,'')) <> 'CH' and d.empresa in ('LK','MIXTO'))
              )
   group by i.id
)
select i.id, i.cod_art, i.marca, i.proveedor, i.descripcion, i.fob_uni, i.uni_x_caja,
       i.principal, i.activo, i.notas, i.est_madre_seed, i.est_madre_override,
       i.pedido_manual,
       coalesce(i.pedido_curso, 0) as pedido_curso,
       case when upper(coalesce(i.marca,'')) = 'CH' then 'Chef' else 'Loeke' end as planta,
       case when p.proy_cajas_mes is not null
            then round(p.proy_cajas_mes * coalesce(i.uni_x_caja, 1)) end as est_madre_live,
       (select meses_objetivo from cfg) as meses_objetivo,
       coalesce(i.est_madre_override,
                case when p.proy_cajas_mes is not null
                     then round(p.proy_cajas_mes * coalesce(i.uni_x_caja, 1)) end,
                i.est_madre_seed, 0) as est_madre_eff,
       case when i.est_madre_override is not null then 'override'
            when p.proy_cajas_mes is not null then 'live'
            else 'seed' end as est_madre_fuente,
       -- v16.04: el stock es el del depósito, en unidades
       round(coalesce(st.cajas,0) * coalesce(i.uni_x_caja,0)) as stock_actual,
       coalesce(st.cajas, 0) as stock_cajas,
       coalesce(si.stock_uni, 0) as stock_insumos,
       pt.cod is not null as es_parte,
       case when pt.cod is not null and si.cod is not null then si.stock_uni
            else round(coalesce(st.cajas,0) * coalesce(i.uni_x_caja,0)) + coalesce(si.stock_uni,0)
       end as stock_total
  from public."Importados" i
  left join stk st on st.id = i.id
  left join pe p on p.cod_norm = public.gv_cod_stock(i.cod_art)
                and p.empresa = case when upper(coalesce(i.marca,'')) = 'CH' then 'chef' else 'lk' end
  left join partes pt on pt.cod = upper(i.cod_art)
  left join public.gv_importados_stock_insumos si
         on upper(si.cod) = upper(i.cod_art) and i.principal and i.activo
        and (upper(coalesce(i.marca,'')) = 'CH'
             or not exists (select 1 from ch_rows c where c.cod = upper(i.cod_art)));

comment on view public.gv_importados_ordenes is
  'v16.04 — motor de pedidos de importación. Igual a v_importados_ordenes pero stock_actual sale del DEPÓSITO REAL (gv_importados_stock_dep -> vista_saldos_stock), no del libro propio Importados_Mov_Stock. Agrega stock_cajas.';

grant select on public.gv_importados_stock_dep to anon, authenticated;
grant select on public.gv_importados_ordenes   to anon, authenticated;

-- ============================================================================
-- ROLLBACK: el front vuelve a `v_importados_ordenes` (que NO se tocó) cambiando
-- SUPABASE_IMPORTADOS_OC_ENDPOINT en index.html. Las dos vistas nuevas se pueden
-- dejar o dropear:
--   drop view if exists public.gv_importados_ordenes;
--   drop view if exists public.gv_importados_stock_dep;
--
-- POR QUÉ NO SE TOCÓ v_importados_ordenes: la usa Producción Virgilio
-- (repo loekemeyer/Produccion-Virgilio, index.html:12022, lectura REST con la anon
-- key). Protocolo del CLAUDE.md: sobre un objeto que usa Producción se AGREGA uno
-- nuevo con prefijo gv_, no se hace create or replace.
--
-- EFECTO MEDIDO (12/09/2026, 154 filas principal+activo):
--   122 filas sin cambio · 32 cambiaron.
--   Las dos grandes son PARTES y NO cambian el resultado: 505C stock_actual
--   262.400 -> 0 y 1000900 68.000 -> 0, pero su stock_total sigue siendo el del
--   depósito de insumos (130.000 y 107.500) porque para una parte manda el insumo.
--   026 +2.520 u y 027 +1.272 u: antes no cruzaban contra el depósito.
--   Las otras 28 son de 8 a 192 unidades (1 a 16 cajas): la deriva desde el sync
--   manual del 11/09.
--
-- BONUS: "marcar llegada" seguía insertando en Importados_Mov_Stock y sumaba stock
-- al módulo; la recepción real del depósito lo sumaba otra vez. Con esta vista el
-- módulo sólo mira el depósito, así que ese doble conteo desaparece. La RPC
-- importados_marcar_llegada no se tocó (la usa Producción) — ahora es inocua acá.
-- ============================================================================
