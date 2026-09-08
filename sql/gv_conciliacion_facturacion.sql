-- ══════════════════════════════════════════════════════════════════════════
-- gv_conciliacion_facturacion.sql — CONCILIACIÓN forward-looking (pestaña nueva)
-- v14.30 · 2026-09-08 · Virgilio (hrxfctzncixxqmpfhskv) · objetos NUEVOS gv_/GV_
-- ══════════════════════════════════════════════════════════════════════════
-- QUÉ ES (pedido de Luis, 08/09): la pestaña "Conciliación" de Facturación no es el
-- cruce retrospectivo de 30 días (ese sigue existiendo en "🔍 Cruce con ISIS" y en
-- Deuda/Cobranzas). Es un REGISTRO FORWARD-LOOKING: a partir de hoy, cada vez que se
-- manda algo a facturar desde Gestión (NP web = bajar el Excel ISIS · NP de ISIS =
-- tilde ✓ — las dos pasan por facMarcarFacturada en el front), se guarda UNA FILA con
-- el monto que Gestión definió que correspondía facturar (SNAPSHOT, congelado), y en
-- otra columna aparece el monto de la factura parseada de ISIS que le corresponde
-- (se completa solo cuando ISIS la sube). Más recientes arriba.
--
-- POR QUÉ SNAPSHOT: "este módulo debería ser un snapshot de lo que se mandó vs lo que
-- se facturó realmente; el resto del pipeline siempre en vivo" (Luis). El neto de
-- Gestión se recalcula solo en el resto del pipeline (cambia con lista/cajas); acá se
-- congela lo que se envió ese día. El neto de la factura (ISIS) se resuelve en vivo
-- contra los documentos parseados hasta que aparece.
--
-- COMPARTIDA: todo lleva prefijo GV_/gv_ y NO lo lee Producción Virgilio. No se toca
-- ningún objeto de Producción. Se REUSA (sólo lectura) gv_vista_facturacion_neto y
-- gv_vista_cruce_facturacion (creados en gv_cruce_facturacion.sql, v13.10/v14.13).
--
-- ROLLBACK:
--   drop function if exists public.gv_conciliacion_lista(int,int,text,text);
--   drop function if exists public.gv_conciliacion_registrar(text);
--   drop table if exists public."GV_Conciliacion_Facturacion";
-- ══════════════════════════════════════════════════════════════════════════

-- 1) La tabla del snapshot. Nuestra (GV_), RLS prendida. La NP es la clave: una NP se
--    manda a facturar una vez; si se re-factura, el snapshot original NO se pisa
--    (ON CONFLICT DO NOTHING en el registrar) — es lo que se envió la primera vez.
create table if not exists public."GV_Conciliacion_Facturacion" (
  np              text primary key,
  empresa         text,
  tanda           text,
  cod_cliente     text,
  razon_social    text,
  fecha_salida    date,
  cajas_ent       numeric,
  neto_gestion    numeric,            -- SNAPSHOT: lo que Gestión calculó al facturar
  items_sin_precio integer,
  origen          text,               -- 'web' | 'isis' (informativo)
  registrado_at   timestamptz not null default now()
);

alter table public."GV_Conciliacion_Facturacion" enable row level security;

-- Lectura para el front (anon/authenticated). La escritura va SÓLO por la RPC
-- SECURITY DEFINER de abajo; no se da INSERT/UPDATE/DELETE directo a la anon key.
drop policy if exists gv_concil_sel on public."GV_Conciliacion_Facturacion";
create policy gv_concil_sel on public."GV_Conciliacion_Facturacion"
  for select to anon, authenticated using (true);

revoke insert, update, delete on public."GV_Conciliacion_Facturacion" from anon, authenticated;
grant select on public."GV_Conciliacion_Facturacion" to anon, authenticated;

