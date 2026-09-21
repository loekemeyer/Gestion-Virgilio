-- ════════════════════════════════════════════════════════════════════════════════════════
-- v20.45 (Luis, 2026-09-21) — EL DESTINO DEL EXPRESO, Y EL AVISO DE MISIONES
-- ════════════════════════════════════════════════════════════════════════════════════════
-- Pedido textual: *"Tenemos que traer el dato de las dos paginas, tiene que viajar con los
-- pedidos. Esta bueno que muestre la zona así para los expresos (expreso y provincia destino).
-- Pero particularmente para los pedido de misiones necesito que la fila del día que tenga
-- programado un pedido de misiones se ponga naranja y aparezca una medalla que diga (Hay
-- pedido misiones). Lo mismo para tandas. Que las NPs de ese tipo de pedidos tambien se
-- coloreen de naranja y tengan el badge "MISIONES"*.
--
-- ⚠ QUÉ SE MIDIÓ ANTES DE ESCRIBIR ESTO (21/09), porque cambia dónde va el arreglo:
--
--   · El dato SÍ existe en las dos páginas, estructurado:
--     `customer_delivery_addresses` tiene `provincia`, `localidad`, `nombre_expreso`.
--     Para Albalandia (LK 958): provincia = Misiones, localidad = Puerto Rico,
--     nombre_expreso = Snaider, zona_expreso = Soldati.
--   · Y YA VIAJA a Gestión: `GV_Clientes_Direcciones` (2.321 filas, 2.248 con provincia,
--     las dos empresas) la llena todos los días `gv-sync-padron-direcciones`.
--   · Lo que NO existía era atarlo a la NP y mostrarlo. En la PPP, de Misiones no quedaba
--     nada: `PPP_Web_Programacion` guarda `direccion`, `barrio` y `zona`, y ninguna columna
--     de provincia. Lo único que se leía era "Zona 1 · Soldati" — el barrio del galpón del
--     EXPRESO, en CABA, que operativamente está bien (ahí va el camión) pero esconde el
--     destino final.
--   · Tamaño: 143 de 390 pedidos web de LK de los últimos 60 días van al interior (37 %), y
--     141 de ellos con zona de CABA/GBA.
--
-- ⚠ POR QUÉ SE RESUELVE AL LEER Y NO SE PERSISTE EN `PPP_Web_Programacion`:
--   la tabla tiene CINCO caminos de escritura (`gv_ppp_web_armar_pendientes`,
--   `gv_ppp_web_tanda_programar`, `ppp_web_armar_tandas`, `ppp_web_resync` y el upsert del
--   front). Persistir obliga a tocar los cinco y a acordarse del sexto que aparezca — es
--   exactamente el agujero que ya mordió tres veces con `'super|retira|expo'` y con Retira.
--   Resolviéndolo al leer hay UN solo lugar, sirve igual para las NP de ISIS (que nunca
--   pasaron por la página) y para lo viejo, y si el cliente corrige su provincia la PPP se
--   corrige sola en la próxima corrida del padrón.
--
-- ⚠ LA ETIQUETA (`GV_Clientes_Direcciones.etiqueta`, v20.45) ES LA QUE DESAMBIGUA.
--   119 clientes (85 de LK + 34 de Chef) tienen direcciones en MÁS DE UNA provincia: cruzar
--   por `(empresa, cod)` solo no alcanza. La dirección que la PPP guarda lleva la etiqueta
--   de la sucursal entre paréntesis —"Exp. Snaider — PERGAMINO 3751, Soldati (San Martin
--   1801- Puerto Rico)"— y esa etiqueta es el `label` de la dirección en la página.
--   Sin señal que desambigüe NO se inventa: `provincia` queda en null y `como = 'ambiguo'`.
--   Mismo criterio que la reposición chica: *sin datos, retener*.
-- ════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. la columna nueva del padrón y su índice de búsqueda ──────────────────────────────
alter table public."GV_Clientes_Direcciones" add column if not exists etiqueta text;
create index if not exists gv_clientes_direcciones_emp_cod
  on public."GV_Clientes_Direcciones" (empresa, cod);

