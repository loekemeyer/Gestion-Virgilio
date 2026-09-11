-- ══════════════════════════════════════════════════════════════════════════
-- v15.82 (2026-09-11) — PRECIO POR CLIENTE: la LÍNEA LOKE (1xx) no tiene lista general
-- ══════════════════════════════════════════════════════════════════════════
-- Dueño (11/09), corrigiendo el informe de la v15.76: *"Los artículos que empiezan con uno
-- son línea Loke, y no hay una lista definida por Loke. Hay solo dos clientes y un par de
-- supermercados que la compran y cada uno tiene su precio cada uno."*
--
-- O sea que los 1xx que quedaban "sin precio" NO son una lista desactualizada: **no existe
-- lista general de Loke**. Verificado: `precios_venta` tiene 0 códigos 1xx. El uxb sí está
-- (`cob_uxb_lk`, que sale de products ∪ loke_products de LK).
--
-- Quién compra Loke hoy (líneas de Facturación):
--   · SUPERMERCADOS — ya resueltos por su LISTA DE CADENA (cobranzas_precios_super):
--     Diarco 4112 (12 códigos 1xx), Coto 801 (4), La Anónima 771 (2), Chango Más (16),
--     Carrefour/INC (11). Salen con precio, 0 líneas sin valorizar.
--   · CENCOSUD (Chef 2444) — está declarada como cadena con lista propia
--     (`usa_lista_general = false`, hoja "Jumbo Krea T") pero la lista está **VACÍA**:
--     0 precios cargados. Por eso sus 24 líneas / 840 cajas de 102E, 106E y 123 salen sin
--     precio. **No es código: hay que importar esa hoja** desde el admin de LK
--     (PDF Krikos → listas de súper). Ídem Dorinka/Walmart (Chef 2686, hoja "WMart Chef").
--   · CLIENTES COMUNES — Osa Distribuidora SRL (LK 2533): 4 líneas / 774 cajas de 102E,
--     103, 106E y 198E. Para éstos NO HABÍA NINGÚN LUGAR donde poner el precio pactado.
--     Eso es lo que agrega este archivo.
--
-- ── La tabla ──────────────────────────────────────────────────────────────
-- public."GV_Precios_Cliente" — precio negociado, por (empresa, cod_cliente, cod).
--   · `es_final = true`  (default): el precio ES el final acordado → NO se le aplica el
--     dto_vol del cliente ni el 2% web. Es la lectura de "cada uno tiene su precio".
--   · `es_final = false`: se trata como precio de lista de ese cliente → se le aplican los
--     dos, igual que la lista general. Se deja por fila para no tener que adivinar.
--   · `uxb` NULL = sale de la lista que corresponda o de `cob_uxb_lk` (para los Loke, de ahí).
--
-- ── Prioridad de precio, ya con esto (las tres vistas) ────────────────────
--   1. lista de SÚPER (cobranzas_precios_super) — es la oficial y la mantiene el importador
--   2. **GV_Precios_Cliente** (precio pactado con ese cliente)
--   3. lista de la empresa de la NP (precios_venta_chef para Chef)
--   4. lista de LK (precios_venta) — fallback, y la única para las NP de LK
--   El uxb suma un último escalón: cob_uxb_lk.
--   La lista de súper va PRIMERO a propósito: es la que se mantiene sola desde el Excel;
--   así una fila cargada a mano acá no le puede pisar en silencio la lista a una cadena.
--
-- ── Cómo se carga un precio ───────────────────────────────────────────────
--   insert into public."GV_Precios_Cliente"
--     (empresa, cod_cliente, cod, precio_unit, es_final, nota, actualizado_por)
--   values ('lk','2533','102E', <precio POR UNIDAD, no por caja>, true,
--           'precio pactado con Osa', 'thomas')
--   on conflict (empresa, cod_cliente, cod) do update
--     set precio_unit = excluded.precio_unit, es_final = excluded.es_final,
--         nota = excluded.nota, actualizado = now(), actualizado_por = excluded.actualizado_por;
--
-- ⚠ `precio_unit` es POR UNIDAD (igual que precios_venta / list_price de LK), no por caja:
--   el importe es cajas × uxb × precio_unit.
--
-- ROLLBACK: drop table public."GV_Precios_Cliente" cascade; + recrear las tres vistas con
--   sql/gv_precio_chef_v1576.sql (que es el estado inmediatamente anterior a esto).
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public."GV_Precios_Cliente" (
  empresa          text        not null check (empresa in ('lk','chef')),
  cod_cliente      text        not null,
  cod              text        not null,
  precio_unit      numeric     not null check (precio_unit > 0),
  uxb              integer     check (uxb is null or uxb > 0),
  es_final         boolean     not null default true,
  nota             text,
  actualizado      timestamptz not null default now(),
  actualizado_por  text,
  primary key (empresa, cod_cliente, cod)
);

create unique index if not exists gv_precios_cliente_canon_uk
  on public."GV_Precios_Cliente" (empresa, cod_cliente, public.canon_cod(cod));

alter table public."GV_Precios_Cliente" enable row level security;
drop policy if exists gvpc_sel on public."GV_Precios_Cliente";
create policy gvpc_sel on public."GV_Precios_Cliente" for select to authenticated using (true);
drop policy if exists gvpc_wr on public."GV_Precios_Cliente";
create policy gvpc_wr on public."GV_Precios_Cliente" for all to authenticated using (true) with check (true);
revoke all on public."GV_Precios_Cliente" from anon;

comment on table public."GV_Precios_Cliente" is
 'Precio NEGOCIADO por cliente (empresa, cod_cliente, cod). Existe porque la LINEA LOKE (codigos 1xx) NO tiene lista general: la compran dos clientes y un par de supermercados, y cada uno tiene su precio. Los supermercados ya van por cobranzas_precios_super (su lista de cadena, que manda sobre esta tabla); esta es para los clientes comunes. es_final=true: el precio es el final acordado, no se le aplica dto_vol ni el 2% web. es_final=false: se trata como precio de lista y se le aplican los dos. uxb null = sale de cob_uxb_lk / de la lista que corresponda.';

-- Las tres vistas quedan como en gv_precio_chef_v1576.sql MÁS el join a GV_Precios_Cliente
-- (y el escalón de uxb contra cob_uxb_lk). La definición vigente de cada una se saca con
--   select pg_get_viewdef('public.<vista>'::regclass, true);
-- Resumen del cambio en cada una:
--   vista_facturacion_neto_items : CTE `val` suma `pcl` y `ux`; `precio_cliente_final`
--     manda el dto a 0 y el factor_web a 1 cuando el precio salió de la tabla con es_final.
--   vista_facturable_anticipado  : CTE `precio` suma `pcl` y `ux`; si es_final, ni dto ni 0,98.
--   vista_plata_perdida          : suma `pcl` y `ux` a la cascada de precio/uxb.

-- ══════════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (hecha el 11/09 con la tabla VACÍA → cero impacto hasta cargar precios)
-- ══════════════════════════════════════════════════════════════════════════
-- · 0 filas con importe/dto/factor distinto contra el estado post-v15.76.
-- · El uxb nuevo aparece en 29 líneas, TODAS sin precio (importe null) → no mueve plata.
-- · Prueba en vivo (cargado y borrado): Osa 2533 · 102E a $1.000 → 200 cajas × 12 × 1.000
--   = $2.400.000, dto 0, factor 1, sin_precio = false. El uxb 12 lo puso cob_uxb_lk.