-- 2) Registrar el snapshot al momento de facturar. Congela el neto que Gestión calculó
--    (gv_vista_facturacion_neto = cajas ENTREGADAS × lista × descuento, web ×0,98) y
--    los datos de la NP (Facturacion_NP). ON CONFLICT DO NOTHING: no repisa el primer envío.
create or replace function public.gv_conciliacion_registrar(p_np text)
returns void
language sql
volatile
security definer
set search_path = public, pg_temp
as $$
  insert into public."GV_Conciliacion_Facturacion"
    (np, empresa, tanda, cod_cliente, razon_social, fecha_salida,
     cajas_ent, neto_gestion, items_sin_precio, origen)
  select f.np,
         public.gv_empresa_de_np_texto(f.np),
         f.tanda,
         coalesce(n.cod_cliente, f.cod_cliente),
         f.razon_social,
         f.fecha_salida,
         n.cajas_ent,
         n.neto,
         n.items_sin_precio,
         case when f.np ~* '^\s*(LK|CH)' then 'web' else 'isis' end
    from public."Facturacion_NP" f
    left join public.gv_vista_facturacion_neto n on n.np = f.np
   where regexp_replace(f.np, '\.0+$', '') = regexp_replace(p_np, '\.0+$', '')
   order by f.facturado_at desc nulls last
   limit 1
  on conflict (np) do nothing;
$$;
grant execute on function public.gv_conciliacion_registrar(text) to anon, authenticated;

-- 3) La lista de la pestaña: snapshot ⋈ factura parseada (en vivo). El neto de Gestión
--    sale del snapshot (congelado); el de ISIS y el match salen de gv_vista_cruce_facturacion
--    (mismo match cliente + fecha ±3 + cajas que usa el cruce). La diferencia y el estado
--    se recalculan CONTRA el snapshot. Más recientes arriba.
create or replace function public.gv_conciliacion_lista(
  p_limit   int  default 200,
  p_offset  int  default 0,
  p_q       text default null,
  p_empresa text default null)
returns table (
  np text, empresa text, tanda text, cod_cliente text, razon_social text,
  fecha_salida date, cajas_ent numeric, neto_gestion numeric, items_sin_precio integer,
  registrado_at timestamptz,
  factura_neto numeric, factura_cajas numeric, comprobante_id text, doc_fecha date,
  storage_path text, es_super boolean,
  diff numeric, diff_pct numeric, estado text, total_count bigint)
language sql
security definer
set search_path = public, pg_temp
as $$
  with j as (
    select s.np, s.empresa, s.tanda, s.cod_cliente, s.razon_social,
           s.fecha_salida, s.cajas_ent, s.neto_gestion, s.items_sin_precio, s.registrado_at,
           c.factura_neto, c.factura_cajas, c.comprobante_id, c.doc_fecha, c.storage_path,
           coalesce(c.es_super, false) as es_super,
           case when c.factura_neto is not null and s.neto_gestion is not null
                then round(c.factura_neto - s.neto_gestion, 2) end as diff,
           case when c.factura_neto is not null and s.neto_gestion is not null and s.neto_gestion <> 0
                then round((c.factura_neto - s.neto_gestion) / s.neto_gestion * 100, 2) end as diff_pct,
           case when s.neto_gestion is null then 'sin_neto'
                when c.factura_neto is null then 'sin_factura'
                when abs(c.factura_neto - s.neto_gestion) <= greatest(50, s.neto_gestion * 0.01) then 'ok'
                else 'diff' end as estado
      from public."GV_Conciliacion_Facturacion" s
      left join public.gv_vista_cruce_facturacion c on c.np = s.np
  )
  select j.*, count(*) over ()::bigint as total_count
    from j
   where (p_empresa is null or p_empresa = '' or j.empresa = p_empresa)
     and (p_q is null or p_q = ''
          or j.razon_social ilike '%'||p_q||'%' or j.cod_cliente ilike '%'||p_q||'%' or j.np ilike '%'||p_q||'%')
   order by j.registrado_at desc
   limit greatest(p_limit, 1) offset greatest(p_offset, 0)
$$;
grant execute on function public.gv_conciliacion_lista(int, int, text, text) to anon, authenticated;

