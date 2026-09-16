/* ============================================================================
   gv_ppp_atrasados — los pedidos de un día que YA PASÓ y de los que todavía no
   se registró la salida.  (v18.77, pedido de Luis 2026-09-16)

   Alimenta el submódulo "Pedidos atrasados", arriba de "Programación de
   entregas": una fila por día vencido, y adentro sus tandas y sus NP, con el
   mismo formato que la tabla de días. La fila del día aparece sola cuando el
   día pasa y quedó algo sin salir; desaparece sola cuando esa NP se carga al
   camión.

   ── Qué cuenta como "no se registró la salida" ──────────────────────────────
   Carga Camión (CCN) sin una vuelta posterior, y sin Recepción Remitos (CRN):

     · sin CCN                          → nunca se cargó            → ATRASADO
     · CCN y después FSS («↩ sin salida») → se cargó y VOLVIÓ al depósito → ATRASADO
     · CCN vigente, sin CRN             → salió, falta el remito     → no
     · CRN                              → entregado                 → no

   ⚠ El FSS no es un detalle: el 2026-09-16 Luis vio la NP 98668 (Nexxo) ofrecida
   en Carga Camión y eso destapó que un conteo que mirara sólo el CCN la daba por
   salida. Tuvo CCN el 11/09 10:28 y FSS el 14/09 10:04 — volvió al depósito, y la
   pantalla del operario hacía bien en ofrecerla.

   ⚠ Y las NP se comparan NORMALIZADAS. La NP web viaja con espacio ("LK 0003") y
   el `.0` de ISIS aparece y desaparece ("98651" / "98651.0"). Comparar el texto
   crudo hace que NINGUNA NP web matchee y que todas se cuenten como atrasadas:
   ese error dio 24 atrasados donde había 18, ese mismo día y en la misma sesión.

   ── Desde cuándo mira ───────────────────────────────────────────────────────
   NO se puede barrer todo el histórico: antes de que los operarios pasaran a
   Gestión (2026-09-07) la Carga Camión casi no se registraba, así que la falta
   de CCN no prueba nada. Medido hacia atrás: junio 274 "sin salida", mayo 424,
   abril 290 — pedidos que salieron y se entregaron hace meses. Por eso hay un
   piso, configurable sin tocar código:

     PPP_Web_Config.clave = 'atrasados_desde'  (valor_texto 'YYYY-MM-DD')

   Para correrlo:  update public."PPP_Web_Config"
                      set valor_texto = '2026-08-01' where clave = 'atrasados_desde';

   ── Forma de la salida ──────────────────────────────────────────────────────
   Las MISMAS columnas que `gv_ppp_prog_arbol`, en el mismo orden, más
   `dias_atraso`. Así el front arma el árbol día → tanda → NP con el mismo
   código que usa para los días futuros, y las dos tablas no pueden divergir.
   ============================================================================ */

insert into public."PPP_Web_Config" (clave, valor_texto)
select 'atrasados_desde', '2026-09-01'
 where not exists (select 1 from public."PPP_Web_Config" where clave = 'atrasados_desde');

create or replace function public.gv_ppp_atrasados(p_desde date default null)
returns table(
  fecha date, tanda text, np text, np_num numeric, cod text, razon_social text,
  localidad text, zona text, zona_corta text, empresa text, origen text, m3 numeric,
  estado text, estado_orden integer, clave text, pide_horario boolean,
  horario_fecha date, horario_franja text, horario_origen text, barrio text,
  fecha_pedido date, dias_atraso integer
)
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
with cfg as (
  select coalesce(
           p_desde,
           (select nullif(btrim(c.valor_texto), '')::date
              from public."PPP_Web_Config" c where c.clave = 'atrasados_desde'),
           date '2026-09-01'
         ) as desde,
         (now() at time zone 'America/Argentina/Buenos_Aires')::date as hoy
),
/* El universo es el MISMO árbol de la programación, mirado hacia atrás: así un
   pedido atrasado se ve igual que cuando estaba a futuro (misma tanda, mismo
   estado, mismo m³) y las dos tablas suman lo mismo. */
arbol as (
  select a.* from cfg, public.gv_ppp_prog_arbol(cfg.desde, cfg.hoy - 1) a
),
/* Último CCN, último FSS y último CRN por NP. Se normaliza igual de los dos
   lados: mayúsculas, sin espacios de más y sin el `.0` final. */
ev as (
  select regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np,
         max(r.ts_cliente) filter (where r.opcion = 'CCN') as ccn,
         max(r.ts_cliente) filter (where r.opcion = 'FSS') as fss,
         max(r.ts_cliente) filter (where r.opcion = 'CRN') as crn
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN', 'FSS', 'CRN')
     and coalesce(btrim(r.legajo), '') not in ('0', '1')   -- legajos de prueba
     and btrim(coalesce(r.texto, '')) <> ''
   group by 1
)
select a.fecha, a.tanda, a.np, a.np_num, a.cod, a.razon_social,
       a.localidad, a.zona, a.zona_corta, a.empresa, a.origen, a.m3,
       a.estado, a.estado_orden, a.clave, a.pide_horario,
       a.horario_fecha, a.horario_franja, a.horario_origen, a.barrio,
       a.fecha_pedido,
       ((select hoy from cfg) - a.fecha)::integer as dias_atraso
  from arbol a
  left join ev e on e.np = regexp_replace(upper(btrim(a.np)), '\.0+$', '')
 where e.crn is null                                        -- no entregado
   and (e.ccn is null or e.ccn < coalesce(e.fss, '-infinity'))   -- sin carga vigente
 order by a.fecha desc, a.tanda, a.np_num nulls last, a.np;
$function$;

revoke all on function public.gv_ppp_atrasados(date) from public;
grant execute on function public.gv_ppp_atrasados(date) to anon, authenticated, service_role;

comment on function public.gv_ppp_atrasados(date) is
  'Pedidos de días ya vencidos sin salida registrada (sin CCN vigente y sin CRN). '
  'Un CCN seguido de FSS no cuenta como salida: la NP volvió al depósito. Piso en '
  'PPP_Web_Config.atrasados_desde. Misma forma que gv_ppp_prog_arbol + dias_atraso.';
