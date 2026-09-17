-- v19.44 (Luis, 2026-09-17) — EXCEPCIÓN "reposición chica" en Cuarentena. SEGUNDO intento:
-- el primero (v19.41) se REVIRTIÓ en la v19.43 porque dejó la Cuarentena en 0. Leer el bloque
-- "Lo que salió mal la primera vez" antes de tocar esto.
--
-- Luis: "si un cliente hizo un pedido, se le factura (tiene deuda) y en un plazo de 10 días desde
-- la facturación entra un pedido de ese mismo cliente de 1 item (un código nada más que pide)
-- debería quedar exceptuado de la cuarentena."
--
-- Es el cliente que acaba de comprar, todavía no le venció la factura —por eso figura con deuda—
-- y pide una reposición chica de un solo código. Retenerlo es ruido.
--
-- ╔══════════════════════════════════════════════════════════════════════════════════════════╗
-- ║ LO QUE SALIÓ MAL LA PRIMERA VEZ (v19.41 → revertida en v19.43). Dos errores, y el segundo ║
-- ║ es el caro:                                                                              ║
-- ║                                                                                          ║
-- ║ 1. El join contra lk_pedidos_match casteaba el order_id DEL PEDIDO a bigint, con un regex ║
-- ║    al lado para "protegerlo":                                                             ║
-- ║        on ... and p.order_id ~ '^[0-9]+$' and lp.order_id = (p.order_id)::bigint          ║
-- ║    Postgres NO garantiza el orden de evaluación: hace el cast primero. "A Programar"      ║
-- ║    disfraza una NP de ISIS como pedido con order_id = 'npNNNNN' → 22P02 invalid input     ║
-- ║    syntax for type bigint → la RPC entera devuelve 400. Es EL MISMO pozo del problema 358 ║
-- ║    (v19.11), que ya estaba escrito en el CLAUDE.md.                                       ║
-- ║    → Ahora se castea el bigint DE LA TABLA a texto (lp.order_id::text = p.order_id), que  ║
-- ║      es una conversión que no puede fallar nunca.                                         ║
-- ║                                                                                          ║
-- ║ 2. En el front, la RPC nueva se pidió DENTRO del mismo Promise.all que gv_cuarentena_     ║
-- ║    marcar. Al fallar una, el await tira y cuarMarcarPedidos entero cae al catch: NINGÚN   ║
-- ║    pedido queda marcado. En pantalla: Cuarentena (0) con 60 pedidos retenidos de verdad.  ║
-- ║    → Ahora va en su propia llamada con su propio catch (cuarRepoCargar), y además el      ║
-- ║      backend llama al ENVOLTORIO gv_cuarentena_repo_seguro, que atrapa cualquier          ║
-- ║      excepción y devuelve vacío: si esto falla, no exime a nadie y la Cuarentena sigue.   ║
-- ║                                                                                          ║
-- ║ Regla que queda: lo nuevo no puede llevarse puesto lo que ya funciona.                    ║
-- ╚══════════════════════════════════════════════════════════════════════════════════════════╝
--
-- QUÉ PERDONA Y QUÉ NO. Saca **`deuda`**, no los otros. Si además está suspendido, sin cta cte o
-- es cliente nuevo, el pedido SIGUE retenido: son estados del cliente, no la plata de la compra
-- que se le acaba de facturar. La lista es configurable (gv_cuarentena_repo_motivos).
--
-- DE DÓNDE SALE CADA DATO
--   · ítems y fecha del pedido → `lk_pedidos_match` (la empuja LK cada 15 min, trae LK y Chef,
--     items_string = "607Ex20"). Es la ÚNICA fuente viva de los ítems de un pedido web dentro de
--     Virgilio: los feeds gv_pedidos_web_np_* viven en los proyectos de las páginas.
--   · última factura → `isis_lk.documentos` / `isis_ch.documentos` (familia='factura_venta').
--     La fuente de deuda (GV_Cuarentena_Fuente) NO sirve: su raw es {cod, deuda, razon_social},
--     sin fecha.
--   · qué cliente es → `gv_cuarentena_ident` (Tierra del Fuego: NP de LK que se factura en Chef).
--
-- ⚠ El plazo se cuenta contra la FECHA DEL PEDIDO, no contra hoy, y el max(fecha) de la factura
-- va TOPEADO a esa fecha. Sin el tope entran facturas POSTERIORES al pedido: LK 1375 y LK 1354
-- daban "-2 días" y se colaban teniendo la última factura real a 44 y 38 días.
--
-- ⚠ Una NP de ISIS no se exime: su única fuente de ítems, GV_PPP_Base_Pedidos, está congelada en
-- 2026-09-04. Sin datos no se exime nunca: el default es retener.

