/* v29.82 (Luis, 2026-10-13) — RECEPCIÓN DE INSUMOS: el ORIGEN es una lista CERRADA por categoría.
   "quiero que el menu sea reducido dependiendo de que es lo que estan recibiendo".

   La lista NO se escribe en el front: sale de GP2 (ahí viven los proveedores y los inyectores)
   menos las exclusiones de GV_Insumo_Origen_Excluido, que es donde queda anotado lo que Luis dijo
   que NO recibimos acá aunque GP2 lo tenga. Agregar o sacar un origen es un insert/delete, no un deploy.

   | categoría          | de dónde sale                                                        |
   |--------------------|----------------------------------------------------------------------|
   | plastico           | proveedor_insumo rubro 'Sector Bolsas Plásticas' que entrega en Virgilio |
   | cajas              | proveedor_insumo rubro 'Sector Caja'                                 |
   | partes_plasticas   | los inyectores (ubicacion tipo 'inyector') + Cervantes               |
   | fleje              | componente.proveedor del sector Fleje + Cervantes                    |
   | partes_crudo / parte_procesado | Cervantes y nada más (Luis: "que ni pregunte")           |
   | inyector           | los inyectores, para el ENVÍO de bolsas (EI)                         |

   Rollback: drop function public.gv_insumo_origenes(text); drop function public.gv_insumo_fleje_proveedor();
             drop table public."GV_Insumo_Origen_Excluido";
*/

create table if not exists public."GV_Insumo_Origen_Excluido" (
  ambito      text not null,
  nombre      text not null,
  motivo      text,
  creado_por  text,
  creado_en   timestamptz not null default now(),
  primary key (ambito, nombre)
);
alter table public."GV_Insumo_Origen_Excluido" enable row level security;
revoke insert, update, delete, truncate on public."GV_Insumo_Origen_Excluido" from anon, authenticated;

insert into public."GV_Insumo_Origen_Excluido" (ambito, nombre, motivo, creado_por) values
  ('plastico',         'Simco',          'Luis 13/10: las bolsas las traen Indarnyl, Beta Plasticos y Santa Rosa. Simco esta activo en GP2 (rubro Bolsas Plasticas, sin cod. de proveedor): revisar alla.', 'Luis'),
  ('partes_plasticas', 'JL Matriceria',  'Luis 13/10: los inyectores son Kollplast, Pat Bet Plast y Pettofrezza. JL Matriceria figura como inyector en GP2: revisar alla.', 'Luis'),
  ('inyector',         'JL Matriceria',  'Luis 13/10: "Bolsas plasticas solo se envian a Kollplast, Pat Bet Plast y Pettofrezza".', 'Luis')
on conflict (ambito, nombre) do nothing;

/* Los nombres que GP2 da y los que el operario conoce no siempre son el mismo string
   ("Santa Rosa Plásticos" / "Pettofrezza Rafael"): el apodo lo pone el front (INS_INY_APODO).
   Acá va el nombre REAL de GP2, que es el que viaja al movimiento y a sus RPC. */
