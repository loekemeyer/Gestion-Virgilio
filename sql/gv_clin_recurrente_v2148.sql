-- v21.48 (Luis, 23/09): el CLIENTE NUEVO RECURRENTE no se vuelve a analizar.
--
-- "ese cliente nuevo esta en su segundo pedido. Esta bien que quede retenido en el modulo de
--  clientes nuevos pero no hace falta volver a hacer el analisis. Para clientes nuevos
--  recurrentes (que todavia no tienen 3 pedidos completados) deberia directamente abrir el
--  'que sigue' en speech 1, speech 2 y agregar la opcion de marcarlo como referido"
--
-- Caso: web LK 1448 · Silvano Lucas Martin (LK 4282), GV_Clientes_Nuevos.pedidos = 1 → 2.º pedido,
-- y el pipeline lo mostraba en «Sin analizar» porque su 1.er pedido es anterior al pipeline
-- (no hay decision que heredar).
--
-- Regla: si el pedido no tiene decision propia ni heredada y el cliente YA tiene 1 o 2 pedidos
-- facturados (GV_Clientes_Nuevos.pedidos >= 1), la decision efectiva es 'no_referenciado':
-- paga por adelantado y arranca en el Speech 1. Sigue pudiendo marcarse REFERENCIADO en cualquier
-- etapa (gv_clin_etapa ya le da prioridad a 'referenciado' sobre los speech).
--
-- Se aplica sobre la definicion VIVA del 23/09 (pg_get_functiondef). Como agrega columnas de
-- salida (recurrente, pedidos_previos) es DROP + CREATE; se reponen los grants que tenia
-- (authenticated, service_role).

