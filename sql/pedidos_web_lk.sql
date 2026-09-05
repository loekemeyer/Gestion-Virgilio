-- ============================================================================
-- Pedidos web de LK, ya partidos en NP · Idea 3717
-- ============================================================================
-- QUÉ ES: las notas de pedido que hoy produce el Excel del mail de las 12:30,
--         calculadas EN VIVO sobre la misma tabla donde caen los pedidos de la
--         página (`orders` del proyecto LK). Gestión Virgilio las lee de acá.
--
-- ⚠ ESTO VIVE ENTERO EN EL PROYECTO **LK** (kwkclwhmoygunqmlegrg).
--
-- NO HAY COPIA. Se probó primero con una tabla espejo en Virgilio alimentada por
--   un cron cada 15 minutos, y se descartó por decisión del dueño (2026-09-03):
--   es otra copia más de un dato que ya existe, con su propia forma de quedar
--   desincronizada. Gestión lee la tabla de LK, directo. Si algo cambia en la
--   página, se ve al instante y no a los 15 minutos.
--
-- CÓMO LLEGA GESTIÓN HASTA ACÁ: el repo ya tiene cliente Supabase de LK y sesión
--   de admin de LK — es el mismo bridge que hoy abre el Panel Web LK sin OTP
--   (`lkTryBridge`, v12.35), que loguea como `loekemeyer.n8n@gmail.com`, que está
--   en `public.admins`. No hace falta ninguna credencial ni permiso nuevo.
--
-- SEGURIDAD: las dos vistas van con `security_invoker = true`, así que la RLS de
--   `orders` es la que decide, no el dueño de la vista. Sin eso, la vista correría
--   como `postgres` y CUALQUIER cliente logueado del portal vería los pedidos de
--   todos los demás. Verificado el 2026-09-03:
--       admin del bridge     → 1.463 NP
--       otro authenticated   → 0 NP
--       anon                 → permission denied
--   Al tocar estas vistas hay que volver a correr esas tres pruebas.
--
-- ----------------------------------------------------------------------------
-- LA REGLA DE CORTE (leída de la Edge Function, no supuesta)
-- ----------------------------------------------------------------------------
--   Sale de `processOrders` de `procesar-pedidos-db`, que es la que arma el Excel
--   del mail. Agrupa por (N° Pedido, Sucursal, Cliente) — y un pedido web tiene un
--   solo cliente y una sola sucursal, así que el grupo es el pedido entero.
--
--   ⚠ **CAMBIÓ el 2026-09-04 (§4.1 del handoff): ahora se BALANCEA POR m³.**
--   El corte viejo hacía bloques del tope contiguos en el orden del carrito
--   (`ceil(linea_rn / tope)`), que es lo que hace la Edge Function del Excel. Eso
--   dejaba colgados: un pedido de 20 líneas salía 18 + 2, y la segunda NP era un
--   viaje por dos renglones. Peor todavía en m³ — el pedido 684 salía
--   0,146 / 0,182 / 0,166 / 0,276 / **0,019**.
--
--   La regla nueva, pedida por el dueño: partir en el MÍNIMO de tramos que respeta
--   el tope —`ceil(lineas / tope)`, el mismo número que antes— y repartir las
--   líneas entre esos tramos de forma pareja en m³. El mismo 684 sale ahora
--   0,171 / 0,161 / 0,157 / 0,152 / 0,147.
--
--   Se puede reordenar porque en el régimen nuevo **el Excel para ISIS lo genera
--   Virgilio**: el pedido web no entra a ISIS hasta que ya está armado y listo, así
--   que no hay nada del otro lado con lo que haya que coincidir línea por línea.
--   (Sigue valiendo el ⚠ de más abajo: NO ordenar por código de artículo. Acá se
--   ordena por m³ para repartir, y dentro de cada NP se restituye el orden del
--   carrito.)
--
--   CÓMO REPARTE — serpentina sobre las líneas ordenadas de mayor a menor m³:
--   1, 2, …, N, N, …, 2, 1, 1, 2, … Las líneas grandes se alternan entre tramos y
--   las chicas compensan. Es determinístico y sale en SQL puro (nada de loops).
--   Deja los tramos parejos en m³ y, de paso, parejos en cantidad de líneas:
--   difieren en 1 como mucho, y no pasan el tope nunca porque
--   `ceil(lineas / N) <= tope` por construcción.
--
--   ⚠ LO QUE **NO** CAMBIA — y es lo que hace seguro el cambio: la CANTIDAD de NP
--   por pedido es idéntica a la del corte viejo, porque N es el mismo. Verificado
--   sobre los 1.019 pedidos: **0 pedidos cambian de cantidad de NP** y **0 tramos
--   pasan el tope**. Como la identidad de una NP es (order_id, np_idx), los números
--   ya repartidos en `PPP_Web_NP` siguen valiendo; lo único que cambia es qué
--   líneas caen en cada uno.
--
--   EL m³ SALE DE VIRGILIO, NO SE COPIA. Se lee por el FDW `virgilio_db` que LK ya
--   tenía, contra la vista `public.vista_volumen_articulo_resuelto` —que además ya
--   resuelve el m³ de un código con "L" desde su artículo base, lo cual importa
--   justamente acá, porque los códigos con L son de Chef—. Una línea sin medida
--   pesa 0 y sólo cuenta por cantidad: no se inventa volumen.
--
--   TOPE: **18 en Loekemeyer, 15 en Chef.** Medido, no recordado: un tope deja una
--   pila de NP justo en el valor del tope. Sobre `PPP_Base_Pedidos` de Virgilio,
--   por cantidad de líneas por NP:
--       líneas:   15    16    17    18    19
--       lk:       25    27    13   253     2      → pila en 18
--       chef:     25     0     1     1     0      → pila en 15, cae a 0 en 16
--   Los pocos que se pasan son NP que no nacieron del Excel web (pedidos por
--   teléfono cargados directo a ISIS): esa tabla tiene todas las NP, no solo las
--   de la página.
--
--   ⚠ NUNCA ORDENAR POR CÓDIGO DE ARTÍCULO ACÁ. La Edge Function no ordena nada:
--   recorre las filas como vienen. Reordenar es el bug clásico de este módulo, y
--   es la razón por la que `lk_pedidos_match` NO sirve para esto — su
--   `items_string` viene ordenado por código y ya perdió el orden del carrito.
--
-- ----------------------------------------------------------------------------
-- ACÁ NO SE NUMERA NADA
-- ----------------------------------------------------------------------------
--   La identidad de una NP es **(order_id, np_idx)**: el pedido y su parte. Nada
--   más. El número visible ("LK 1343") lo reparte GESTIÓN con su propio contador
--   —`ppp_web_np_asignar`, en `sql/ppp_web_programacion.sql`— y se guarda al lado
--   como etiqueta.
--
--   Antes esta vista devolvía un `np_prov` de 9 dígitos que armaba el número acá.
--   Se sacó el 2026-09-03: tener dos numeraciones compitiendo es pedir que se
--   usen mal, y el dueño pidió que el número sea corto (4 dígitos con prefijo de
--   empresa), cosa que una fórmula sobre el order_id no puede dar.
--
--   Lo que sigue valiendo es por qué NO se copia el `N° Pedido` del Excel: ese
--   (`globalN`) es un contador de la tanda —numera primero los pedidos de >= 18
--   líneas y después los chicos—, así que el mismo pedido saca distinto número
--   según con qué otros salga en el mail. No es identidad ni sirve como clave.
--
-- EL m³ NO SALE DE ACÁ: LK no tiene el volumen por caja. Vive en
--   `Volumen_Articulos` de Virgilio y lo resuelve Gestión contra su propia base.
--   Verificado el 2026-09-03: de los 230 artículos que alguna vez se pidieron por
--   la web, los 230 tienen m³ cargado. Del catálogo entero faltan 3 (442E, 444E y
--   446E, los Bowl Ac. Inox. Base Silicona de 16, 20 y 24 cm), que nunca se
--   pidieron por web todavía.
--
-- ALCANCE: hoy solo Loekemeyer. Chef vive en otro proyecto y llega por el FDW
--   `chef_db`; falta el `grant select on public.orders to loke_reader` del lado
--   de Chef, el mismo pendiente que ya saltea `sync_pedidos_match_virgilio`.
--   El tope de 15 ya está contemplado en el CTE `cap`.
-- ============================================================================


