-- =============================================================================
-- v16.00 (2026-09-11/12) — DAR POR SALIDA una NP a mano
-- Migraciones: `gv_ppp_en_salida_manual_v1597` + `gv_ppp_en_salida_marcar_v1597`
-- =============================================================================
-- Thomas, sobre los 7 que habían quedado: *"Los 44xxx mandalos a programar? El otro, dejalo
-- en en salida"*. La 98530 (D60C, Shopping Domino) está armada (TAP 09/09) y facturada (10/09),
-- pero nadie registró la Carga Camión: con la regla de la v15.85 ("a En Salida no entra nada sin
-- CCN y sin fecha") no podía estar ahí.
--
-- CÓMO SE RESOLVIÓ SIN ROMPER ESA REGLA
--   La v15.85 sigue igual: **nada entra solo** a En Salida sin Carga Camión. Lo que se agregó es un
--   OVERRIDE EXPLÍCITO por NP, el mismo patrón que `GV_PPP_Prog_Override` para la PPP: un
--   supervisor decide que ese pedido salió, y queda registrado quién, cuándo y con qué fecha.
--   **No se escribe un evento CCN falso**: inventaría el legajo del que cargó el camión, y la
--   vista justamente descarta los CCN de legajo de prueba.
--
--   · `GV_PPP_Prog_Override.en_salida_manual` boolean not null default false
--   · `GV_PPP_Prog_Override.en_salida_fecha`  date  ← **obligatoria**: en En Salida no puede haber
--     un pedido sin fecha. Si no se pasa, se toma la fecha de entrega de la PPP (o la de factura).
--   · `gv_ppp_en_salida`: la marca entra a la base y pasa el filtro `solo_cargadas`;
--     `estado = 'salida_manual'` y `fecha_carga = coalesce(CCN, en_salida_fecha)`.
--   · `gv_ppp_en_salida_marcar(p_nps, p_fecha, p_motivo, p_por)` — sólo supervisor. Corta si la NP
--     ya tiene CRN (ya está entregada) o CCN (ya está en En Salida por el camino normal).
--   · `gv_ppp_en_salida_desmarcar(p_nps, p_por)` — deshace.
--   · `en_salida_manual` y `desprogramada` son EXCLUYENTES: cada RPC apaga la otra marca.
--   · Front: chip **📝 Dada por salida a mano** y botón **🚚 Ya salió** en la lista de vencidos,
--     al lado de **↩ Sin programar**.
--
-- APLICADO el 11/09:
--   44612..44617 (Cencosud, D72B/D72C) → `gv_ppp_isis_desprogramar`: armadas, **sin facturar**,
--     sin ningún registro de carga → a 📥 A Programar.
--   98530 → `gv_ppp_en_salida_marcar` con fecha 10/09 (la de entrega) → En Salida, `salida_manual`.
--
-- MEDIDO (como `anon`): En Salida 19 → **20**, con **0 sin fecha**. A Programar 8 → **14**.
--   `gv_ppp_programacion_diaria` sigue en **123** filas.
--
-- OBJETOS: todos NUESTROS (`GV_*` / `gv_*`). Ninguno de Producción.
-- BACKUP previo: `public."GV_PPP_Prog_Override_bkp_20260912_pre_ensalida"` (113 filas).
-- ROLLBACK rápido:
--   select public.gv_ppp_en_salida_desmarcar(array['98530'], 'rollback');
--   update public."GV_PPP_Prog_Override" set desprogramada = false where np in ('44612','44613','44614','44615','44616','44617');
--   -- y para sacar la función entera: volver gv_ppp_en_salida a sql/gv_ppp_en_salida_solo_cargadas_v1585.sql
--   --   (sin el CTE `man`, sin la 3ª rama del filtro y sin 'salida_manual' en el case de estado),
--   --   drop function public.gv_ppp_en_salida_marcar(text[],date,text,text);
--   --   drop function public.gv_ppp_en_salida_desmarcar(text[],text);
--   --   alter table public."GV_PPP_Prog_Override" drop column en_salida_manual, drop column en_salida_fecha;
-- =============================================================================

alter table public."GV_PPP_Prog_Override"
  add column if not exists en_salida_manual boolean not null default false,
  add column if not exists en_salida_fecha  date;

comment on column public."GV_PPP_Prog_Override".en_salida_manual is
  'v15.97 — true = la NP se da por SALIDA a mano y entra a En Salida aunque no tenga CCN. Excluyente con desprogramada.';
comment on column public."GV_PPP_Prog_Override".en_salida_fecha is
  'v15.97 — fecha con la que se da por salida (obligatoria: en En Salida no puede haber un pedido sin fecha).';

-- El resto del DDL (la vista `gv_ppp_en_salida` completa y las 3 funciones) se aplicó con las dos
-- migraciones nombradas arriba. Respecto de la v15.85, la vista cambia sólo en:
--
--   + CTE `man`: las NP de GV_PPP_Prog_Override con en_salida_manual y sin oculto
--   + `base`  : union select np from man
--   + `fecha_carga` : coalesce(c.fecha_carga, mn.en_salida_fecha)
--   + `estado`      : when mn.np is not null then 'salida_manual'  (después de 'cargada')
--   + `dias_sin_controlar` : coalesce(c.fecha_carga, mn.en_salida_fecha, <fecha de entrega>)
--   + filtro: and (cfg.solo_cargadas = 0
--                  or (c.np is not null and c.fecha_carga is not null)
--                  or (mn.np is not null and mn.en_salida_fecha is not null))
--   + filtro de "tiene algo que mostrar": ... or mn.np is not null ...

-- Controles
--   select estado, count(*), count(*) filter (where fecha_carga is null) sin_fecha
--     from public.gv_ppp_en_salida group by 1;     -- cargada 19 · salida_manual 1 · sin_fecha 0
--   select np, estado, fecha_carga from public.gv_ppp_en_salida where np = '98530';
--   select count(*) from public.gv_ppp_isis_sin_tanda;   -- 14
