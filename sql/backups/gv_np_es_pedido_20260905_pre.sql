-- Backup 2026-09-05 ~02:40 ART — ANTES de que la NP web pase a ser el número de pedido
-- de la página (sql/gv_np_es_pedido.sql). Estado previo: contador propio (PPP_Web_NP_Seed),
-- etiqueta de 4 dígitos sin bloque. PPP_Web_NP / Programacion / Base en 0 filas.
-- Restore: ejecutar en orden. Sólo tiene sentido mientras no haya nada numerado.

-- PK original
-- alter table public."PPP_Web_NP" drop constraint "PPP_Web_NP_pkey";
-- alter table public."PPP_Web_NP" add primary key (empresa, np);
-- alter table public."PPP_Web_NP" add constraint "PPP_Web_NP_empresa_order_id_np_idx_key" unique (empresa, order_id, np_idx);

drop view if exists public.gv_ppp_web_entregados;
drop view if exists public.gv_ppp_web_estado;
drop function if exists public.gv_ppp_web_np_label(text, integer, integer);

CREATE OR REPLACE FUNCTION public.gv_ppp_web_np_label(p_empresa text, p_np integer)
 RETURNS text LANGUAGE sql IMMUTABLE AS $function$
  select case when lower(coalesce(p_empresa,'')) in ('chef','ch') then 'CH' else 'LK' end
      || ' '
      || case when length(p_np::text) >= 4 then p_np::text else lpad(p_np::text, 4, '0') end;
$function$;
grant execute on function public.gv_ppp_web_np_label(text, integer) to anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.gv_ppp_web_np_asignar(p_empresa text, p_pares jsonb)
 RETURNS TABLE(r_order_id bigint, r_np_idx integer, r_np integer)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare v_next integer;
begin
  if coalesce((select valor from public."PPP_Web_Config" where clave = 'numeracion_activa'), 0) <> 1 then
    raise exception 'Numeración de NP APAGADA (PPP_Web_Config.numeracion_activa = 0). Se prende el día que Gestión tome control de Producción.';
  end if;
  perform pg_advisory_xact_lock(hashtext('ppp_web_np:' || p_empresa));
  select greatest(coalesce((select max(n.np) from public."PPP_Web_NP" n where n.empresa = p_empresa), 0) + 1,
                  coalesce((select s.desde from public."PPP_Web_NP_Seed" s where s.empresa = p_empresa), 1)) into v_next;
  with pedir as (select (x->>'order_id')::bigint as oid, (x->>'np_idx')::int as idx from jsonb_array_elements(p_pares) x),
  nuevos as (select p.oid, p.idx, row_number() over (order by p.oid, p.idx) - 1 as offset_rn from pedir p
             where not exists (select 1 from public."PPP_Web_NP" n where n.empresa = p_empresa and n.order_id = p.oid and n.np_idx = p.idx))
  insert into public."PPP_Web_NP" (empresa, np, order_id, np_idx)
  select p_empresa, v_next + nu.offset_rn::int, nu.oid, nu.idx from nuevos nu
  on conflict (empresa, order_id, np_idx) do nothing;
  return query
    with pedir as (select (x->>'order_id')::bigint as oid, (x->>'np_idx')::int as idx from jsonb_array_elements(p_pares) x)
    select n.order_id, n.np_idx, n.np from public."PPP_Web_NP" n join pedir p on p.oid = n.order_id and p.idx = n.np_idx where n.empresa = p_empresa;
end $function$;

-- ppp_web_resync y gv_ppp_web_tanda_programar: idénticas a sql/gv_np_es_pedido.sql salvo
-- que la etiqueta se llamaba con dos parámetros: gv_ppp_web_np_label(p_empresa, g2.np) y
-- gv_ppp_web_np_label(p_empresa, (select n.np ...)); y `agregadas` no tenía el coalesce(v.order_id).

-- Vistas: idénticas a sql/gv_np_es_pedido.sql con gv_ppp_web_np_label(g.empresa, g.np) /
-- gv_ppp_web_np_label(p.empresa, p.np) (dos parámetros).
