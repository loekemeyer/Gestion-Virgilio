-- =====================================================================================
-- v17.75 (Thomas, 2026-09-14) — CUARENTENA: el pedido que se FACTURA por Chef se evalúa
-- con el cliente de CHEF, no con el de LK.
--
-- EL PEDIDO DEL DUEÑO, textual: *"Hay clientes que compran productos de LK pero se les
-- factura como clientes de CH. Esos clientes son cualquier cliente de Tierra del Fuego +
-- Cencosud. Esos clientes cargan sus pedidos desde la página de LK y se cargan con códigos
-- que terminan con L … La idea es que esos pedidos se pasen como pedidos de CH y se
-- facturen como CH (también, se marcan y se evalúan para cuarentena con código de
-- cliente CH)."*
--
-- ── QUÉ YA ESTABA (v13.77) ───────────────────────────────────────────────────────────
-- La regla vive en la vista `v_pedidos_web` de LK (kwkclwhmoygunqmlegrg): un pedido de la
-- página LK cuya sucursal de entrega está en Tierra del Fuego sale con
--     isis_empresa = 'chef'   ·   cod_isis = el código del MISMO CUIT en `chef_padron`
-- y cada artículo con la L pegada (505 → 505L). El Excel para ISIS ya enruta esa fila al
-- archivo de Chef con ese código (`_facXlsArmar`, index.html ~línea 44022). La NP sigue
-- siendo LK y se pickea de la góndola Loeke: eso NO cambia (decisión del dueño, v13.77).
-- Excepción vigente: La Anónima (CUIT 30506730038) tiene sucursal en Ushuaia y se vende
-- por LK igual — está en `gv_isis_override` de LK y por eso no entra acá.
--
-- ── QUÉ FALTABA, Y ES LO QUE FRENÓ UN PEDIDO REAL ───────────────────────────────────
-- La CUARENTENA seguía mirando el padrón de LK. Y el padrón de LK dice lo que tiene que
-- decir para un cliente al que NO se le vende por LK: **suspendido y límite 0**. Medido el
-- 14/09 sobre `GV_Cuarentena_Fuente`, los 9 clientes mapeados:
--     límite en LK: 0 los nueve      ·  límite en Chef: de $1,2 M a $16 M
--     estado en LK: 4 "Suspendido"   ·  estado en Chef: los nueve "Activo"
--     deuda positiva en Chef: ninguno (tres tienen saldo a favor)
-- O sea: evaluar por LK retiene sin motivo real, y además NUNCA mide el crédito (con
-- límite 0 el cliente ni entra al CTE `lim`, que exige límite > 0).
-- Caso concreto: el pedido **LK 1431** (Il Cheff, 25 líneas en 2 bloques, entrega Deloqui
-- 67, Tierra del Fuego) quedó retenido, no se programó y le abrió tarea a Viviana.
-- Es el problema 192 de `github_repo_problemas`.
--
-- ── EL ARREGLO ───────────────────────────────────────────────────────────────────────
-- Una tabla local `GV_Cliente_Isis` (empresa, cod) → (isis_empresa, cod_isis) que LK
-- EMPUJA por el FDW —exactamente el patrón de `GV_Clientes_Nuevos` y `lk_pedidos_match`:
-- Virgilio lee una tabla local, cero FDW en el camino caliente— y UNA función
-- `gv_cuarentena_ident` que las tres funciones de Cuarentena consultan antes de evaluar.
--
-- POR QUÉ UNA TABLA Y NO EL PAYLOAD: los tres caminos que evalúan cuarentena son el armado
-- automático (Edge Function `gv-ppp-web-tandas-diarias`), "A Programar" (front) y el aviso
-- de lo YA programado (`gv_cuarentena_ya_programado`, que lee `PPP_Web_Programacion` y no
-- tiene ningún payload). Con la tabla la regla queda en UN solo lugar y la ven los tres;
-- con el payload habría que tocar el front y la Edge Function, y el tercero quedaría
-- afuera. **Por eso esta versión no toca ni index.html ni la Edge Function.**
--
-- QUÉ SE MAPEA (y qué no): un cliente de LK entra sólo si **todas** sus direcciones de
-- entrega están en Tierra del Fuego, o si `gv_isis_override` lo manda a Chef, Y además su
-- CUIT existe en `chef_padron`. La Anónima queda afuera por las dos vías (override 'lk' y
-- 10 de sus 11 sucursales fuera de TdF). Medido el 14/09: **9 clientes**, todos con su
-- código de Chef resuelto por CUIT.
--
-- QUÉ **NO** SE REMAPEA: una NP tipeada en ISIS. Lleva el código de ESE ISIS y se factura
-- por esa empresa, así que su padrón es el suyo. Por eso `gv_cuarentena_ident` tiene el
-- tercer argumento `p_es_web`: en `ya_programado` se pasa `origen = 'web'`, y en
-- `marcar_calc` / `limite` se mira que el `order_id` no empiece con `np` (así disfraza el
-- front a una NP de ISIS sin tanda: `order_id = 'np' + NP`).
--
-- ⚠ LÍMITE CONOCIDO: el mapeo es por CLIENTE y la regla real es por PEDIDO (la provincia
-- de la sucursal de entrega). Hoy coinciden porque el único cliente con sucursales mixtas
-- es La Anónima, que va por LK. Si mañana un cliente de TdF suma una sucursal en el
-- continente, deja de cumplir "todas TdF" y vuelve a evaluarse por LK: se degrada al
-- comportamiento viejo, no inventa nada.
--
-- CENCOSUD: hoy NO puede entrar por esta regla porque **no existe como cliente en el
-- padrón de LK** (verificado el 14/09: 0 filas en `customers` con el CUIT 30590360763; en
-- Chef es el 2444). Sus OC entran por PDF Krikos. Para que aplique hacen falta dos cosas
-- del lado de LK: darlo de alta en `customers` con ese CUIT, y —como sus sucursales no son
-- de TdF— agregar `('30590360763','chef')` a `gv_isis_override`. Con esas dos, la vista le
-- pone la L y el cod de Chef, y este mapeo lo toma solo en la próxima corrida del cron.
--
-- MEDICIÓN DESPUÉS (14/09): `gv_cuarentena_marcar_calc` sobre LK 1431 pasó de 1 motivo
-- ('suspendido') a 0; el armado intradía de las 15:45 lo programó solo como **LK 0083 /
-- LK 0084, tanda D69F, entrega 21/09**. `gv_cuarentena_ya_programado` quedó en las mismas
-- 3 filas y ninguna es de los 9 clientes mapeados. Ningún cliente GANA un motivo por el
-- remapeo (ver el cuadro de arriba).
--
-- ROLLBACK (deja todo como el 14/09 a la mañana):
--   -- en LK:       select cron.unschedule('sync-cliente-isis-virgilio');
--   -- en Virgilio: delete from public."GV_Cliente_Isis" where empresa is not null;
--   Con la tabla vacía, `gv_cuarentena_ident` ya devuelve el (empresa, cod) que le entra y
--   el comportamiento es el viejo. Para sacarlo del todo, volver las tres funciones a
--   sql/backups/gv_cuarentena_pre_v1775_20260914.sql.
-- =====================================================================================