-- 4) Totales del período (para el resumen arriba de la tabla).
create or replace function public.gv_conciliacion_totales(
  p_empresa text default null)
returns table (estado text, n bigint, suma_diff numeric)
language sql
security definer
set search_path = public, pg_temp
as $$
  with j as (
    select case when s.neto_gestion is null then 'sin_neto'
                when c.factura_neto is null then 'sin_factura'
                when abs(c.factura_neto - s.neto_gestion) <= greatest(50, s.neto_gestion * 0.01) then 'ok'
                else 'diff' end as estado,
           case when c.factura_neto is not null and s.neto_gestion is not null
                then round(c.factura_neto - s.neto_gestion, 2) end as diff
      from public."GV_Conciliacion_Facturacion" s
      left join public.gv_vista_cruce_facturacion c on c.np = s.np
     where (p_empresa is null or p_empresa = '' or s.empresa = p_empresa)
  )
  select estado, count(*)::bigint, coalesce(sum(diff), 0) from j group by estado;
$$;
grant execute on function public.gv_conciliacion_totales(text) to anon, authenticated;

-- ══════════════════════════════════════════════════════════════════════════
-- v14.31 (2026-09-08) — DETALLE "a facturar" por NP (pedido de Luis: "mostrame además
-- del PDF, el listado de a facturar que aparecía en la página, para visualizar el error").
-- Devuelve las líneas por artículo que Gestión mandó a facturar (cajas ENTREGADAS × lista ×
-- descuento, web ×0,98), para comparar contra el PDF de ISIS. Sólo lee. La usa el botón 📋
-- de la pestaña Conciliación.
-- ROLLBACK: drop function if exists public.gv_conciliacion_detalle(text);
-- ══════════════════════════════════════════════════════════════════════════
create or replace function public.gv_conciliacion_detalle(p_np text)
returns table (
  cod text, cajas_ped numeric, cajas_ent numeric, uxb numeric,
  precio_lista numeric, dto_vol numeric, importe_ent numeric, neto_linea numeric, sin_precio boolean)
language sql
security definer
set search_path = public, pg_temp
as $$
  select i.cod, i.cajas_ped, i.cajas_ent, i.uxb, i.precio_lista, i.dto_vol, i.importe_ent,
         round(coalesce(i.importe_ent, 0) * i.factor_web, 2) as neto_linea, i.sin_precio
    from public.gv_vista_facturacion_neto_items i
   where i.np = regexp_replace(p_np, '\.0+$', '')
   order by (i.cajas_ent is null), i.cod;
$$;
grant execute on function public.gv_conciliacion_detalle(text) to anon, authenticated;

-- ══════════════════════════════════════════════════════════════════════════
-- v14.34 (2026-09-08) — neto EN VIVO + flag "corregido" + diagnóstico línea a línea.
-- Pedido de Luis: (a) toggle "sólo diferencias" (front), (b) diagnóstico de a qué se debe
-- la diferencia (item sin precio, descuento/lista, precio puntual), (c) detectar si un
-- cambio posterior ya la corrigió → mostrar OK + leyenda del error original.
--   · gv_conciliacion_lista suma `neto_actual` (recálculo en vivo de gv_vista_facturacion_neto)
--     y `corregido` (tenía diff en el snapshot pero el cálculo actual ya coincide con ISIS).
--   · gv_conciliacion_comparar(np): compara LÍNEA A LÍNEA Gestión (cálculo actual) vs los
--     documento_items de la factura de ISIS matcheada (precio, dto_1+dto_2, cajas, importe),
--     full outer join por canon_cod, con un `motivo` por renglón (precio/descuento/sin_precio/
--     falta_en_gestion/no_facturado/importe/ok). El front arma el diagnóstico a partir de eso.
-- ROLLBACK: recrear gv_conciliacion_lista con la firma vieja (sin neto_actual/corregido) y
--   drop function if exists public.gv_conciliacion_comparar(text);
-- (SQL vigente aplicado por migración gv_conciliacion_diag_corregido_v1434.)
-- ══════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════
-- v14.38 (2026-09-08) — "corregido"/"ok" = IDÉNTICO (tolerancia estricta $100, no 1%) +
-- columna "¿Por qué?" (motivo) en la lista. Pedido de Luis: "corregido = que dé IGUAL
-- ISIS = Gestión; tiene que ser idéntico" (Vargas 98484 marcaba corregido con 0,76% de dif).
--   · gv_conciliacion_lista: estado 'ok' y flag 'corregido' pasan a exigir |dif| <= $100 (antes
--     greatest(50, neto*0.01) = 1%). Suma columna `motivo` (sólo filas con diferencia).
--   · gv_conciliacion_motivo(np): arma el texto de la causa a partir de gv_conciliacion_comparar
--     (dif. pareja %, descuento, precio: <cods>, N sin precio, N sólo factura/Gestión).
-- (SQL vigente aplicado por migración gv_conciliacion_estricto_motivo_v1438.)
-- ══════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════
-- v14.41 (2026-09-08) — comparar: PRORRATEO del descuento global de ISIS.
-- La página LK mete el 2% web en el BRUTO de cada renglón; ISIS lo aplica como UN renglón
-- global sobre el total ("2% Descuento Web", que el parser detecta pero con importe null).
-- Así, renglón a renglón Gestión (neto) contra ISIS (bruto) daba 2% de diferencia falsa en todos.
-- Fix: gv_conciliacion_comparar excluye las líneas sin código y multiplica cada renglón de ISIS
-- por el factor = subt_gravado (neto) / suma de renglones brutos → compara NETO vs NETO. El neto
-- (subt_gravado) es el dato confiable del parser (medido: neto = renglones × 0,98 en 5/5 facturas web).
-- Efecto: LK 0011 cierra a $0 en cada renglón; Vargas 98484 queda con la única diferencia REAL,
-- el 809E ($3.005 vs $4.060). (Aplicado por migración gv_conciliacion_comparar_prorrateo_v1441.)
-- ══════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════
-- v14.48 (2026-09-08) — FIX del TIMEOUT de la pestaña Conciliación.
-- SÍNTOMA: "No se pudo cargar la conciliación: canceling statement due to statement timeout".
-- CAUSA (medida): gv_conciliacion_lista tardaba ~8,5 s para 20 filas y PostgREST (rol anon,
--   statement_timeout = 8 s) la cancelaba. El 80% del costo era `motivo` en el SELECT del
--   listado: `public.gv_conciliacion_motivo(np)` corría UNA VEZ POR FILA con diferencia y cada
--   llamada re-materializa el cruce completo (gv_vista_cruce_facturacion + gv_vista_facturacion_neto,
--   que recorren ~9.800 entregas y ~28.000 documentos enteros). El join en vivo solo ya cuesta ~1,6 s.
-- FIX (backend): gv_conciliacion_lista YA NO calcula motivo → devuelve null::text. La firma NO
--   cambia (la columna `motivo` sigue existiendo). Se agrega red de seguridad
--   `set statement_timeout to '20000'` en la función (SECURITY DEFINER) por si el cruce crece.
-- FIX (front, index.html): concilRender pinta la celda "¿Por qué?" con "…" para las filas 'diff'
--   no corregidas y concilCargarMotivos() pide gv_conciliacion_motivo(np) on-demand, en paralelo,
--   sin bloquear el render. gv_conciliacion_motivo NO se toca (sólo lee).
-- MEDIDO: explain analyze gv_conciliacion_lista(300,0,null,null): 8.492 ms → 1.732 ms.
-- Migración aplicada: gv_conciliacion_lista_sin_motivo_v1448 (idempotente, CREATE OR REPLACE).
-- ROLLBACK: recrear gv_conciliacion_lista con el `case when j2.estado='diff' ... then
--   public.gv_conciliacion_motivo(j2.np) end as motivo` y sin el SET statement_timeout
--   (definición previa guardada en la migración/backup del 2026-09-08).
-- ══════════════════════════════════════════════════════════════════════════