-- ── 1. qué provincias se marcan (configurable, no hardcodeado) ──────────────────────────
insert into public."PPP_Web_Config" (clave, valor_texto)
values ('provincias_alerta', 'Misiones')
on conflict (clave) do nothing;

create or replace function public.gv_provincia_alerta(p_provincia text)
returns boolean
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select exists (
    select 1
      from unnest(string_to_array(coalesce(
             (select c.valor_texto from public."PPP_Web_Config" c
               where c.clave = 'provincias_alerta'), ''), ',')) as t(p)
     where btrim(t.p) <> ''
       and lower(btrim(t.p)) = lower(btrim(coalesce(p_provincia, '')))
  );
$function$;

-- ── 2. EL PUNTAJE, EN UN SOLO LUGAR ────────────────────────────────────────────────────
-- Lo usan los dos consumidores (la función por pedido y la vista en bloque). Si vive
-- duplicado, un día uno de los dos se corrige y el otro no.
--   9  la ETIQUETA de la sucursal coincide con la del paréntesis  ← la señal que desambigua
--   7  la etiqueta coincide con la dirección entera (pedido sin expreso guardado por etiqueta)
--   6  la dirección de entrega coincide pelada
--   5  mismo dir_key (dirección + barrio normalizados)
--   4  mismo expreso
--   3  la etiqueta del pedido contiene la localidad de la dirección
--   2  misma dirección de expreso
create or replace function public.gv_destino_score(
  p_etiqueta text, p_direccion text, p_dir_key text, p_nombre_expreso text,
  p_dir_expreso text, p_localidad text,
  p_dir text, p_bar text, p_x_exp text, p_x_dirx text, p_x_lab text)
returns integer
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select   (case when coalesce(btrim(p_etiqueta), '') <> ''
                  and lower(btrim(p_etiqueta)) = lower(coalesce(p_x_lab, '')) then 9 else 0 end)
         + (case when coalesce(btrim(p_etiqueta), '') <> '' and p_x_lab is null
                  and lower(btrim(p_etiqueta)) = lower(coalesce(p_dir, '')) then 7 else 0 end)
         + (case when coalesce(btrim(p_direccion), '') <> ''
                  and lower(btrim(p_direccion)) = lower(coalesce(p_dir, '')) then 6 else 0 end)
         + (case when coalesce(p_dir_key, '') <> '' and coalesce(p_dir, '') <> ''
                  and p_dir_key = public.gv_dir_key(p_dir, nullif(p_bar, '')) then 5 else 0 end)
         + (case when coalesce(btrim(p_nombre_expreso), '') <> ''
                  and upper(btrim(p_nombre_expreso)) = upper(coalesce(p_x_exp, '')) then 4 else 0 end)
         + (case when coalesce(btrim(p_localidad), '') <> '' and coalesce(p_x_lab, '') <> ''
                  and lower(p_x_lab) like '%' || lower(btrim(p_localidad)) || '%' then 3 else 0 end)
         + (case when coalesce(btrim(p_dir_expreso), '') <> ''
                  and lower(btrim(p_dir_expreso)) = lower(coalesce(p_x_dirx, '')) then 2 else 0 end);
$function$;

-- ── 3. el resolutor de UN pedido (el que se usa a mano y para probar) ───────────────────
-- Devuelve 0 filas si el cliente no está en el padrón (el llamador usa LEFT JOIN LATERAL).
create or replace function public.gv_destino_de(
  p_empresa   text,
  p_cod       text,
  p_direccion text default null,
  p_barrio    text default null)