-- ═════════════════════════════════════════════════════════════════════════════════════
-- PARTE 1 — VIRGILIO (hrxfctzncixxqmpfhskv)
-- ═════════════════════════════════════════════════════════════════════════════════════

-- ── 1.1) la tabla que empuja LK ──────────────────────────────────────────────────────
create table if not exists public."GV_Cliente_Isis" (
  empresa        text        not null,          -- empresa del PEDIDO (hoy siempre 'lk')
  cod            text        not null,          -- código del cliente en esa empresa
  isis_empresa   text        not null,          -- a qué ISIS va la factura ('chef')
  cod_isis       text        not null,          -- código del MISMO CUIT en esa empresa
  razon_social   text,
  cuit           text,
  motivo         text,                          -- 'tierra_del_fuego' | 'override'
  actualizado_at timestamptz not null default now(),
  primary key (empresa, cod)
);

alter table public."GV_Cliente_Isis" enable row level security;

drop policy if exists "GV_Cliente_Isis_sel"    on public."GV_Cliente_Isis";
drop policy if exists "GV_Cliente_Isis_writer" on public."GV_Cliente_Isis";
create policy "GV_Cliente_Isis_sel"    on public."GV_Cliente_Isis" for select to authenticated using (true);
create policy "GV_Cliente_Isis_writer" on public."GV_Cliente_Isis" for all    to lk_ppp_reader using (true) with check (true);

grant select on public."GV_Cliente_Isis" to anon, authenticated;
grant select, insert, update, delete on public."GV_Cliente_Isis" to lk_ppp_reader;

