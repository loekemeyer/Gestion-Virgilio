-- v22.40 (Luis, 24/09, problema "Descuento de OC se pierde si la recepción cae en un timeout de la base")
-- Caso: 24/09 11:49 la base cortó por statement timeout; la carga de Blist-Pack (763 + 764) dio 500 en
-- gv_oc_aplicar_recepcion y el 764 (19 cajas) no se imputó a la OC 1668 (quedó 0/15). recepcion.js
-- llama la RPC sin mirar el error, y el único recálculo automático era el del miércoles (cron 93),
-- que es del circuito de OCs automáticas y NO se toca (Luis: "lo del miércoles es que se manden las OCs").
--
-- Red de seguridad: cada 30 min se recalculan las OC de los códigos recibidos en las últimas 36 h.
-- Idempotente: si todo cuadra no escribe nada (medido 24/09: 22 códigos, 0 OC cambiadas, 1,4 s).

create or replace function public.gv_oc_recompute_recepciones_recientes(p_horas int default 36)
returns table(codigos int, oc_cambiadas int)
language plpgsql security definer set search_path to 'public'
as $function$
declare c text; k int := 0; n int := 0;
begin
  for c in
    select distinct norm_cod(x.cod) from (
      select "Cod" as cod from "Entregas Tallerista Virgilio"
       where created_at >= now() - make_interval(hours => p_horas)
      union all
      select "Cod_Art" from "Entregas Prov AT"
       where created_at >= now() - make_interval(hours => p_horas)) x
     where coalesce(norm_cod(x.cod), '') <> ''
  loop
    k := k + 1;
    n := n + public.gv_oc_recompute_recibido(null, c);
  end loop;
  return query select k, n;
end $function$;

revoke all on function public.gv_oc_recompute_recepciones_recientes(int) from public, anon, authenticated;

-- v22.42: cada ~12 min, minutos impares fuera del 57 (3-59/6) y el 68 (1-59/10)
select cron.schedule('gv-oc-recepcion-red', '7,19,29,43,55 * * * *',
  'select * from public.gv_oc_recompute_recepciones_recientes(36)');

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select 'gv_oc_recompute_recepciones_recientes','funcion','gv_oc_recompute_recibido\(null, c\)',
       'lo recibido en las últimas 36 h se vuelve a imputar a su OC aunque el celular haya fallado','Luis','v22.40'
where not exists (select 1 from public."GV_Reglas_Centinela" where objeto='gv_oc_recompute_recepciones_recientes');

-- Rollback: select cron.unschedule('gv-oc-recepcion-red');
