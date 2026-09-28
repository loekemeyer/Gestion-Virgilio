-- v23.00 (Luis, 28/09, problema 578): PPP_Web_Base PODA los artículos que salen de una NP.
--
-- Los tres que escriben la foto de picking (Edge gv-ppp-web-tandas-diarias, pppGuardarWeb del
-- front y gv_ppp_web_tanda_programar) hacían upsert y nunca borraban: si el pedido cambiaba
-- después de programado (corte de diferido del 24/09, pedido 1524) el artículo quedaba en las
-- dos NP y E37A pickeó 954E y 956E de más.
--
-- Regla: cada escritura manda la foto COMPLETA de cada NP que toca; lo que la NP tenía y no
-- viene se borra — SÓLO si su tanda no empezó (ningún evento de operario real, mismo criterio
-- que el TANDA_CANDADO de gv_ppp_tanda_mover). Tanda empezada: no se toca, queda anotado como
-- 'retenido' para que lo decida una persona.
-- Todo lo borrado queda en GV_PPP_Web_Base_Podado (es el backup: se restaura con un insert).
--
-- Rollback:
--   drop function public.gv_ppp_web_base_podar(text, jsonb);
--   (y re-deployar la Edge anterior; la RPC manual: quitar el perform marcado v23.00-podar)

create table if not exists public."GV_PPP_Web_Base_Podado" (
  id         bigserial primary key,
  ts         timestamptz not null default now(),
  empresa    text not null,
  order_id   bigint not null,
  np_idx     int not null,
  np_label   text,
  articulo   text not null,
  cajas      numeric,
  tanda      text,
  accion     text not null check (accion in ('borrado','retenido')),
  origen     text
);
alter table public."GV_PPP_Web_Base_Podado" enable row level security;
revoke all on public."GV_PPP_Web_Base_Podado" from anon, authenticated;
create index if not exists gv_ppp_web_base_podado_np on public."GV_PPP_Web_Base_Podado" (empresa, order_id, np_idx);

create or replace function public.gv_ppp_web_base_podar(p_empresa text, p_lineas jsonb, p_origen text default null)
returns table(np_label text, articulo text, cajas numeric, tanda text, accion text)
language plpgsql security definer set search_path to 'public'
as $function$
-- v23.00-podar
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Sólo supervisores pueden tocar la foto de picking.';
  end if;

  create temp table if not exists _pw_lin (order_id bigint, np_idx int, articulo text) on commit drop;
  truncate _pw_lin;
  insert into _pw_lin
  select (x->>'order_id')::bigint, (x->>'np_idx')::int, upper(btrim(x->>'articulo'))
    from jsonb_array_elements(coalesce(p_lineas, '[]'::jsonb)) x
   where btrim(coalesce(x->>'articulo','')) <> '';

  create temp table if not exists _pw_sob on commit drop as
    select b.empresa, b.order_id, b.np_idx, b.np_label, b.articulo, b.cajas, ''::text tanda, false empezada
      from public."PPP_Web_Base" b limit 0;
  truncate _pw_sob;
  insert into _pw_sob
  select b.empresa, b.order_id, b.np_idx, b.np_label, b.articulo, b.cajas,
         coalesce(g.tanda, ''),
         exists (select 1 from public."Registros_Produccion_Virgilio" r
                  where coalesce(g.tanda,'') <> ''
                    and upper(btrim(split_part(r.texto, '|', 1))) = upper(btrim(g.tanda))
                    and coalesce(btrim(r.legajo), '') not in ('0','1'))
    from public."PPP_Web_Base" b
    left join public."PPP_Web_Programacion" g
      on g.empresa = b.empresa and g.order_id = b.order_id and g.np_idx = b.np_idx
   where b.empresa = p_empresa
     and exists (select 1 from _pw_lin l where l.order_id = b.order_id and l.np_idx = b.np_idx)
     and not exists (select 1 from _pw_lin l where l.order_id = b.order_id and l.np_idx = b.np_idx
                                               and l.articulo = upper(btrim(b.articulo)));

  insert into public."GV_PPP_Web_Base_Podado" (empresa, order_id, np_idx, np_label, articulo, cajas, tanda, accion, origen)
  select s.empresa, s.order_id, s.np_idx, s.np_label, s.articulo, s.cajas, s.tanda,
         case when s.empezada then 'retenido' else 'borrado' end, p_origen
    from _pw_sob s
   where not s.empezada
      or not exists (select 1 from public."GV_PPP_Web_Base_Podado" p      -- un retenido se anota una vez
                      where p.empresa = s.empresa and p.order_id = s.order_id and p.np_idx = s.np_idx
                        and p.articulo = s.articulo and p.accion = 'retenido');

  delete from public."PPP_Web_Base" b
   using _pw_sob s
   where not s.empezada and b.empresa = s.empresa and b.order_id = s.order_id
     and b.np_idx = s.np_idx and b.articulo = s.articulo;

  return query select s.np_label, s.articulo, s.cajas, s.tanda,
                      case when s.empezada then 'retenido' else 'borrado' end
                 from _pw_sob s;
end $function$;

revoke all on function public.gv_ppp_web_base_podar(text, jsonb, text) from public, anon;
grant execute on function public.gv_ppp_web_base_podar(text, jsonb, text) to authenticated, service_role;

-- Lo que la poda NO pudo sacar porque la tanda ya estaba empezada. Vacía = todo bien.
create or replace view public.gv_ppp_web_base_sobrante with (security_invoker = true) as
select p.ts, p.empresa, p.np_label, p.articulo, p.cajas, p.tanda
  from public."GV_PPP_Web_Base_Podado" p
  join public."PPP_Web_Base" b
    on b.empresa = p.empresa and b.order_id = p.order_id and b.np_idx = p.np_idx and b.articulo = p.articulo
 where p.accion = 'retenido';
revoke all on public.gv_ppp_web_base_sobrante from anon;

-- La RPC manual (A Programar → tanda borrador → programar): después de su upsert, podar.
-- Se aplica sobre la definición VIVA (bloque DO aparte, idempotente).

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_ppp_web_tanda_programar', 'funcion', 'gv_ppp_web_base_podar',
        'la foto de picking poda los artículos que salen de la NP (problema 578)', 'Luis', 'v23.00');

do $patch$
declare d text; n text;
  ancla text := E'    get diagnostics v_base = row_count;\n';
  extra text := E'    get diagnostics v_base = row_count;\n'
    || E'    -- v23.00-podar (problema 578): lo que la NP tenía y ya no viene, sale de la foto.\n'
    || E'    perform public.gv_ppp_web_base_podar(p_empresa,\n'
    || E'      (select jsonb_agg(jsonb_build_object(''order_id'', x->>''order_id'', ''np_idx'', x->>''np_idx'', ''articulo'', it->>''art''))\n'
    || E'         from jsonb_array_elements(p_items) x, jsonb_array_elements(coalesce(x->''items'',''[]''::jsonb)) it),\n'
    || E'      ''gv_ppp_web_tanda_programar'');\n';
begin
  d := pg_get_functiondef('public.gv_ppp_web_tanda_programar(text,text,date,jsonb,text)'::regprocedure);
  if d ~ 'v23\.00-podar' then raise notice 'ya estaba'; return; end if;
  if position(ancla in d) = 0 then raise exception 'ancla no encontrada en gv_ppp_web_tanda_programar'; end if;
  n := replace(d, ancla, extra);
  execute n;
end $patch$;