-- 1) El pedido web abierto en líneas, EN EL ORDEN DEL CARRITO.
--    `with ordinality` es la pieza que conserva ese orden.
--    La normalización del código replica `padCodArt` de la Edge Function:
--    primera corrida de dígitos a 3 posiciones + primera corrida de letras.
--    El filtro `~ '\d'` no pierde nada: 0 de 16.137 ítems históricos no tienen
--    dígitos (medido 2026-09-03).
create or replace view public.v_pedidos_web
with (security_invoker = true) as
select
  'lk'::text                                                as empresa,
  o.id                                                      as order_id,
  it.ord::int                                               as linea_rn,
  coalesce(o.sheets_payload->>'cod_cliente',
           o.sheets_payload->>'codCliente')                 as cod_cliente,
  c.business_name                                           as razon_social,
  (o.created_at at time zone 'America/Argentina/Buenos_Aires')::date        as fecha_pedido,
  to_char(o.created_at at time zone 'America/Argentina/Buenos_Aires',
          'HH24:MI:SS')                                     as hora_pedido,
  o.created_at,
  coalesce(o.sheets_payload->>'sucursal_entrega',
           o.sheets_payload->>'sucursalEntrega')            as sucursal_entrega,
  o.sheets_payload->>'vend'                                 as vend,
  coalesce(o.sheets_payload->>'condicion_pago_code',
           o.sheets_payload->>'condicionPagoCode')          as condicion_pago_code,
  coalesce(o.sheets_payload->>'numOC',
           o.sheets_payload->>'numero_oc',
           o.sheets_payload->>'numeroOC')                   as numero_oc,
  o.sheets_payload->>'observaciones'                        as observaciones,
  lpad((regexp_match(it.value->>'cod_art', '\d+'))[1], 3, '0')
    || coalesce((regexp_match(it.value->>'cod_art', '[a-zA-Z]+'))[1], '')   as art,
  nullif(coalesce(it.value->>'cajas', it.value->>'Cajas'), '')::numeric     as cajas,
  nullif(it.value->>'uxb', '')::numeric                                     as uxb,
  coalesce(nullif(it.value->>'cajas', ''), '0')::numeric
    * coalesce(nullif(it.value->>'uxb', ''), '0')::numeric                  as uni,
  o.enviado_a_compras_at