-- 1) Config
insert into public."PPP_Web_Config" (clave, valor) values
  ('cuar_repo_activo', 1),      -- 0 = apagar la excepción entera
  ('cuar_repo_dias', 10),       -- plazo desde la factura
  ('cuar_repo_max_items', 1)    -- cuántos códigos distintos puede traer el pedido
on conflict (clave) do nothing;
insert into public."PPP_Web_Config" (clave, valor_texto) values ('cuar_repo_motivos', 'deuda')
on conflict (clave) do nothing;

-- 2) Qué motivos perdona. Default `deuda`; acepta suspendido / sin_cta_cte / cliente_nuevo.
--    ⚠ `limite_credito` NO: ese motivo lo arma gv_cuarentena_limite, no marcar_calc, así que
--    ponerlo acá no haría nada. Medido el 17/09: los dos casos reales no estaban retenidos por
--    límite, así que hoy no cambia nada.
create or replace function public.gv_cuarentena_repo_motivos()
returns text[] language sql stable as $$
  select coalesce(
    (select array_agg(btrim(x)) from unnest(string_to_array(
       (select c.valor_texto from public."PPP_Web_Config" c where c.clave = 'cuar_repo_motivos'), ',')) x
      where btrim(x) <> ''),
    array['deuda']::text[]);
$$;
revoke execute on function public.gv_cuarentena_repo_motivos() from public, anon;
grant  execute on function public.gv_cuarentena_repo_motivos() to authenticated, service_role;

-- 3) El evaluador. Trabaja EN BLOQUE (un solo escaneo de facturas para todo el lote): fila por
--    fila cuesta ~95 ms por cliente y con 100 pedidos no entra en el statement_timeout de 8 s.
--    Clave: lp.order_id::text = p.order_id — NUNCA (p.order_id)::bigint.
create or replace function public.gv_cuarentena_repo_lote(p_pedidos jsonb)
returns table (
  empresa text, order_id text, exento boolean, items integer,
  fecha_pedido date, fecha_factura date, dias integer, motivo text
)
language sql stable security definer set search_path to 'public'
as $$
  with cfg as (
    select coalesce((select c.valor from public."PPP_Web_Config" c where c.clave = 'cuar_repo_activo'), 1) <> 0 as activo,
           coalesce((select c.valor from public."PPP_Web_Config" c where c.clave = 'cuar_repo_dias'), 10)::int as dias,
           coalesce((select c.valor from public."PPP_Web_Config" c where c.clave = 'cuar_repo_max_items'), 1)::int as max_items
  ),
  ped as (
    select nullif(btrim(e->>'order_id'), '') as order_id,
           lower(coalesce(e->>'empresa','lk')) as empresa,
           id.empresa as emp_ev,
           id.cod     as cod_ev
      from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
      cross join lateral public.gv_cuarentena_ident(
        lower(coalesce(e->>'empresa','lk')),
        nullif(btrim(e->>'cod'), ''),
        coalesce(nullif(btrim(e->>'order_id'), ''), '') !~* '^np') id
     where nullif(btrim(e->>'order_id'), '') is not null
  ),
  det as (
    select p.order_id, p.empresa, p.emp_ev, p.cod_ev,
           lp.fecha_pedido,
           array_length(string_to_array(nullif(btrim(lp.items_string), ''), ','), 1) as items
      from ped p
      left join public.lk_pedidos_match lp
        on lp.empresa = p.empresa
       and lp.order_id::text = p.order_id     -- ← bigint → text, JAMÁS al revés
  ),
  lim as (
    select coalesce((select min(d.fecha_pedido) from det d), current_date) - (select dias from cfg) - 1 as desde
  ),
  fc as (
    select 'lk'::text as empresa, canon_cod(d.contraparte_codigo) as cod, d.fecha
      from isis_lk.documentos d, lim
     where d.familia = 'factura_venta' and d.contraparte_codigo is not null and d.fecha >= lim.desde
    union all
    select 'chef', canon_cod(d.contraparte_codigo), d.fecha
      from isis_ch.documentos d, lim
     where d.familia = 'factura_venta' and d.contraparte_codigo is not null and d.fecha >= lim.desde
  ),
  ev as (
    select d.*,
           (select max(f.fecha) from fc f
             where f.empresa = d.emp_ev and f.cod = canon_cod(d.cod_ev)
               and d.fecha_pedido is not null
               and f.fecha <= d.fecha_pedido
               and f.fecha >= d.fecha_pedido - (select dias from cfg)) as fc_en_plazo
      from det d
  )
  select e.empresa, e.order_id,
         ((select activo from cfg)
           and e.items is not null and e.items <= (select max_items from cfg)
           and e.fc_en_plazo is not null) as exento,
         e.items, e.fecha_pedido, e.fc_en_plazo,
         (e.fecha_pedido - e.fc_en_plazo)::int as dias,
         case when not (select activo from cfg)              then 'apagado'
              when e.fecha_pedido is null or e.items is null then 'sin_datos'
              when e.items > (select max_items from cfg)     then 'muchos_items'
              when e.fc_en_plazo is null                     then 'sin_factura_en_plazo'
              else 'reposicion' end as motivo
    from ev e
   where es_supervisor_virgilio() or gv_es_supervisor_o_servicio();
