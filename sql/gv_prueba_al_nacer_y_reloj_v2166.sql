-- v21.66 (Luis, 2026-09-23) — aplicado en Gestión el 23/09.
--
-- (1) LA TANDA DE PRUEBA NACE COMO PRUEBAn. En la v21.63 el renombre lo hacía un cron cada 5 min, y
--     el 23/09 la tanda de LK 0213 existió 2 minutos como E81A (10:45 → 10:47) antes de ser PRUEBA1.
--     Ahora hay un constraint trigger DIFERIDO sobre PPP_Web_Programacion: corre al COMMIT de la
--     transacción que programó el pedido (cuando ya se escribieron todas las tablas de la tanda) y la
--     renombra ahí; afuera nunca se ve el código intermedio. Probado en transacción abortada: pedido
--     de prueba → PRUEBA2, pedido real → intacto. El cron gv-prueba-tandas sigue de red.
create or replace function public.gv_prueba_tanda_al_nacer() returns trigger
language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if public.gv_es_cliente_prueba(new.empresa, new.cod_cliente) then
    begin
      perform public.gv_prueba_tandas_normalizar();
    exception when others then
      raise warning 'gv_prueba_tanda_al_nacer: %', sqlerrm;
    end;
  end if;
  return null;
end $$;
revoke execute on function public.gv_prueba_tanda_al_nacer() from public, anon, authenticated;
drop trigger if exists zz_gv_prueba_tanda_al_nacer on public."PPP_Web_Programacion";
create constraint trigger zz_gv_prueba_tanda_al_nacer
  after insert or update of tanda on public."PPP_Web_Programacion"
  deferrable initially deferred for each row
  when (new.tanda is not null and upper(btrim(new.tanda)) !~ '^PRUEBA[0-9]+$')
  execute function public.gv_prueba_tanda_al_nacer();
-- rollback: drop trigger zz_gv_prueba_tanda_al_nacer on public."PPP_Web_Programacion";

-- (2) EL RELOJ DE PROGRAMACIÓN: primero el día/franja que eligió el cliente en el pedido
--     (lk_pedidos_match.retiro_*), y si no hay, el cargado a mano en A Programar (GV_Pedido_Horario).
--     Antes mostraba SOLO el manual: todos los Retira con día elegido salían «⏱ ----».
--     Se aplicó sobre pg_get_functiondef de gv_ppp_prog_arbol (replace de la línea
--     `h.fecha, h.franja, h.origen,` + left join lk_pedidos_match cm por empresa y order_id, sólo
--     para origen 'web'). Medido: 520 filas antes y después. Centinela en GV_Reglas_Centinela.
--     ⚠ A Programar sigue con la precedencia de la v19.60 (el manual pisa al cliente).