from public.orders o
left join public.customers c
  on c.cod_cliente::text = coalesce(o.sheets_payload->>'cod_cliente',
                                    o.sheets_payload->>'codCliente')
cross join lateral jsonb_array_elements(o.sheets_payload->'items')
     with ordinality as it(value, ord)
where o.sheets_payload is not null
  and jsonb_typeof(o.sheets_payload->'items') = 'array'
  and (it.value->>'cod_art') ~ '\d';


-- 2) Las NP ya cortadas. Esto es lo que consume Gestión Virgilio.
--    `items` va como jsonb EN ORDEN para que el front no tenga que pedir las
--    líneas por separado ni volver a ordenarlas.
--    `enviado_a_compras` en false = el pedido todavía no salió por mail, o sea
--    que ISIS ni se enteró. Ese es el caso que la idea 3717 viene a resolver.
-- Ojo al reemplazarla: Postgres no deja SACAR columnas con `create or replace`.
-- Si cambia la lista de columnas hay que `drop view` y volver a crearla.
-- 2.b) El m³ de Virgilio, envuelto. El user mapping del FDW `virgilio_db` es para
--      `postgres`, y la vista de abajo corre con security_invoker; un foreign scan
--      directo adentro fallaría con "permission denied for schema virgilio" al
--      correr como el invocante (mismo caso que la RPC de Chef). Esto NO amplía el
--      acceso a nada: devuelve sólo (código, m³) del catálogo, que no es dato de
--      nadie. Quién ve qué PEDIDO lo sigue decidiendo la RLS de `orders`, afuera.
create or replace function public.virgilio_volumen_map()
returns table (codigo text, m3 numeric)
language sql
security definer
stable
set search_path to 'public', 'virgilio'
as $$
  select v.codigo, v.m3 from virgilio.volumen_articulo v where v.m3 > 0;
