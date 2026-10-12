-- v29.44 (Thomas, 10/10): "el 119 pasa a ser secundario del 119E, pero cuando llega".
-- Familia DIFERIDA: la fila de Equivalencias_Familia se escribe sola cuando el principal
-- tiene stock de verdad (llegó la importación). Hasta entonces el 119 sigue como está.
-- Generico: otro caso igual = un insert en GV_Familia_Al_Llegar.
create table if not exists public."GV_Familia_Al_Llegar" (
  cod_secundario text primary key,
  cod_principal  text not null,
  empresa        text,
  descripcion    text,
  pedido_por     text,
  creado_en      timestamptz not null default now(),
  aplicado_en    timestamptz,
  aplicado_motivo text
);
alter table public."GV_Familia_Al_Llegar" enable row level security;
revoke insert, update on public."GV_Familia_Al_Llegar" from anon, authenticated;

create or replace function public.gv_familia_al_llegar_tick(p_simular boolean default false)
returns table(cod_secundario text, cod_principal text, stock_principal numeric, llegado_u numeric, accion text)
language plpgsql security definer set search_path = public as $$
declare r record; v_stk numeric; v_lleg numeric;
begin
  for r in select f.* from public."GV_Familia_Al_Llegar" f where f.aplicado_en is null loop
    select coalesce(sum(m.delta),0) into v_stk from public."Movimientos_Stock" m
     where upper(btrim(m.cod_art)) = upper(btrim(r.cod_principal))
       and m.deposito in ('terminado','a_guardar','racks','racks_ch','excedente','separar_pedidos','a_facturar');
    select coalesce(sum(b.unidades_llegadas),0) into v_lleg from public."GV_Importados_Baches" b
     where upper(btrim(b.cod_art)) = upper(btrim(r.cod_principal)) and b.estado <> 'anulado';
    cod_secundario := r.cod_secundario; cod_principal := r.cod_principal;
    stock_principal := v_stk; llegado_u := v_lleg;
    if v_stk > 0 or v_lleg > 0 then
      accion := case when p_simular then 'aplicaria' else 'aplicado' end;
      if not p_simular then
        insert into public."Equivalencias_Familia" (cod_secundario, cod_principal, empresa, descripcion, actualizado_en)
        values (r.cod_secundario, r.cod_principal, r.empresa, r.descripcion, now())
        on conflict on constraint "Equivalencias_Familia_pkey" do nothing;
        update public."GV_Familia_Al_Llegar" set aplicado_en = now(),
               aplicado_motivo = format('llegó %s: stock %s cajas, %s u recibidas', r.cod_principal, v_stk, v_lleg)
         where "GV_Familia_Al_Llegar".cod_secundario = r.cod_secundario;
      end if;
    else
      accion := 'espera';
    end if;
    return next;
  end loop;
end $$;
revoke all on function public.gv_familia_al_llegar_tick(boolean) from public, anon, authenticated;

insert into public."GV_Familia_Al_Llegar" (cod_secundario, cod_principal, empresa, descripcion, pedido_por)
values ('119','119E','LK','Corta Queso Mgo Alambre Loke','Thomas Loekemeyer')
on conflict (cod_secundario) do nothing;

-- cron 1 vez por hora, minuto 39 (gv_cron_colisiones: 3 jobs, 0 pesados), anti-solape
select cron.schedule('gv-familia-al-llegar', '39 * * * *',
  $c$do $d$ begin if pg_try_advisory_xact_lock(hashtext('cron:gv_familia_al_llegar_tick')::bigint) then perform public.gv_familia_al_llegar_tick(false); end if; end $d$;$c$);

-- Lectura: select * from public."GV_Familia_Al_Llegar";
--          select * from public.gv_familia_al_llegar_tick(true);
-- Rollback: select cron.unschedule('gv-familia-al-llegar');
--   (si ya se aplicó, la fila de Equivalencias_Familia del 119 se saca a mano con el «sí»)
