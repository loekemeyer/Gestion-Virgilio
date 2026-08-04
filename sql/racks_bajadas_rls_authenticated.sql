-- =====================================================================
--  racks_bajadas_rls_authenticated.sql — FIX (2026-08-04)
--
--  SÍNTOMA: la administrativa entraba a Recepción → "📦 Bajadas Racks → góndola"
--  y le decía "✓ No hay bajadas pendientes de aprobar", aunque los operarios sí
--  habían marcado bajadas (quedaban en Racks_Bajadas estado='propuesta'). Se
--  acumularon 9 sin aprobar desde el 30-07 (las aprobaciones se cortaron el 29-07).
--
--  CAUSA: RLS por ROL.
--   • Recepción (recepcion.js) entra con **sesión anónima** vía
--     `supabase.auth.signInAnonymously()` → su rol PostgREST es **`authenticated`**.
--   • El operario (index.html) hace `fetch` con la anon key SIN sesión → rol **`anon`**.
--   • Las policies de `Racks_Bajadas` (y `Racks_Ordenes`) eran **solo para `anon`**:
--       rb_select/insert/update : {anon}
--     → el operario INSERTA la propuesta (anon ✓) pero la admin (authenticated) lee
--       **0 filas** (no matchea ninguna policy SELECT) → "no hay pendientes".
--   `Movimientos_Stock` y `Control_Modo_OP` ya eran {anon,authenticated}, por eso
--   ESAS sí le funcionaban a la admin — de ahí que el bug pareciera puntual de racks.
--
--  FIX: agregar el rol `authenticated` a las policies de las dos tablas (mismo patrón
--  que el resto). Sin exposición nueva: `anon` y `authenticated` usan la MISMA
--  publishable key; cualquier cosa que pueda `anon` la puede una sesión anónima
--  `authenticated`. Aplicado por la migración `racks_bajadas_ordenes_rls_authenticated`.
--
--  BARRIDO (auditor): otras tablas anon-only con RLS (Insumos, Stock_Config,
--  Racks_Planimetria, Equivalencias_Codigos, Fichadas_*, Comprobantes_ARCA,
--  Zonas_Barrios) NO las lee ninguna app con sesión authenticated (recepcion.js no
--  las toca; fichada/monitor/index usan anon), así que no estaban rotas. Si en el
--  futuro una pantalla authenticated necesita alguna, hay que darle {anon,authenticated}.
-- =====================================================================

alter policy rb_select on public."Racks_Bajadas" to anon, authenticated;
alter policy rb_insert on public."Racks_Bajadas" to anon, authenticated;
alter policy rb_update on public."Racks_Bajadas" to anon, authenticated;

alter policy ro_select on public."Racks_Ordenes" to anon, authenticated;
alter policy ro_insert on public."Racks_Ordenes" to anon, authenticated;
alter policy ro_update on public."Racks_Ordenes" to anon, authenticated;
