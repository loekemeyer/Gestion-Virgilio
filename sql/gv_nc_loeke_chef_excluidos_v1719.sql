-- gv_nc_loeke_chef_excluidos_v1719.sql — APLICADO 2026-09-14 (v17.19).
--
-- Marianela: *"el art 809E CORTA QUESO es un art de Chef que vende Chef"* … *"no corresponde
-- hacer NC de Loekemeyer a Chef"*.
--
-- El checklist "NC a Loeke + stock a Chef" de Facturación mostraba **36 pendientes y 34 eran
-- del 809E** (Corta queso x12, 203 cajas). Ninguna de esas 34 correspondía.
--
-- ── POR QUÉ LO MARCABA ───────────────────────────────────────────────────────────────────
-- `vista_nc_loeke_chef` cruza tres cosas: (a) `Importados` con proveedor Ownland/Kangli/
-- Fujian/Frontier, (b) `Planimetria` con el código cargado en las DOS góndolas, (c) una
-- válvula de escape para decir "este código es de Chef".
--
-- El 809E cumple (a) y (b): `Importados` lo tiene comprado a Ownland, y `Planimetria` tiene
-- TRES filas — `809E` (M13), `809E CH` (M13) y `809E LK` (J13). O sea que físicamente sí está
-- en las dos góndolas; lo que no corresponde es la nota de crédito.
--
-- ⚠ Y la válvula de escape **nunca funcionó**. El CTE `home_chef` excluye lo que
-- `Equivalencias_Codigos` tenga con `cod_real` terminado en `' CH'`, pero esa tabla tiene
-- **4 filas y ninguna termina en ' CH' ni en ' LK'** (438EL→438E, 439EL→439E, 727→727E,
-- 727EN→727E). `home_chef` no matcheaba nada, así que no excluía a nadie desde siempre.
--
-- ── LO QUE SE HIZO ───────────────────────────────────────────────────────────────────────
-- Una tabla propia de exclusiones, en vez de tocar `Equivalencias_Codigos` (que traduce
-- códigos en el PICKING: meterle una fila para apagar un cartel de Facturación cambiaría
-- cómo se pickea) y en vez de borrar el `809E LK` de `Planimetria` (que es la góndola real).

create table if not exists public."GV_NC_Loeke_Chef_Excluidos" (
  cod         text primary key,
  motivo      text not null,
  creado_por  text,
  creado_en   timestamptz not null default now()
);
alter table public."GV_NC_Loeke_Chef_Excluidos" enable row level security;
drop policy if exists gvnce_sel on public."GV_NC_Loeke_Chef_Excluidos";
create policy gvnce_sel on public."GV_NC_Loeke_Chef_Excluidos" for select using (true);
grant select on public."GV_NC_Loeke_Chef_Excluidos" to anon, authenticated;

insert into public."GV_NC_Loeke_Chef_Excluidos" (cod, motivo, creado_por)
values ('809E', 'Articulo de Chef que vende Chef: no corresponde NC de Loekemeyer a Chef (Marianela, 14/09/2026)',
        'Marianela (claude-remote)')
on conflict (cod) do nothing;

-- La vista: `home_chef` ahora es la unión de lo de siempre MÁS esta tabla, y se agrega la
-- columna `razon_social` al final (ver abajo por qué). El CREATE completo está aplicado en la
-- base; acá queda el diff conceptual — la definición viva se recupera con
-- `select pg_get_viewdef('public.vista_nc_loeke_chef'::regclass, true);`
--
--   home_chef AS (
--       SELECT … FROM "Equivalencias_Codigos" WHERE cod_real LIKE '% CH' AND cod_pedido NOT LIKE '%L'
--     UNION
--       SELECT ltrim(upper(btrim(x.cod)), '0') FROM public."GV_NC_Loeke_Chef_Excluidos" x
--   )
--
-- ── Y LA RAZÓN SOCIAL, QUE SALÍA VACÍA ───────────────────────────────────────────────────
-- La columna "Razón Social" del checklist estaba SIEMPRE vacía para las NP viejas, y no era
-- un dato faltante: el front la buscaba en `_facLastTandas`, o sea **sólo entre las tandas que
-- estaban en pantalla ese día**. Como el checklist lista NP históricas (44506, 44508, …), el
-- `rsByNp.get(np)` devolvía "" siempre. Ahora la vista la resuelve en el backend —
-- programación (`gv_ppp_prog_rs`) → `Facturacion_NP` → el cliente de la base del pedido — y el
-- front la usa, dejando el mapa de pantalla sólo como respaldo.
--
-- ── MEDICIÓN ─────────────────────────────────────────────────────────────────────────────
--   Antes: 36 filas (34 del 809E · 203 cajas, 1 del 438E, 1 del 439E), razón social vacía.
--   Después: **2 filas** — 44600 (439E, 16 cajas) y 44601 (438E, 16 cajas), las dos con
--   razón social "Dorinka S.R.L". Son las legítimas: la regla de los coladores 437E/438E/439E
--   (sólo cuando el artículo viene con L) ya estaba en la vista y sigue igual.
--   `NC_Loeke_Chef_Hechas` tenía **0 filas del 809E**: nadie llegó a tildar ninguna de las 34,
--   así que no hay NC mal emitida que deshacer.
--
-- ── ROLLBACK ─────────────────────────────────────────────────────────────────────────────
-- delete from public."GV_NC_Loeke_Chef_Excluidos" where cod = '809E';   -- vuelven las 34
-- (y para sacar la columna razon_social, recrear la vista con la definición anterior a este commit)
