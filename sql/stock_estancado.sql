-- =====================================================================
--  stock_estancado.sql — Alerta Telegram "STOCK ESTANCADO" 👀
--
--  Avisa cuando algo quedó en un estado INTERMEDIO más días de lo normal:
--    · a_guardar        → llegó y no se pasó a góndola (MG)
--    · separar_pedidos  → se pickeó y no se separó/armó
--    · a_facturar       → se armó y no se facturó
--  Suele ser que ya lo hicieron físicamente y se olvidaron de marcarlo en la
--  app → el stock queda "trabado" en el depósito intermedio.
--
--  Solo TELEGRAM: el tablero Agentes ya muestra `mg_pendiente` (a guardar) y
--  `pipeline_atascado` (pickeado/a facturar) desde `generar_reporte_agentes`;
--  lo que faltaba era el aviso por Telegram. Umbral configurable en
--  `Stock_Config.dias_estancado` (default 2). Respeta el cutoff, excluye 0/1.
--  Lista los 15 más viejos + "… y N más". Dedup diario por el set (depósito|cod).
--
--  Encadenada al cron de agentes (jobid 14, 3×/día):
--    ... select public.reporte_agentes_stock_estancado();
--  SECURITY DEFINER + grant solo service_role (patrón de las demás alertas).
-- =====================================================================

create or replace function public.reporte_agentes_stock_estancado()
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  hoy     text := to_char((now() at time zone 'America/Argentina/Buenos_Aires')::date, 'YYYY-MM-DD');
  dias    int;
  n       int;
  detalle text;
  ids     text;
  extra   int;
begin
  select coalesce((select nullif(trim(valor), '')::int from public."Stock_Config" where clave = 'dias_estancado' limit 1), 2) into dias;
  if dias is null or dias < 1 then dias := 2; end if;

  with cfg as (select valor::timestamptz as cutoff from public."Stock_Config" where clave = 'cutoff_ts' limit 1),
  mv as (
    select m.deposito,
           upper(regexp_replace(trim(m.cod_art), '^0+(.)', '\1')) as cod,
           sum(m.delta) as saldo,
           max(m.ts)    as ult
    from public."Movimientos_Stock" m left join cfg on true
    where m.deposito in ('a_guardar', 'separar_pedidos', 'a_facturar')
      and (cfg.cutoff is null or m.tipo = 'inicial' or m.ts >= cfg.cutoff)
      and coalesce(m.legajo, '') not in ('0', '1')
    group by 1, 2
    having sum(m.delta) > 0.5
       and max(m.ts) < (now() - make_interval(days => dias))
  ),
  etiq as (
    select deposito, cod, round(saldo) as cajas,
           floor(extract(epoch from (now() - ult)) / 86400)::int as dq,
           case deposito when 'a_guardar' then 'a guardar (no pasó a góndola)'
                         when 'separar_pedidos' then 'pickeado sin separar/armar'
                         when 'a_facturar' then 'sin facturar'
                         else deposito end as est,
           row_number() over (order by floor(extract(epoch from (now() - ult)) / 86400) desc, cod) as rn
    from mv
  )
  select count(*),
         string_agg('cod ' || cod || ' — ' || cajas || ' cj · ' || est || ' (hace ' || dq || 'd)', E'\n• ' order by rn) filter (where rn <= 15),
         string_agg(deposito || '|' || cod, ',' order by deposito, cod),
         greatest(count(*) - 15, 0)
    into n, detalle, ids, extra
    from etiq;

  if coalesce(n, 0) = 0 then return; end if;

  perform public.tg_enqueue(
    '👀 STOCK ESTANCADO — ' || n || ' cosa(s) hace +' || dias || ' día(s) en un estado intermedio:' || E'\n• ' || coalesce(detalle, '-')
      || case when extra > 0 then E'\n… y ' || extra || ' más.' else '' end
      || E'\n\n👉 Puede que ya lo hicieron y se olvidaron de marcarlo. Revisá y cerralo.',
    'stock_estancado_' || hoy || '_' || md5(coalesce(ids, '')));
exception when others then null;
end
$function$;

revoke execute on function public.reporte_agentes_stock_estancado() from public, anon, authenticated;
grant execute on function public.reporte_agentes_stock_estancado() to service_role;

-- Encadenar al cron de agentes (jobid 14):
--   select cron.alter_job(14, command => '<... el resto ...> select public.reporte_agentes_stock_estancado();');

-- Tunear el umbral (opcional, default 2):
--   insert into "Stock_Config"(clave,valor) values ('dias_estancado','2')
--     on conflict (clave) do update set valor=excluded.valor;