$$;

revoke all on function public.virgilio_volumen_map() from public;
grant execute on function public.virgilio_volumen_map() to authenticated, service_role;

-- La foreign table, si no existiera todavía:
--   create foreign table virgilio.volumen_articulo (codigo text, m3 numeric, origen text)
--     server virgilio_db options (schema_name 'public', table_name 'vista_volumen_articulo_resuelto');
-- Y del lado de VIRGILIO, para que el lector del FDW la pueda leer:
--   grant select on public."Volumen_Articulos"             to lk_ppp_reader;
--   grant select on public.vista_volumen_articulo_resuelto to lk_ppp_reader;
--   create policy vol_art_select_lk_reader on public."Volumen_Articulos"
--     for select to lk_ppp_reader using (true);

create view public.v_pedidos_web_np
with (security_invoker = true) as
with vol as materialized (
  -- ⚠ EL `MATERIALIZED` NO ES DECORATIVO. Sin él el planner mete la función adentro
  --   del nested loop y ejecuta el salto FDW a Virgilio UNA VEZ POR PEDIDO: medido,
  --   1.019 veces. Materializado se trae las 1.482 filas una sola vez.
  select codigo, m3 from public.virgilio_volumen_map()
),
cap as (
  select 'lk'::text as empresa, 18 as cap_lineas
  union all
  select 'chef',                15
),
lin as (
  -- m³ de la línea = cajas × m³/caja. Sin medida pesa 0 y sólo cuenta por cantidad.
  select i.*, c.cap_lineas,
         coalesce(i.cajas, 0) * coalesce(v.m3, 0) as linea_m3
  from public.v_pedidos_web i
  join cap c on c.empresa = i.empresa
  left join vol v on v.codigo = upper(btrim(i.art))
),
tramos as (
  -- El MÍNIMO de tramos que respeta el tope. Mismo número que daba el corte viejo,
  -- así que ningún pedido gana ni pierde NP (ver "LA REGLA DE CORTE" arriba).
  select l.*,
         ceil(count(*) over (partition by l.empresa, l.order_id)::numeric
              / l.cap_lineas::numeric)::int as n_tramos
  from lin l
),
orden as (
  -- 2026-09-05 (dueño, v12.94): los bloques van SEGUIDOS en el orden del carrito
  -- (linea_rn), igual que el mail de las 12:30 / ISIS: de a 18 (LK) o 15 (Chef).
  -- Antes era una serpentina balanceada por m³ (rk por linea_m3 desc + ida y vuelta)
  -- que daba la MISMA cantidad de bloques pero con otras líneas adentro: "LK 1345-2"
  -- no era el segundo pedido que ISIS tenía de 1345 (mail 18+4, Gestión 11+11).
  -- Como la página LK guarda los ítems ordenados por código (script.js, sort antes
  -- de grabar), "seguidos" = por código ascendente, exactamente lo que ve ISIS.
  select t.*,
         row_number() over (partition by t.empresa, t.order_id order by t.linea_rn) as rk
  from tramos t
),
part as (
  select o.*, ceil(o.rk::numeric / o.cap_lineas::numeric)::int as np_idx
  from orden o
)
select
  p.empresa,
  p.order_id,
  p.np_idx,
  min(p.cod_cliente)                                 as cod,
  min(p.razon_social)                                as razon_social,
  min(p.fecha_pedido)                                as fecha_recep,
  min(p.hora_pedido)                                 as hora_recep,
  min(p.sucursal_entrega)                            as direccion,
  min(p.vend)                                        as v,
  min(p.condicion_pago_code)                         as condicion_pago_code,
  min(p.numero_oc)                                   as numero_oc,
  bool_and(p.enviado_a_compras_at is not null)       as enviado_a_compras,
  count(*)                                           as lineas,
  sum(p.cajas)                                       as cajas,
  -- Dentro de la NP se restituye el ORDEN DEL CARRITO, no el del balanceo.
  jsonb_agg(jsonb_build_object('art', p.art, 'cajas', p.cajas, 'uxb', p.uxb, 'uni', p.uni)
            order by p.linea_rn)                     as items,
  string_agg(p.art, ',' order by p.linea_rn)         as arts,
  -- v12.73/v12.74: el punto de entrega sale del padrón, no de parsear la dirección.
  min(p.localidad)                                   as localidad,
  min(p.provincia)                                   as provincia,
  min(p.zona_expreso)                                as zona_expreso,
  min(p.nombre_expreso)                              as nombre_expreso,
  min(p.direccion_expreso)                           as direccion_expreso
