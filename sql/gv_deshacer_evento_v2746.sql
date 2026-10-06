-- v27.46 (06/10/2026) — DESHACER (60 s) del operario por RPC, no por DELETE.
-- Caso: F46A, legajo 191, 17:39. El celular mando DELETE ?client_id=eq.… con la clave publica,
-- anon no tiene DELETE (401) y el EP quedo vivo: la TV seguia diciendo «Pickeando F46A».
-- Rollback: drop function public.gv_deshacer_evento(text,text);  (y el front vuelve a la v27.45)
create or replace function public.gv_deshacer_evento(p_client_id text, p_legajo text)
returns text language plpgsql security definer set search_path to 'public' as $f$
declare r record; v_res text;
begin
  select id, opcion, texto, legajo into r from public."Registros_Produccion_Virgilio"
   where client_id = btrim(coalesce(p_client_id,'')) and legajo = btrim(coalesce(p_legajo,''))
     and created_at > now() - interval '10 minutes'
   order by created_at desc limit 1;
  if r.id is null then return 'sin_fila'; end if;
  if r.opcion ~ 'X$' then return 'ya_deshecho'; end if;
  if r.opcion = 'EP' then
    return public.gv_anular_picking_virgilio(r.legajo, r.texto);
  elsif r.opcion = 'AP' then
    v_res := public.anular_armado_virgilio(r.legajo, r.texto, 'deshacer del operario');
    return v_res;
  end if;
  update public."Registros_Produccion_Virgilio"
     set opcion = r.opcion || 'X',
         descripcion = 'Deshecho por el operario · ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires','DD/MM HH24:MI')
   where id = r.id;
  return 'ok';
end $f$;
revoke all on function public.gv_deshacer_evento(text,text) from public;
grant execute on function public.gv_deshacer_evento(text,text) to anon, authenticated;
-- Probado como anon en transaccion abortada: EP -> 'ok' (EPX) · RT -> 'ok' (RTX) · repetir -> 'ya_deshecho' · otro legajo -> 'sin_fila'.

-- v27.50 (Thomas, D3, 06/10): deshacer un TP/TAP = como si nunca hubiera ocurrido. Reemplaza la funcion
-- de arriba agregando, despues del update a <opcion>X:
--   if r.opcion in ('TP','TAP') then   -- v27.47-deshacer-tp
--     v_t := upper(btrim(split_part(coalesce(r.texto,''),'|',1)));
--     v_f := case r.opcion when 'TP' then 'picking' else 'armado' end;
--     update "GV_Tandas_Lock" set estado='tomada', legajo=r.legajo, ts_estado=now()
--      where tanda=v_t and fase=v_f and estado='completada';
--     if r.opcion='TP' then
--       delete from "GV_Picking_Tanda" where tanda=v_t and legajo=r.legajo;
--       begin perform reconciliar_pipeline_stock_etapa1(); exception when others then null; end;
--     end if;
--   end if;
-- Probado como anon en transaccion abortada: TP -> 'ok' (TPX), lock completada -> tomada:1.
-- La definicion viva completa: select pg_get_functiondef('public.gv_deshacer_evento(text,text)'::regprocedure);
