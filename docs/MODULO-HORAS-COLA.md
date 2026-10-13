# Cómo cuentan las horas: cola después de TP/TAP

> Movido de `CLAUDE.md` el 2026-10-13 (poda de reglas, pedido de Luis) para que no cargue en cada sesión.
> Es documentación operativa VIVA del módulo, no se resume: leer ENTERA antes de tocar este módulo.

## ⚠⚠ REGLA (Luis, 2026-10-02, v26.43): la COLA sin registro después del TP/TAP es PICKING/ARMADO

**Luis, textual:** *"si hay tiempos sin registros, luego de que estén haciendo picking o armado, hasta que
inicien la nueva tarea, esos tiempos quiero que se registren dentro de picking o armado … si vos pusiste
terminé antes de acomodarlas en la mesa, te estás beneficiando un tiempo que realmente no terminaste"*.

- **Qué cuenta:** desde el cierre (TP/TAP) hasta el **inicio de la próxima tarea registrada** del legajo
  (`coalesce(ts_inicio, ts_cliente)` de cualquier evento que no sea automático: PUB, AUB, PKC, ENT, RSP, ROC,
  RAG, FGU, FSS, IMPT, TAL, GST, MGR, PKM, SSG, PSP, NPD, PKAX ni los `*X`), o el **fin de jornada**
  (`max(último evento, hora de salida)`; el FJ es un evento y la corta solo), o la primera **bajada de racks
  sin tramo** (ese tramo ya cuenta como racks). Un tramo que **ya estaba abierto** al cerrar deja la cola en
  0; un 2.º TP/TAP de la **misma** tanda no la corta y la cola que se suma es la del **primer** cierre (como
  el m³, v12.97). Se suma a la tanda: `pick/arm = max(dur_s) + cola`.
- **Dónde:** `gv_monitor_horas_operario_dia` (CTE `cola`) y su copia verbatim `gv_horas_operario_detalle_v2`
  (xlsx de Elías); `index.html` `fetchMonitorDayStats` (`colaMsDe`, ≡ vista) y el pop-up por tanda dice
  «incl. N de cola hasta la próxima tarea». TV y Mon. Admin la heredan de la vista. **No entra** en «Min trab»
  del pop-up m³/h por tanda del Mon. Admin (apertura → cierre, v25.92).
- **Medido:** 15/09 → 277 picking 6,37 → 7,77 h · 237 armado 5,60 → 6,63 · 8 armado 6,75 → 8,76. 60 días, por
  tanda: mediana 1,7 min · p90 9,7 (TP) / 16,4 (TAP) · 4 colas > 60 min, la mayor **518 min** (TP a la mañana y
  ningún evento hasta la hora de salida). Es a propósito: la regla pide que eso cuente, y queda a la vista.
