-- =====================================================================
--  stock_estancado.sql — Alerta Telegram "STOCK ESTANCADO" 👀
--
--  CONCEPTO (redefinido): no interesa "cuánto hay a guardar hace X días"
--  (una recepción entera sin tocar es trabajo pendiente normal, no un error),
--  sino los POTENCIALES ERRORES reales — mercadería que quedó trabada porque
--  alguien empezó y no cerró:
--
--   1) RESTO SIN GUARDAR (deposito a_guardar):
--      Guardaron parte de un artículo (a góndola y/o excedente) pero dejaron un
--      resto sin guardar. Ej: llegan 100, suben 50 a góndola + 40 a excedente y
--      quedan 10 "a guardar" → esas 10 están estancadas (se olvidaron el resto).
--      Señal = hubo `guardado` para ese código (guardado parcial) Y todavía queda
--      saldo > 0 en a_guardar. Si NUNCA se guardó nada (recepción entera intacta),
--      NO se avisa: es pendiente normal, no un error.
--
--   2) PICKEADO SIN AVANZAR (deposito separar_pedidos + a_facturar):
--      Mercadería ya pickeada que quedó en un estado intermedio sin que nadie la
--      trabaje: pickeada sin separar/armar, o armada sin facturar. No puede quedar
--      así más de `dias_estancado` días hábiles.
--
--  DÍAS HÁBILES: los operarios NO trabajan sábado ni domingo, así que la
--  antigüedad se mide en días hábiles (lun–vie), no en días corridos. Algo que
--  quedó el viernes recién dispara el martes (vie + lun = 2 días hábiles), no el
--  lunes. Umbral configurable en `Stock_Config.dias_estancado` (default 2).
--
--  Solo TELEGRAM. Respeta el cutoff, excluye legajos 0/1. Lista los 15 más viejos
--  + "… y N más". Dedup diario por el set (depósito|cod).
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
    select upper(regexp_replace(trim(m.cod_art), '^0+(.)', '\1')) as cod,
           m.deposito, m.tipo, m.delta, m.ts
    from public."Movimientos_Stock" m left join cfg on true
    where m.deposito in ('a_guardar', 'separar_pedidos', 'a_facturar')
      and (cfg.cutoff is null or m.tipo = 'inicial' or m.ts >= cfg.cutoff)
      and coalesce(m.legajo, '') not in ('0', '1')
  ),
  -- (1) resto sin guardar: quedó saldo en a_guardar Y hubo guardado parcial
  ag as (
    select cod, sum(delta) as saldo, max(ts) as ult
    from mv
    where deposito = 'a_guardar'
    group by cod
    having sum(delta) > 0.5
       and coalesce(-sum(delta) filter (where tipo = 'guardado'), 0) > 0.5
  ),
  -- (2) pickeado sin avanzar: separar_pedidos / a_facturar con saldo > 0
  pick as (
    select deposito, cod, sum(delta) as saldo, max(ts) as ult
    from mv
    where deposito in ('separar_pedidos', 'a_facturar')
    group by deposito, cod
    having sum(delta) > 0.5
  ),
  todo as (
    select 'a_guardar'::text as deposito, cod, saldo, ult,
           'resto sin guardar (ya guardaron el resto)'::text as est from ag
    union all
    select deposito, cod, saldo, ult,
           case deposito when 'a_facturar' then 'pickeado sin facturar'
                         else 'pickeado sin separar/armar' end
    from pick
  ),
  etiq as (
    select deposito, cod, round(saldo) as cajas,
           -- antigüedad en días HÁBILES (lun–vie), sin contar sáb/dom
           (select count(*) from generate_series(
              (ult at time zone 'America/Argentina/Buenos_Aires')::date + 1,
              (now() at time zone 'America/Argentina/Buenos_Aires')::date,
              interval '1 day') d
            where extract(isodow from d) < 6)::int as dh,
           est
    from todo
  ),
  fil as (
    select deposito, cod, cajas, dh, est,
           row_number() over (order by dh desc, cod) as rn
    from etiq
    where dh >= dias
  )
  select count(*),
         string_agg('cod ' || cod || ' — ' || cajas || ' cj · ' || est || ' (hace ' || dh || ' d. háb.)', E'\n• ' order by rn) filter (where rn <= 15),
         string_agg(deposito || '|' || cod, ',' order by deposito, cod),
         greatest(count(*) - 15, 0)
    into n, detalle, ids, extra
    from fil;

  if coalesce(n, 0) = 0 then return; end if;

  perform public.tg_enqueue(
    '👀 STOCK ESTANCADO — ' || n || ' cosa(s) sin moverse +' || dias || ' día(s) hábil(es):' || E'\n• ' || coalesce(detalle, '-')
      || case when extra > 0 then E'\n… y ' || extra || ' más.' else '' end
      || E'\n\n👉 O guardan el resto que quedó, o cierran lo pickeado. Si ya lo hicieron, márquenlo en la app.',
    'stock_estancado_' || hoy || '_' || md5(coalesce(ids, '')));
exception when others then null;
end
$function$;

revoke execute on function public.reporte_agentes_stock_estancado() from public, anon, authenticated;
grant execute on function public.reporte_agentes_stock_estancado() to service_role;

-- Encadenar al cron de agentes (jobid 14):
--   select cron.alter_job(14, command => '<... el resto ...> select public.reporte_agentes_stock_estancado();');

-- Tunear el umbral en días HÁBILES (opcional, default 2):
--   insert into "Stock_Config"(clave,valor) values ('dias_estancado','2')
--     on conflict (clave) do update set valor=excluded.valor;
