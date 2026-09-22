-- ============================================================================
-- v20.96 (Thomas, 2026-09-22) — EL LOG DE CUARENTENA MUESTRA EL PEDIDO CANCELADO
--
-- Thomas, textual: "fijate que en «estado» aparezca cuando le cancelan/anulan un pedido".
--
-- QUÉ PASABA: el estado del log salía del ÚLTIMO EVENTO escrito en GV_Cuarentena_Log
-- (`entro` / `aprobado` / `devuelto` / `anulado`). El caso 'anulado' estaba contemplado
-- en el CASE desde siempre, pero NUNCA se escribió ese evento:
--
--   select count(*) from public."GV_Cuarentena_Log" where evento = 'anulado';   -- 0
--   select count(*) from public."GV_Pedidos_Anulados";                          -- 1
--   select count(*) from public."GV_Web_Cancelados";                            -- 7
--
-- O sea: 8 cancelaciones registradas y ninguna llegaba al log. Un pedido cancelado seguía
-- diciendo "retenido · — sigue retenido" para siempre, y el supervisor lo leía como un
-- pendiente suyo.
--
-- QUÉ SE HIZO: el estado se lee del HECHO, donde queda registrado, y no de un evento que
-- alguien tendría que haber copiado. CTE `canc`, que une las tres tablas de cancelación:
--   · GV_Web_Cancelados        (pedido web entero)
--   · GV_PPP_Web_NP_Cancelada  (una NP suelta de un pedido de varias)
--   · GV_Pedidos_Anulados      (el log de anulados, web e ISIS)
-- Con la clave normalizada por gv_cuarentena_clave, que es la que ya unifica `np98587` con
-- `98587`. Si hay cancelación, el estado es `cancelado` y "quién lo cerró" sale de ahí.
--
-- Es el mismo criterio de §"el log del paso que falló no está donde está el log del paso que
-- anduvo": preguntarse qué fila EXISTE cuando el hecho ocurre, y mirar ahí.
--
-- IMPACTO MEDIDO (ventana de 60 días, antes → después):
--   retenido  17 → 15     aprobado 35 → 35     cancelado  0 → 2
-- Los dos que cambiaron: `web LK 1503` (Clapera Alicia Raquel, cancelado el 21/09) y
-- `web LK 1375` (Andser Quimica SRL, cancelado el 15/09). Los dos con deuda, los dos
-- figurando como retenidos desde entonces.
--
-- El front acompaña: chip de filtro "🗑 Cancelados" y su color (`e-cancelado`).
--
-- Chequeo:
--   select estado, count(*) from public.gv_cuarentena_log(60) group by 1;
--   select np, razon_social, estado, cerrado_at, persona from public.gv_cuarentena_log(60)
--    where estado = 'cancelado';
-- ============================================================================

-- Se aplica SOBRE LA DEFINICIÓN VIVA (varias sesiones tocan estos objetos), es idempotente y
-- FALLA con un raise si el texto no matchea, en vez de escribir una versión vieja encima.
do $outer$
declare
  v_def text; v_new text;
  v_anc_res constant text := '  res as (   -- cascada de resolucion: primero el cod, que es la llave del nombre';
  v_anc_case constant text := '         case when r.ult_evento = ''anulado''  then ''anulado''';
  v_anc_from constant text := '    from res r
   where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())';
  v_cte text; v_case text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='gv_cuarentena_log';
  if v_def is null then raise exception 'no encuentro gv_cuarentena_log'; end if;
  if position('canc as (' in v_def) > 0 then raise notice 'ya tiene el CTE canc'; return; end if;
  if position(v_anc_res  in v_def) = 0 then raise exception 'no matchea el ancla res'; end if;
  if position(v_anc_case in v_def) = 0 then raise exception 'no matchea el ancla del case'; end if;
  if position(v_anc_from in v_def) = 0 then raise exception 'no matchea el ancla del from'; end if;

  v_cte := $cte$  canc as (   -- v20.96 (Thomas, 2026-09-22) -- LA CANCELACION VIVE EN SU PROPIA TABLA.
    -- El log mostraba "anulado" solo si alguien habia escrito el evento en GV_Cuarentena_Log, y
    -- eso NUNCA paso: 0 filas con evento='anulado' al 22/09, contra 8 pedidos cancelados entre
    -- las tres tablas. Un pedido cancelado seguia diciendo "retenido - sigue retenido" para
    -- siempre. Se lee el HECHO donde queda registrado, no donde alguien deberia haberlo copiado.
    select z.empresa, z.k,
           (array_agg(z.at     order by z.at desc))[1] as at,
           (array_agg(z.quien  order by z.at desc))[1] as quien,
           (array_agg(z.motivo order by z.at desc))[1] as motivo
      from (
        select c.empresa, public.gv_cuarentena_clave(c.order_id::text) k, c.creado_at at,
               nullif(btrim(coalesce(c.por,'')),'') quien, nullif(btrim(coalesce(c.motivo,'')),'') motivo
          from public."GV_Web_Cancelados" c
        union all
        select c.empresa, public.gv_cuarentena_clave(c.order_id::text), c.creado_at,
               nullif(btrim(coalesce(c.por,'')),''), nullif(btrim(coalesce(c.motivo,'')),'')
          from public."GV_PPP_Web_NP_Cancelada" c
        union all
        select a.empresa, public.gv_cuarentena_clave(a.clave::text), a.anulado_at,
               coalesce(nullif(btrim(coalesce(a.persona,'')),''), nullif(btrim(coalesce(a.por,'')),'')),
               nullif(btrim(coalesce(a.motivo,'')),'')
          from public."GV_Pedidos_Anulados" a
      ) z group by z.empresa, z.k
  ),
$cte$;

  v_case := $cs$         case when cn.at is not null then 'cancelado'
              when r.ult_evento = 'anulado'  then 'anulado'$cs$;

  v_new := replace(v_def, v_anc_res, v_cte || v_anc_res);
  v_new := replace(v_new, v_anc_case, v_case);
  v_new := replace(v_new,
    '         case when r.ult_evento in (''aprobado'',''devuelto'',''anulado'') then r.cerrado_at end,',
    '         case when cn.at is not null then cn.at
              when r.ult_evento in (''aprobado'',''devuelto'',''anulado'') then r.cerrado_at end,');
  v_new := replace(v_new,
    '         case when r.ult_evento in (''aprobado'',''devuelto'',''anulado'') then r.persona end,',
    '         case when cn.at is not null then cn.quien
              when r.ult_evento in (''aprobado'',''devuelto'',''anulado'') then r.persona end,');
  v_new := replace(v_new,
    '         case when r.ult_evento in (''aprobado'',''devuelto'',''anulado'') then r.por end,',
    '         case when cn.at is not null then coalesce(cn.quien, ''(sin registrar)'')
              when r.ult_evento in (''aprobado'',''devuelto'',''anulado'') then r.por end,');
  v_new := replace(v_new, v_anc_from,
    '    from res r
    left join canc cn on cn.empresa = r.empresa and cn.k = r.k
   where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())');

  if v_new = v_def then raise exception 'el reemplazo no cambio nada'; end if;
  execute v_new;
end $outer$;
