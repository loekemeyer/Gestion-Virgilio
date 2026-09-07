-- ═══════════════════════════════════════════════════════════════════════════════════════
-- v13.70 (2026-09-07) — NP WEB = CONTADOR PROPIO, UN NÚMERO POR BLOQUE, SIN SUFIJO
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Dueño: "el pedido tiene que ser único. No puede haber cuatro variantes de un pedido cuando se
-- separa en cuatro. Guardá el ID del pedido de la página, pero que sea un número de pedido
-- diferente. No 1540-1, 1540-2, 1540-3." Y después: "LK y 4 dígitos. No importa que no tenga
-- relación con el id de página". Retroactivo sobre los 7 pedidos ya partidos (nada pickeado).
--
-- Deshace la regla de v12.92 (NP = número de pedido de la página, bloque con sufijo). Vuelve el
-- CONTADOR de v12.91 (PPP_Web_NP_Seed, lk 1 / chef 1): cada bloque (empresa, order_id, np_idx)
-- recibe el próximo número libre de su empresa la primera vez que se lo pide
-- (gv_ppp_web_np_asignar, idempotente, con lock). El order_id de la página queda guardado en
-- PPP_Web_NP / PPP_Web_Programacion / PPP_Web_Base como referencia; la etiqueta es
-- "LK 0001" / "CH 0001" (4 dígitos, crece pasado 9999).
--
-- Quién pide números: la Edge Function (job 00:01 e intradía) antes de armar, y
-- gv_ppp_web_tanda_programar al programar a mano. A Programar muestra "web 1350" hasta ahí.
--
-- Datos (backup sql/backups/np_web_20260907_pre_contador_v1370.sql): los 26 bloques existentes se
-- renumeraron en orden (empresa, order_id, np_idx): LK 0001–0023, CH 0001–0003; PPP_Web_Programacion.np
-- y PPP_Web_Base.np_label acompañan. Facturacion_NP / Entregas_Virgilio no tenían NP web todavía.
-- ═══════════════════════════════════════════════════════════════════════════════════════

-- ── 1. Etiqueta sin sufijo (misma firma de 3 argumentos: las 8 vistas y 3 funciones que la llaman no cambian)
create or replace function public.gv_ppp_web_np_label(p_empresa text, p_np integer, p_np_idx integer default 1)
returns text language sql immutable as $$
  -- "LK 0001" · "CH 0001". v13.70: un número por bloque, sin "-N" (p_np_idx se ignora).
  select case when lower(coalesce(p_empresa,'')) in ('chef','ch') then 'CH' else 'LK' end
      || ' '
      || case when length(p_np::text) >= 4 then p_np::text else lpad(p_np::text, 4, '0') end;
$$;
grant execute on function public.gv_ppp_web_np_label(text, integer, integer) to anon, authenticated, service_role;

-- ── 2. Un número no se repite dentro de la empresa
create unique index if not exists ppp_web_np_empresa_np_uk on public."PPP_Web_NP" (empresa, np);

-- ── 3. Asignar = contador (idempotente, serializado por empresa)
create or replace function public.gv_ppp_web_np_asignar(p_empresa text, p_pares jsonb)
returns table(r_order_id bigint, r_np_idx integer, r_np integer)
language plpgsql security definer set search_path to 'public'
as $function$
declare v_next int;
begin
  if coalesce((select valor from public."PPP_Web_Config" where clave = 'numeracion_activa'), 0) <> 1 then
    raise exception 'Numeración de NP APAGADA (PPP_Web_Config.numeracion_activa = 0). Se prende el día que Gestión tome control de Producción.';
  end if;
  -- Dos corridas a la vez no pueden repartir el mismo número.
  perform pg_advisory_xact_lock(hashtext('gv_ppp_web_np_asignar:' || p_empresa));
  select greatest(coalesce((select s.desde from public."PPP_Web_NP_Seed" s where s.empresa = p_empresa), 1),
                  coalesce((select max(n.np) + 1 from public."PPP_Web_NP" n where n.empresa = p_empresa), 1))
    into v_next;
  insert into public."PPP_Web_NP" (empresa, np, order_id, np_idx)
  select p_empresa, v_next - 1 + row_number() over (order by q.oid, q.idx), q.oid, q.idx
    from (
      select distinct (x->>'order_id')::bigint as oid, (x->>'np_idx')::int as idx
        from jsonb_array_elements(coalesce(p_pares, '[]'::jsonb)) x
    ) q
   where not exists (select 1 from public."PPP_Web_NP" n
                      where n.empresa = p_empresa and n.order_id = q.oid and n.np_idx = q.idx);
  return query
    with pedir as (
      select (x->>'order_id')::bigint as oid, (x->>'np_idx')::int as idx
      from jsonb_array_elements(coalesce(p_pares, '[]'::jsonb)) x
    )
    select n.order_id, n.np_idx, n.np
      from public."PPP_Web_NP" n
      join pedir p on p.oid = n.order_id and p.idx = n.np_idx
     where n.empresa = p_empresa;
end
$function$;
revoke all on function public.gv_ppp_web_np_asignar(text, jsonb) from public, anon, authenticated;
grant execute on function public.gv_ppp_web_np_asignar(text, jsonb) to service_role;

-- ── 4. Renumeración de lo existente (se corrió una vez el 2026-09-07; idempotente sólo si no hay np > 26)
-- with ord as (select empresa, order_id, np_idx, row_number() over (partition by empresa order by order_id, np_idx) as nuevo
--                from public."PPP_Web_NP")
-- update public."PPP_Web_NP" n set np = o.nuevo from ord o where ...;   (ver §3.aw)