from part p
group by p.empresa, p.order_id, p.np_idx;


-- 3) Permisos. `anon` no entra ni a mirar; `authenticated` entra pero la RLS de
--    `orders` decide qué ve, y solo un admin ve todo.
revoke all on public.v_pedidos_web    from anon;
revoke all on public.v_pedidos_web_np from anon;
grant select on public.v_pedidos_web    to authenticated;
grant select on public.v_pedidos_web_np to authenticated;


-- ----------------------------------------------------------------------------
-- Controles (correr a mano)
-- ----------------------------------------------------------------------------
--
--   -- Lo que todavía no salió por mail. Sin esto, estos pedidos no existen para
--   -- nadie hasta el día siguiente:
--   select order_id, np_idx, cod, razon_social, fecha_recep, hora_recep, direccion,
--          lineas, cajas
--     from public.v_pedidos_web_np
--    where not enviado_a_compras
--    order by order_id, np_idx;
--
--   -- Que el corte no se haya roto: ninguna NP puede pasarse de su tope.
--   select empresa, max(lineas) from public.v_pedidos_web_np group by empresa;
--
--   -- Las tres pruebas de seguridad (ver arriba). La del medio y la de abajo
--   -- tienen que dar 0 y "permission denied":
--   begin;
--     set local role authenticated;
--     set local request.jwt.claims = '{"sub":"<uid del admin>","role":"authenticated"}';
--     select count(*) from public.v_pedidos_web_np;
--   rollback;
-- ----------------------------------------------------------------------------

-- ============================================================================
-- ANEXO · Validación del m³  (correr en VIRGILIO, hrxfctzncixxqmpfhskv)
-- ============================================================================
-- El m³ de este módulo es `Σ cajas × Volumen_Articulos.m3`. Esta consulta lo
-- contrasta contra el m³ oficial de las NP que ya pasaron por ISIS, que viene de
-- la columna `Mt3` del Sheet. Medido el 2026-09-03 sobre 158 NP:
--   total 51,00 m³ calculado contra 51,13 reales (0,26% de diferencia)
--   error mediano por NP 0,0008 m³ · p95 0,0094 · máximo 0,1239
--   151 de 158 por debajo de los 10 litros
-- Contra `PPP_Entregados_Meta` (637 NP, la otra fuente): total 1,75% abajo,
-- mediana por NP 0,9985.
--
-- ⚠ El filtro `v.m3 > 0` NO es cosmético: 1.613 de las 2.547 filas de
--    `Volumen_Articulos` tienen m³ nulo o cero. Sin ese filtro, un artículo sin
--    medir suma 0 y el resultado sale de menos sin avisar.
--
--   with calc as (
--     select b.pedido as np,
--            sum(b.cajas * v.m3) as m3_calc,
--            count(*) filter (where v.codigo is null) as sin_m3
--     from "PPP_Base_Pedidos" b
--     left join "Volumen_Articulos" v on v.codigo = b.articulo and v.m3 > 0
--     group by b.pedido),
--   real as (
--     select np, max(m3) as m3_real from "PPP_Programacion_Diaria"
--      where m3 > 0 group by np)
--   select count(*) as np,
--          round(sum(c.m3_calc)::numeric, 2)                     as total_calculado,
--          round(sum(r.m3_real)::numeric, 2)                     as total_real,
--          round((percentile_cont(0.5) within group
--                 (order by abs(c.m3_calc - r.m3_real)))::numeric, 4) as err_mediana_m3
--     from calc c join real r on r.np = c.np
--    where c.m3_calc > 0;
--
-- Artículos del catálogo de la web SIN m³ útil (al 2026-09-03): 071, 241, 242,
-- 441Z, 442E, 444E, 446E. Para listarlos de nuevo:
--   select codigo, m3 from "Volumen_Articulos" where m3 is null or m3 <= 0;
-- ============================================================================