-- ── 1.2) la resolución, en un solo lugar ─────────────────────────────────────────────
-- Devuelve el (empresa, cod) con el que hay que MIRAR EL PADRÓN. Si no hay mapeo, el mismo
-- que entró. Nunca devuelve null: el llamador la usa sin defensas.
create or replace function public.gv_cuarentena_ident(p_empresa text, p_cod text, p_es_web boolean default true)
returns table (empresa text, cod text)
language sql
stable
set search_path to 'public'
as $$
  -- v17.75 — a qué padrón hay que mirarle la deuda / el límite / el estado. Si el cliente
  -- está mapeado en GV_Cliente_Isis (pedido de la página LK que se factura por Chef: Tierra
  -- del Fuego, o un CUIT puesto a mano en gv_isis_override de LK), devuelve el par de CHEF;
  -- si no, el mismo que entró. Nunca devuelve null.
  -- p_es_web = false apaga el remapeo: una NP tipeada en ISIS lleva el código de ESE ISIS y
  -- se factura por esa empresa, así que su padrón es el suyo. El remapeo es de los pedidos
  -- de la PÁGINA, que son los que la vista v_pedidos_web de LK manda al ISIS de Chef.
  select coalesce(ci.isis_empresa, lower(coalesce(p_empresa, 'lk'))),
         coalesce(ci.cod_isis,     btrim(coalesce(p_cod, '')))
    from (select 1) _
    left join public."GV_Cliente_Isis" ci
           on coalesce(p_es_web, true)
          and ci.empresa = lower(coalesce(p_empresa, 'lk'))
          and ci.cod     = btrim(coalesce(p_cod, ''));
$$;

revoke all on function public.gv_cuarentena_ident(text, text, boolean) from public;
grant execute on function public.gv_cuarentena_ident(text, text, boolean) to anon, authenticated, service_role;

-- ── 1.3) las tres funciones de Cuarentena, evaluando con el par remapeado ────────────
-- El CREATE completo de las tres está en este archivo a propósito: lo único que cambia
-- respecto de sql/backups/gv_cuarentena_pre_v1775_20260914.sql es de dónde salen la
-- `empresa` y el `cod` con los que se consulta GV_Cuarentena_Fuente / GV_Cuarentena_Pagados
-- / GV_Clientes_Nuevos / cobranzas_cliente_cadena. La IDENTIDAD que sale (order_id +
-- empresa) NO se toca: es la clave de Liberados, del Log y de los Comentarios, y la que
-- usa el front.