$$;
revoke execute on function public.gv_cuarentena_repo_lote(jsonb) from public, anon;
grant  execute on function public.gv_cuarentena_repo_lote(jsonb) to authenticated, service_role;

-- 4) El ENVOLTORIO que usa gv_cuarentena_marcar_calc. Si el evaluador levanta CUALQUIER
--    excepción, devuelve vacío (nadie exento = todos retenidos) y deja un warning. Es lo que
--    impide que un bug acá vuelva a dejar la Cuarentena en 0.
create or replace function public.gv_cuarentena_repo_seguro(p_pedidos jsonb)
returns table (empresa text, order_id text)
language plpgsql stable security definer set search_path to 'public'
as $$
begin
  return query
    select r.empresa, r.order_id from public.gv_cuarentena_repo_lote(p_pedidos) r where r.exento;
exception when others then
  raise warning 'gv_cuarentena_repo_seguro: la excepcion de reposicion fallo (%), se retiene todo', sqlerrm;
  return;
end;
$$;
revoke execute on function public.gv_cuarentena_repo_seguro(jsonb) from public, anon;
grant  execute on function public.gv_cuarentena_repo_seguro(jsonb) to authenticated, service_role;

-- 5) gv_cuarentena_marcar_calc: CTE `repo` desde el ENVOLTORIO + una condición más en el filtro
--    de motivos: and not (rp.order_id is not null and x = any (gv_cuarentena_repo_motivos()))
--    Respaldo de la versión previa: sql/backups/gv_cuarentena_marcar_calc_pre_v1941_20260917.sql

-- 6) Centinela
create or replace view public.gv_cuarentena_repo_hoy
with (security_invoker = true) as
  select r.*, lp.cod_cliente, lp.items_string
    from public.gv_cuarentena_repo_lote(
          (select coalesce(jsonb_agg(jsonb_build_object(
                    'order_id', m.order_id::text, 'empresa', m.empresa, 'cod', m.cod_cliente)), '[]'::jsonb)
             from public.lk_pedidos_match m
            where m.status = 'pendiente' and m.fecha_pedido >= current_date - 30)) r
    left join public.lk_pedidos_match lp
      on lp.empresa = r.empresa and lp.order_id::text = r.order_id;
revoke select on public.gv_cuarentena_repo_hoy from anon;

-- PRUEBAS CORRIDAS ANTES DE APLICAR (2026-09-17) — esta vez sí, y en este orden:
--   a) lote hostil contra gv_cuarentena_repo_lote: 'np98587', 'np44620', 'EJEMPLO', ' 1449 ',
--      '1450-2', '', sin order_id, cod null y '999999999999999999999' (no entra en bigint).
--      → 0 errores; todos los que no son un pedido web caen en motivo 'sin_datos'.
--   b) gv_cuarentena_repo_seguro con jsonb que no es array y con null → 0 filas, sin error.
--   c) LA PRUEBA DE FUEGO: se reemplazó gv_cuarentena_repo_lote por una versión que hace 1/0 y
--      se corrió gv_cuarentena_marcar_calc con el lote real + una NP de ISIS:
--         excepción ROTA      → 60 retenidos  (la Cuarentena sigue viva, nadie exento)
--         excepción restaurada → 59 retenidos  (saca exactamente 1: LK 1449)
--   d) exentos de hoy: LK 1449 (607Ex20, facturado el mismo día) y CH 217 (609x20, 3 días).
--      Los dos habían entrado a Cuarentena con motivo `deuda` (GV_Cuarentena_Log) y al CH 217
--      tuvo que liberarlo alguien a mano el 17/09 12:07 — ese es el trabajo que esto ahorra.
--   e) front: tests/apr-cuarentena.cjs bloque 4c, con el caso "la RPC del chip explota y la
--      Cuarentena sigue marcando".

-- ROLLBACK
-- drop view if exists public.gv_cuarentena_repo_hoy;
-- drop function if exists public.gv_cuarentena_repo_seguro(jsonb);
-- drop function if exists public.gv_cuarentena_repo_lote(jsonb);
-- drop function if exists public.gv_cuarentena_repo_motivos();
-- delete from public."PPP_Web_Config" where clave like 'cuar_repo%';
-- y correr sql/backups/gv_cuarentena_marcar_calc_pre_v1941_20260917.sql