returns table (provincia text, localidad text, expreso text, como text)
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  with _de_q as (
    -- "Exp. Snaider — PERGAMINO 3751, Soldati (San Martin 1801- Puerto Rico)"
    --       └ x_exp        └ x_dirx                └ x_lab
    select lower(btrim(coalesce(p_empresa, ''))) as emp,
           btrim(coalesce(p_cod, ''))            as cod,
           btrim(coalesce(p_direccion, ''))      as dir,
           btrim(coalesce(p_barrio, ''))         as bar,
           (regexp_match(btrim(coalesce(p_direccion, '')), '^Exp\.\s*(.+?)\s+—\s'))[1]       as x_exp,
           (regexp_match(btrim(coalesce(p_direccion, '')), '—\s*(.*?)\s*\([^()]*\)\s*$'))[1] as x_dirx,
           (regexp_match(btrim(coalesce(p_direccion, '')), '\(([^()]*)\)\s*$'))[1]           as x_lab
  ), _de_c as (
    select d.slot, d.provincia, d.localidad, d.nombre_expreso,
           public.gv_destino_score(d.etiqueta, d.direccion, d.dir_key, d.nombre_expreso,
                                   d.dir_expreso, d.localidad,
                                   q.dir, q.bar, q.x_exp, q.x_dirx, q.x_lab) as score
      from _de_q q
      join public."GV_Clientes_Direcciones" d
        on d.empresa = q.emp and btrim(d.cod) = q.cod
  ), _de_s as (
    select c.*,
           (select max(z.score) from _de_c z)                              as mx,
           (select count(distinct coalesce(z.provincia, '')) from _de_c z) as prov_todas,
           (select count(distinct coalesce(z.provincia, '')) from _de_c z
             where z.score = (select max(y.score) from _de_c y))           as prov_top
      from _de_c c order by c.score desc, c.slot limit 1
  )
  select case when (s.mx > 0 and s.prov_top = 1) or s.prov_todas = 1 then s.provincia end,
         case when (s.mx > 0 and s.prov_top = 1) or s.prov_todas = 1 then s.localidad end,
         case when (s.mx > 0 and s.prov_top = 1) or s.prov_todas = 1 then s.nombre_expreso end,
         case when s.mx > 0 and s.prov_top = 1 then 'match'
              when s.prov_todas = 1             then 'unica'
              else                                   'ambiguo' end
    from _de_s s;
$function$;

-- ── 4. una fila por NP con su destino: lo que consume la Programación ───────────────────
-- ⚠ Va EN BLOQUE, no llamando a gv_destino_de por fila. Medido el 21/09 sobre las 1.482 NP:
--   por fila 3.219 ms · en bloque 407 ms. La pantalla la pide en cada refresco.
drop view if exists public.gv_destino_sin_provincia;
drop view if exists public.gv_np_destino;