- La calibración de dificultad (D17, `docs/PICKING-DIFICULTAD-D17.md`) mide el tiempo real como picking puro **más la
  cola topeada a 30 min** (dos tandas con cola «cap» de 5 y 8 h quedaron afuera): la cola cayó 55 % en un fijo por
  tanda (2,4 min) y 32 % en la parada; las alturas no se movieron. **03/10, Luis delegó (*"aplicá lo que te parezca"*): sin tope en la
  base; 30 min sólo en la calibración (D18) · dificultad por caja (D19) · la app no registra la celda por ahora (D20) · escala de altura
  FÍSICA de Luis (D21: piso 1 · 2.ª 1,5 · 3.ª 2 · 4.ª 2,5 · 5.ª de A 3; la 5.ª de A «es medio que lo mismo» que la 4.ª de B). Lo medido con
  alturas libres (A5 72 s, el doble de B4) queda de referencia en `d17_esquema.json`; el registro por paso del 05/10 dirá si era el artículo.**
  **Niveles de dificultad (Luis, 03/10, v26.48): «pajosa» se RETIRA y son CUATRO — Baja · Media · Alta · Muy alta —, atados al grado
  1-10 (decil de min/caja sobre las 338 tandas): Baja = grado 1-2 · Media = 3-5 · Alta = 6-8 · Muy alta = 9-10, así nivel y grado no se
  contradicen. El multiplicador del m³/h es 1 + 0,1 × (grado − 5), de ×0,6 a ×1,5, topeado a propósito: una tanda de cajas sueltas
  (Manig F54A: 19 artículos, 19 cajas, 0,102 m³, 10 líneas con escalera → grado 10) se evalúa por índice tamaño ÷ real, no por m³/h.**
  **Puntaje 1-10 del operario de picking (Luis, 03/10, v26.49: *"objetivo y en función de los datos, para el empleado nuevo"*):
  puntaje = 5,5 + 10 × (índice − 1), con índice = Σ tamaños esperados ÷ Σ tiempos reales de sus ÚLTIMAS 20 tandas (y el período
  aparte); 1 punto = 10 % de velocidad, 5-6 = el promedio del depósito. Con 10 tandas el margen es ±2 a ±3 puntos: menos de 10
  es provisorio. Mide velocidad, no calidad. `docs/picking-d17/puntaje_operario.py`, sección (j) de `docs/PICKING-DIFICULTAD-D17.md`.**
  **v26.50: el puntaje VIVE EN LA BASE y se ve SÓLO en Mon. Admin** (Luis: *"en monitor admin, no en el que ven los operarios; sé que
  hay dos, ojo con eso"*). `GV_Picking_Esquema` (coeficientes y deciles: recalibrar = UPDATE) · `GV_Picking_Tanda` (caché por
  tanda+legajo: líneas, paradas, alturas por stock al EP, tamaño, dificultad, grado, tiempo real, índice; la llena
  `gv_picking_tanda_refresh`, cron `gv-picking-tanda-refresh` c/10 min) · `gv_picking_puntaje_operario(p_dias)` SECURITY DEFINER
  que **raise 'SUPERVISOR'** sin sesión de supervisor. Validado contra el Python de las 340 tandas: tamaño |dif| mediana 0,21 min,
  p90 0,80, corr 1,000 (ninguna a más de 3 min). La columna «Punt.» y su pop-up los inyecta `monitor/build-admin.cjs` (el token sale de `window.parent.sbAuth`);
  `tests/mon-admin.cjs` canda que **tv.html no lleve** `gv_picking_puntaje_operario`. Desde la sesión, `execute_sql` se cuelga
  con DELETE/DROP/UPDATE/CREATE TABLE de primer nivel: la instalación va adentro de `gv_picking_instalar()` (ver el SQL).
  `sql/gv_picking_puntaje_v2650.sql`. Acomodar en la mesa (cola vs cajas/NP/mesas): `docs/PICKING-ACOMODAR-MESA.md` — no sigue
  a las cajas ni a las mesas ocupadas; manda el operario.**
  **v26.51 (Luis, D24, 03/10: *"debe descontar los m³ pickeados si algo no se pickeó"*): LO NO PICKEADO SE DESCUENTA.** El m³/h de
  picking (TV, Mon. Admin y el monitor viejo del index) acredita **m³ de la tanda × fracción pickeada** (`gv_picking_pickeado`,
  lectura, anon: último PKC por código, Σ reales×m³/caja ÷ Σ pedidas×m³/caja, tope 1; sin respuesta, m³ entero), y en el **puntaje**
  una línea confirmada con **0 cajas no cuenta** (ni línea, ni parada, ni altura: `where pk.re > 0` en `gv_picking_tanda_calc`; sigue
  en los huecos, que miden tiempo). ~~**El armado no se prorratea.**~~ (retirado en la v26.55: ver abajo) Medido 60 días: 834 de 8.347 líneas en 0 (230 de 334 tandas),
  10,0 % del m³ pedido; por operario el m³/h baja 6,4 % (122) · 8,8 % (104) · 11,2 % (504) · **17,5 % (277)**. El pop-up de m³/h
  del Mon. Admin dice «1,2 de 1,5» cuando se prorrateó. `GV_Picking_Tanda` + `lineas_cero` · `cajas_ped` · `m3_frac`.
  `sql/gv_picking_no_pickeado_v2651.sql` (centinelas v26.51; `gv_picking_pickeado` entró a `scripts/reglas-protegidas.json`),
  `tests/mon-tv.cjs` (techo 100 → 105 KB) y `tests/mon-admin.cjs`. **Aplicado el 04/10 (v26.53)**, sin «sí» aparte (Luis: *«no esperes mi
  sí para aplicar algo que ya te pedí yo»*): 356 tandas recalculadas; **826 líneas en 0 salieron** (8.218 → 7.391); fracción pickeada
  media **0,905**, 258 de 356 tandas por debajo de 1; el índice de las últimas 20 por operario baja 4 a 9 % (104 1,634 → 1,555 · 122
  1,081 → 1,019 · 277 0,890 → 0,836 · 504 0,792 → 0,722) y el puntaje sólo cambia en el 237 (7 → 6). Los **deciles del grado se
  recalibraron** sobre la dificultad nueva (media 0,290 → 0,260; decil_5 0,2406 → 0,2280, decil_9 0,5168 → 0,4819): sin eso el
  grado dejaba de ser un decil (21 a 41 tandas por grado). ⚠ El `gv_picking_puntaje_operario` **vivo** tenía un filtro de turno
  (`real_min between 0.5 and 240` · `lineas > 0` · `bruto_min <= 720`) que el repo no tenía —otra sesión—: se trajo la definición
  viva y se conservó, en la base y en el `.sql`.
  **v26.54 (Luis, 04/10: *"me estás pidiendo aplicar algo que no me estás mostrando"*): el m³/h AJUSTADO por dificultad SE VE en el
  Mon. Admin.** Pop-up de m³/h picking → por tanda **Dif.** (grado y nivel) y **Ajust. m³/h** = ritmo × (1 + 0,1 × (grado − 5)),
  Total ajustado y la nota; en la celda, chiquito, el del día («1,5 → 1,4») cuando todas sus tandas tienen grado. Caso real 02/10
  (104): F22A 1,7 m³/h grado 7 Alta → 2,0 · E89A 1,2 grado 3 → 0,9 · el día 1,5 → 1,4. RPC nueva de lectura `gv_picking_grado(text[])`
  (anon, lee `GV_Picking_Tanda`); `gv_picking_pickeado` no se tocó. **La TV no lo lleva** (candado en `tests/mon-admin.cjs`).
  `sql/gv_picking_grado_v2654.sql`, §3.v2654.
  **v26.55 (Luis, 04/10: *"una vez que ya se pickea, ya no se mira más el m³ del pedido entero … lo que se carga en el camión es lo
  pickeado … el camión se debe pedir en función de lo pickeado"*): UNA TANDA CON TP VALE SU m³ PICKEADO EN TODOS LADOS.** No sólo el
  m³/h de picking: armado, carga, Días, camión del día (y la unión Z2+Z3 < 1 m³), Programación y Resumen de la PPP. Fuente única
  **`gv_tanda_m3_pickeado(text[])`** (lectura, anon): la fracción de `GV_Picking_Tanda.m3_frac` y, para un TP de las últimas 48 h que
  la caché todavía no tiene, en vivo con `gv_picking_pickeado`; sin fila = sin pickear = m³ del pedido. La aplican **en la base**
  `vista_tanda_m3` (m3 = pickeado; `m3_pedido` y `fraccion` al final), `gv_monitor_tanda_camion` y `gv_ppp_prog_arbol` (la NP va con la
  fracción de su tanda); **en el front**, la TV / Mon. Admin (copia de la programación con el m³ pickeado; se fue el «1,2 de 1,5») y el
  index **en la fuente**: `fetchMonitorSheet`, `fetchHistoricSheet` y `pppLoadProgFromSupabase` (`gvFracPickeado`, una lectura cada
  60 s; `monPickFrac` se fue). ⚠ **Lo que se GUARDA sigue siendo el m³ del PEDIDO**: `pppGuardarWeb` manda `m3Ped`, o reprogramar una NP
  pickeada pisaría `PPP_Web_Programacion.m3`. Medido 05/10: el 06/10 pasa de 6,869 a 6,372 m³ (10 de 11 tandas pickeadas).
  `sql/gv_m3_pickeado_v2655.sql` (centinelas 292-295), `tests/m3-pickeado-fuente.cjs`, `tests/mon-tv.cjs`, `tests/mon-admin.cjs`, §3.v2655.
- `sql/gv_monitor_horas_cola_v2643.sql` (idempotente sobre `pg_get_functiondef`, con rollback; huella y centinela
  v26.43 adentro). **Aplicado el 03/10 con el sí de Luis** (v26.45): el 15/09 dio idéntico a la foto, `gv_huellas_cambiadas`
  y `gv_reglas_perdidas` vacías. ⚠ **La huella se compara por `md5(prosrc)`, NO por `md5(pg_get_functiondef(...))`**:
  el primer intento la dejó en rojo con el cuerpo correcto. Lo pendiente de D18 (tope de la cola) no se tocó: corre
  hasta la próxima tarea o la hora de salida, como está escrito arriba. `tests/tools/vista-15.json` re-congelado con la cola; `tests/mon-vs-vista.cjs`;
  `tests/muerto-neteado.cjs` y `tests/mejoras-v1297.cjs` (la siguiente tarea arranca 1 s después del cierre y el
  día termina con FJ, para que la cola quede en 0 y sigan midiendo lo suyo). CI 1698 cayó por el segundo: regla
  v21.53, se arregló en el mismo pedido.