begin;
drop function public.gv_clin_pipeline_lote(jsonb);
CREATE FUNCTION public.gv_clin_pipeline_lote(p_pedidos jsonb)
 RETURNS TABLE(empresa text, order_id text, etapa text, reloj_desde timestamp with time zone, vencido boolean, decision text, decision_persona text, decision_at timestamp with time zone, analisis_at timestamp with time zone, speech1_at timestamp with time zone, speech2_at timestamp with time zone, pagado_at timestamp with time zone, cerrado_at timestamp with time zone, cerrado_motivo text, aprobado boolean, vinc_empresa text, vinc_cod text, vinc_razon_social text, cli_analisis_at timestamp with time zone, cli_analisis_np text, cli_decision text, cli_decision_at timestamp with time zone, cli_decision_persona text, cli_decision_np text, analisis_heredado boolean, decision_heredada boolean, recurrente boolean, pedidos_previos integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with cfg as (
    select coalesce((select valor from public."PPP_Web_Config" where clave='clin_speech_horas'), 24)::int   as h_speech,
           coalesce((select valor from public."PPP_Web_Config" where clave='clin_analisis_horas'), 24)::int as h_analisis),
  ped as (
    select lower(coalesce(e->>'empresa','lk')) as empresa,
           public.gv_cuarentena_clave(nullif(btrim(e->>'order_id'),'')) as order_id,
           regexp_replace(btrim(coalesce(e->>'cod','')), '\.0+$', '') as cod
      from jsonb_array_elements(coalesce(p_pedidos,'[]'::jsonb)) e
     where nullif(btrim(e->>'order_id'),'') is not null),
  fila as (
    select p.empresa, p.order_id, p.cod, t.*,
           exists (select 1 from public."GV_Cuarentena_Liberados" lb
                    where lb.empresa = p.empresa
                      and public.gv_cuarentena_clave(lb.order_id) = p.order_id) as aprobado,
           -- v21.48: pedidos ya facturados del cliente (1 o 2 = recurrente; al 3.º sale de la tabla)
           coalesce((select max(cn.pedidos) from public."GV_Clientes_Nuevos" cn
                      where cn.empresa = p.empresa
                        and regexp_replace(btrim(coalesce(cn.cod,'')), '\.0+$','') = p.cod), 0) as ped_prev
      from ped p
      left join lateral (
        select x.analisis_at, x.decision, x.decision_at, x.decision_persona,
               x.speech1_at, x.speech2_at, x.pagado_at, x.cerrado_at, x.cerrado_motivo
          from public."GV_Cliente_Nuevo_Pipeline" x
         where x.empresa = p.empresa and x.order_id = p.order_id) t on true),
  hist as (
    select f.*,
           ha.analisis_at as cli_analisis_at, ha.np as cli_analisis_np,
           hd.decision as cli_decision, hd.decision_at as cli_decision_at,
           hd.decision_persona as cli_decision_persona, hd.np as cli_decision_np
      from fila f
      left join lateral (
        select y.analisis_at, y.np from public."GV_Cliente_Nuevo_Pipeline" y
         where y.empresa = f.empresa
           and regexp_replace(btrim(coalesce(y.cod,'')), '\.0+$','') = f.cod
           and y.order_id <> f.order_id and y.analisis_at is not null
         order by y.analisis_at desc limit 1) ha on true
      left join lateral (
        select y.decision, y.decision_at, y.decision_persona, y.np
          from public."GV_Cliente_Nuevo_Pipeline" y
         where y.empresa = f.empresa
           and regexp_replace(btrim(coalesce(y.cod,'')), '\.0+$','') = f.cod
           and y.order_id <> f.order_id and y.decision is not null
         order by y.decision_at desc limit 1) hd on true),
  eta as (
    select h.*, coalesce(h.analisis_at, h.cli_analisis_at) as analisis_ef,
           -- v21.48: recurrente sin decision -> no_referenciado (arranca en el Speech 1)
           coalesce(h.decision, h.cli_decision,
                    case when h.ped_prev >= 1 then 'no_referenciado' end) as decision_ef,
           (h.analisis_at is null and h.cli_analisis_at is not null) as heredado,
           (h.decision is null and h.cli_decision is not null)       as dec_heredada,
           (h.ped_prev >= 1)                                          as recurrente
      from hist h),
  eta2 as (
    select e.*, public.gv_clin_etapa(e.analisis_ef, e.decision_ef, e.speech1_at,
                                     e.speech2_at, e.pagado_at, e.cerrado_at, e.aprobado) as etapa
      from eta e)
  select e.empresa, e.order_id, e.etapa,
         public.gv_clin_reloj(e.etapa, e.analisis_ef, e.speech1_at, e.speech2_at),
         case when public.gv_clin_reloj(e.etapa, e.analisis_ef, e.speech1_at, e.speech2_at) is null then false
              when e.heredado and e.etapa = 'analisis' then false
              else now() - public.gv_clin_reloj(e.etapa, e.analisis_ef, e.speech1_at, e.speech2_at)
                   > make_interval(hours => case when e.etapa='analisis' then c.h_analisis else c.h_speech end) end,
         e.decision_ef,
         coalesce(e.decision_persona, case when e.dec_heredada then e.cli_decision_persona end),
         coalesce(e.decision_at, case when e.dec_heredada then e.cli_decision_at end),
         e.analisis_ef, e.speech1_at, e.speech2_at, e.pagado_at, e.cerrado_at, e.cerrado_motivo,
         e.aprobado, v.vinc_empresa, v.vinc_cod, v.vinc_razon_social,
         e.cli_analisis_at, e.cli_analisis_np,
         e.cli_decision, e.cli_decision_at, e.cli_decision_persona, e.cli_decision_np,
         e.heredado, e.dec_heredada, e.recurrente, e.ped_prev::int
    from eta2 e cross join cfg c
    left join public."GV_Cliente_Vinculo" v
      on v.activo and v.empresa = e.empresa and v.cod = e.cod;
$function$;
revoke all on function public.gv_clin_pipeline_lote(jsonb) from public, anon;
grant execute on function public.gv_clin_pipeline_lote(jsonb) to authenticated, service_role;
commit;

-- centinela
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_clin_pipeline_lote','funcion','ped_prev >= 1',
        'cliente nuevo recurrente (1-2 pedidos facturados) sin decision arranca en Speech 1, no en Sin analizar',
        'Luis','v21.48');

-- rollback: re-crear la definicion de sql/gv_clin_dos_estados_v2086.sql (o la viva del 23/09
-- sin las columnas recurrente/pedidos_previos).
