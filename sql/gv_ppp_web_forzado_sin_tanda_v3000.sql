-- v29.82 (Luis, 2026-10-13): "lk 1670, por que no se programo solo?"
--
-- CAUSA. El intradia (cron 73, cada 5 min) llama al armador SOLO si lo pendiente de las ZONAS
-- AUTOMATICAS (1, 2 y 3) llega al umbral, o si hay algo de zona manual con camion a su zona
-- (`pendienteAutomatico` de la Edge Function gv-ppp-web-tandas-diarias: "Super, Retira y el
-- resto nunca", y el conteo manual exige zona `^Zona N`). Asi que un pendiente que un pase
-- programa SI O SI hoy no llegaba NUNCA al armador: la corrida salia por `intradia_sin_umbral`
-- sin llamarlo.
--   Medido el 13/10: LK 1670 (Retira, dia pactado 16/10) entro 13:31; el armador habia corrido
--   13:02 y todas las corridas siguientes dieron "pendiente automatico 0.000 m3 (0 NP)".
--   El pedido quedaba esperando el job de las 00:01: hasta 11 h parado.
-- Es el mismo agujero que la regla v19.52 ya marca para `'^\s*Zona\s*[0-9]+'`: al tocar el
-- armado, preguntarse si ahi no falta Retira.
--
-- QUE SE HIZO. Sin tocar la Edge Function (no hace falta redeploy):
--   · gv_ppp_web_forzado_sin_tanda(): los pedidos SIN TANDA que un pase programa si o si hoy —
--       (a4)  Retira con dia elegido por el cliente   -> gv_web_retiro_pactado
--       (b2)  diferido con su piso ya cumplido        -> GV_PPP_Web_Diferido + gv_diferido_piso
--       (a0e) cliente nuevo aprobado (sale en 48 h)   -> GV_Cuarentena_Liberados con cliente_nuevo
--     Lee lk_pedidos_match (el FDW ya esta en la base): no necesita el feed de la Edge Function.
--   · cron 156 `gv-ppp-web-forzado` (minutos 7,17,37,47; anti-solape por advisory lock): si esa
--     funcion devuelve algo, llama a la Edge Function en modo DIARIO (el de las 00:01, que no
--     mira el umbral) y el armador corre. Si no devuelve nada, no hace nada.
--   Sobrar una fila no cuesta (el armador decide); faltar una deja el pedido sin programar.
--
-- Probado: con LK 1670 pendiente, la funcion devolvia 1 fila ("retira con dia pactado") y la
-- corrida lo programo como LK 0414, tanda F89A, Retira, 16/10.
--
-- ⚠ Queda ademas gv_ppp_web_pendiente_forzado(text,jsonb) — el mismo criterio pero recibiendo
--   los pendientes por jsonb — SIN LLAMADOR: es la mitad del fix para el dia que se re-deploye
--   gv-ppp-web-tandas-diarias y el umbral se arregle adentro (sumar su conteo a npManual).
--
-- Rollback:
--   select cron.unschedule('gv-ppp-web-forzado');
--   drop function if exists public.gv_ppp_web_forzado_sin_tanda();

create or replace function public.gv_ppp_web_forzado_sin_tanda()
returns table (empresa text, order_id bigint, motivo text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with minimo as (select public.gv_ppp_web_dia_minimo() as d),
  sin_tanda as (
    select p.empresa, p.order_id
      from public.lk_pedidos_match p
     where coalesce(lower(p.status),'') not in ('cancelado','anulado')
       and p.fecha_pedido >= current_date - 60
       and not exists (select 1 from public."PPP_Web_Programacion" g
                        where g.empresa = p.empresa and g.order_id = p.order_id and g.tanda is not null)
       and not exists (select 1 from public."GV_Web_Cancelados" c
                        where c.empresa = p.empresa and c.order_id = p.order_id)
  )
  select s.empresa, s.order_id, 'retira con dia pactado'::text
    from sin_tanda s
   where public.gv_web_retiro_pactado(s.empresa, s.order_id) is not null
  union
  select s.empresa, s.order_id, 'diferido con el piso cumplido'::text
    from sin_tanda s cross join minimo m
   where exists (select 1 from public."GV_PPP_Web_Diferido" d
                  where d.empresa = s.empresa and d.order_id = s.order_id
                    and public.gv_diferido_piso(d.no_antes_de) <= m.d)
  union
  select s.empresa, s.order_id, 'cliente nuevo aprobado'::text
    from sin_tanda s
   where exists (select 1 from public."GV_Cuarentena_Liberados" l
                  where l.empresa = s.empresa and btrim(l.order_id) = s.order_id::text
                    and (l.motivos is null or cardinality(l.motivos) = 0
                         or 'cliente_nuevo' = any(l.motivos)));
$function$;

grant execute on function public.gv_ppp_web_forzado_sin_tanda() to anon, authenticated, service_role;

-- el cron (se creo con cron.schedule; el command va adentro de un do con advisory lock)
-- select cron.schedule('gv-ppp-web-forzado', '7,17,37,47 * * * *', $cmd$ ... $cmd$);

-- centinela: el umbral del intradia no puede volver a frenar lo que tiene dia forzado
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select 'gv_ppp_web_forzado_sin_tanda()', 'funcion', 'gv_web_retiro_pactado',
       'El umbral del intradia no frena un pendiente que un pase programa si o si hoy: Retira con dia pactado (a4), diferido con el piso cumplido (b2) y cliente nuevo aprobado (a0e). Lo mira el cron 156 gv-ppp-web-forzado. Caso LK 1670.',
       'Luis', 'v29.82'
 where not exists (select 1 from public."GV_Reglas_Centinela"
                    where objeto = 'gv_ppp_web_forzado_sin_tanda()' and patron = 'gv_web_retiro_pactado');
