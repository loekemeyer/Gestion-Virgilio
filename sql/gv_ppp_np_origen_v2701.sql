-- v27.01 (Luis, 05/10): «que eligiendo una celda me diga la lógica que empleó para armarla así
-- y/o si alguien metió mano». Una fila por NP programada (web e ISIS): quién la dejó en ese día
-- (automático / a mano / ISIS) y con qué regla. Sólo lectura. Lo lee el Resumen de la PPP.
-- ⚠ El armador no guarda la regla por NP: la regla automática se DEDUCE de los datos del pedido
--   (retira con día, súper, importado diferido, movida del cron 18:00) y, si no es ninguna, es la
--   de grupo de zonas. Lo que sí es dato duro: manual (gv_manual_por / creado_por) y el log del cron.
create or replace function public.gv_ppp_np_origen()
returns table(np text, origen text, por text, cuando timestamptz, regla text)
language sql stable security definer set search_path = public as $f$
  with w as (
    select p.*, public.gv_ppp_web_np_label(p.empresa, p.np, p.np_idx) as lbl
      from public."PPP_Web_Programacion" p
     where p.fecha_entrega >= (now() at time zone 'America/Argentina/Buenos_Aires')::date - 30
  ), anc as (
    select upper(a.np) np, a.motivo, a.ancla from public.gv_ppp_demora_ancla() a
  ), mov as (
    select distinct on (upper(btrim(l.tanda))) upper(btrim(l.tanda)) tanda, l.corrida, l.accion, l.destino, l.detalle
      from public."GV_Reprog_Sin_Factura_Log" l
     where l.accion in ('movida','opt_movida') and l.destino is not null
     order by upper(btrim(l.tanda)), l.corrida desc
  )
  select w.lbl,
         case when w.gv_manual_por is not null or coalesce(w.creado_por,'sistema') <> 'sistema' then 'manual' else 'automatico' end,
         coalesce(w.gv_manual_por, nullif(w.creado_por,'sistema')),
         coalesce(w.gv_manual_at, w.creado_at),
         case
           when w.gv_manual_por is not null or coalesce(w.creado_por,'sistema') <> 'sistema' then
             'Programada o movida A MANO' ||
             case when anc.motivo = 'importado' then ' (espera el importado que llega el ' || to_char(anc.ancla,'DD/MM') || ')' else '' end ||
             '. El automático no la mueve (regla v23.50).'
           when mov.tanda is not null and mov.destino = w.fecha_entrega then
             case when mov.accion = 'opt_movida' then 'Optimizador de las 18:00 (' || to_char(mov.corrida,'DD/MM') || '): ' || mov.detalle
                  else 'Cron de las 18:00 (' || to_char(mov.corrida,'DD/MM') || '): no se facturó a tiempo. ' || mov.detalle end
           when lower(btrim(w.zona)) = 'retira' then 'Retira: día elegido por el cliente (pisa el cupo, tanda propia).'
           when public.gv_es_super(w.empresa, w.cod_cliente) then 'Súper: va en su propio camión, con el turno pactado.'
           when anc.motivo = 'importado' then 'Diferido: espera el importado que llega el ' || to_char(anc.ancla,'DD/MM') || '; se arma desde ahí.'
           else 'Grupo de zonas: sale con el camión de su grupo dentro del plazo (pedido ' ||
                coalesce(to_char(w.fecha_recep,'DD/MM'),'?') || ' + 14 días = ' || coalesce(to_char(w.fecha_recep + 14,'DD/MM'),'?') ||
                case when w.fecha_recep is not null and w.fecha_entrega > w.fecha_recep + 14 then '; ya venció: lo antes posible' else '' end || ').'
         end
    from w
    left join anc on anc.np = upper(w.lbl)
    left join mov on mov.tanda = upper(btrim(w.tanda))
  union all
  select o.np::text, 'manual', o.gv_manual_por, coalesce(o.gv_manual_at, o.creado_en),
         'NP de ISIS ajustada A MANO en Gestión (tanda o día pisados). El automático no la mueve.'
    from public."GV_PPP_Prog_Override" o
   where not coalesce(o.oculto,false) and (o.tanda is not null or o.fecha_entrega is not null)
$f$;
revoke all on function public.gv_ppp_np_origen() from public;
grant execute on function public.gv_ppp_np_origen() to anon, authenticated, service_role;
-- Rollback: drop function if exists public.gv_ppp_np_origen();