create or replace function public.gv_insumo_origenes(p_cat text)
returns table (nombre text, fuente text, orden int)
language sql stable security definer set search_path = public, "GP2" as $fn$
  -- marcador v29.82-origenes
  with cat as (select lower(btrim(coalesce(p_cat, ''))) k),
  base as (
    -- proveedores por rubro: bolsas (sólo los que entregan en Virgilio) y cajas
    select pi.nombre, 'proveedor'::text fuente, 2 orden
      from "GP2".proveedor_insumo pi, cat
     where pi.activo
       and ((cat.k = 'plastico' and pi.rubro = 'Sector Bolsas Plásticas' and pi.entrega_en is null)
         or (cat.k = 'cajas'    and pi.rubro = 'Sector Caja'))
    union all
    -- inyectores: para recibir partes plásticas y para enviar bolsas
    select pi.nombre, 'inyector'::text, 2
      from "GP2".proveedor_insumo pi
      join "GP2".ubicacion u on u.tipo = 'inyector' and u.ref_id = pi.id, cat
     where pi.activo and cat.k in ('partes_plasticas', 'inyector')
    union all
    -- flejes: el proveedor que GP2 tiene asignado a cada fleje
    select distinct btrim(c.proveedor), 'proveedor'::text, 2
      from "GP2".componente c, cat
     where cat.k = 'fleje' and c.sector_id = 5
       and not coalesce(c.discontinuado, false) and btrim(coalesce(c.proveedor, '')) <> ''
    union all
    -- Cervantes: la otra planta. En SC/SP es el único origen posible.
    select 'Cervantes'::text, 'cervantes'::text, 1
      from cat where cat.k in ('fleje', 'partes_plasticas', 'partes_crudo', 'parte_procesado')
  )
  select b.nombre, b.fuente, b.orden
    from base b
   where not exists (select 1 from public."GV_Insumo_Origen_Excluido" x
                      where x.ambito = (select k from cat) and upper(btrim(x.nombre)) = upper(btrim(b.nombre)))
   order by b.orden, b.nombre;
$fn$;
revoke all on function public.gv_insumo_origenes(text) from public;
grant execute on function public.gv_insumo_origenes(text) to anon, authenticated, service_role;

/* De qué proveedor es cada fleje: para que al elegir un proveedor el operario vea SÓLO los de él.
   Devuelve el código de Virgilio (si el fleje está vinculado) y el componente de GP2 (que es lo que
   la lista de recepción muestra cuando el fleje todavía no existe en Virgilio, v29.35). */
create or replace function public.gv_insumo_fleje_proveedor()
returns table (cod text, comp_id bigint, proveedor text)
language sql stable security definer set search_path = public, "GP2" as $fn$
  -- marcador v29.82-flejeprov
  select (select i.cod from "GP2".insumo_equivalencia m
            join public."Insumos" i on upper(btrim(i.cod)) = m.cod_virgilio
           where m.componente_id = c.id limit 1),
         c.id, btrim(c.proveedor)
    from "GP2".componente c
   where c.sector_id = 5 and not coalesce(c.discontinuado, false)
     and btrim(coalesce(c.proveedor, '')) <> '';
$fn$;
revoke all on function public.gv_insumo_fleje_proveedor() from public;
grant execute on function public.gv_insumo_fleje_proveedor() to anon, authenticated, service_role;

/* ⚠ El patrón de un centinela sale del CÓDIGO, nunca del comentario: `gv_reglas_perdidas` limpia
   los comentarios antes de buscar (regla v21.82 / v29.66), así que un patrón `v29.82-origenes` que
   sólo vive en un `--` da "regla perdida" con la regla puesta. Y `objeto` es el NOMBRE pelado de la
   función: la vista cruza por `pg_proc.proname`, no por la firma. Los tres patrones aparecen UNA
   sola vez en su cuerpo (criterio v21.84: 1 = es la regla, borrarla la borra). */
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
  ('gv_insumo_origenes', 'funcion', 'GV_Insumo_Origen_Excluido',
   'El origen de una recepcion de insumos es una lista CERRADA por categoria, derivada de GP2 menos GV_Insumo_Origen_Excluido. SC/SP no preguntan: siempre Cervantes.', 'Luis', 'v29.82'),
  ('gv_insumo_origenes', 'funcion', '''partes_crudo'', ''parte_procesado''',
   'SC y SP no preguntan de quien reciben: el unico origen posible es Cervantes (Luis 13/10).', 'Luis', 'v29.82'),
  ('gv_insumo_fleje_proveedor', 'funcion', 'insumo_equivalencia',
   'Elegido un proveedor de flejes, el operario ve SOLO los flejes que GP2 le tiene asignados (los que no tienen proveedor quedan atras de un boton, nunca se esconden).', 'Luis', 'v29.82');

/* chequeo
   select * from public.gv_reglas_perdidas;                                  -- vacía = todo bien
   select nombre, fuente from public.gv_insumo_origenes('plastico');         -- los 3 de Luis
   select count(*) from public.gv_insumo_fleje_proveedor();                  -- 53 al 13/10
   select ambito, nombre, motivo from public."GV_Insumo_Origen_Excluido";    -- lo que GP2 tiene y acá no va
*/

