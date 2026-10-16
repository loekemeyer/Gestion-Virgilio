-- v31.66 (Luis, 16/10/2026): «en la página tienen que aparecer 636 y 635 (nacionales) y no el importado
-- hasta que no se acabe el stock del nacional (que haya suficientes pedidos que comprometan el total del
-- stock del 636 y 635)».
--
-- Cómo: GV_Pick_Liquidar.web_switch = true → el feed de ocultos que LK aplica cada 5 min
-- (sync_web_ocultos_virgilio, también sobre products de Chef por el FDW) recibe:
--   · libre > 0  → se oculta el IMPORTADO (636E) · se ve el nacional
--   · libre <= 0 → se oculta el NACIONAL (636)   · se ve el importado
--   · par ya liquidado (activo = false) → se oculta el nacional para siempre
-- libre = disponible del nacional (terminado + excedente + racks + racks_ch + a_guardar + para_envasar;
--         lo separado y a facturar ya está comprometido) − cajas pedidas sin pickear (gv_stock_pedidas_neto.neto)
--         del nacional y del importado (el pedido del E también se lleva el nacional).
-- LK sólo reactiva lo que ocultó este feed: un producto apagado a mano no se toca.
-- Si la cuenta falla se oculta el importado (queda el nacional, que es lo vigente mientras dure).

alter table public."GV_Pick_Liquidar" add column if not exists web_switch boolean not null default false;

create or replace function public.gv_pick_liquidar_web_ocultos()
returns table(cod text, empresa text, libre numeric)
language plpgsql stable security definer set search_path to 'public' as $f$
-- v31.65-web-switch
declare r record; v_disp numeric; v_dem numeric; v_libre numeric; v_oc text;
begin
  for r in select upper(btrim(g.cod_pedido)) cp, upper(btrim(g.cod_liq)) cl, upper(btrim(g.empresa)) emp,
                  g.activo
             from public."GV_Pick_Liquidar" g where g.web_switch
  loop
    v_libre := null;
    if not r.activo then
      v_oc := r.cl;                                   -- liquidado: el nacional no vuelve
    else
      begin
        select coalesce(sum(greatest(coalesce(v.terminado,0),0) + greatest(coalesce(v.excedente,0),0)
                          + greatest(coalesce(v.racks,0),0) + greatest(coalesce(v.racks_ch,0),0)
                          + greatest(coalesce(v.a_guardar,0),0) + greatest(coalesce(v.para_envasar,0),0)), 0)
          into v_disp from public.vista_saldos_stock v
         where upper(btrim(v.cod_art)) = r.cl and upper(coalesce(v.empresa, r.emp)) = r.emp;
        select coalesce(sum(n.neto), 0) into v_dem from public.gv_stock_pedidas_neto n
         where upper(regexp_replace(btrim(n.cod), '\s+(LK|CH|LOKE)$', '')) in (r.cl, r.cp);
        v_libre := v_disp - v_dem;
        v_oc := case when v_libre > 0 then r.cp else r.cl end;
      exception when others then
        v_oc := r.cp;                                 -- sin cuenta: queda el nacional a la vista
      end;
    end if;
    cod := v_oc; empresa := r.emp; libre := v_libre; return next;
  end loop;
end $f$;
revoke execute on function public.gv_pick_liquidar_web_ocultos() from public, anon, authenticated;
grant execute on function public.gv_pick_liquidar_web_ocultos() to lk_ppp_reader, service_role;

create or replace function public.lk_web_ocultos_feed()
returns table(cod text, empresa text)
language sql stable security definer set search_path to 'public' as $function$
  select x.cod, x.empresa from public."GV_Web_Oculto" x
  union
  select s.cod, s.empresa from public.gv_pick_liquidar_web_ocultos() s;   -- v31.65-web-switch
$function$;

update public."GV_Pick_Liquidar" set web_switch = true where cod_liq in ('636','635') and upper(empresa) = 'CH';

-- Chequeo: select * from public.gv_pick_liquidar_web_ocultos();  select * from public.v_lk_web_ocultos;
-- Rollback: update public."GV_Pick_Liquidar" set web_switch = false where web_switch;
--           (al próximo sync LK reactiva lo que había ocultado)

insert into "GV_Reglas_Centinela"(objeto, clase, patron, regla, quien_pidio, version) values
('lk_web_ocultos_feed','funcion','gv_pick_liquidar_web_ocultos','La página de Chef muestra el nacional (636/635) hasta que los pedidos comprometen su stock; recién ahí el importado','Luis','v31.66'),
('gv_pick_liquidar_web_ocultos','funcion','then r\.cp else r\.cl end','libre > 0 oculta el importado; libre <= 0 oculta el nacional','Luis','v31.66');
-- En Chef (por chef_ext de LK), a mano, Luis 16/10: update chef_ext.products set active = false where cod = '634E';