-- ============================================================================
-- ANEXO · CHEF  ·  get_pedidos_web_np_chef(p_dias)
-- ============================================================================
-- Chef vive en OTRO proyecto Supabase (nkhzocgdpwtgrmwleihr, otra organización) y
-- se lee por el FDW `chef_db` con el rol remoto `loke_reader`. Habilitado el
-- 2026-09-03 con, del lado de Chef:
--     grant usage on schema public to loke_reader;
--     grant select on public.orders  to loke_reader;
--
-- ⚠ VA EN UNA RPC APARTE, **NO** UNIDA A `v_pedidos_web_np`. Medido: leer
--   `chef_orders` por el FDW cuesta **3.338 ms**. Si Chef estuviera en la misma
--   vista, CADA carga de la pantalla pagaría esos 3,3 s aunque nadie mire Chef.
--   Es exactamente la lección que ya había dejado el padrón de Chef.
--
-- ⚠ VA `SECURITY DEFINER`, no `security_invoker` como las de Loekemeyer, y no es
--   un descuido: el user mapping del FDW es para `postgres`, así que leyendo como
--   el invocante el foreign scan falla. Al correr como el dueño saltea RLS, por
--   eso el chequeo contra `admins` está DENTRO de la función y se le revocó el
--   EXECUTE a `anon`.
--
-- Diferencias con Loekemeyer, todas reales:
--   · tope de **15 líneas** por NP (18 en LK);
--   · la razón social sale de `chef_padron` (copia local), no de `customers`:
--     las numeraciones de cliente son independientes entre las dos empresas;
--   · `chef_orders` **no espeja `enviado_a_compras_at`**, así que
--     `enviado_a_compras` vuelve NULL — de Chef no se sabe si ya salió por mail.
--
-- Estado al 2026-09-03: 116 pedidos, **59 con `sheets_payload`**. Los otros 57 no
-- se pueden partir en NP (no hay ítems) y no aparecen.
--
-- ⚠ 2026-09-04: la RPC usa **el mismo corte balanceado por m³** que la vista de
--   Loekemeyer (ver "LA REGLA DE CORTE" arriba) — mismo `ceil(lineas/15)` de tramos,
--   misma serpentina sobre las líneas ordenadas por m³, mismo orden del carrito
--   restituido dentro de cada NP. Acá el m³ se lee de `virgilio.volumen_articulo`
--   directo (sin la función envoltorio: la RPC ya es SECURITY DEFINER, corre como
--   `postgres` y el foreign scan le funciona). Que la vista de Virgilio resuelva la
--   "L" desde el artículo base importa sobre todo acá: los códigos con L son de Chef.
--   Verificado: 84 NP antes y 84 después, máximo 15 líneas, 0 pedidos cambian de
--   cantidad de NP, y **0 líneas sin m³**.
--
--   -- Control (como admin):
--   select order_id, np_idx, cod, razon_social, lineas, cajas
--     from public.get_pedidos_web_np_chef(30) order by order_id desc, np_idx;
-- ============================================================================
