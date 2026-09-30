-- GESTIÓN (hrxfctzncixxqmpfhskv) — Luis 30/09/2026, problema 640.
-- El desglose por cliente del pop-up de proyección pide la FAMILIA entera (principal +
-- secundarios de Equivalencias_Familia), igual que ventas_mensuales_cod, a la función nueva
-- de LK fn_ventas_clientes_mes_fam_virgilio (regla L, sin interco). Suma `codigos`.
-- Cambia el tipo de retorno → drop + create (no tiene dependientes en la base; lo llama el front).
-- Rollback: volver a la definición anterior (abajo, comentada) con drop + create.
drop function if exists public.gv_ventas_clientes_mes_cod(text, text, text);
create function public.gv_ventas_clientes_mes_cod(p_cod text, p_mes text, p_empresa text default null)
 returns table(cliente text, cajas numeric, codigos text)
 language plpgsql stable security definer set search_path to 'public'
as $function$
declare
  resp public.http_response; v_cod text; v_mes text; v_url text; v_emp text; v_cods text;
  k constant text := 'sb_publishable_mVX5MnjwM770cNjgiL6yLw_LDNl9pML';
  s constant text := '8b1d35b0182310464380b8e390ac89e96acd0c42fe8c7f98';
begin
  v_cod := regexp_replace(upper(btrim(coalesce(p_cod, ''))), '[^A-Z0-9]', '', 'g');
  v_mes := substr(btrim(coalesce(p_mes, '')), 1, 7);
  if v_cod = '' or v_mes !~ '^[0-9]{4}-[0-9]{2}$' then return; end if;
  v_emp := case lower(btrim(coalesce(p_empresa, '')))
             when 'lk' then 'lk' when 'chef' then 'chef' when 'ch' then 'chef' else '' end;
  -- v24.97 (Luis 30/09) la familia del principal, igual que ventas_mensuales_cod (Equivalencias_Familia)
  select string_agg(c, ',') into v_cods from (
    select v_cod c union
    select regexp_replace(upper(btrim(f.cod_secundario)), '[^A-Z0-9]', '', 'g')
      from public."Equivalencias_Familia" f
     where public.gv_cod_stock(f.cod_principal) = public.gv_cod_stock(v_cod)
       and nullif(btrim(f.cod_secundario), '') is not null) z;
  v_url := 'https://kwkclwhmoygunqmlegrg.supabase.co/rest/v1/rpc/fn_ventas_clientes_mes_fam_virgilio'
        || '?p_cods=' || v_cods || '&p_mes=' || v_mes
        || case when v_emp <> '' then '&p_empresa=' || v_emp else '' end;
  begin
    resp := public.http(('GET', v_url,
      array[ public.http_header('apikey', k), public.http_header('Authorization', 'Bearer ' || k),
             public.http_header('x-feed-secret', s) ],
      null, null)::public.http_request);
  exception when others then return; end;
  if resp is null or resp.status <> 200 then return; end if;
  return query select x.cliente, x.cajas, x.codigos
                 from jsonb_to_recordset(resp.content::jsonb) as x(cliente text, cajas numeric, codigos text);
end $function$;
revoke execute on function public.gv_ventas_clientes_mes_cod(text,text,text) from public;
grant execute on function public.gv_ventas_clientes_mes_cod(text,text,text) to anon, authenticated, service_role;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_ventas_clientes_mes_cod', 'funcion', 'Equivalencias_Familia',
        'El desglose por cliente del pop-up de proyección suma la familia del principal (702EN en 702E), igual que el total mensual',
        'Luis', 'v24.97');

/* ANTERIOR (rollback):
 returns table(cliente text, cajas numeric) — pedía sólo p_cod a fn_ventas_clientes_mes_virgilio
 (url ...rpc/fn_ventas_clientes_mes_virgilio?p_cod=<cod>&p_mes=<mes>[&p_empresa=]) */
