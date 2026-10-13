-- v29.45 (Luis, D10, 10/10/2026): cuando LLEGA el principal, además de la familia,
-- la góndola del secundario pasa al principal y la OC del secundario se apaga.
-- APLICADO 10/10/2026. Probado en transacción abortada: 119E con stock 5 → familia 119→119E,
-- Ñ26 = 119E, OC_Maximos 119 activo=false, 119E activo=true.
-- Rollback: volver al cuerpo de sql/gv_familia_al_llegar_v2944.sql (las columnas nuevas quedan, sin uso).

alter table public."GV_Familia_Al_Llegar"
  add column if not exists pasar_gondola boolean not null default false,
  add column if not exists apagar_oc     boolean not null default false;

update public."GV_Familia_Al_Llegar" set pasar_gondola = true, apagar_oc = true
 where cod_secundario = '119';

CREATE OR REPLACE FUNCTION public.gv_familia_al_llegar_tick(p_simular boolean DEFAULT false)
 RETURNS TABLE(cod_secundario text, cod_principal text, stock_principal numeric, llegado_u numeric, accion text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; v_stk numeric; v_lleg numeric; g record; v_extra text;
begin
  for r in select f.* from public."GV_Familia_Al_Llegar" f where f.aplicado_en is null loop
    select coalesce(sum(m.delta),0) into v_stk from public."Movimientos_Stock" m
     where upper(btrim(m.cod_art)) = upper(btrim(r.cod_principal))
       and m.deposito in ('terminado','a_guardar','racks','racks_ch','excedente','separar_pedidos','a_facturar');
    select coalesce(sum(b.unidades_llegadas),0) into v_lleg from public."GV_Importados_Baches" b
     where upper(btrim(b.cod_art)) = upper(btrim(r.cod_principal)) and b.estado <> 'anulado';
    cod_secundario := r.cod_secundario; cod_principal := r.cod_principal;
    stock_principal := v_stk; llegado_u := v_lleg; v_extra := '';
    if v_stk > 0 or v_lleg > 0 then
      accion := case when p_simular then 'aplicaria' else 'aplicado' end;
      if not p_simular then
        insert into public."Equivalencias_Familia" (cod_secundario, cod_principal, empresa, descripcion, actualizado_en)
        values (r.cod_secundario, r.cod_principal, r.empresa, r.descripcion, now())
        on conflict on constraint "Equivalencias_Familia_pkey" do nothing;
        -- v29.45 (D10): la góndola del secundario pasa al principal
        if r.pasar_gondola then
          for g in select li.sector, li.clase, li.cajas_max from public."GV_Lugar_Item" li
                    where upper(btrim(li.cod)) = upper(btrim(r.cod_secundario)) and li.activo loop
            begin
              perform public.gv_lugar_item_guardar(g.sector, r.cod_principal, g.clase, g.cajas_max);
              perform public.gv_lugar_item_sacar(g.sector, r.cod_secundario, g.clase);
              v_extra := v_extra || format(' · góndola %s → %s', g.sector, r.cod_principal);
            exception when others then
              v_extra := v_extra || format(' · góndola %s NO pasó: %s', g.sector, sqlerrm);
            end;
          end loop;
        end if;
        -- v29.45 (D10): el secundario deja de generar OC; el principal queda con su línea
        if r.apagar_oc then
          update public."OC_Maximos" set activo = false, actualizado = now()
           where upper(btrim(cod)) = upper(btrim(r.cod_secundario)) and activo;
          insert into public."OC_Maximos" (cod, descripcion, linea, activo)
          select r.cod_principal, r.descripcion, coalesce(r.empresa,'LK'), true
           where not exists (select 1 from public."OC_Maximos" o where upper(btrim(o.cod)) = upper(btrim(r.cod_principal)));
          v_extra := v_extra || ' · OC del secundario apagada';
        end if;
        update public."GV_Familia_Al_Llegar" set aplicado_en = now(),
               aplicado_motivo = format('llegó %s: stock %s cajas, %s u recibidas', r.cod_principal, v_stk, v_lleg) || v_extra
         where "GV_Familia_Al_Llegar".cod_secundario = r.cod_secundario;
      end if;
    else
      accion := 'espera';
    end if;
    return next;
  end loop;
end $function$;

revoke all on function public.gv_familia_al_llegar_tick(boolean) from public, anon, authenticated;