create view public.gv_np_destino
with (security_invoker = true) as
with _nd_todo as (
  select public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np,
         lower(btrim(coalesce(w.empresa, '')))                 as empresa,
         btrim(coalesce(w.cod_cliente, ''))                    as cod,
         w.direccion, w.barrio, 1 as pri, true as programada
    from public."PPP_Web_Programacion" w
  union all
  select regexp_replace(btrim(g.np), '\.0+$', ''),
         public.gv_emp_de_np(g.np), btrim(coalesce(g.cod, '')),
         g.direccion, g.barrio, 2, true
    from public.gv_ppp_programacion_diaria g
  union all
  -- las que ya sólo figuran facturadas: sin dirección, se resuelve por cliente
  select regexp_replace(upper(btrim(f.np)), '\.0+$', ''),
         public.gv_emp_de_np(f.np), btrim(coalesce(f.cod_cliente, '')),
         null::text, null::text, 3, false
    from public."Facturacion_NP" f
), _nd as (
  select distinct on (t.np) t.*
    from _nd_todo t
   where coalesce(btrim(t.np), '') <> '' and t.cod <> ''
   order by t.np, t.pri, t.direccion nulls last
), _q as (
  select n.*,
         (regexp_match(coalesce(n.direccion, ''), '^Exp\.\s*(.+?)\s+—\s'))[1]       as x_exp,
         (regexp_match(coalesce(n.direccion, ''), '—\s*(.*?)\s*\([^()]*\)\s*$'))[1] as x_dirx,
         (regexp_match(coalesce(n.direccion, ''), '\(([^()]*)\)\s*$'))[1]           as x_lab
    from _nd n
), _c as (
  -- LEFT JOIN a propósito: la NP de un cliente que no está en el padrón tiene que seguir
  -- apareciendo, con `como = 'sin padron'`. Si no, el centinela no la ve.
  select q.np, q.empresa, q.cod, q.programada, d.slot, d.provincia, d.localidad, d.nombre_expreso,
         public.gv_destino_score(d.etiqueta, d.direccion, d.dir_key, d.nombre_expreso,
                                 d.dir_expreso, d.localidad,
                                 q.direccion, q.barrio, q.x_exp, q.x_dirx, q.x_lab) as score
    from _q q
    left join public."GV_Clientes_Direcciones" d
      on d.empresa = q.empresa and btrim(d.cod) = q.cod
), _a as (
  select np, max(score) mx, count(slot) cands,
         count(distinct coalesce(provincia, '')) filter (where slot is not null) prov_todas
    from _c group by np
), _t as (
  select c.np, count(distinct coalesce(c.provincia, '')) prov_top
    from _c c join _a a using (np) where c.slot is not null and c.score = a.mx group by c.np
), _p as (
  select distinct on (c.np) c.* from _c c order by c.np, c.score desc nulls last, c.slot
), _r as (
  select p.np, p.empresa, p.cod, p.programada, a.mx, a.cands, a.prov_todas, t.prov_top,
         p.provincia, p.localidad, p.nombre_expreso,
         (a.cands > 0 and ((a.mx > 0 and t.prov_top = 1) or a.prov_todas = 1)) as ok
    from _p p join _a a using (np) left join _t t using (np)
)
select r.np, r.empresa, r.cod, r.programada,
       case when r.ok then r.provincia end                                          as provincia,
       case when r.ok then r.localidad end                                          as localidad_destino,
       case when r.ok then r.nombre_expreso end                                     as expreso,
       case when r.cands = 0                             then 'sin padron'
            when r.mx > 0 and r.prov_top = 1             then 'match'
            when r.prov_todas = 1                        then 'unica'
            else                                              'ambiguo' end         as como,
       public.gv_provincia_alerta(case when r.ok then r.provincia end)              as alerta,
       nullif(concat_ws(' · ',
         nullif(btrim(coalesce(case when r.ok then r.nombre_expreso end, '')), ''),
         nullif(btrim(coalesce(case when r.ok then r.provincia      end, '')), '')), '') as destino_txt
  from _r r;

-- ── 5. el centinela: pedido programado cuyo destino no se pudo resolver ─────────────────
create view public.gv_destino_sin_provincia
with (security_invoker = true) as
select d.np, d.empresa, d.cod, d.como
  from public.gv_np_destino d
 where d.provincia is null and d.programada;

-- las dos vistas nacen con security_invoker; se repite por el protocolo (un CREATE OR
-- REPLACE sin WITH borra las reloptions sin avisar)
alter view public.gv_np_destino            set (security_invoker = true);
alter view public.gv_destino_sin_provincia set (security_invoker = true);

grant select on public.gv_np_destino            to anon, authenticated;
grant select on public.gv_destino_sin_provincia to anon, authenticated;

-- ── 6. centinelas de regla ──────────────────────────────────────────────────────────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values
 ('gv_destino_score', 'funcion', 'p_etiqueta',
  'El destino del expreso se desambigua por la ETIQUETA de la sucursal: 119 clientes tienen direcciones en mas de una provincia y cruzar por (empresa, cod) solo se equivoca.',
  'Luis', 'v20.45'),
 ('gv_np_destino', 'vista', 'sin padron',
  'Sin senal que desambigue NO se inventa la provincia: queda null, y el centinela gv_destino_sin_provincia la muestra.',
  'Luis', 'v20.45'),
 ('gv_np_destino', 'vista', 'gv_provincia_alerta',
  'Que provincias se marcan sale de PPP_Web_Config.provincias_alerta, no hardcodeado en el codigo.',
  'Luis', 'v20.45')
on conflict do nothing;

-- ── chequeo ─────────────────────────────────────────────────────────────────────────────
-- select * from public.gv_np_destino where alerta;              -- los pedidos a Misiones
-- select como, count(*) from public.gv_np_destino group by 1;   -- cuanto resuelve
-- select * from public.gv_destino_sin_provincia;                -- lo que quedo sin destino
-- select * from public.gv_reglas_perdidas;                      -- vacia = todo bien