create or replace function public.gv_cuarentena_marcar_calc(p_pedidos jsonb)
 returns table(order_id text, empresa text, cod text, np text, razon_social text, motivos text[], deuda numeric, estado text, nuevo_pedidos integer)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- v17.75 (Thomas, 2026-09-14): el pedido de la página LK que se FACTURA por Chef (Tierra
  -- del Fuego, artículos con L) se evalúa contra el padrón de CHEF, con el código de Chef del
  -- mismo CUIT. El mapeo vive en GV_Cliente_Isis (lo empuja LK) y lo resuelve gv_cuarentena_ident;
  -- sin mapeo devuelve el mismo (empresa, cod) y nada cambia. Sólo se remapea un pedido de la
  -- PÁGINA: "A Programar" disfraza una NP de ISIS sin tanda como pedido con order_id = 'np'+NP
  -- (index.html), y esa NP lleva el código de SU ISIS, así que su padrón es el suyo.
  -- La IDENTIDAD del pedido (order_id + empresa) NO se toca: aprobaciones, log y comentarios
  -- siguen guardados como 'lk', que es lo que ve el front.
  with ped as (
    select nullif(trim(e->>'order_id'), '') as order_id,
           lower(coalesce(e->>'empresa','lk')) as empresa,
           nullif(trim(e->>'cod'), '') as cod,
           nullif(trim(e->>'np'), '') as np,
           nullif(trim(e->>'razon_social'), '') as razon_social,
           id.empresa as emp_ev,
           id.cod     as cod_ev
    from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
    cross join lateral public.gv_cuarentena_ident(
      lower(coalesce(e->>'empresa','lk')),
      nullif(trim(e->>'cod'), ''),
      coalesce(nullif(trim(e->>'order_id'), ''), '') !~* '^np') id
  ),
  marca as (
    select p.order_id, p.empresa, p.cod, p.np, p.razon_social,
      array_remove(array[
        (select case when f.estado ilike '%suspend%' then 'suspendido'
                     when f.estado ilike '%sin%cta%' then 'sin_cta_cte'
                     when f.suspendido is true then 'suspendido' end
           from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.emp_ev and f.tipo = 'busqueda'
            and f.cod = p.cod_ev and f.suspendido is true limit 1),
        (select 'deuda' from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.emp_ev and f.tipo = 'deuda'
            and f.cod = p.cod_ev and coalesce(f.deuda,0) > 1000
            and not exists (
              select 1 from public.cobranzas_cliente_cadena cc
               where cc.cod_cliente = p.cod_ev
                 and lower(cc.empresa) in (p.emp_ev, case p.emp_ev when 'chef' then 'ch' when 'ch' then 'chef' else p.emp_ev end))
            and not exists (
              select 1 from public."GV_Cuarentena_Pagados" pg
               where pg.empresa = p.emp_ev and pg.cod = p.cod_ev
                 and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
          limit 1),
        (select 'cliente_nuevo' from public."GV_Clientes_Nuevos" cn
          where cn.empresa = p.emp_ev and cn.cod = p.cod_ev limit 1)
      ], null) as motivos,
      (select round(f.deuda, 2) from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.emp_ev and f.tipo = 'deuda'
          and f.cod = p.cod_ev and coalesce(f.deuda,0) > 1000
          and not exists (
            select 1 from public.cobranzas_cliente_cadena cc
             where cc.cod_cliente = p.cod_ev
               and lower(cc.empresa) in (p.emp_ev, case p.emp_ev when 'chef' then 'ch' when 'ch' then 'chef' else p.emp_ev end))
          and not exists (
            select 1 from public."GV_Cuarentena_Pagados" pg
             where pg.empresa = p.emp_ev and pg.cod = p.cod_ev
               and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
        limit 1) as deuda,
      (select nullif(trim(f.estado), '') from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.emp_ev and f.tipo = 'busqueda'
          and f.cod = p.cod_ev and f.suspendido is true limit 1) as estado,
      (select cn.pedidos from public."GV_Clientes_Nuevos" cn
        where cn.empresa = p.emp_ev and cn.cod = p.cod_ev limit 1) as nuevo_pedidos
    from ped p
    where p.cod is not null and p.order_id is not null
  )
  select m.order_id, m.empresa, m.cod, m.np, m.razon_social, m.motivos, m.deuda, m.estado, m.nuevo_pedidos
  from marca m
  where array_length(m.motivos, 1) >= 1
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and not exists (select 1 from public."GV_Cuarentena_Liberados" lb
                     where lb.empresa = m.empresa and public.gv_cuarentena_clave(lb.order_id) = public.gv_cuarentena_clave(m.order_id));
$function$;


create or replace function public.gv_cuarentena_limite(p_pendientes jsonb)
 returns table(order_id text, empresa text, exceso numeric, limite numeric)
 language sql
 security definer
 set search_path to 'public'
as $function$
  -- v15.04 (dueño 2026-09-11): además de marcar, devuelve POR CUÁNTO se pasa del límite
  -- ("Excede crédito por $100.000") y cuál es el límite. La lógica de greedy no cambió.
  -- v17.75 (Thomas, 2026-09-14): el pedido de la página LK que se factura por Chef mide contra
  -- el LÍMITE DE CRÉDITO DE CHEF y con el código de Chef (gv_cuarentena_ident / GV_Cliente_Isis).
  -- El crédito YA USADO se remapea igual, así que las NP web de LK de ese cliente y las NP de
  -- Chef del mismo cliente suman a la misma cuenta. Las NP de ISIS no se remapean: llevan el
  -- código de su propio ISIS. La valorización va con el par remapeado: gv_ppp_web_valor_items
  -- cotiza los artículos con L contra la lista de LK pelando la L, que es el precio real.
  -- La columna `empresa` que sale sigue siendo la del PEDIDO ('lk'): es la clave que usa el front.
  with recursive
  ped as (
    select nullif(trim(e->>'order_id'),'') as order_id,
           lower(coalesce(e->>'empresa','lk')) as empresa,
           nullif(trim(e->>'cod'),'') as cod,
           id.empresa as emp_ev,
           id.cod     as cod_ev,
           coalesce(e->>'fecha_recep','') as fecha_recep,
           public.gv_ppp_web_valor_items(id.empresa, id.cod, e->'items', nullif(e->>'cond','')) as monto
    from jsonb_array_elements(coalesce(p_pendientes,'[]'::jsonb)) e
    cross join lateral public.gv_cuarentena_ident(
      lower(coalesce(e->>'empresa','lk')),
      nullif(trim(e->>'cod'),''),
      coalesce(nullif(trim(e->>'order_id'),''), '') !~* '^np') id
    where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
      and not exists (select 1 from public."GV_Cuarentena_Liberados" lb
                       where lb.empresa = lower(coalesce(e->>'empresa','lk'))
                         and lb.order_id = nullif(trim(e->>'order_id'),''))
  ),
  lim as (
    select f.empresa, f.cod, max(f.limite_credito) as limite
    from public."GV_Cuarentena_Fuente" f
    where f.tipo='busqueda' and coalesce(f.limite_credito,0) > 0
    group by f.empresa, f.cod
  ),
  cl as (
    select distinct p.emp_ev as empresa, p.cod_ev as cod
    from ped p join lim l on l.empresa=p.emp_ev and l.cod=p.cod_ev
    where p.cod_ev is not null
  ),
  npcod0 as (
    select regexp_replace(np::text,'\D','','g') as np, empresa, btrim(cod_cliente) as cod, true as es_web
      from public."PPP_Web_Programacion" where np is not null
    union
    select regexp_replace(np::text,'\D','','g') as np, gv_empresa_de_np_texto(np::text) as empresa, btrim(cod) as cod, false
      from public."GV_PPP_Programacion_Diaria" where np is not null and cod is not null
  ),
  npcod as (
    select n.np, id.empresa, id.cod
      from npcod0 n
      cross join lateral public.gv_cuarentena_ident(n.empresa, n.cod, n.es_web) id
  ),
  base_np as (
    select regexp_replace(bp.pedido::text,'\D','','g') as np,
           jsonb_agg(jsonb_build_object('art', bp.articulo, 'cajas', bp.cajas)) as items
    from public."GV_PPP_Base_Pedidos" bp
    where regexp_replace(bp.pedido::text,'\D','','g') not in
          (select regexp_replace(np::text,'\D','','g') from public."Facturacion_NP" where np is not null)
    group by 1
  ),
  base as (
    select m.empresa, m.cod,
           sum(public.gv_ppp_web_valor_items(m.empresa, m.cod, b.items, '8')) as usado
    from base_np b
    join npcod m on m.np = b.np
    join cl on cl.empresa = m.empresa and cl.cod = m.cod
    group by m.empresa, m.cod
  ),
  pend as (
    select p.empresa, p.emp_ev, p.cod_ev, p.order_id, p.monto, l.limite,
           row_number() over (partition by p.emp_ev, p.cod_ev order by p.fecha_recep, p.order_id) as rn
    from ped p join lim l on l.empresa = p.emp_ev and l.cod = p.cod_ev
    where p.order_id is not null and p.cod_ev is not null
  ),
  walk as (
    select p.empresa, p.emp_ev, p.cod_ev, p.order_id, p.rn, p.monto, p.limite,
           (coalesce(b.usado,0) + p.monto > p.limite) as cuar,
           case when coalesce(b.usado,0) + p.monto > p.limite then coalesce(b.usado,0)
                else coalesce(b.usado,0) + p.monto end as usado,
           (coalesce(b.usado,0) + p.monto - p.limite) as exceso
    from pend p
    left join base b on b.empresa = p.emp_ev and b.cod = p.cod_ev
    where p.rn = 1
    union all
    select p.empresa, p.emp_ev, p.cod_ev, p.order_id, p.rn, p.monto, p.limite,
           (w.usado + p.monto > p.limite),
           case when w.usado + p.monto > p.limite then w.usado else w.usado + p.monto end,
           (w.usado + p.monto - p.limite)
    from walk w join pend p on p.emp_ev = w.emp_ev and p.cod_ev = w.cod_ev and p.rn = w.rn + 1
  )
  select order_id, empresa, round(exceso::numeric, 2) as exceso, round(limite::numeric, 2) as limite
  from walk where cuar;
$function$;


create or replace function public.gv_cuarentena_ya_programado()
 returns table(origen text, empresa text, np text, order_id bigint, clave text, tanda text, fecha_entrega date, cod text, razon_social text, motivos text[], deuda numeric, estado text, picking_empezado boolean, nuevo_pedidos integer, aprobado_at timestamp with time zone, aprobado_por text, comentarios integer)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- v16.57 (problema 14) — La Cuarentena sólo mira lo que TODAVÍA NO tiene tanda:
  -- gv_cuarentena_marcar / _limite corren adentro del armado, sobre los pendientes. Si el
  -- reporte de deuda llega DESPUÉS de que el pedido ya recibió tanda, el pedido sigue viaje.
  -- Esto lo saca a la luz: los mismos motivos, aplicados a lo YA programado y todavía frenable.
  -- No retira nada: retirar un pedido de una tanda ya armada es una decisión operativa.
  -- v17.12 (Luis, 2026-09-14): mismos motivos = también `cliente_nuevo` (GV_Clientes_Nuevos).
  -- v17.23 (Luis, 2026-09-14): el pedido APROBADO sale de la lista — su historia vive en el LOG.
  -- v17.75 (Thomas, 2026-09-14): "mismos motivos" incluye mirar el padrón que corresponde. Un
  -- pedido WEB de LK que se factura por Chef (Tierra del Fuego) se evalúa con el cliente de Chef
  -- (gv_cuarentena_ident / GV_Cliente_Isis). Las NP de ISIS NO se remapean: llevan el código de
  -- su propio ISIS. La columna `empresa` sigue siendo la del pedido: es la clave de Liberados
  -- y Comentarios.
  with prog as (
    select 'web'::text as origen, w.empresa,
           public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np,
           w.order_id, w.tanda, w.fecha_entrega, btrim(w.cod_cliente) as cod, w.razon_social
      from public."PPP_Web_Programacion" w
     where w.np is not null and w.fecha_entrega >= current_date
    union all
    select 'isis', case when (regexp_replace(coalesce(d.np,''),'\D','','g'))::bigint > 90000
                        then 'lk' else 'chef' end,
           btrim(d.np), null::bigint, d.tanda,
           nullif(btrim(d.fecha_entrega),'')::date, btrim(d.cod), d.razon_social
      from public.gv_ppp_programacion_diaria d
     where nullif(regexp_replace(coalesce(d.np,''),'\D','','g'),'') is not null
       and nullif(btrim(d.fecha_entrega),'')::date >= current_date
  ),
  prog2 as (
    select p.*, id.empresa as emp_ev, id.cod as cod_ev
      from prog p
      cross join lateral public.gv_cuarentena_ident(p.empresa, p.cod, p.origen = 'web') id
  ),
  marca as (
    select p.*,
      coalesce(p.order_id::text, p.np) as clave,
      array_remove(array[
        (select case when f.estado ilike '%suspend%' then 'suspendido'
                     when f.estado ilike '%sin%cta%' then 'sin_cta_cte'
                     when f.suspendido is true then 'suspendido' end
           from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.emp_ev and f.tipo = 'busqueda'
            and f.cod = p.cod_ev and f.suspendido is true limit 1),
        (select 'deuda' from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.emp_ev and f.tipo = 'deuda'
            and f.cod = p.cod_ev and coalesce(f.deuda,0) > 1000
            and not exists (
              select 1 from public.cobranzas_cliente_cadena cc
               where cc.cod_cliente = p.cod_ev
                 and lower(cc.empresa) in (p.emp_ev, case p.emp_ev when 'chef' then 'ch' when 'ch' then 'chef' else p.emp_ev end))
            and not exists (
              select 1 from public."GV_Cuarentena_Pagados" pg
               where pg.empresa = p.emp_ev and pg.cod = p.cod_ev
                 and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
          limit 1),
        (select 'cliente_nuevo' from public."GV_Clientes_Nuevos" cn
          where cn.empresa = p.emp_ev and cn.cod = p.cod_ev limit 1)
      ], null) as motivos,
      (select round(f.deuda, 2) from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.emp_ev and f.tipo = 'deuda' and f.cod = p.cod_ev
          and coalesce(f.deuda,0) > 1000
          and not exists (select 1 from public.cobranzas_cliente_cadena cc
                           where cc.cod_cliente = p.cod_ev
                             and lower(cc.empresa) in (p.emp_ev, case p.emp_ev when 'chef' then 'ch' when 'ch' then 'chef' else p.emp_ev end))
          and not exists (select 1 from public."GV_Cuarentena_Pagados" pg
                           where pg.empresa = p.emp_ev and pg.cod = p.cod_ev
                             and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
        limit 1) as deuda,
      (select nullif(trim(f.estado), '') from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.emp_ev and f.tipo = 'busqueda'
          and f.cod = p.cod_ev and f.suspendido is true limit 1) as estado,
      (select cn.pedidos from public."GV_Clientes_Nuevos" cn
        where cn.empresa = p.emp_ev and cn.cod = p.cod_ev limit 1) as nuevo_pedidos
    from prog2 p
   where p.cod is not null
  )
  select m.origen, m.empresa, m.np, m.order_id, m.clave, m.tanda, m.fecha_entrega, m.cod, m.razon_social,
         m.motivos, m.deuda, m.estado,
         exists (select 1 from public."Registros_Produccion_Virgilio" r
                  where btrim(r.texto) = btrim(m.tanda) and nullif(btrim(m.tanda),'') is not null),
         m.nuevo_pedidos,
         lb.liberado_at, nullif(lb.liberado_por,''),
         (select count(*)::int from public."GV_Cuarentena_Comentarios" c
           where c.empresa = m.empresa and public.gv_cuarentena_clave(c.order_id) = public.gv_cuarentena_clave(m.clave))
  from marca m
  left join public."GV_Cuarentena_Liberados" lb
         on lb.empresa = m.empresa and public.gv_cuarentena_clave(lb.order_id) = public.gv_cuarentena_clave(m.clave)
  where array_length(m.motivos, 1) >= 1
    and lb.order_id is null
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and not exists (select 1 from public."Facturacion_NP" fn where btrim(fn.np) = m.np)
  order by m.fecha_entrega, m.empresa, m.np;
$function$;


-- ═════════════════════════════════════════════════════════════════════════════════════
-- PARTE 2 — LK (kwkclwhmoygunqmlegrg): quién calcula el mapeo y lo empuja
-- ═════════════════════════════════════════════════════════════════════════════════════
-- (este bloque NO se corre en Virgilio; va en el SQL editor del proyecto LK)
--
-- create or replace view public.gv_cliente_isis_calc as
-- with c as (
--   select cu.id, cu.cod_cliente::text as cod, cu.business_name,
--          nullif(regexp_replace(coalesce(cu.cuit,''), '\D', '', 'g'), '') as cuit
--     from public.customers cu
-- ), dir as (
--   select d.customer_id,
--          count(*) as n,
--          count(*) filter (where coalesce(d.provincia,'') ilike '%tierra del fuego%') as tdf
--     from public.customer_delivery_addresses d
--    group by 1
-- ), res as (
--   select 'lk'::text as empresa, c.cod,
--          coalesce(ov.isis_empresa,
--                   case when coalesce(dir.n,0) > 0 and dir.tdf = dir.n then 'chef' else 'lk' end) as isis_empresa,
--          (select p.cod_cliente::text from public.chef_padron p
--            where nullif(regexp_replace(coalesce(p.cuit,''), '\D', '', 'g'), '') = c.cuit
--            order by p.cod_cliente limit 1) as cod_isis,
--          c.business_name as razon_social, c.cuit,
--          case when ov.isis_empresa is not null then 'override' else 'tierra_del_fuego' end as motivo
--     from c
--     left join public.gv_isis_override ov on ov.cuit = c.cuit
--     left join dir on dir.customer_id = c.id
--    where c.cuit is not null
-- )
-- select empresa, cod, isis_empresa, cod_isis, razon_social, cuit, motivo
--   from res
--  where isis_empresa <> 'lk' and cod_isis is not null;
--
-- revoke all on public.gv_cliente_isis_calc from public, anon, authenticated;
--
-- create foreign table if not exists virgilio.cliente_isis (
--   empresa text, cod text, isis_empresa text, cod_isis text,
--   razon_social text, cuit text, motivo text, actualizado_at timestamptz
-- ) server virgilio_db options (schema_name 'public', table_name 'GV_Cliente_Isis');
--
-- create or replace function public.sync_cliente_isis_virgilio() ... (reemplazo total;
--   si el cálculo da 0 filas NO pisa nada, porque una lista vacía volvería a evaluar contra
--   el padrón LK, que es justo el bug que esto arregla)
--
-- select cron.schedule('sync-cliente-isis-virgilio', '7-59/15 * * * *',
--                      $$select public.sync_cliente_isis_virgilio();$$);   -- jobid 47
