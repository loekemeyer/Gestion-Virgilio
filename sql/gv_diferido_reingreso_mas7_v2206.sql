-- Pedido diferido: la NP que espera mercaderia se arma REINGRESO + 7 DIAS, y nunca se
-- suma a la tanda del resto del pedido (Luis, 2026-09-23). APLICADO en hrxfctzncixxqmpfhskv.
--
-- Caso: pedido de prueba LK 1536 (Luiggy y Luiggy). La pagina lo partio bien (LK 0219 normal,
-- LK 0220 = 323E, reingreso 03/11) y el armador dejo LK 0220 afuera. Pero 5 min despues
-- ppp_web_resync ("agregadas": NP nueva de un pedido ya programado -> a la tanda del pedido)
-- la metio en PRUEBA2 el 15/10 sin mirar GV_PPP_Web_Diferido. Ademas el pase (b2) del armador
-- solo tomaba Zona N: un Retira diferido no se programaba nunca solo.
--
-- Cambios (parche sobre la definicion viva, idempotente por el guard):
--   1. PPP_Web_Config.diferido_dias_post_reingreso = 7 (se cambia con un update, sin deploy).
--   2. gv_diferido_piso(reingreso) = reingreso + esos dias.
--   3. gv_ppp_web_armar_pendientes: (a0) y (b2) usan gv_diferido_piso(no_antes_de); (b2) toma
--      tambien zona Retira.
--   4. ppp_web_resync: "agregadas" saltea la NP con fila en GV_PPP_Web_Diferido cuyo piso aun
--      no llego (gv_diferido_piso(no_antes_de) > gv_ppp_web_dia_minimo()).
-- Probado corriendolo (transaccion abortada): resync no la suma; armador -> 10/11 (03/11 + 7).
-- Aplicado al pedido real: LK 0220 -> PRUEBA3 10/11 (backup zz_backups."GV_Backup_WebProg_LK1536_20260923").
-- Centinelas: GV_Reglas_Centinela (version v22.06), 3 filas.

insert into public."PPP_Web_Config" (clave, valor) values ('diferido_dias_post_reingreso', 7)
on conflict (clave) do nothing;

create or replace function public.gv_diferido_piso(p_reingreso date)
returns date language sql stable set search_path to 'public' as $$
  select p_reingreso + coalesce((select valor::int from public."PPP_Web_Config"
                                  where clave = 'diferido_dias_post_reingreso'), 7);
$$;

do $prueba$
declare d text; n text; c int;
begin
  d := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
  if d !~ 'gv_diferido_piso' then
    n := replace(d, $a$jsonb_build_object('no_antes_de', d.no_antes_de)$a$,
                    $a$jsonb_build_object('no_antes_de', public.gv_diferido_piso(d.no_antes_de))$a$);
    n := replace(n, $a$d.no_antes_de > v_min$a$, $a$public.gv_diferido_piso(d.no_antes_de) > v_min$a$);
    c := (length(n) - length(replace(n,'gv_diferido_piso','')))/length('gv_diferido_piso');
    if c <> 3 then raise exception 'armador: esperaba 3 reemplazos, hubo %', c; end if;
    d := n;
    n := replace(d, $a$      from jsonb_array_elements(v_dif) x
     where nullif(btrim(coalesce(x->>'cod','')),'') is not null
       and coalesce(x->>'zona','') ~ '^\s*Zona\s*[0-9]+'$a$,
    $a$      from jsonb_array_elements(v_dif) x
     where nullif(btrim(coalesce(x->>'cod','')),'') is not null
       -- Luis 23/09: un Retira diferido tambien se programa solo (reingreso + N dias)
       and (coalesce(x->>'zona','') ~ '^\s*Zona\s*[0-9]+' or coalesce(x->>'zona','') ~* '^\s*retira\s*$')$a$);
    if n = d then raise exception 'armador: no matcheo el filtro de zona de (b2)'; end if;
    execute n;
  end if;

  d := pg_get_functiondef('public.ppp_web_resync(text,jsonb)'::regprocedure);
  if d !~ 'GV_PPP_Web_Diferido' then
    n := replace(d, $a$                          and g.order_id = v.order_id and g.np_idx = v.np_idx)
    returning order_id, np_idx, es_agregado$a$,
    $a$                          and g.order_id = v.order_id and g.np_idx = v.np_idx)
       -- Luis 23/09: la NP que espera mercaderia NO se suma a la tanda del resto del pedido:
       -- la programa el pase (b2) del armador, reingreso + N dias.
       and not exists (select 1 from public."GV_PPP_Web_Diferido" dd
                        where dd.empresa = p_empresa and dd.order_id = v.order_id and dd.np_idx = v.np_idx
                          and public.gv_diferido_piso(dd.no_antes_de) > public.gv_ppp_web_dia_minimo())
    returning order_id, np_idx, es_agregado$a$);
    if n = d then raise exception 'resync: no matcheo'; end if;
    execute n;
  end if;
end $prueba$;
