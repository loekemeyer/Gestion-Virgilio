-- v28.61 (Luis, 08/10/2026): "si la OC es menor a 10 cajas, sólo puede pedirse si hay menos que 30 % de góndola".
-- Por CÓDIGO (el total antes de repartir entre proveedores). Góndola = terminado de stocks_carga_rapida vs
-- capacidad de vista_generador_oc. Sin capacidad cargada no se frena. Parámetros en Stock_Config
-- (oc_chica_cajas = 10, oc_chica_gondola_pct = 0.30): cambiarlos es un update.
-- Lo usan: generar_ocs_automaticas (marcador v28.61-oc-chica, aplicado con replace sobre pg_get_functiondef)
-- y el generador manual del front (ocgEnter → a pedir 0 + nota «⏸ N OC de menos de 10 cajas no se piden»).
insert into public."Stock_Config"(clave, valor, actualizado) values ('oc_chica_cajas','10',now()),('oc_chica_gondola_pct','0.30',now()) on conflict (clave) do nothing;
create or replace function public.gv_oc_chica_frenada()
returns table (cod text, total numeric, terminado numeric, cap numeric, pct numeric)
language sql stable security definer set search_path = public
as $f$
  with cfg as (select coalesce((select nullif(valor,'')::numeric from "Stock_Config" where clave = 'oc_chica_cajas'), 10) cj,
                      coalesce((select nullif(valor,'')::numeric from "Stock_Config" where clave = 'oc_chica_gondola_pct'), 0.30) pc),
  g as (select regexp_replace(upper(btrim(s.cod)), '^0+(?=.)', '') k, sum(coalesce(s.terminado,0)) t
          from stocks_carga_rapida s group by 1)
  select v.cod, round(v.total), coalesce(g.t, 0), v.cap, round(100 * coalesce(g.t,0) / v.cap)
    from vista_generador_oc v cross join cfg
    left join g on g.k = regexp_replace(upper(btrim(v.cod)), '^0+(?=.)', '')
   where v.activo and v.total > 0 and round(v.total) < cfg.cj
     and coalesce(v.cap, 0) > 0 and coalesce(g.t, 0) >= cfg.pc * v.cap;
$f$;
grant execute on function public.gv_oc_chica_frenada() to anon, authenticated;
-- generar_ocs_automaticas: en los DOS «where activo and total > 0 and tiene_prov_real» del split se agrega
--   and cod not in (select f.cod from public.gv_oc_chica_frenada() f) /*v28.61-oc-chica*/
-- Al 08/10 frena 18 códigos; la corrida probada (forzada, en transacción abortada) dio 130 líneas y ninguna frenada.
