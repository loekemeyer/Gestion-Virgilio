-- v22.08 (Luis, 23/09): switch "Cartel web" por importado en Pedidos Importacion.
-- ON  = el codigo muestra "Sin stock hasta dd/mm" en las paginas LK/CH y parte el pedido.
-- OFF = fila en GV_Reingreso_Excluido (la lee gv_reingresos_feed). Llega a las paginas en la
--       proxima corrida del cron 39 de LK (minutos 09 y 39). Front: _reingWebSwitchHtml /
--       pedImpReingresoWeb en index.html. Test: tests/pedimp-reingreso-switch.cjs.
-- Aplicado en hrxfctzncixxqmpfhskv el 23/09 (definicion viva volcada abajo).

CREATE OR REPLACE FUNCTION public.gv_reingreso_excluidos()
 RETURNS TABLE(cod text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  -- Lista para el switch "Cartel web" de Importados (no es dato sensible: codigos).
  select x.cod from public."GV_Reingreso_Excluido" x order by 1;
$function$;
grant execute on function public.gv_reingreso_excluidos() to anon, authenticated;

CREATE OR REPLACE FUNCTION public.gv_reingreso_web_set(p_cod text, p_activo boolean)
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_cod text := public.gv_cod_stock(p_cod);
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede cambiar el cartel de reingreso';
  end if;
  if coalesce(v_cod,'') = '' then raise exception 'codigo vacio'; end if;
  if p_activo then
    delete from public."GV_Reingreso_Excluido" where cod = v_cod;
  else
    insert into public."GV_Reingreso_Excluido" (cod, motivo, pedido_por)
    values (v_cod, 'apagado desde Importados', coalesce(auth.jwt()->>'email','?'))
    on conflict (cod) do nothing;
  end if;
  return p_activo;
end $function$;
revoke execute on function public.gv_reingreso_web_set(text, boolean) from public, anon;
grant execute on function public.gv_reingreso_web_set(text, boolean) to authenticated;