/* ============================================================================================
   v29.87 (Luis, 13/10): "crea tabla si sólo está en el front el dato".
   Lo que quedaba escrito en `index.html` y es DATO del negocio, no código:
     · el apodo con que el operario conoce a un origen («Manolo» = Pat Bet Plast)  → GV_Insumo_Origen_Apodo
     · cuántas cajas trae un paquete (25) y las marcas que se pueden elegir al recibir → GV_Insumo_Config
   El front los hidrata en `insLoadMeta` (`insFetchConfig`) y lo que tiene escrito queda de
   FALLBACK: si la base no contesta, el operario carga igual que antes.
   ⚠ `gv_insumo_origenes` NO devuelve el apodo: cambiarle las columnas pide DROP + CREATE y el
   connector se cuelga con la palabra de borrado (regla del 07/10). Va en su propia RPC.
   Rollback: drop function public.gv_insumo_config(); drop function public.gv_insumo_apodos();
             drop table public."GV_Insumo_Config", public."GV_Insumo_Origen_Apodo";
   ============================================================================================ */

create table if not exists public."GV_Insumo_Origen_Apodo" (
  nombre     text primary key,
  apodo      text not null,
  nota       text,
  creado_en  timestamptz not null default now()
);
alter table public."GV_Insumo_Origen_Apodo" enable row level security;
revoke insert, update, delete, truncate on public."GV_Insumo_Origen_Apodo" from anon, authenticated;

create table if not exists public."GV_Insumo_Config" (
  clave        text primary key,
  valor        numeric,
  valor_texto  text,
  nota         text,
  creado_en    timestamptz not null default now()
);
alter table public."GV_Insumo_Config" enable row level security;
revoke insert, update, delete, truncate on public."GV_Insumo_Config" from anon, authenticated;

insert into public."GV_Insumo_Origen_Apodo" (nombre, apodo, nota) values
  ('Pat Bet Plast', 'Manolo', 'Thomas D12 (06/10): el nombre con que lo conoce el operario')
on conflict (nombre) do nothing;

insert into public."GV_Insumo_Config" (clave, valor, valor_texto, nota) values
  ('caja_x_paquete', 25, null, 'Thomas D22 (09/10): cada paquete de cajas trae 25'),
  ('marcas', null, 'Loeke,Chef,Mixto', 'Luis 13/10: de que empresa viene el insumo recibido (Mixto = las dos)'),
  ('marcas_cajas', null, 'Loeke,Chef', 'Thomas D26: las cajas son de Loeke o de Chef, no Mixto')
on conflict (clave) do nothing;

create or replace function public.gv_insumo_config()
returns table (clave text, valor numeric, valor_texto text)
language sql stable security definer set search_path = public as $fn$
  -- v29.87: los numeros y las listas del modulo de insumos que vivian en el front
  select c.clave, c.valor, c.valor_texto from public."GV_Insumo_Config" c order by c.clave;
$fn$;
revoke all on function public.gv_insumo_config() from public;
grant execute on function public.gv_insumo_config() to anon, authenticated, service_role;

create or replace function public.gv_insumo_apodos()
returns table (nombre text, apodo text)
language sql stable security definer set search_path = public as $fn$
  -- v29.87: el apodo con que el operario conoce a un origen (antes vivia en el front)
  select a.nombre, a.apodo from public."GV_Insumo_Origen_Apodo" a order by a.nombre;
$fn$;
revoke all on function public.gv_insumo_apodos() from public;
grant execute on function public.gv_insumo_apodos() to anon, authenticated, service_role;

/* chequeo (como anon)
   select * from public.gv_insumo_config();   -- caja_x_paquete 25 · marcas Loeke,Chef,Mixto · marcas_cajas Loeke,Chef
   select * from public.gv_insumo_apodos();   -- Pat Bet Plast → Manolo
*/
