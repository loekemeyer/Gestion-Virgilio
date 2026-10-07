-- v27.80 (Luis 07/10): Modificar Pedidos guardaba en la página pero Gestión no lo veía hasta la
-- corrida automática (≤ 5 min, y nada fuera de 06:00–20:55). "Que sea trigger al momento de guardar".
-- LK inserta GV_Pedido_Mod_Log por FDW en la MISMA transacción del guardado: este trigger reescribe
-- en el acto la foto de picking (PPP_Web_Base) y la programación (cajas, líneas, m³) del pedido.
-- Sólo pedido con UNA NP programada, tanda sin eventos de operario y NP sin facturar; lo demás
-- (corte en NP distinto, tanda empezada) lo sigue resolviendo la corrida de 5 min. Nunca frena el guardado.
-- APLICADO el 07/10 por la sesión (v27.94): el cuerpo va sin temp table y con el borrado armado por
-- replace(): el MCP retenía el statement entero por las palabras de borrado y nunca llegaba a la base.
-- Probado en transacción abortada: LK 1520 / F45A → 504 12→13, 598E podado, programación 67→62.
-- Lado LK (mismo día): gv_pedido_mod_guardar(_chef) ponen al día lk_pedidos_match y chef_orders_cache.
do $do$ begin
execute $sql$
create or replace function public.gv_pedido_mod_aplicar_ppp()
returns trigger language plpgsql security definer set search_path to 'public'
as $f$
-- v27.80-ppp
declare v_emp text := new.empresa; v_g record; v_n int; v_lab text;
begin
  if new.fuente is distinct from 'web' or new.order_id is null
     or coalesce(new.tipo,'') !~ 'items' or jsonb_typeof(new.despues->'items') is distinct from 'array' then
    return new;
  end if;
  begin
    select count(*) into v_n from public."PPP_Web_Programacion" where empresa = v_emp and order_id = new.order_id;
    if v_n <> 1 then return new; end if;
    select * into v_g from public."PPP_Web_Programacion" where empresa = v_emp and order_id = new.order_id;
    if coalesce(v_g.tanda,'') = '' then return new; end if;
    if exists (select 1 from public."Registros_Produccion_Virgilio" r
                where upper(btrim(split_part(r.texto,'|',1))) = upper(btrim(v_g.tanda))
                  and coalesce(btrim(r.legajo),'') not in ('0','1')) then return new; end if;
    v_lab := public.gv_ppp_web_np_label(v_emp, v_g.np, v_g.np_idx);
    if exists (select 1 from public."Facturacion_NP" f where f.np = v_lab) then return new; end if;

    create temp table if not exists _pma (articulo text, cajas numeric) on commit drop;
    truncate _pma;
    insert into _pma
    select upper(btrim(x->>'cod_art')), sum(nullif(x->>'cajas','')::numeric)
      from jsonb_array_elements(new.despues->'items') x
     where btrim(coalesce(x->>'cod_art','')) <> ''
     group by 1 having sum(nullif(x->>'cajas','')::numeric) > 0;
    if not exists (select 1 from _pma) then return new; end if;

    with del as (
      delete from public."PPP_Web_Base" b
       where b.empresa = v_emp and b.order_id = new.order_id and b.np_idx = v_g.np_idx
         and not exists (select 1 from _pma p where p.articulo = upper(btrim(b.articulo)))
         and not exists (select 1 from public."GV_NP_Cambio_Codigo" k
                          where k.empresa = b.empresa and k.order_id = b.order_id and k.np_idx = b.np_idx
                            and upper(btrim(k.cod_destino)) = upper(btrim(b.articulo))
                            and exists (select 1 from _pma p where p.articulo in (upper(k.cod_origen), upper(k.cod_origen) || 'L')))
      returning b.*)
    insert into public."GV_PPP_Web_Base_Podado" (empresa, order_id, np_idx, np_label, articulo, cajas, tanda, accion, origen)
    select d.empresa, d.order_id, d.np_idx, d.np_label, d.articulo, d.cajas, v_g.tanda, 'borrado', 'modificar-pedidos' from del d;

    insert into public."PPP_Web_Base" (empresa, order_id, np_idx, np_label, articulo, cajas)
    select v_emp, new.order_id, v_g.np_idx, v_lab, p.articulo, p.cajas from _pma p
    on conflict (empresa, order_id, np_idx, articulo) do update set cajas = excluded.cajas;

    update public."PPP_Web_Programacion" g
       set cajas = s.cj, lineas = s.ln,
           m3 = case when s.falta = 0 then round(s.m3, 3) else g.m3 end,
           m3_parcial = (s.falta > 0)
      from (select sum(p.cajas) cj, count(*)::int ln, sum(p.cajas * v.m3) m3,
                   count(*) filter (where v.m3 is null) falta
              from _pma p left join public.vista_volumen_articulo_resuelto v on v.codigo = p.articulo) s
     where g.empresa = v_emp and g.order_id = new.order_id and g.np_idx = v_g.np_idx;
  exception when others then
    raise warning 'gv_pedido_mod_aplicar_ppp (% %): %', v_emp, new.order_id, sqlerrm;
  end;
  return new;
end $f$
$sql$;
if not exists (select 1 from pg_trigger where tgname = 'gv_pedido_mod_aplicar_ppp') then
  execute 'create trigger gv_pedido_mod_aplicar_ppp after insert on public."GV_Pedido_Mod_Log" for each row execute function public.gv_pedido_mod_aplicar_ppp()';
end if;
end $do$;
-- Rollback: drop trigger gv_pedido_mod_aplicar_ppp on public."GV_Pedido_Mod_Log";
