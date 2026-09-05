# Análisis: tandas por cercanía real de barrios — 2026-09-05

> Pedido del dueño (idea 7317): *"1, 2 y 3 [juntas] pero hay cosas que no son parejas. Núñez con Villa Lugano estaría dentro de 1 y 2 y no debe ir junto."* Workflow de análisis (sólo lectura, 10 agentes): minado del historial de tandas, lectura del código del armado, geodatos disponibles, tres diseños independientes, tres jueces y una síntesis. Nada se modificó en Supabase ni en el repo durante el análisis.

## Recomendación (síntesis)

# Recomendación: regla de cercanía para armar tandas

## 1) La regla, en una frase

**Dos pedidos van en la misma tanda si sus barrios están en el mismo sector o en sectores vecinos (lista que cargás vos), y cada pedido que entra tiene que ser compatible con TODOS los que ya están en la tanda.** Ni el número de zona ni los kilómetros deciden: decide una tabla de "quién con quién" que se lee y se corrige a mano. Por encima de eso, una lista de pares de barrios con SÍ/NO explícito (ahí queda escrito "Núñez con Lugano: NO", pase lo que pase).

Los tres jueces coincidieron: es la única que se prende esta semana sin geocodificar nada y que vos podés leer y discutir fila por fila.

## 2) Parámetros, con el historial atrás

**14 sectores** (CABA por comunas de a 2, GBA por corredor) y **~23 pares de vecinos**. Carga inicial propuesta:

| Sector | Barrios |
|---|---|
| A Cap Sur-Este | Barracas, La Boca, Constitución, P.Patricios, San Cristóbal, **Boedo** (a confirmar) |
| B Cap Sur Soldati | Pompeya, Soldati, Lugano, V.Riachuelo |
| C Cap Oeste-Sur (depósito) | Mataderos, P.Avellaneda, Liniers, Villa Luro |
| D Cap Centro-Oeste | Flores, P.Chacabuco, Caballito |
| E Cap Oeste-Norte | V.del Parque, Devoto, V.Gral.Mitre, Paternal |
| F Cap Centro | Once, Balvanera, Almagro, Monserrat, Microcentro, Pto Madero, Retiro, Recoleta |
| G Cap Norte Palermo | Palermo, V.Crespo, Colegiales, V.Ortúzar |
| H Cap Norte Belgrano | Belgrano, Núñez, V.Urquiza, V.Pueyrredón |
| J / J2 GBA Sur | Avellaneda–Lanús–V.Alsina / Bernal–Quilmes–Berazategui–F.Varela |
| K GBA Sur-Oeste | Lomas, Banfield, Temperley, Adrogué, Burzaco, M.Grande, Guernica |
| L GBA Oeste | Ciudadela → Luján |
| M GBA Norte | San Martín, V.Ballester, Chilavert, Munro, San Miguel, J.C.Paz |
| N GBA Norte Ribera | V.López, Olivos, Martínez, San Isidro, Tigre, Pilar |

**Vecinos:** A-B, A-F, A-D, B-C, B-D, C-D, C-E, C-L, D-E, D-F, D-G, E-G, E-H, E-L, E-M, F-G, F-H, G-H, H-M, H-N, J-J2, J-K, J2-K, L-M, M-N. Y opcionales que dependen de vos: A-J y B-J (Capital Sur con Avellaneda/Lanús).
**No vecinos a propósito:** H y G (Núñez/Belgrano/Palermo) con A y B (Barracas/Lugano/Soldati); F (Once) con B (Soldati).

Por qué así y no "10 km":
- En 8 meses (2.454 NP con tanda, 359 tandas con 2+ clientes) **mezclaste Z1+Z2 en 13 tandas, Z1+Z3 en 9, Z2+Z3 en 8** → la regla de hoy (2+3 sí, 1 sola) no es lo que hacés. Las 27 tandas mixtas de Capital tienen máximo entre paradas de 1,7 a 12,3 km, mediana 6,5.
- **Norte con Sur: 0 veces** (Núñez/Belgrano/Colegiales con Lugano/Soldati/Pompeya). Lo más lejano que juntaste fue Palermo+P.Patricios 1 vez (9,3 km).
- Lo que juntás de verdad: Pompeya–Soldati 6, Flores–Soldati 3, Balvanera–Constitución 3, Constitución–Microcentro 2, Flores–Mataderos 2, Flores–P.Patricios 2, Lanús–Quilmes 2, Bernal–Temperley 2, San Martín–Tigre 2. Todos entran en los sectores/vecinos de arriba.
- Un radio de km quedaba colgado de coordenadas que no existen: **Núñez, Colegiales, V.Crespo, Devoto, Caballito tienen 0 puntos en PPP_Geo**; 52 de ~176 pedidos vivos con zona están en barrios sin ubicación; 30 de los 48 centroides "medidos" son la casa de UN cliente. Y Belgrano–Soldati (11,4) queda a 1,4 km de un umbral de 10 con centroides de ±1 km. Demasiado fino para decidir justo lo que pediste hoy.

## 3) Ejemplos

| Par | Sectores | Resultado |
|---|---|---|
| **Núñez + Villa Lugano** | H / B, no vecinos + par NO cargado | **NO** (0 veces en el historial; 14,8 km) |
| Pompeya + Barracas | B / A vecinos | SÍ (par más común de Z1) |
| Boedo + Pompeya | A / B vecinos (si Boedo va en A) | SÍ — hoy prohibido por zonas |
| Flores + Mataderos | D / C vecinos | SÍ (2 tandas históricas) |
| Devoto + Villa Luro | E / C vecinos | SÍ |
| Belgrano + Palermo | H / G vecinos | SÍ |
| Belgrano + Recoleta | H / F vecinos (lo hiciste en D56A) | SÍ — sacás el par si no querés |
| Constitución + Once | A / F vecinos | SÍ (3 tandas) |
| Constitución + Devoto | A / E no vecinos | NO (0 veces) |
| Núñez + Palermo + Almagro en una tanda | H-G sí, G-F sí, **H-F decide** | sólo si dejás H-F: no hay "cadena" |
| Quilmes + Avellaneda | J2 / J vecinos | SÍ (Lanús–Quilmes 2 tandas) |
| Lanús + Soldati | J / B — sólo si cargás B-J | vos decidís (5 tandas Z1+Z4 en el historial, hoy prohibido) |
| Pilar + Núñez | N / H vecinos | SÍ por sectores (ojo, 42 km; ver riesgo 2) |

## 4) Qué se construye (todo backend, prefijo GV_/gv_, RLS, sin tocar Producción)

**Tablas (archivo nuevo `sql/gv_sectores.sql`):**
- `GV_Sectores (sector pk, nombre, camion, orden, activo)`
- `GV_Barrios_Sector (barrio_norm pk = _norm_barrio, sector fk, nota)` — los alias (p.patricios, v.devoto, "mataderos (8:30 a 14)") son filas propias.
- `GV_Sectores_Vecinos (sector_a < sector_b pk, permitido, nota)`
- `GV_Barrios_Pares (barrio_a < barrio_b pk, permitido, motivo, actualizado_por)` — gana sobre todo lo demás.
- `PPP_Web_Config`: `sectores_activos` (1/0 = kill switch), y `zonas_automaticas` '1,2' → '1,2,3' si querés que la Z3 entre al job.

**Funciones:**
- `gv_ppp_web_sector(p_zona, p_barrio) → text`: sector del barrio; Super/Retira/Expo devuelven la zona; barrio sin sector devuelve `'~Zona X'` (pseudo-sector que sólo va consigo mismo = regla de hoy).
- `gv_ppp_web_pueden_compartir(p_zona_a, p_barrio_a, p_zona_b, p_barrio_b) → (ok, motivo)`: 1º par de barrios cargado, 2º mismo sector o vecinos.
- `gv_ppp_web_compatible(p_sector, p_barrio, p_tanda jsonb) → bool`: contra todas las paradas de la tanda.
- `gv_ppp_web_camion(p_sector) → (camion, orden)`.
- `gv_ppp_web_validar_tanda(p_items jsonb) → (i, j, ok, motivo)`: para el semáforo del tablero.
- Vistas `gv_ppp_web_sectores` y `gv_barrios_sin_sector` (security_invoker).

**Integración en `ppp_web_armar_tandas` (sql/ppp_web_tandas.sql):** la selección diaria (prioritarios, antigüedad, cupo 5 m³, líneas 322-341) no cambia. En `_sin_tanda` (L268) se agrega `sector`/`camion` (con `sectores_activos=0` el sector ES el grupo actual → mismo resultado que hoy). El bucle 348-376 pasa de "una tanda abierta por grupo" a **first-fit sobre varias tandas abiertas**: el cliente entra en la primera donde cabe en 0,80 m³ Y es compatible con todas las paradas; si ninguna, abre tanda nueva. El NN del código = orden del camión ese día; la letra final = tanda dentro del camión. Además se expone un dry-run (`p_simular`) que devuelve `(order_id, np_idx, tanda, motivo)` sin insertar. La Edge Function no cambia (ya manda barrio y zona).

**Tablero:** hoy un camión = una zona (v13.03) y el sugeridor manual (`pppSugerirTandas`) agrupa por zona con tope 1,00 (otra regla distinta al backend). Pasa a: cargar `gv_ppp_web_sectores` + vecinos una vez, agrupar camiones por la etiqueta `camion` del sector (si cargás `camion = zona`, el tablero queda igual que hoy y sólo cambia la mezcla dentro de la tanda), pintar en rojo la tanda que `validar_tanda` rechace (aviso, no bloqueo: vos mandás), y el sugeridor llama al dry-run en vez de calcular por su cuenta. Una regla, un lugar.

## 5) Carga inicial y barrios nuevos

- **115 filas** de `GV_Barrios_Sector` salen de `Zonas_Barrios` por lista (las 14 de arriba), 14 sectores, ~25 pares de vecinos, ~12 pares de barrios NO (3 barrios norte × 4 sur). **Cero coordenadas, cero geocodificación.** 1–2 h de SQL + 30 min tuyos revisando la tabla impresa.
- Backup previo del cuerpo actual de `ppp_web_armar_tandas` (md5 3b7ae2a5…) en el repo. `PPP_Web_Programacion` tiene 0 filas: no hay migración.
- Dry-run con `begin … rollback` sobre las 182 filas vivas y contra `GV_Tandas_Auto_Log` de los días anteriores, en 0 (tiene que dar idéntico) y en 1, antes de prender.
- **Barrio nuevo** (lo aprende Producción con su trigger): cae en pseudo-sector `~Zona X` → se programa sólo con su zona, como hoy. Aparece en `gv_barrios_sin_sector` y como ⚠ en el tablero; lo asignás con una fila. Nada se traba.

## 6) Qué ajustás vos, sin programar

- Mover un barrio de sector: 1 update en `GV_Barrios_Sector`.
- Permitir/prohibir una mezcla: agregar/borrar un par en `GV_Sectores_Vecinos`.
- Excepción puntual sin abrir sectores enteros ("Recoleta con Soldati sí", "Luján va solo"): fila en `GV_Barrios_Pares`.
- Cómo se agrupan los camiones del tablero: `camion`/`orden` en `GV_Sectores`.
- Apagar todo: `sectores_activos = 0` (vuelve a 2+3/6+7 al instante).
Desde el Table Editor de Supabase alcanza; una pantalla "📍 Sectores" en el panel supervisor es medio día más de front, opcional.

## 7) Riesgos y qué NO se toca

1. La partición es lectura mía del mapa y de tu historial, no algo que dijiste vos. Hay 4 decisiones tuyas (abajo). Si se prende con sectores mal cargados, arma tandas raras hasta que alguien lo vea → por eso el dry-run y el switch.
2. Dentro de un sector o entre vecinos **no hay tope de km**: L junta Ciudadela con Luján, N junta V.López con Pilar. En Capital no importa (todo dentro de ~7 km entre centroides); en GBA es más grueso que tu práctica. Solución si molesta: par de barrios NO, o fase 2 con `GV_Barrios_Geo` + km máximo por sector cuando haya coordenadas verificadas.
3. Hoy conviven 3 reglas (job 0,80 con grupos, sugeridor front 1,00 sin grupos, tablero por zona): si no se reemplazan las tres por la RPC, siguen diciendo cosas distintas.
4. El first-fit sobre varias tandas es más complejo que el actual; se valida que con el switch en 0 reproduzca bit a bit lo de hoy.
5. Normalización JS ≠ SQL (tildes: "Núñez"/"nuñez"): hay que agregar `_pppNormBarrio` en el front.
6. Esto **no** resuelve "Zona 1 y 2 todos los días": eso es disparo/cupo (idea 7317, `m3_max_dia`), cambio aparte. Con Z3 automática entra más m³ a la cola de 5 diarios.
7. **No se toca de Producción:** `Zonas_Barrios`, `PPP_Geo` (10 refs en su app, sólo lectura), `PPP_Programacion_Diaria` (4 triggers suyos). Ningún trigger nuevo en compartidas, ninguna fila en `PPP_Geo`. `ppp_web_armar_tandas`, `gv_ppp_web_grupo_zona`, `PPP_Web_Programacion`: 0 referencias en el repo de Producción (HEAD e15b682), se pueden cambiar. Todo objeto nuevo GV_/gv_, RLS prendida, vistas security_invoker, anotado el mismo día en `docs/SUPABASE-GESTION-VIRGILIO.md` con dry-run y rollback. Datos sucios vistos y NO corregidos: Burzaco cargado como Zona 2 (3 pedidos vivos), Villa Lugano como Zona 3 en `wa_np_snapshot`.

Estimación: 1 día SQL + pruebas, 1 día tablero/sugeridor, media hora tuya.

## Preguntas que sólo vos podés contestar

1. **Backend o front:** ¿la regla va en Supabase (`ppp_web_armar_tandas`, es lo recomendado y lo que asume todo esto) y el tablero sólo la muestra? ¿Y das el OK para crear las tablas GV_ y modificar la función?
2. **Bordes a confirmar:** Boedo ¿con Constitución/P.Patricios (A) o con Once/Almagro (F)? ¿Capital Sur puede ir con Avellaneda/Lanús (A-J, B-J)? ¿Belgrano con Recoleta (H-F)? ¿Quilmes con Avellaneda (J-J2)?
3. **Zona 3 al automático** (`zonas_automaticas = '1,2,3'`, consume del cupo de 5 m³) y **el camión del tablero** pasa de "una zona" a "etiqueta de sector" (o cargás camión = zona y queda igual): ¿sí o no?

## Veredictos de los jueces

**Juez 1** — ganador: Propuesta 2 — Sectores + vecinos

- Propuesta 1 — Distancia entre centroides (10 km CABA / 20 km GBA, diámetro de tanda, pares de excepción): fidelidad 7 · simple 5 · implementable 5 · robusto 6 = **23** — Fidelidad 7: con X=10 reproduce 24/27 tandas mixtas de Capital y bloquea Núñez–Lugano (14,8), pero la frontera es un filo: Belgrano–Soldati 11,4 y V.Urquiza–Lugano 11,1 quedan a 1,1–1,4 km del umbral con centroides de 1–2 puntos (Belgrano 1, Lugano 2) y Núñez/Colegiales/V.Crespo sin punto (coordenada de memoria ±1 km). Además deja pasar Villa Crespo+Lugano 9,4 y Recoleta+Soldati 8,5 (norte-centro con sur, justo lo que el dueño no quiere; historial 1 vez c/u) y rechaza Palermo+Barracas por 200 m. Con `tanda_cruzar_caba_gba=1` habilita Z1+Z4 por defecto (historial 5 tandas, pero la regla vigente del dueño dice 'el resto sola'): eso es decisión suya, no default. Simple 5: 'radio 10 km' no es cómo piensa el dueño (él piensa Núñez no va con Lugano); el porqué de un NO requiere mirar km y un mapa. Implementable 5: depende de sembrar ~50 `manual_aprox` no verificados + revisar 8-10 barrios frontera en el mapa; sin eso Devoto/Núñez/Colegiales (10 pedidos vivos Colegiales) caen a 'sin geo'. Robusto 6: fallback `sin_geo_modo='zona'` no rompe nada y la vista viva de PPP_Geo se actualiza sola, pero 30/48 centroides son la casa de UN cliente, y el camión por enlace completo 15 km cambia el número NN de forma poco predecible día a día. Retira/Súper: bien, quedan como hoy.
- Propuesta 2 — Sectores compactos + lista de sectores vecinos (tablas GV_, sin coordenadas): fidelidad 7 · simple 9 · implementable 9 · robusto 8 = **33** — Fidelidad 7: bloquea Núñez(H)+Lugano(B) sin depender de ningún centroide, y Boedo+Pompeya da SÍ sólo porque Boedo se movió a A a mano (decisión que hay que confirmar: Boedo–Once son 1,5 km y quedan en sectores distintos A/F, aunque A-F es vecino, ok). Las tandas vivas cruzadas (D55A Flores+P.Patricios, D56A Belgrano+Recoleta) pasan sólo por pares A-D y H-F agregados ad hoc; con vecindad estricta pierde Palermo+P.Patricios (B65K), Recoleta+Soldati (B86A), Balvanera+San Martín (3 tandas históricas, F-M no vecinos) y Constitución+V.Urquiza/V.Pueyrredón. Punto débil real: dentro de un sector no hay distancia — L junta Ciudadela con Luján (~55 km) y N junta Vicente López con Pilar (~42 km, el caso extremo C05A Núñez+Pilar 42,5 que nadie quiere repetir). Simple 9: es exactamente el lenguaje del dueño ('quién con quién'), una fila por barrio, una fila por par; el motivo de un NO es legible sin mapa. Implementable 9: 115 filas + 14 sectores + ~25 pares, cero geocodificación, 1–2 h de SQL + 30 min del dueño; PPP_Web_Programacion tiene 0 filas, no hay migración. Robusto 8: barrio nuevo → pseudo-sector '~Zona X' = comportamiento de hoy, visible en `gv_barrios_sin_sector`; `sectores_activos=0` es rollback de un update; Retira/Súper/Expo sector = zona, sin vecinos. Le falta la red de km para GBA y hay que agregar `_pppNormBarrio` en JS (tildes).
- Propuesta 3 — 4 capas: barrio canónico → pares de barrios (semilla historial + dueño) → pares de zonas → distancia 8/20 km, fallback misma zona, kill switch: fidelidad 8 · simple 4 · implementable 5 · robusto 7 = **24** — Fidelidad 8: es la que mejor calca la práctica porque la lista blanca se siembra con los ~60-90 pares que el dueño YA juntó (Pompeya–Soldati 6, Flores–Soldati 3, Balvanera–Constitución 3…), la distancia sólo decide pares nunca vistos, y Z1-Z4 arranca apagado (respeta la regla vigente aunque el historial tenga 5). Núñez+Lugano cae por doble red (par 'dueño' + 14,8 > 8). 8 km es más prudente que 10: bloquea Palermo+P.Patricios 9,3 y V.Crespo+Lugano 9,4. Camión = 'Capital 1+2+3' con Núñez y Lugano en tandas distintas encaja con 'Zona 1 y 2 se reparte todos los días'. Pero la semilla histórica es ruidosa (barrio por moda del cliente, 206 NP con domicilio fiscal) y 'la lista blanca gana sin red' — un par mal cargado permite cualquier cosa. Simple 4: 4 capas, 3 tablas, km por par de zonas y una pantalla de 3 pestañas; para el dueño explicar por qué dos pedidos no fueron juntos requiere leer `motivo`. Implementable 5: mismo cuello que la P1 (Devoto/Núñez sin punto → ejemplo 5 falla hasta cargar ~50 `manual_aprox`), más 8 funciones, refactor a `gv_ppp_web_armar_core`, re-correr el análisis para la semilla y emular `_rtNorm` en SQL para el dir_key (frágil con tildes). Es la más larga (≈2,5 días). Robusto 7: Capa 4 (misma zona) = hoy, kill switch byte a byte, usa la dirección exacta de PPP_Geo cuando existe (24/83 hoy); Retira/Súper por pares Retira-Retira/Super-Super, ok.

Mezcla sugerida: Base = Propuesta 2 (GV_Sectores / GV_Barrios_Sector / GV_Sectores_Vecinos, pseudo-sector '~zona' como fallback, camión = etiqueta del sector, first-fit sobre varias tandas abiertas): es lo único que se puede prender esta semana sin geocodificar nada y que el dueño puede leer y corregir fila por fila. Sumarle de la Propuesta 3: (a) la tabla `GV_Barrios_Pares` (par de barrios, permitido true/false, fuente 'dueño'|'historial', n_hist) evaluada ANTES que la vecindad de sectores — así D55A Flores+P.Patricios, D56A Belgrano+Recoleta, Palermo+P.Patricios o Balvanera+San Martín se habilitan como pares puntuales en vez de abrir sectores enteros (A-D, H-F) que arrastran barrios que el dueño no pidió; y las prohibiciones explícitas (Núñez/Belgrano/Colegiales × Lugano/Soldati/Pompeya) quedan escritas aunque alguien mueva un barrio de sector; (b) el kill switch en PPP_Web_Config y el dry-run `gv_ppp_web_sugerir_tandas` para que el sugeridor del front y el tablero consuman la misma RPC (matar `pppSugerirTandas` T_MAX 1,00). Sumarle de la Propuesta 1, como fase 2 y sólo cuando existan coordenadas verificadas: `GV_Barrios_Geo` + un `km_max` por sector/par de sectores (20 km en GBA) como red de seguridad para que Luján no comparta tanda con Ciudadela ni Pilar con Vicente López dentro del mismo sector; en Capital la vecindad ya alcanza. Antes de todo: preguntar al dueño backend vs front (esperado: backend), confirmar Boedo en A o F, si Z1 va con Z4 (B-J/A-J) y si `zonas_automaticas` pasa a '1,2,3'; validar con dry-run sobre las 182 filas vivas y las 27 tandas mixtas históricas.

**Juez 2** — ganador: Propuesta 2 — sectores + vecinos

- Propuesta 1 — distancia entre centroides (10 km CABA / 20 km GBA) + radio por barrio + pares + camión por clustering: fidelidad 7 · simple 5 · implementable 4 · robusto 6 = **22** — Fidelidad: 10 km reproduce 24/27 tandas mixtas de Capital y bloquea Núñez–Lugano (14,8), pero deja pasar Villa Crespo+Lugano (9,4, nunca hecho) y corta Palermo+Barracas por 200 m; en GBA 20 km es más laxo que la práctica (Martínez+Morón 18,5 pasa, Quilmes+Lomas también). Simple: el dueño piensa en 'Núñez con Lugano no', no en '10 km'; radio_km por barrio y camion_km_max son dos perillas más, y el NN de la tanda pasa a ser un cluster por enlace completo, que ya no coincide con 'un camión = una zona' (v13.03). Implementable HOY es el punto débil: verifiqué con SELECT que 52 de ~176 pedidos vivos con zona (30 %) están en barrios SIN ningún punto en PPP_Geo, y en Zona 2 son 12 de 23 barrios; los que faltan son justo la frontera norte (Colegiales 10 pedidos, Villa Crespo 6, Villa Ortúzar 4, Núñez, Devoto, Caballito). Sin sembrar ~50 coordenadas manual_aprox no verificables desde acá (30 de los 48 'medidos' son la casa de un cliente) la regla cae al fallback en un tercio de Capital. Además reemplaza el bucle entero por gv_ppp_web_agrupar + clustering de camiones: refactor grande, sin un switch que reproduzca byte a byte lo actual. Robusto: sin_geo_modo='zona' y la vista viva con mediana ≥3 puntos son buenas ideas, pero la decisión de frontera vive en un margen de 1,1–1,4 km (Belgrano–Soldati 11,4, V.Urquiza–Lugano 11,1) con centroides de ±1 km: un geocode corrido invierte la regla. No toca PPP_Geo/Zonas_Barrios (bien).
- Propuesta 2 — partición en 14 sectores + lista de sectores vecinos (GV_Sectores / GV_Barrios_Sector / GV_Sectores_Vecinos), sin coordenadas: fidelidad 7 · simple 9 · implementable 9 · robusto 8 = **33** — Fidelidad: cubre lo que el dueño hizo en las tandas vivas (D55A/D55B Flores+P.Patricios/Soldati vía A-D y B-D, D53F Barracas+Soldati, D57B Chilavert+Olivos, D56A Belgrano+Recoleta vía H-F) y la no-transitividad impide la cadena Núñez→Palermo→Almagro; pero sin distancia deja pasar Luján dentro de L (60 km) y Quilmes–Avellaneda 12,8, y descarta Balvanera–San Martín (3 tandas históricas, F-M no vecinos) y los 5 casos borde de 1 vez (Palermo+P.Patricios, Soldati+Recoleta, Mataderos+Núñez…) igual que P1 a 10 km; es MI lectura del mapa y hay 4 pares a confirmar (Boedo en A, H-F, B-J/A-J, J-J2). Simple: 'quién con quién' en tablas legibles, un update por barrio, un insert por par; el rollback es sectores_activos=0. Implementable hoy: es la única que no depende de geocodificar nada — el SELECT confirma que hoy sólo 48/115 barrios tienen punto y 52 pedidos vivos no lo tienen; el sector se define por Comuna/Partido, que además ya viene en PPP_Geo.comp->>'state_district' (93 filas) para validar la partición. El cambio en ppp_web_armar_tandas es acotado (columna sector en _sin_tanda + first-fit sobre _abiertas) y con el switch en 0 el sector ES el grupo actual, así que se puede probar en dry-run contra GV_Tandas_Auto_Log antes de prender. Cero triggers, cero escritura en compartidas, 0 refs en Producción. Robusto: barrio nuevo → pseudo-sector '~zona' = regla vigente (nada se rompe), alias como filas propias, sin Nominatim ni cron; el punto flojo es que dentro de un sector o entre vecinos no hay tope de km, y la normalización JS ≠ SQL (tildes) hay que agregarla en el tablero.
- Propuesta 3 — 4 capas: barrio canónico → pares de barrios (blanca/negra, semilla historial) → pares de zonas (GV_Zonas_Pares) → distancia (8/20 km) → sin geo = misma zona: fidelidad 8 · simple 5 · implementable 5 · robusto 7 = **25** — Fidelidad: la más expresiva — la lista blanca sembrada del historial (n_hist, km) recupera Pompeya–Soldati 6, Flores–Soldati 3, Balvanera–Constitución 3, y GV_Zonas_Pares con 1-4/5-6/2-6 cargados pero apagados refleja exactamente 'el resto sola' con la evidencia a un toggle; camión = componente conexa (Capital 1+2+3 en un solo NN) es coherente con 'no debe ir junto = misma tanda, no mismo día'. Pero contradice 'un camión = una zona' de v13.03 y 8 km corta Recoleta+Soldati (8,5, B86A) salvo que esté en la lista. Simple: tres tablas más config más un orden de precedencia de 4 capas es lo más difícil de explicar; la grilla 10×10 de zonas con km por par es más de lo que el dueño pidió. Implementable hoy: la capa 3 tiene la misma dependencia de coordenadas que P1 (el ejemplo 5 lo admite: Devoto+Villa Luro es NO hasta cargar GV_Barrios_Geo; Colegiales/Villa Crespo/V.Ortúzar con 20 pedidos vivos caen en capa 4), y la semilla de pares sale de scripts del scratchpad que mapearon barrio por moda de cliente y 206 NP por domicilio fiscal — hay que rehacerla y que el dueño la revise. Suma emular _rtNorm en SQL para el dir_key, reescribir gv_ppp_web_grupo_zona como CTE recursiva y extraer un core compartido: ~350 líneas y 8 funciones, la mayor superficie de bugs. A favor: kill switch tanda_regla_cercania=0 y la capa 4 hacen que funcione desde el día 1 sin geo (sólo pares cargados + misma zona). Robusto: los mejores fallbacks (dirección exacta de PPP_Geo si existe, centroide vivo, misma zona sin punto), pero la lista blanca gana sin red (un SÍ mal cargado junta cualquier cosa) y el radio 8 km es aún más fino que 10.

Mezcla sugerida: Base = Propuesta 2 (GV_Sectores, GV_Barrios_Sector con alias como filas, GV_Sectores_Vecinos no transitivos, pseudo-sector '~zona' para barrio nuevo, switch sectores_activos que con 0 reproduce el grupo actual, first-fit sobre varias tandas abiertas exigiendo compatibilidad con TODAS las paradas). Es la única que funciona hoy con lo que hay: 52 pedidos vivos y 12 de 23 barrios de Zona 2 no tienen punto en PPP_Geo. Tomar de la Propuesta 3: (a) GV_Barrios_Pares como capa 1 que gana sobre los sectores — ahí van los NO explícitos del dueño (Núñez/Belgrano/Colegiales × Lugano/Soldati/Pompeya, con motivo y actualizado_por) y los SÍ puntuales tipo Belgrano+Recoleta o Balvanera+San Martín sin tener que abrir todo H-F o F-M; (b) el historial como EVIDENCIA para revisar la partición (lista de pares con n_hist y km que se le muestra al dueño), no como semilla automática; (c) gv_ppp_web_validar_tanda para el semáforo del tablero y una RPC dry-run del mismo núcleo que reemplace pppSugerirTandas (T_MAX 1,00 sin grupos) — una sola regla en backend, front sólo la pinta. Tomar de la Propuesta 1 como fase 2, sólo cuando haya cobertura: GV_Barrios_Geo + vista gv_barrio_geo_vivo (mediana, ≥3 puntos, sin tocar PPP_Geo) y un tanda_km_max por ámbito como red de seguridad DENTRO de sector/vecinos (tapa Luján dentro de L y Quilmes–Avellaneda si molesta), más el fallback de depósito a Virgilio 2788 y el centroide como fallback en _pppOrdenCarga. No tomar: el clustering de camiones por km ni el componente conexo como NN — dejar camión = etiqueta por sector elegida por el dueño (o = zona, que deja el tablero v13.03 idéntico). Orden: (1) preguntar backend vs front y permiso (protocolo), (2) sembrar tablas con backup, dry-run en begin…rollback contra GV_Tandas_Auto_Log, (3) prender switch + zonas_automaticas '1,2,3' como decisión aparte, (4) documentar el mismo día en docs/SUPABASE-GESTION-VIRGILIO.md.

**Juez 3** — ganador: Propuesta 2 — Sectores + vecinos (33/40). Es la única que el dueño puede leer, discutir y corregir él solo ('Núñez va con Belgrano y Vicente López, no con Lugano'), que se prende HOY sin geocodificar nada ni verificar 50 pines, y que ante un barrio nuevo vuelve sola a la regla de hoy. Las otras dos ponen la decisión que él pidió hoy (frontera norte-sur) a 1-1,4 km de un centroide que nadie verificó.

- Propuesta 1 — Distancia entre centroides (10 km CABA / 20 km GBA) + radio por barrio + pares de excepción + camión por enlace 15 km: fidelidad 8 · simple 4 · implementable 5 · robusto 6 = **23** — FIDELIDAD 8: X=10 reproduce 24/27 tandas mixtas de Capital (89 %) y bloquea Núñez–Lugano 14,8, Devoto–Constitución 12,2; los 3 que pierde (B28A 11,3; B64C 11,5; C10C 12,3) son 1 vez cada uno. Deja pasar Boedo+Pompeya (2,5 km, vecinos reales) y Lanús+Soldati (4,3; 5 tandas históricas). Resta: el margen contra Belgrano–Soldati es 1,4 km y contra V.Urquiza–Lugano 1,1 km con centroides de ±1 km (Belgrano 1 punto, Núñez sin punto) → la frontera norte-sur, que es JUSTO lo que pidió el dueño hoy, queda colgada de coordenadas que nadie verificó; los 20 km de GBA dejan pasar Martínez+Morón (sí lo hizo) pero también Quilmes+Lomas. SIMPLE 4: '10 km' se entiende, pero cuando una tanda le parezca mal el dueño no ve los km ni sabe si mandó el radio_km del barrio, el par prohibido, el cruce CABA/GBA o un centroide corrido: 5 claves de config + 2 tablas + pantalla de mapa con pines nueva. Y el número de camión pasa a ser un cluster por 15 km que cambia según qué cayó ese día — no lo puede predecir. IMPLEMENTABLE 5: depende de sembrar ~50 barrios 'manual_aprox' sin verificar (el sandbox no geocodifica) y 30 de los 48 'medidos' son la casa de UN cliente, no el barrio; Núñez, Colegiales, Villa Crespo, Devoto, Caballito —los del borde— tienen 0 puntos. Sin esa carga el ejemplo Devoto+Villa Luro no funciona. ROBUSTO 6: barrio nuevo → 'sin_geo' agrupa con su zona (no rompe), la vista viva de PPP_Geo se actualiza sola; pero un geocode malo de Nominatim (ya hubo: Moreno con CP 0237) mueve la mediana de un barrio con 1-2 puntos y da vuelta una decisión sin que nadie lo note. Ejemplo que lo condena para el dueño: Palermo+Barracas NO por 200 m (10,2).
- Propuesta 2 — Sectores compactos (14) + lista de sectores vecinos (23 pares), compatible con TODOS los de la tanda, pseudo-sector '~zona' de fallback, camión = etiqueta del sector: fidelidad 7 · simple 9 · implementable 9 · robusto 8 = **33** — FIDELIDAD 7: resuelve lo dicho hoy (Núñez=H, Lugano=B, H-B no vecinos → NO; Capital se mezcla por bordes reales) y la no-transitividad evita la cadena Núñez→Palermo→Almagro→Constitución. Pero la partición es lectura del mapa, no del historial: hubo que cargar a mano A-D (Flores+P.Patricios, D55A viva) y H-F (Belgrano+Recoleta, D56A viva); Soldati+Recoleta (B86A) y Palermo+P.Patricios (B65K) quedan NO; Boedo se movió a Sur-Este por suposición. Y no mide distancia: Ciudadela+Luján (60 km) son el mismo sector L → SÍ, Pilar+Vicente López mismo N → SÍ; Quilmes+Avellaneda 12,8 pasa por J-J2 (bien, 2 tandas Lanús–Quilmes) pero también Berazategui+V.Alsina. Para Capital (lo pedido) alcanza; para GBA es más grueso que su práctica (p90 21 km). SIMPLE 9: es 'quién con quién' en dos tablas que una persona lee en voz alta: mover un barrio = 1 fila, prohibir una mezcla = borrar un par, cambiar el camión del tablero = editar una etiqueta. Se puede operar desde el Table Editor de Supabase sin pantalla nueva. Kill switch sectores_activos=0 vuelve a hoy. Única cosa que le cuesta: revisar 14 sectores + 23 pares de una vez, y entender que 'una tanda A+F no acepta G aunque F↔G sí' (pero es el comportamiento que él quiere). IMPLEMENTABLE 9: cero geocodificación; 115 filas salen de Zonas_Barrios por listas en 1-2 h; los alias de grafía son filas propias. El bucle first-fit nuevo es el mismo esfuerzo que en las otras dos. ROBUSTO 8: barrio nuevo cae a '~Zona X' = regla de hoy, aparece en gv_barrios_sin_sector y lo asigna en una fila; no hay coordenadas que se corran; grafías raras ('mataderos (8:30 a 14)') sólo pierden mezcla hasta asignarse. Punto flojo: un barrio mal sectorizado por error de carga junta cosas lejanas sin ninguna red (no hay km que lo frene), y la normalización JS ≠ SQL (tildes) puede hacer que el tablero no encuentre 'Núñez'.
- Propuesta 3 — 4 capas: barrio canónico → pares de barrios (semilla historial + dueño) → pares de zonas con km_max → distancia por dirección/centroide; kill switch; dry-run RPC: fidelidad 8 · simple 4 · implementable 4 · robusto 7 = **23** — FIDELIDAD 8: es la que más se pega al historial porque lo carga como lista blanca (60-90 pares vistos en la misma tanda, con n_hist y km) y usa la DIRECCIÓN exacta de PPP_Geo cuando existe (Palermo largo 5 km deja de ser un punto); 1-4 apagado por defecto respeta la regla vigente y el dueño lo prende con un toggle. Contras: 8 km en Capital tira Palermo–P.Patricios 9,3 y Recoleta–Soldati 8,5 (los hizo 1 vez cada uno; quedan en 'lista para que decida'); y la semilla histórica trae ruido: barrio por MODA del código de cliente (1792 tiene sucursales en Colegiales/V.Crespo/Almagro), 206 NP con domicilio FISCAL, y 49 % de NP del interior sin hub — o sea la lista blanca puede autorizar pares que nunca pasaron de verdad. SIMPLE 4: cuando una tanda salga rara hay 4 capas, 3 tablas, km_max por par de zonas y un kill switch para averiguar cuál decidió; el campo 'motivo' ayuda pero el dueño tiene que revisar 60-90 pares heredados + ~50 pines + una grilla 10×10 antes de confiar. 'Lista blanca gana sin red' (riesgo 4 de la propia propuesta) es lo peor para alguien que carga rápido. IMPLEMENTABLE 4: necesita TODO lo de la P1 (geo de ~50 barrios sin verificar; sin eso Devoto+Villa Luro da NO por 'sin ubicación', reconocido en su ejemplo 5) MÁS el script de semilla histórica MÁS 8 funciones, 3 tablas, refactor del bucle y una pantalla con 3 pestañas: ~1 día SQL + 1,5 front + 2-3 h del dueño. Es la que más tarde en prenderse. ROBUSTO 7: Capa 4 (sin punto → sólo misma zona) no rompe nada; direcciones nuevas de PPP_Geo entran solas; kill switch en 1 update; `gv_ppp_web_grupo_zona` pasa a componente conexa de GV_Zonas_Pares (elegante). Pero un par SÍ mal tipeado o heredado del historial sucio junta cualquier cosa hasta que alguien lo vea (sólo hay un aviso amarillo).

Mezcla sugerida: Base = Propuesta 2 entera (GV_Sectores / GV_Barrios_Sector / GV_Sectores_Vecinos, compatible-con-todos, pseudo-sector '~zona', camión = etiqueta del sector, sectores_activos como kill switch, gv_barrios_sin_sector). Sumarle de la P3 SOLO la capa 1: una tabla GV_Barrios_Pares (barrio_a, barrio_b, permitido, motivo) que gana sobre los sectores — sirve para dejar escrito 'nuñez–villa lugano NO' aunque alguien mueva un barrio de sector, y para habilitar excepciones puntuales sin abrir sectores enteros (Belgrano+Recoleta SÍ sin declarar H↔F; Soldati+Recoleta SÍ si lo quiere; Luján 'solo' aunque esté en L). NO cargar la semilla histórica automática (ruido de moda/fiscal): mostrarle al dueño la lista de ~20 pares históricos que la partición deja afuera (B86A, B65K, B28A, C10C…) y que él tilde. También de la P3: el campo `motivo` en la salida y la RPC dry-run (gv_ppp_web_sugerir_tandas) para que el sugeridor del front y el tablero consuman el MISMO núcleo y muera pppSugerirTandas (T_MAX 1,00 sin grupos). De la P1, como fase 2 y sólo si el GBA molesta: GV_Barrios_Geo + un `km_max` opcional por sector (red de seguridad dentro de L y N: Luján, Pilar) y el arreglo del depósito fallback (Obelisco → Virgilio 2788); no como regla principal. Puntos a cerrar con el dueño antes de escribir DDL (protocolo backend vs front + permiso): Boedo en Sur-Este o en Centro, si Capital Sur puede ir con Avellaneda/Lanús (B-J/A-J), si Quilmes va con Avellaneda (J-J2), zonas_automaticas '1,2,3', y que 'un camión = una zona' del tablero pasa a 'un camión = etiqueta de sector'. Aparte queda la idea 7317 (Z1/Z2 todos los días es disparo/cupo, ninguna de las tres lo resuelve).

## Los tres diseños evaluados

### Regla de cercanía por SECTORES: partición de barrios en sectores compactos + lista de sectores vecinos, editable en tablas GV_ (backend), consumida por ppp_web_armar_tandas y por el tablero vía vista/RPC

**Regla.** **Enunciado (una sola frase):** dos pedidos pueden ir en la misma tanda si (1) ninguno tiene regla `solo`, (2) los dos tienen SECTOR, y (3) sus sectores son el mismo o figuran como VECINOS en `GV_Sectores_Vecinos`. La zona (1/2/3…) deja de decidir la mezcla; sólo decide qué entra al armado automático (`zonas_automaticas`) y el cupo.

**Sector** = partición fija de barrios en zonas geográficas compactas (Comunas de CABA agrupadas de a 2, partidos del primer cordón agrupados por corredor). Cada barrio de `Zonas_Barrios` (las 115 grafías, alias incluidos) apunta a exactamente un sector en `GV_Barrios_Sector`. **Vecindad** = lista simétrica de pares de sectores que comparten borde real (y que el dueño acepta mezclar). No es transitiva a propósito: Núñez(H) puede con Palermo(G), Palermo con Almagro(F), pero Núñez NO con Almagro salvo que el dueño cargue H↔F.

**Compatibilidad con una tanda ya abierta:** un cliente entra a una tanda abierta sólo si es compatible con TODOS los sectores que ya están en ella (par a par). Así una tanda A+F (Barracas+Once) no puede seguir creciendo con G (Palermo) aunque F↔G sean vecinos, porque A↔G no lo son. Eso es lo que impide la "cadena" norte–sur.

**Fallback para barrio nuevo o sin sector:** `gv_ppp_web_sector(zona, barrio)` devuelve `'~' || zona` (pseudo-sector "zona sola", p.ej. `~Zona 2 - CABA Centro`). Un pseudo-sector es compatible sólo consigo mismo ⇒ el pedido se programa igual (no se pierde ni se traba el job) pero sólo junto a otros de la misma zona sin sector, que es exactamente la regla vigente hoy. Y aparece en la vista `gv_barrios_sin_sector` para que el dueño lo asigne. Súper/Retira/Expo: sector = la zona tal cual (`Super`, `Retira`, `Expo`), sin vecinos; Súper sigue abriendo tanda por cliente.

**Camión (NN del código de tanda y agrupación del tablero):** cada sector tiene un `camion` (etiqueta editable, p.ej. `CAP-SUR`, `CAP-CENTRO`, `CAP-NORTE`, `GBA-SUR`, `GBA-OESTE`, `GBA-NORTE`) y un `orden`. La tanda hereda el camión del cliente que la ABRE; el NN del código es el orden del camión ese día (ya no el orden alfabético del nombre de grupo). El tablero agrupa por ese camión con la misma función.

**Partición propuesta (carga inicial, para que el dueño la revise; 14 sectores):**
- A CAP_SUR_ESTE: barracas, la boca, constitucion, parque patricios (+p.patricios, p. patricios), **boedo**, san cristobal
- B CAP_SUR_SOLDATI: pompeya, nueva pompeya, soldati, villa soldati, villa lugano, lugano, villa riachuelo
- C CAP_OESTE_SUR: mataderos (+"mataderos (8:30 a 14)"), parque avellaneda, liniers, villa luro  ← depósito
- D CAP_CENTRO_OESTE: flores, parque chacabuco, caballito
- E CAP_OESTE_NORTE: villa del parque, villa devoto (+devoto, v.devoto), villa general mitre, paternal
- F CAP_CENTRO: once, balvanera, almagro, monserrat, microcentro (+micro centro), puerto madero, retiro, recoleta
- G CAP_NORTE_PALERMO: palermo, villa crespo, colegiales, villa ortuzar
- H CAP_NORTE_BELGRANO: belgrano, nuñez, villa urquiza, villa pueyrredon
- J GBA_SUR_AVELLANEDA: avellaneda, valentin alsina (+v.alsina), lanus, lanus este, lanus oeste, remedios de escalada
- J2 GBA_SUR_QUILMES: bernal, quilmes, quilmes oeste, berazategui, platanos, florencio varela (+f.varela)
- K GBA_SUR_LOMAS: lomas de zamora, banfield, temperley, adrogue, burzaco, longchamps, rafael calzada, monte grande, esteban echeverria, guernica
- L GBA_OESTE: ciudadela, ramos mejia, villa sarmiento, san justo, mercado central, laferrere (+gregorio de laferrere), gonzalez catan, caseros, palomar, hurlingham, moron, castelar, ituzaingo, san antonio de padua, merlo, moreno, lujan
- M GBA_NORTE_SAN_MARTIN: san martin, v. maipu - san martin, villa lynch, villa ballester, chilavert, jose leon suarez, villa bosch (+v.bosch), munro, villa adelina, san miguel, muñiz, bella vista, jose c paz (+jose c. paz), campo de mayo, tortuguitas (+tortuguita)
- N GBA_NORTE_RIBERA: vicente lopez, olivos, martinez, san isidro, tigre, garin, pilar

**Vecinos propuestos (23 pares, simétricos):** A-B, A-F, A-D, A-J · B-C, B-D, B-J · C-D, C-E, C-L · D-E, D-F, D-G · E-G, E-H, E-L, E-M · F-G, F-H · G-H · H-M, H-N · J-J2, J-K, J2-K · L-M · M-N.
Deliberadamente NO vecinos: H/G con A/B (Núñez/Belgrano/Palermo con Lugano/Soldati/Barracas), F con B (Once con Soldati), H con F es dudoso (Belgrano–Recoleta ~7 km; el dueño lo hizo una vez en D56A) → lo dejo cargado y él lo saca si no quiere. A-D (Flores–P.Patricios) está porque el dueño lo hizo en D55A. Boedo lo muevo de Centro a A para que Boedo–Pompeya (vecinos reales) sea SÍ sin abrir F↔B.

**Parámetros.** Todo lo que el dueño ajusta sin programar vive en 3 tablas + 2 claves de `PPP_Web_Config` (misma reja de escritura que `GV_Clientes_Reglas`: los 3 mails de supervisor):

1. `GV_Sectores` (sector pk, nombre, camion, orden, activo). Cambiar `camion` reagrupa el tablero y el NN de las tandas; `orden` define la secuencia de camiones/recorrido; `activo=false` manda sus barrios al fallback "zona sola".
2. `GV_Barrios_Sector` (barrio_norm pk, sector fk, nota). Mover un barrio de sector = un `update` de una fila. Un alias de grafía es una fila más apuntando al mismo sector (no hace falta unificar `Zonas_Barrios`).
3. `GV_Sectores_Vecinos` (sector_a, sector_b, permitido, nota; pk del par ordenado, check a<b). Agregar/borrar un par = habilitar/prohibir esa mezcla. `permitido=false` sirve para dejar documentado un "NO" explícito (p.ej. H-B con nota "Núñez con Lugano no, dueño 2026-09-05").
4. `PPP_Web_Config`: `sectores_activos` (1 = regla por sectores; 0 = vuelve a `gv_ppp_web_grupo_zona` tal cual hoy — rollback de un update), `zonas_automaticas` = '1,2,3' (para que la Z3 entre al job; hoy '1,2'). Los demás no cambian: `tanda_m3_max_mezcla` 0,80, `m3_max_dia` 5, `dias_hasta_entrega` 0.

No hay coordenadas ni umbral de km en esta regla: es una tabla de "quién con quién", legible y discutible por una persona. Si más adelante se quiere una red de seguridad por distancia, se agrega `tanda_km_max` + `GV_Barrios_Geo` como segunda condición sin tocar esto.

**Ejemplos.** Evaluados con la carga inicial propuesta (`sector(a)`, `sector(b)`, ¿mismo o vecinos?):

1. **Núñez + Villa Lugano → NO.** Núñez = H (CAP_NORTE_BELGRANO), Lugano = B (CAP_SUR_SOLDATI). H-B no está en vecinos (y se puede cargar con `permitido=false` y nota para que quede escrito). Es el caso que pidió el dueño: las zonas 1 y 2 se mezclan, este par no.
2. **Pompeya + Barracas → SÍ.** B y A, par A-B declarado (3,4 km, Av. Sáenz/Amancio Alcorta). Es el par más frecuente del historial junto con Pompeya–Soldati.
3. **Boedo + Pompeya → SÍ** con la carga propuesta (Boedo en A; A-B vecinos). Si el dueño prefiere Boedo en Centro (F), pasa a NO porque F-B no son vecinos; es una decisión de una fila en `GV_Barrios_Sector`. Lo marco como punto a confirmar con él.
4. **Flores + Mataderos → SÍ.** D y C, par C-D declarado (4 km por Av. Directorio/Alberdi). Además ya lo hizo (2 tandas históricas).
5. **Devoto + Villa Luro → SÍ.** E y C, par C-E declarado (Comunas 10/11, ~4 km por Av. Lope de Vega). Villa Luro es el barrio del depósito.
6. **Lanús + Soldati → SÍ por sectores** (J y B, par B-J por Puente Alsina, ~5 km) **pero hoy no pasa por el automático**: Lanús es Zona 4 y `zonas_automaticas` sería '1,2,3'. Sólo lo permitiría a mano en "A Programar" (el sugeridor del front con la misma RPC). Si el dueño no quiere cruzar Capital con GBA Sur ni a mano, se borra el par B-J (y A-J). Historial: Z1+Z4 en 5 tandas, así que lo dejo cargado.
7. **Belgrano + Palermo → SÍ.** H y G, par G-H declarado (Comunas 13/14, ~3 km).
8. **Quilmes + Avellaneda → SÍ.** J2 y J, par J-J2 declarado (mismo corredor Sur-Este, ~14 km por Av. Mitre/Calchaquí). Ojo: es el ejemplo de que la vecindad no mide distancia; si el dueño quiere que Quilmes sólo vaya con Bernal/Berazategui, borra J-J2 y listo. Historial: Lanús–Quilmes 2 tandas.

Extra que muestra el "no transitivo": Núñez(H)+Palermo(G)=SÍ, Palermo(G)+Almagro(F)=SÍ, pero una tanda que ya tiene Núñez+Palermo NO acepta Almagro (H-F no es vecino… salvo que se deje cargado H-F por D56A; entonces sí). Constitución(A)+Once(F)=SÍ, Constitución(A)+Devoto(E)=NO, Constitución(A)+Villa Urquiza(H)=NO — los 0/1 casos históricos, todos casos borde.

**Backend.** Todo objeto nuevo con prefijo `GV_`/`gv_`, RLS prendida, vistas `security_invoker=true`, sin triggers en tablas compartidas; `Zonas_Barrios` y `PPP_Geo` sólo se leen. `ppp_web_armar_tandas` y `gv_ppp_web_grupo_zona` son nuestras (0 refs en Producción, HEAD e15b682) → se pueden reemplazar con `create or replace`. Archivo nuevo `sql/gv_sectores.sql`.

```sql
-- ── Tablas ──
create table if not exists public."GV_Sectores" (
  sector text primary key,                      -- 'A','B',…,'N' (clave corta)
  nombre text not null,                         -- 'Capital Sur-Este (Barracas/Constitución)'
  camion text not null,                         -- etiqueta del camión del tablero: 'CAP-SUR'
  orden  int  not null default 100,             -- secuencia de camiones/recorrido
  activo boolean not null default true,
  nota   text, actualizado timestamptz not null default now());

create table if not exists public."GV_Barrios_Sector" (
  barrio_norm text primary key,                 -- = public._norm_barrio(barrio), igual que Zonas_Barrios
  sector text not null references public."GV_Sectores"(sector),
  nota text, actualizado timestamptz not null default now());

create table if not exists public."GV_Sectores_Vecinos" (
  sector_a text not null references public."GV_Sectores"(sector),
  sector_b text not null references public."GV_Sectores"(sector),
  permitido boolean not null default true,
  nota text, actualizado timestamptz not null default now(),
  primary key (sector_a, sector_b),
  constraint gv_sectores_vecinos_orden_chk check (sector_a < sector_b));  -- el par se guarda una vez
-- RLS + policies: copiar las de GV_Clientes_Reglas (select authenticated; write 3 mails).
-- Además `grant select … to anon` en las 3 (el tablero puede abrirse sin login).

-- ── Funciones ──
-- Sector de un pedido. Fallback '~zona' = pseudo-sector "zona sola" (regla de hoy).
create or replace function public.gv_ppp_web_sector(p_zona text, p_barrio text)
returns text language sql stable as $$
  select case
    when coalesce(btrim(p_zona),'') = '' then null
    when p_zona in ('Super','Retira','Expo') then p_zona
    else coalesce(
      (select b.sector from public."GV_Barrios_Sector" b
         join public."GV_Sectores" s on s.sector = b.sector and s.activo
        where b.barrio_norm = public._norm_barrio(p_barrio)),
      '~' || btrim(p_zona))
  end $$;

-- ¿Dos sectores pueden compartir tanda?  mismo, o vecinos permitidos. Pseudo-sectores: sólo consigo mismos.
create or replace function public.gv_ppp_web_pueden_compartir(p_a text, p_b text)
returns boolean language sql stable as $$
  select p_a is not null and p_b is not null and (p_a = p_b or exists (
    select 1 from public."GV_Sectores_Vecinos" v
     where v.permitido and v.sector_a = least(p_a,p_b) and v.sector_b = greatest(p_a,p_b))) $$;

-- ¿Un sector es compatible con TODOS los que ya están en una tanda?
create or replace function public.gv_ppp_web_compatible(p_sector text, p_sectores text[])
returns boolean language sql stable as $$
  select coalesce(p_sectores,'{}') = '{}'
      or not exists (select 1 from unnest(p_sectores) s where not public.gv_ppp_web_pueden_compartir(p_sector, s)) $$;

-- Camión + orden de un sector (para el NN del código y el tablero). Pseudo-sector → camión = la zona.
create or replace function public.gv_ppp_web_camion(p_sector text)
returns table (camion text, orden int) language sql stable as $$
  select coalesce(s.camion, ltrim(p_sector,'~')), coalesce(s.orden, 900)
    from (select p_sector x) q left join public."GV_Sectores" s on s.sector = q.x $$;

-- Par a par desde el front (RPC): mismo criterio, entrada = zona+barrio de cada pedido.
create or replace function public.gv_ppp_web_pueden_compartir_pedidos(
  p_zona_a text, p_barrio_a text, p_zona_b text, p_barrio_b text)
returns boolean language sql stable as $$
  select public.gv_ppp_web_pueden_compartir(public.gv_ppp_web_sector(p_zona_a,p_barrio_a),
                                            public.gv_ppp_web_sector(p_zona_b,p_barrio_b)) $$;

-- Vistas (security_invoker) para el tablero y el mantenimiento.
create or replace view public.gv_ppp_web_sectores with (security_invoker=true) as
  select b.barrio_norm, b.sector, s.nombre, s.camion, s.orden, s.activo
    from public."GV_Barrios_Sector" b join public."GV_Sectores" s using (sector);
create or replace view public.gv_barrios_sin_sector with (security_invoker=true) as
  select z.barrio_norm, z.zona from public."Zonas_Barrios" z
   where z.zona not in ('Super','Retira','Expo')
     and not exists (select 1 from public."GV_Barrios_Sector" b where b.barrio_norm = z.barrio_norm);
-- grant execute a anon, authenticated, service_role en las 5 funciones; grant select en las 2 vistas.
```

**Integración en `ppp_web_armar_tandas` (sql/ppp_web_tandas.sql):**
- L268: agregar a `_sin_tanda` la columna `sector = case when v_sect then public.gv_ppp_web_sector(zona, barrio) else public.gv_ppp_web_grupo_zona(zona) end` (con `v_sect := coalesce(cfg 'sectores_activos',0)<>0`) y `camion`/`orden` vía `gv_ppp_web_camion(sector)`. Con `sectores_activos=0` el sector ES el grupo de hoy y el bucle nuevo se comporta idéntico al actual (los grupos sólo son compatibles consigo mismos) → rollback sin redeploy.
- L294/L310/L314-341 (filtros, cupo, selección por cliente): sin cambios.
- L344-376 (bucle): reemplazar "una tanda abierta por grupo" por **first-fit sobre varias tandas abiertas**:
  ```sql
  create temp table _abiertas (code text, camion text, sectores text[], acum numeric, abierta_en int) on commit drop;
  create temp table _camiones (camion text primary key, zn int, ti int) on commit drop;
  for r_cli in
    select cliente, sum(m3) m3_cli, bool_or(va_solo) solo,
           min(orden) orden, min(camion) camion, min(sector) sector   -- un cliente = un sector (min por si trae 2 NP)
      from _sin_tanda group by cliente
     order by min(orden), min(sector), sum(m3) desc, cliente          -- recorrido por camión → sector → tamaño
  loop
    v_code := null;
    if not (r_cli.sector in ('Super') or r_cli.solo or r_cli.m3_cli >= v_tope) then
      select code into v_code from _abiertas a
       where a.acum + r_cli.m3_cli <= v_tope
         and public.gv_ppp_web_compatible(r_cli.sector, a.sectores)
       order by (a.camion = r_cli.camion) desc, a.abierta_en limit 1;   -- preferí el camión propio
    end if;
    if v_code is null then
      insert into _camiones (camion, zn, ti) values (r_cli.camion, (select coalesce(max(zn),0)+1 from _camiones), 0)
        on conflict (camion) do nothing;
      select zn, ti into v_zn, v_ti from _camiones where camion = r_cli.camion;
      v_code := case when v_pref <> '' then v_pref else public.ppp_web_letra(v_letra) end
                || lpad(v_zn::text,2,'0') || public.ppp_web_letra(v_ti);
      update _camiones set ti = ti + 1 where camion = r_cli.camion;
      insert into _abiertas values (v_code, r_cli.camion, '{}', 0, (select count(*) from _abiertas));
    end if;
    insert into _asig select s.order_id, s.np_idx, v_code from _sin_tanda s where s.cliente = r_cli.cliente;
    update _abiertas set acum = acum + r_cli.m3_cli,
           sectores = array_append(sectores, r_cli.sector) where code = v_code;
    if r_cli.sector = 'Super' or r_cli.solo or r_cli.m3_cli >= v_tope then delete from _abiertas where code = v_code; end if;
  end loop;
  ```
  Retira sigue juntándose entre sí (mismo sector 'Retira'). El `return query` (L392) devuelve `min(sector)` y `min(camion)` en vez de `min(grupo)`; `PPP_Web_Programacion` recibe además `gv_sector`/`gv_camion` (2 columnas nuevas nullable, tabla nuestra) para que el tablero no tenga que recalcular.
- `gv_ppp_web_zona_automatica` no cambia; sólo `zonas_automaticas` → '1,2,3'.
- La Edge Function `gv-ppp-web-tandas-diarias` no cambia (ya manda `barrio` y `zona` en `p_filas`). El `GV_Tandas_Auto_Log` pasa a mostrar sector/camión.

**Pruebas antes de prender** (sólo SELECT / dry-run): (i) `select public.gv_ppp_web_pueden_compartir_pedidos('Zona 2 - CABA Centro','Núñez','Zona 1 - CABA Sur','Lugano')` → false; los 8 ejemplos de arriba; (ii) correr `ppp_web_armar_tandas` dentro de `begin … rollback` con las filas de hoy y comparar contra la corrida real del log; (iii) `select * from gv_barrios_sin_sector` = 0 filas después de la carga.

**Tablero.** Hoy el tablero (`_pppCamiones`, index.html:29359-29374) hace **un camión = una zona suelta** por día (decisión del dueño en v13.03) y el sugeridor manual (`pppSugerirTandas`) agrupa por zona sin 2+3. Para que las tres cosas usen UNA regla:

1. **Carga única al abrir el tablero:** `supabase.from('gv_ppp_web_sectores').select('*')` (≈115 filas) + `from('GV_Sectores_Vecinos')` (≈25 filas) → se cachean en `_pppSectores` (Map barrio_norm→{sector,camion,orden}) y `_pppVecinos` (Set 'A|B'). Normalización en JS: misma que `_norm_barrio` (lower, sin tildes, espacios colapsados) — hay que agregar una `_pppNormBarrio` porque `_rtNorm` conserva tildes.
2. **`_pppCamionPed(p)`** reemplaza a `_pppZonaPed` como clave de agrupación: si la fila trae `gv_camion` (web, ya calculado por el backend) se usa tal cual; si no (filas ISIS de `gv_ppp_programacion_diaria`, que no pasan por el armado), `camion = _pppSectores.get(norm(p.barrio||p.localidad))?.camion ?? p.zona` (mismo fallback "zona sola" que el backend). Súper y Retira siguen aparte. El encabezado del camión muestra `camion` + los sectores/barrios que contiene (`CAP-SUR · Barracas, Pompeya, Soldati`) y las tandas acumuladas como hoy. Orden de camiones por `orden` de `GV_Sectores` (hoy `RT_RUTAS` so/n) — sigue habiendo un `_pppOrdenCarga` por camión con `_rtOptimize`, sin cambios.
3. **Sugeridor manual (`pppSugerirTandas` / `_pppBalancearZona`):** en vez de `byZ` por zona, agrupar por `camion` y, al llenar una tanda, aceptar un cliente sólo si `_pppCompatible(sector, sectoresTanda)` (misma lógica que `gv_ppp_web_compatible`, duplicada como UX). Y unificar T_MAX con `tanda_m3_max_mezcla` (hoy front 1,00 vs backend 0,80: es una divergencia que conviene cerrar en el mismo cambio, preguntándole al dueño cuál vale). Opción más limpia: agregar `p_dry boolean default false` a `ppp_web_armar_tandas` (no inserta, sólo devuelve `(order_id, np_idx, tanda)`) y que el sugeridor llame la RPC: cero duplicación. Lo propongo como paso 2.
4. **Avisos en el tablero:** pill "N barrios sin sector" leyendo `gv_barrios_sin_sector`; y en cada pedido con pseudo-sector (`~Zona…`) un ⚠ "barrio sin sector: sólo se junta con su zona". Botón "📍 Sectores" en el panel supervisor con tres listas editables (sectores, barrio→sector, vecinos) que escriben directo en las tablas GV_ (RLS ya limita a los 3 mails). Sin ese botón el dueño puede editar desde el Table Editor de Supabase; la regla igual funciona.
5. **Mismo camión en las dos pantallas:** "A Programar" (pwebZonaSugerida) muestra junto a la zona el sector/camión (`Zona 2 · Núñez · CAP-NORTE`), así lo que ve al programar a mano coincide con cómo lo va a agrupar el job.

Nota al dueño: esto cambia "un camión = una zona" por "un camión = grupo de sectores" (la etiqueta `camion` la elige él; si carga `camion = zona` para cada sector, el tablero queda idéntico a hoy y sólo cambia la mezcla dentro de la tanda). Hay que preguntárselo explícitamente antes de tocar el tablero.

**Mantenimiento.** **Carga inicial (una vez, con backup y INSERT-only):**
- 14 filas en `GV_Sectores`, ~115 en `GV_Barrios_Sector` (se generan con `insert … select barrio_norm, <sector> from "Zonas_Barrios"` por listas; los alias de grafía entran como filas propias, no hay que arreglar `Zonas_Barrios`), ~25 pares en `GV_Sectores_Vecinos`. Estimo 1–2 h de SQL + 30 min del dueño revisando la tabla impresa (barrio → sector, y la lista de pares). No hace falta geocodificar nada: no se usan coordenadas. Los puntos a decidir con él están listados: Boedo en A o F, H-F (Belgrano–Recoleta), B-J/A-J (Capital Sur con Avellaneda/Lanús), J-J2 (Avellaneda con Quilmes).
- `PPP_Web_Programacion` tiene 0 filas hoy → no hay migración de datos; las 2 columnas nuevas (`gv_sector`, `gv_camion`) son nullable.
- Prender: `update "PPP_Web_Config" set valor=1 where clave='sectores_activos'; update … set valor_texto='1,2,3' where clave='zonas_automaticas';`. Apagar: `valor=0` (vuelve a `gv_ppp_web_grupo_zona`) y `'1,2'`. Rollback total: `drop` de las 5 funciones nuevas, 2 vistas, 3 tablas y 2 columnas; restaurar `ppp_web_armar_tandas` desde `sql/ppp_web_tandas.sql` actual (md5 3b7ae2a5…).

**Cuando aparece un barrio nuevo:** Producción lo aprende con su trigger en `Zonas_Barrios` (nosotros no podemos reaccionar con trigger); el pedido entra al job con pseudo-sector `~Zona X` → se programa solo con su zona (regla de hoy, nada se rompe), el tablero lo marca ⚠ y `gv_barrios_sin_sector` lo lista. El dueño lo asigna (una fila) y desde la corrida siguiente ya mezcla. Sin cron ni Edge Function nuevos.

**Cuando el dueño cambia de opinión:** mover un barrio = `update GV_Barrios_Sector`; permitir/prohibir una mezcla = insert/delete/`permitido` en `GV_Sectores_Vecinos`; redefinir camiones = `update GV_Sectores set camion/orden`. Efecto en la próxima corrida del job (00:01) y al recargar el tablero; lo ya programado con tanda no se reacomoda (idempotencia actual).

**Documentación el mismo día:** `docs/SUPABASE-GESTION-VIRGILIO.md` (objetos, medición: la query de los 8 ejemplos y el dry-run comparado, rollback), `GUIA-PROYECTO.md` (regla de sectores, pseudo-sector, camión), `sql/gv_sectores.sql` con la carga inicial versionada (así la tabla se puede re-sembrar), bump de versión y `docs/IDEAS-USUARIO.md` (idea 7317 queda aparte: es de disparo/cupo, no de cercanía).

**Riesgos.** **Honestos, en orden de importancia:**
1. **La partición y los vecinos son MI lectura del mapa y del historial, no una regla dicha por el dueño.** 27 tandas históricas mixtas de Capital es una muestra chica; dos tandas reales (D55A Flores+P.Patricios, D56A Belgrano+Recoleta) sólo pasan porque cargué A-D y H-F a mano. Hay que sentarse con él a validar barrio por barrio antes de prender. Riesgo: si se prende con sectores mal cargados, el job arma tandas raras hasta que alguien lo note (mitigación: dry-run comparado + `sectores_activos=0` de rollback inmediato).
2. **La vecindad no mide distancia:** dentro de un sector o entre vecinos puede haber 12–15 km (Quilmes–Avellaneda, Luján dentro de L, Pilar en N). Para Capital (lo que pidió hoy) alcanza; para GBA es más grueso que la práctica real. Si hace falta, segunda condición por km (`GV_Barrios_Geo`, ya diseñada) — pero eso sí requiere geocodificar ~50 barrios.
3. **Protocolo backend vs front y cambio de "camión":** el dueño decidió el 2026-09-04 "2+3 y 6+7" y en v13.03 "un camión = una zona". Esta regla reemplaza las dos. Hay que preguntarle explícitamente (a) que la regla vaya al backend (b) si el camión del tablero pasa a ser por sector/etiqueta (c) `zonas_automaticas` a '1,2,3' (la Z3 entra al automático y consume del cupo de 5 m³ compartido). Nada de esto se implementa sin su OK.
4. **Base compartida:** no se toca `Zonas_Barrios`, `PPP_Geo` ni `PPP_Programacion_Diaria` (4 triggers de Producción). `ppp_web_armar_tandas`/`gv_ppp_web_grupo_zona`/`PPP_Web_Programacion` tienen 0 refs en Producción (grep HEAD e15b682) — igual grepear de nuevo el día del cambio. El clon de Producción está en `/home/user/produccion-virgilio`, no en la ruta del CLAUDE.md.
5. **Alias y normalización:** `_norm_barrio` (SQL) y `_rtNorm` (JS) normalizan distinto (tildes); si el front busca `Núñez` con `_rtNorm` no matchea `nuñez`. Hay que agregar una normalización JS igual a la SQL. Grafías nuevas que Producción cree ("mataderos (8:30 a 14)") caen al fallback hasta que se asignen — no rompe, pero deja de mezclar ese barrio.
6. **Bucle first-fit nuevo:** más complejo que el actual (varias tandas abiertas, `_abiertas`/`_camiones` temporales). Riesgo de bug en el borde (Súper/solo/≥tope, clientes con NP en 2 sectores → tomo `min(sector)`). Mitigación: `sectores_activos=0` debe reproducir bit a bit la salida actual — probarlo en dry-run contra el `GV_Tandas_Auto_Log` de los días anteriores antes de prender.
7. **Zona 1 y 2 "todos los días" no la resuelve esta regla:** eso es disparo/cupo (idea 7317 + `m3_max_dia`), un cambio aparte. Con más zonas automáticas y cupo 5 m³, más clientes quedan en cola: revisar el cupo con el dueño.
8. **Datos sucios ya detectados y NO tocados** (protocolo): `PPP_Programacion_Diaria` burzaco→Zona 2 (3 pedidos vivos), `wa_np_snapshot` villa lugano→Zona 3. Con sectores el barrio manda sobre la zona, así que esos errores de zona dejan de importar para la mezcla (burzaco→K), pero siguen mal para el cupo/automático. Sólo reportar; corregir si el dueño lo pide.
9. **Trabajo estimado:** SQL (tablas, funciones, bucle, carga) ~1 día; tablero + sugeridor + normalización JS + pantalla de edición ~1 día; validación con el dueño y docs ~medio día. Sin la pantalla de edición (Table Editor de Supabase) se ahorra medio día.

### Regla de cercanía por distancia entre barrios (centroides GV_Barrios_Geo, umbral por ámbito CABA/GBA, diámetro de tanda acotado, excepciones por par)

**Regla.** **Enunciado (una sola regla, backend):** dos pedidos A y B pueden ir en la misma tanda si (1) los dos suman ≤ `tanda_m3_max_mezcla` (0,80, como hoy), (2) los dos tienen centroide de barrio resuelto por `gv_barrio_geo()`, (3) no hay una fila en `GV_Barrios_Pares` que prohíba el par (y si hay una que lo permite, gana y se saltea el punto 4), y (4) la distancia haversine entre los centroides es ≤ `min(radio(A), radio(B))`, donde `radio(X)` = `GV_Barrios_Geo.radio_km` del barrio si está cargado, si no el default por ámbito: `tanda_km_max_caba` (10 km) si el barrio es de Zona 1/2/3, `tanda_km_max_gba` (20 km) si es de Zona 4–7. Un par CABA+GBA usa el mínimo (10) y además necesita `tanda_cruzar_caba_gba = 1`. **La condición se exige contra TODOS los que ya están en la tanda** (diámetro de la tanda ≤ umbral), no sólo contra el último: así Villa Crespo no "puentea" Núñez con Lugano. Retira, Súper, Expo y los clientes `solo` siguen con la regla actual (Súper uno por cliente, Retira se junta entre sí, solo abre tanda propia) — la distancia no aplica a ellos.

**Sin sectores fijos:** el número de zona deja de decidir la mezcla. Zonas 1, 2 y 3 se mezclan libremente si están a ≤10 km; las zonas 6+7 y 5+6 se mezclan si están a ≤20 km (reproduce lo que el dueño hace hoy: Chilavert+Olivos 7,3, San Martín+V.Urquiza 5,1, Martínez+Morón 18,5), y 1+4 se mezcla sólo cuando son linderos de verdad (Lanús+Soldati 4,3, Avellaneda+Barracas 2,1), que es lo que muestra el historial (5 tandas Z1+Z4) y hoy está prohibido.

**Por qué X = 10 km en Capital (elegido con el historial):** de las 27 tandas históricas que mezclan Z1/Z2/Z3, 24 (89 %) tienen diámetro ≤ 10 km y las 3 que caen (B28A Constitución+V.Pueyrredón 11,3; B64C Soldati+Ciudadela 11,5; C10C Mataderos+Núñez 12,3) son justamente casos "norte+sur" u "oeste lejos" de los que el dueño hoy dice que no. Del otro lado, los pares que él no quiere quedan todos por encima: Núñez–Lugano 14,8, Devoto–Constitución 12,2, Belgrano–Soldati 11,4, V.Urquiza–Lugano 11,1, Palermo–Soldati 11,1, Colegiales–Lugano 11,6. X=12 dejaría pasar Belgrano+Soldati (11,4) y V.Urquiza+Lugano (11,1): descartado. X=10 es la banda que separa lo hecho de lo prohibido; el margen contra Belgrano–Soldati es de sólo 1,4 km, por eso existe `GV_Barrios_Pares` (para clavar "nuñez–villa lugano: no" aunque alguien corra un centroide) y `radio_km` por barrio (p.ej. Palermo y Soldati son barrios de 4–5 km de largo: si generan tandas raras se les baja el radio a 8 sin tocar el resto). **Por qué 20 km en GBA:** las tandas históricas 5+6 tienen máximo 18,5 y las 6+7 mediana 17,8; las que pasan de 20 son casi todas Pilar/Guernica/Berazategui (outliers que con 20 quedan solas, que es lo deseable).

**Fallback barrio nuevo (no rompe nada):** si `gv_barrio_geo(barrio)` devuelve null (barrio que Producción acaba de aprender en `Zonas_Barrios` y nadie ubicó), el pedido conserva su zona y sólo puede compartir tanda con pedidos de la MISMA zona exacta que tampoco tengan geo o que estén a ≤ umbral del centroide de la zona (config `sin_geo_modo` = 'zona'; 'solo' = abre tanda propia). Motivo `sin_geo` queda en la salida de la RPC y en `GV_Tandas_Auto_Log`, y el tablero muestra el contador de `gv_barrios_sin_geo`. Nunca se cae el job ni queda un pedido sin programar por falta de coordenada.

**Camión (número de la tanda):** con la regla nueva el "grupo" ya no existe, así que el número NN de `LETRA+NN+LETRA` se asigna al final: las tandas del día se agrupan en camiones por enlace completo con radio `camion_km_max` (15 km default): una tanda entra al camión si TODAS sus paradas están a ≤ 15 km de todas las paradas del camión; si no, abre camión nuevo. Es la misma función para el job y para el tablero.

**Parámetros.** Todo en `PPP_Web_Config` (tabla nuestra, ya la edita el dueño desde la pantalla de configuración de la PPP Web) + dos tablas editables:

| clave | default | qué hace |
|---|---|---|
| `tanda_km_max_caba` | 10 | radio para pares donde los dos barrios son Zona 1/2/3 |
| `tanda_km_max_gba` | 20 | radio para pares donde los dos barrios son Zona 4–7 |
| `tanda_cruzar_caba_gba` | 1 | 1 = un pedido de CABA puede ir con uno de GBA si están a ≤ `tanda_km_max_caba`; 0 = nunca (vuelve a "1 con nadie de GBA") |
| `camion_km_max` | 15 | diámetro máximo de un camión (agrupa tandas para el número NN y para el tablero) |
| `sin_geo_modo` (valor_texto) | 'zona' | barrio sin coordenada: 'zona' = sólo con su misma zona, 'solo' = tanda propia |
| `tanda_m3_max_mezcla`, `m3_max_dia`, `zonas_automaticas` | 0,80 / 5 / '1,2' | no cambian; para que la Z3 entre al job de las 00:01 el dueño pone `zonas_automaticas = '1,2,3'` (ya previsto) |

Por barrio (`GV_Barrios_Geo`): `lat`, `lng`, `radio_km` (null = default del ámbito), `activo`. Por par (`GV_Barrios_Pares`): `barrio_a`, `barrio_b`, `permitido` (true = siempre juntos aunque pase el radio; false = nunca), `motivo`. Ejemplos que el dueño cargaría hoy: (`nuñez`,`villa lugano`,false,'dueño 2026-09-05'), (`belgrano`,`soldati`,false), y si quiere (`quilmes`,`avellaneda`,true). Todo se edita desde una pantalla nueva "📍 Barrios" (mapa Leaflet ya existente en v9.75 + tabla): arrastrar el pin corrige lat/lng, un campo radio, y un botón "probar par" que llama a `gv_ppp_web_pueden_compartir` y muestra km + motivo. No hay que programar para cambiar X, prohibir un par ni ubicar un barrio.

**Ejemplos.** Distancias haversine sobre los centroides propuestos (PPP_Geo o manual_aprox), X_caba=10, X_gba=20, cruce CABA/GBA=1:

1. **Núñez + Lugano → NO.** 14,8 km > 10 (ambos CABA). Aunque alguien subiera X a 14 sigue no; y con la fila `GV_Barrios_Pares(nuñez, villa lugano, false)` queda clavado independientemente de los centroides.
2. **Pompeya + Barracas → SÍ.** 3,4 km ≤ 10. Ambos Z1 (hoy ya iban juntos); es el par histórico más común de Z1.
3. **Boedo + Pompeya → SÍ.** 2,5 km ≤ 10. Z2+Z1: hoy PROHIBIDO por la regla de grupos, pero son barrios linderos (Boedo termina en Av. Caseros / Sáenz). Es exactamente el caso que el dueño quiere habilitar.
4. **Flores + Mataderos → SÍ.** 5,1 km ≤ 10. Ambos Z3; historial: 2 tandas.
5. **Devoto + Villa Luro → SÍ.** 3,8 km ≤ 10. Z2+Z3 (ya permitido hoy), y además Villa Luro es el barrio del depósito (0,6 km).
6. **Lanús + Soldati → SÍ (con `tanda_cruzar_caba_gba=1`).** 4,3 km ≤ min(10, 20) = 10. Z4+Z1: hoy prohibido; el historial tiene 5 tandas Z1+Z4 (Soldati/Pompeya con Avellaneda/Lanús). Si el dueño no quiere cruzar Gral. Paz/Riachuelo: config a 0 y pasa a NO.
7. **Belgrano + Palermo → SÍ.** 1,8 km ≤ 10. Z2+Z2.
8. **Quilmes + Avellaneda → SÍ.** 12,8 km ≤ 20 (ambos GBA, Z4). Historial: Lanús–Quilmes 13,8 km en 2 tandas. Con X_gba=10 sería NO: por eso el umbral de GBA es distinto (el conurbano sur es un solo corredor por Av. Mitre/Calchaquí).

Casos borde que conviene mostrarle al dueño: Belgrano+Soldati 11,4 → NO (margen 1,4 km); Palermo+Barracas 10,2 → NO por 200 m (si le molesta, `radio_km` o par permitido); Palermo+P.Patricios 9,3 → SÍ (lo hizo 1 vez, B65K); Villa Crespo+Lugano 9,4 → SÍ (dudoso: un par prohibido lo resuelve, o X=9 que sólo pierde B65K del historial); Recoleta+Soldati 8,5 → SÍ (B86A, 1 vez); Núñez+Flores 8,5 → SÍ; Mataderos+Núñez 12,4 → NO (C10C se perdería, coherente con "norte no va con sur/oeste lejos"); San Martín+Tigre 17,8 → SÍ (Z6+Z7, 2 tandas históricas); Pilar+cualquiera de Capital → NO (≥ 40 km).

**Backend.** Todo con prefijo `GV_`/`gv_`, RLS on, vistas `security_invoker`, sin triggers sobre `PPP_Geo` ni `Zonas_Barrios` (compartidas; sólo se leen). Nada de esto lo referencia Producción (`ppp_web_armar_tandas`, `gv_ppp_web_grupo_zona`, `PPP_Web_Programacion`: 0 refs en su repo).

```sql
-- 1) Centroides por barrio (fuente canónica de Gestión)
create table public."GV_Barrios_Geo" (
  barrio_norm  text primary key,               -- = public._norm_barrio(barrio), misma clave que Zonas_Barrios
  barrio_canon text not null,                  -- alias → canónico ('p.patricios' → 'parque patricios')
  lat numeric(9,6) not null, lng numeric(9,6) not null,
  radio_km numeric(5,2),                       -- null = default del ámbito
  ambito text not null check (ambito in ('CABA','GBA','OTRO')),
  fuente text not null check (fuente in ('manual','ppp_geo','manual_aprox')),
  n_puntos int default 0, activo boolean default true,
  motivo text, actualizado timestamptz default now());
alter table public."GV_Barrios_Geo" enable row level security;
-- select: anon, authenticated · insert/update/delete: sólo los 3 mails de supervisor (misma policy que GV_Clientes_Reglas)

-- 2) Excepciones por par (gana sobre la distancia)
create table public."GV_Barrios_Pares" (
  barrio_a text not null, barrio_b text not null,   -- guardar ordenados: least/greatest
  permitido boolean not null, motivo text, actualizado timestamptz default now(),
  primary key (barrio_a, barrio_b), check (barrio_a < barrio_b));
-- RLS igual que arriba.

-- 3) Centroide vivo desde PPP_Geo (sin mantenimiento, sin tocar PPP_Geo)
create view public.gv_barrio_geo_vivo with (security_invoker = true) as
select public._norm_barrio(barrio) barrio_norm, count(*) n,
       percentile_cont(0.5) within group (order by lat) lat,
       percentile_cont(0.5) within group (order by lng) lng
  from public."PPP_Geo"
 where lat between -35.2 and -34.2 and lng between -59.3 and -57.9
 group by 1;

-- 4) Resolución con precedencia: manual > vivo (≥3 puntos) > tabla (ppp_geo/manual_aprox) > null
create or replace function public.gv_barrio_geo(p_barrio text)
returns table (lat numeric, lng numeric, radio_km numeric, ambito text, fuente text)
language sql stable as $$ ... coalesce por barrio_norm y por barrio_canon ... $$;

-- 5) Distancia y compatibilidad de a pares
create or replace function public.gv_barrio_dist_km(p_a text, p_b text) returns numeric
language sql stable;   -- haversine: 2*6371*asin(sqrt(...)); null si falta alguno

create or replace function public.gv_ppp_web_pueden_compartir(p_barrio_a text, p_barrio_b text, p_zona_a text, p_zona_b text)
returns table (ok boolean, km numeric, umbral numeric, motivo text)
language plpgsql stable;
-- motivos: 'par_prohibido' | 'par_permitido' | 'sin_geo' (→ ok = misma zona exacta según sin_geo_modo)
--          | 'cruce_caba_gba' | 'km' (ok = km <= umbral) ; umbral = min(radio_a, radio_b) con defaults de PPP_Web_Config

create or replace function public.gv_ppp_web_compatible_con_tanda(p_barrio text, p_zona text, p_barrios text[], p_zonas text[])
returns boolean language sql stable;   -- bool_and(pueden_compartir) contra todas las paradas de la tanda

-- 6) Agrupador puro (dry-run). Lo usan el job Y el tablero: misma regla, un solo lugar.
create or replace function public.gv_ppp_web_agrupar(p_filas jsonb, p_tope numeric default null)
returns table (id text, cliente text, barrio text, zona text, m3 numeric,
               camion int, tanda_idx int, km_max_tanda numeric, motivo text)
language plpgsql stable;
-- p_filas: [{id, cliente, barrio, zona, m3, solo, prioritario}] — el id es libre (order_id|np_idx, o np de ISIS)
-- salida: número de camión y tanda dentro del camión; el llamador arma el código LETRA+NN+LETRA si quiere.

-- vista de control
create view public.gv_barrios_sin_geo with (security_invoker = true) as
select z.barrio_norm, z.zona from public."Zonas_Barrios" z
 where z.zona ~ '^Zona' and not exists (select 1 from public.gv_barrio_geo(z.barrio_norm) g where g.lat is not null);
```

**Cómo cambia el bucle de `ppp_web_armar_tandas` (sql/ppp_web_tandas.sql:346-376):** la selección diaria (322-341: prioritarios, antigüedad, cupo 5 m³) no se toca. Se reemplaza el `for v_grupo …` por una llamada a `gv_ppp_web_agrupar(jsonb_agg(_sin_tanda))`, y con su salida se asignan los códigos:

```sql
-- reemplaza 346-376
create temp table _agr on commit drop as
select * from public.gv_ppp_web_agrupar(
  (select jsonb_agg(jsonb_build_object('id', order_id||'|'||np_idx, 'cliente', cliente,
          'barrio', barrio, 'zona', zona, 'm3', m3, 'solo', va_solo, 'prioritario', prioritario))
     from _sin_tanda), v_tope);
insert into _asig (order_id, np_idx, tanda)
select split_part(id,'|',1)::bigint, split_part(id,'|',2)::int,
       case when v_pref <> '' then v_pref else public.ppp_web_letra(v_letra) end
       || lpad(camion::text, 2, '0') || public.ppp_web_letra(tanda_idx)
  from _agr;
-- r_zona del return query pasa a ser string_agg(distinct zona) de la tanda (hoy min(grupo))
```

**Dentro de `gv_ppp_web_agrupar`** (esto es lo que cambia de verdad respecto del bin-packing actual):
1. Clientes ordenados `prioritario desc, sum(m3) desc, cliente` (first-fit decreasing, como hoy) — Super/Retira/Expo/`solo` se tratan igual que ahora (Super uno por cliente, solo abre propia, Retira junta entre sí sin distancia).
2. Para cada cliente se recorren **todas** las tandas abiertas (no sólo la última): entra en la que cumpla `acum + m3 ≤ tope` **y** `gv_ppp_web_compatible_con_tanda(barrio, zona, barrios_tanda, zonas_tanda)`; si hay varias, la de menor `km_max` resultante (best-fit por cercanía). Si ninguna, abre tanda nueva. Un cliente con NP en barrios distintos aporta todos sus barrios a la tanda.
3. Al terminar, las tandas se agrupan en camiones: orden por lat desc (barrido norte→sur) y enlace completo con `camion_km_max`; `camion` = 1..N, `tanda_idx` = 0..k dentro del camión. Tandas de Retira/Super/Expo van cada una a su camión como hoy (`v_zn` por grupo).
4. `motivo` por fila: 'ok' | 'sin_geo' | 'solo' | 'super' — para el log y el tablero.

`gv_ppp_web_grupo_zona` queda sólo para la etiqueta del resumen/log (o se deprecia); `zonas_automaticas` sigue filtrando qué zonas entran al job. Grants: `execute` a `anon, authenticated, service_role` como las actuales. Documentar en `docs/SUPABASE-GESTION-VIRGILIO.md` el mismo día con la consulta de impacto (`select count(*) from gv_barrios_sin_geo`; diff de tandas entre armado viejo y nuevo sobre `PPP_Programacion_Diaria` como dry-run) y rollback (drop de los objetos `gv_*`/`GV_*` + restaurar el cuerpo actual de `ppp_web_armar_tandas`, md5 3b7ae2a5…, guardado en el repo).

**Tablero.** Hoy `_pppCamiones` (index.html:29355-29370) hace **un camión = una zona** con `_pppZonaPed`. Con la regla nueva el tablero deja de calcular agrupación en el front y consume la misma RPC:

1. Al cargar el día (`_pppPlanDiaHtml`), el front arma `p_filas` con TODOS los pedidos del día (ISIS de `gv_ppp_programacion_diaria` + web de `PPP_Web_Programacion`), con `id = np`, `barrio = localidad||barrio`, `zona`, `m3`, `cliente = cod`, y llama `supabase.rpc('gv_ppp_web_agrupar', {p_filas})`. Cada fila vuelve con `camion`, `tanda_idx`, `km_max_tanda`, `motivo`. Una llamada por día (≈200 filas, < 100 ms).
2. **Para lo que YA tiene tanda asignada** (ISIS o job) el tablero no reagrupa: respeta la tanda cargada y sólo agrupa las tandas en camiones con el mismo enlace completo (`camion_km_max`), así el número que se ve coincide con el código de la tanda si vino del job. Para pedidos sin tanda (los que se programan a mano) muestra la sugerencia de la RPC en gris, igual que hoy hace `pppSugerirTandas` — que se reemplaza por esta llamada (hoy usa T_MAX 1,00 y sin grupos: es la segunda regla que hay que eliminar).
3. **Cómo se muestra "camión":** tarjeta por `camion` con título = barrios distintos ordenados por ruta (`Pompeya · Soldati · Boedo`), subtítulo = zonas involucradas (`Z1+Z2`), m³ total, `km_max` del camión y las tandas adentro como chips (`E01A 0,78 m³ · 3,4 km`). El orden de carga LIFO sigue saliendo de `_pppOrdenCarga` con `_rtOptimize` sobre `PPP_Geo`, pero el punto de cada parada pasa a `PPP_Geo` (dirección exacta) con fallback al centroide de `gv_barrio_geo` (hoy sin punto la parada se pierde), y el depósito con fallback a (-34.636,-58.505) en vez del Obelisco.
4. Badges: pedido con `motivo='sin_geo'` → 📍 gris "barrio sin ubicación" con link a la pantalla Barrios; contador "N barrios sin ubicación" desde `gv_barrios_sin_geo`. Al arrastrar a mano un pedido a otra tanda el front llama `gv_ppp_web_pueden_compartir` contra las paradas destino y avisa en rojo "Núñez–Villa Lugano 14,8 km > 10" pero **no bloquea** (la persona manda; se guarda igual con `pppGuardarWeb`).
5. Producción no ve nada de esto (su tablero no existe; su ruteo sigue leyendo `PPP_Geo` sin cambios).

**Mantenimiento.** **Carga inicial (una vez, ~2–3 h del dueño + 1 h de SQL, INSERT-only con backup previo):**
1. Sembrar `GV_Barrios_Geo` con los 48 centroides medidos de `PPP_Geo` (`fuente='ppp_geo'`, n_puntos), ~50 `manual_aprox` de la tabla propuesta en los hallazgos y 13 alias (`p.patricios`, `v.devoto`, `micro centro`, `f.varela`, `v.alsina`, `laferrere`, `jose c. paz`, `v.bosch`, `mataderos (8:30 a 14)`, `lanus este/oeste`, `p. patricios`, `villa devoto`) apuntando a su canónico con las mismas coordenadas. `ambito` se deriva de `Zonas_Barrios.zona` (1-3 CABA, 4-7 GBA, resto OTRO). Antes de sembrar, geocodificar los ~50 `manual_aprox` desde el navegador (`_zgGeocode("<barrio>, Buenos Aires, Argentina")`, 1 req/s, ~1 min) y que el dueño los mire en el mapa: 30 de los 48 "medidos" son 1 sola dirección de un cliente, no el barrio, y los que importan para la frontera (Belgrano 1 punto, Núñez/Colegiales/Villa Crespo sin punto, Lugano 2-3 puntos) hay que verificarlos a mano.
2. Cargar en `GV_Barrios_Pares` las prohibiciones explícitas del dueño (Núñez/Belgrano/Colegiales × Lugano/Soldati/Pompeya) aunque la distancia ya las bloquee: son la red de seguridad contra un centroide corrido.
3. Dry-run: correr `gv_ppp_web_agrupar` sobre las 182 filas vivas de `PPP_Programacion_Diaria` y sobre las 27 tandas mixtas históricas, comparar con lo que hizo el dueño y ajustar X/radios con él antes de cambiar `ppp_web_armar_tandas`.

**Operación:**
- Barrio nuevo: Producción lo agrega a `Zonas_Barrios` con su trigger; nosotros no podemos reaccionar con trigger. Aparece en `gv_barrios_sin_geo` → badge en el tablero → el dueño abre "📍 Barrios", el front lo geocodifica y lo inserta en `GV_Barrios_Geo` (`fuente='manual'`). Mientras tanto la regla `sin_geo_modo='zona'` lo agrupa sólo con su zona: nada se rompe.
- Direcciones nuevas geocodificadas por el ruteo caen en `PPP_Geo` y la vista `gv_barrio_geo_vivo` las promedia sola (mediana, ≥3 puntos) — sin cron. Opcional: `gv_barrios_geo_recalcular()` mensual (cron `gv_barrios_geo_mensual`) que materializa el vivo en la tabla sin pisar `manual`.
- Cambiar X, radio por barrio, prohibir/permitir un par, prender/apagar cruce CABA-GBA: desde la pantalla, sin deploy. Cada cambio queda con `actualizado` para auditar.
- Documentación: `docs/SUPABASE-GESTION-VIRGILIO.md` (objetos, impacto medido, rollback) y `GUIA-PROYECTO.md` (regla, parámetros, vista de control) el mismo día; `sql/gv_barrios_geo.sql` nuevo y edición de `sql/ppp_web_tandas.sql`.

**Riesgos.** 1. **Margen fino en la frontera norte-sur:** Belgrano–Soldati 11,4 y V.Urquiza–Lugano 11,1 quedan sólo 1,1–1,4 km por encima de X=10, y los centroides tienen ±1 km de error (Belgrano y Lugano con 1–2 puntos; Núñez, Colegiales y Villa Crespo son coordenadas de conocimiento general). Un centroide corrido puede invertir la decisión. Mitigación: verificar esos 8-10 barrios en el mapa antes de prender, cargar los pares prohibidos, y ajustar `radio_km` a los barrios largos (Palermo, Soldati, Lugano).
2. **Centroide ≠ dirección:** un cliente en el borde de Palermo (Pacífico) está a 12 km de otro en el borde sur de Soldati aunque los centroides digan 11. Refinamiento posible después: usar el punto exacto de `PPP_Geo` cuando la dirección está geocodificada y el centroide sólo como fallback (misma función, un `coalesce` más). Distancias en línea recta, no de ruta: el Riachuelo y la Gral. Paz no cuentan.
3. **Historial chico:** 27 tandas mixtas de Capital y 117 con ≥2 barrios; X=10 reproduce el 89 % pero los casos borde (Palermo–P.Patricios 9,3, Villa Crespo–Lugano 9,4, Recoleta–Soldati 8,5) son 1 tanda cada uno. El dueño tiene que validar la lista de "sí/no" de ejemplos antes de implementar; es una lectura de sus datos, no una regla que él haya dicho. Además 49 % de las NP históricas son del interior sin hub conocido (no aportan pares).
4. **GBA con 20 km es laxo:** Quilmes+Lomas o Martínez+Morón pasan; si el dueño quiere corredores (Sur vs Oeste vs Norte) la distancia sola no lo modela y habría que sumar un par prohibido por zona (p.ej. Z4 nunca con Z5: 32 km, ya cae por distancia) o volver a un umbral menor.
5. **Cambia el significado del número de camión:** deja de ser "grupo de zona" y pasa a ser un cluster geográfico del día; los códigos LETRA+NN+LETRA no colisionan con Producción (la letra global sigue avanzando con `ppp_web_proxima_letra`), pero el monitor que agrupa por código verá camiones con barrios de distintas zonas. Cosmético, avisar.
6. **Dos armadores en el front hoy** (`pppSugerirTandas` con T_MAX 1,00 sin grupos; `_pppCamiones` por zona): si no se reemplazan por la RPC, la regla queda en tres lugares distintos. Trabajo de front: ~1 día (llamada RPC, tarjetas por camión, badges, pantalla Barrios sobre el mapa v9.75).
7. **Base compartida:** `PPP_Geo` y `Zonas_Barrios` sólo se leen; cero triggers, cero columnas nuevas ahí. El clon de Producción para grepear está en `/home/user/produccion-virgilio` (no donde dice el CLAUDE.md); confirmado 0 refs a los objetos que se tocan, pero `PPP_Geo` sí la usa (10 refs) — jamás insertar barrios "pelados" ahí.
8. **Rendimiento:** `gv_ppp_web_agrupar` es O(clientes × tandas abiertas × paradas), con ≤ 60 clientes/día es trivial; el tablero hace 1 RPC por día abierto. Sin extensiones nuevas (haversine en SQL puro; postgis no hace falta).
9. **Protocolo:** es lógica de negocio → backend, pero por CLAUDE.md hay que preguntarle al dueño explícitamente backend vs front y pedir permiso antes de cualquier DDL; backup (`GV_*` son tablas nuevas, el backup relevante es el cuerpo actual de `ppp_web_armar_tandas`); anotar en `docs/SUPABASE-GESTION-VIRGILIO.md` con impacto medido y rollback; `zonas_automaticas` a '1,2,3' es decisión aparte del dueño (hoy la Z3 se programa a mano); la idea 7317 ("Z1 y Z2 apenas llegan a 0,80") es otro cambio (disparo/cupo) y no se resuelve con esto.
10. En este análisis no se modificó nada: sólo SELECT y lectura de archivos; las distancias se calcularon en el scratchpad (`dist.py`) sobre los centroides propuestos.

### Regla de cercanía para tandas: zonas compatibles + lista blanca/negra de barrios + distancia entre puntos (historial como semilla)

**Regla.** **Pregunta que responde el backend:** ¿el pedido A (zona, barrio, dirección) y el pedido B pueden compartir TANDA? Se evalúa en 4 capas, en este orden, y la primera que decide gana. Una tanda admite a un cliente sólo si es compatible con TODOS los que ya están en ella (par a par, sin transitividad) y cabe en los 0,80 m³.

**Capa 0 — mismo barrio canónico** (`gv_barrio_canon(a) = gv_barrio_canon(b)`): SÍ. Colapsa alias (p.patricios = parque patricios, lugano = villa lugano, mataderos (8:30 a 14) = mataderos).

**Capa 1 — par de barrios cargado** (`GV_Barrios_Pares`): si existe la fila (a,b) devuelve su `permitido` tal cual, sea SÍ o NO. Es la palabra del dueño: manda sobre zonas y sobre distancia. Se siembra con el historial (pares que ya juntó en la misma tanda, ene–sep 2026) y con los bloqueos que dijo hoy (Núñez/Belgrano/Colegiales × Lugano/Soldati/Pompeya/V.Riachuelo).

**Capa 2 — par de zonas** (`GV_Zonas_Pares`, reemplaza a la regla fija 2+3 / 6+7): si el par (zona_a, zona_b) no está o está `activo=false` → NO ("zonas no compatibles"). Semilla: 1-1, 2-2, 3-3, 1-2, 1-3, 2-3 (Capital entera, radio 8 km); 4-4, 5-5, 6-6, 7-7, 6-7 (GBA, radio 20 km); Retira-Retira, Super-Super, Expo-Expo. Cargados pero APAGADOS para que el dueño decida: 1-4 (Soldati/Pompeya con Lanús/Avellaneda: 5 tandas en el historial), 5-6 (9 tandas), 2-6 (6 tandas).

**Capa 3 — distancia real** (fallback para todo par de barrios sin fila en Capa 1): `km = haversine(punto_a, punto_b)`; SÍ si `km ≤ km_max` del par de zonas (8 km en Capital, 20 en GBA). El punto de cada pedido sale de `gv_barrio_punto(direccion, barrio)`: (1) la dirección exacta si está en `PPP_Geo` (mismo `dir_key` que usa el ruteo), (2) coordenada `manual` de `GV_Barrios_Geo`, (3) centroide vivo de `PPP_Geo` si el barrio tiene ≥3 direcciones geocodificadas (mediana, no promedio), (4) `ppp_geo`/`manual_aprox` de `GV_Barrios_Geo`, (5) nada.

**Capa 4 — sin coordenada (barrio nuevo)**: si a alguno de los dos le falta punto: SÍ sólo si son de la MISMA zona (exactamente lo que hace hoy el armado dentro de una zona), NO si son de zonas distintas ("sin ubicación: decidir a mano"). El barrio aparece en la vista `gv_barrios_sin_geo` para que el dueño lo ubique. Nada se rompe: lo peor que pasa es que el pedido se programa como hasta ayer.

**Kill switch:** `PPP_Web_Config.tanda_regla_cercania = 0` → la función devuelve SÍ para todo par con el mismo `gv_ppp_web_grupo_zona` (comportamiento actual, idéntico byte a byte). Rollback en un `update`.

**Por qué 8 km en Capital y no 12:** las 27 tandas históricas que mezclan Z1/Z2/Z3 tienen dmax 1,7–12,3 km, mediana 6,5; con 8 km entran 24 de 27 por distancia y las 3 restantes (Constitución+V.Pueyrredón 11,3; Pompeya+Ciudadela 11,5; Mataderos+Núñez 12,3, todas 1 sola vez) quedan para que el dueño las cargue a mano si las quiere. A 8 km se bloquean solos Belgrano–Soldati (11,4), V.Urquiza–Lugano (11,1), Constitución–Devoto (12,2) y Palermo–P.Patricios (9,3, pasó 1 vez). Las 2 zonas en GBA necesitan 20 km porque Quilmes–Avellaneda ya son 12,8 y son del mismo corredor.

**Camión vs tanda:** el CAMIÓN (número NN del código) = componente conexa de `GV_Zonas_Pares` (hoy: "Capital 1+2+3", "GBA Sur 4", "GBA Oeste 5", "GBA Norte 6+7", Retira, Super). La TANDA (letra final) = clique de clientes compatibles par a par dentro de ese camión, ≤ 0,80 m³. Así Núñez y Lugano pueden ir en el mismo camión (Capital) pero nunca en la misma tanda, que es lo que pidió el dueño ("no debe ir junto" = misma parada/tanda, no mismo día).

**Parámetros.** Todo editable desde una pantalla nueva "⚙ Reglas de tandas" (supervisor), sin programar:

1. `GV_Zonas_Pares (zona_a, zona_b, activo, km_max, motivo)` — qué zonas pueden compartir tanda y con qué radio de distancia. Toggle por par + número. Semilla arriba. Cambiar 1-4 a `activo=true` habilita Soldati+Lanús sin tocar código.
2. `GV_Barrios_Pares (barrio_a, barrio_b, permitido, fuente 'historial'|'dueño', n_hist, km, motivo)` — lista blanca/negra por barrio. Gana sobre todo. La pantalla muestra km y cuántas veces lo juntó en el historial; avisa en rojo si se carga un SÍ con km > 2×radio.
3. `GV_Barrios_Geo (barrio_norm pk, barrio_canon, lat, lng, fuente 'ppp_geo'|'manual'|'manual_aprox'|'alias', n_puntos)` — coordenada por barrio + alias. Botón "📍 Ubicar" en la pantalla geocodifica "<barrio>, Buenos Aires, Argentina" con `_zgGeocode` (ya respeta 1 req/s) y guarda acá, NUNCA en `PPP_Geo`. El dueño puede arrastrar el pin (fuente pasa a `manual` y gana siempre).
4. `PPP_Web_Config`: `tanda_regla_cercania` (1/0, kill switch), `tanda_m3_max_mezcla` (0,80, ya existe), `zonas_automaticas` ('1,2' → hay que pasarla a '1,2,3' para que la Z3 entre al job de las 00:01; hoy Z3 se programa a mano y la regla sólo se aplica al sugeridor/tablero), `m3_max_dia` (5, no cambia).
5. Vista `gv_barrios_sin_geo` (security_invoker): barrios de `Zonas_Barrios` sin punto, con cantidad de pedidos vivos que los usan → contador "N barrios sin ubicación" en el tablero.

Qué NO es parámetro: la fórmula de distancia (haversine línea recta), el orden de las capas y la exigencia "compatible con todos los de la tanda". Eso es código.

**Ejemplos.** Distancias sobre centroides (PPP_Geo o manual_aprox), km_max Capital 8 / GBA 20, semilla propuesta:

1. **Núñez + Lugano → NO.** Capa 1: par cargado `permitido=false` (bloqueo del dueño, fuente 'dueño'). Si no estuviera cargado: Capa 2 Z2-Z1 activo, Capa 3 14,8 km > 8 → NO igual. Historial: 0 veces en 8 meses. Doble red.
2. **Pompeya + Barracas → SÍ.** Capa 1: par 'historial' (Z1-Z1 tiene 11 pares observados; Barracas+Soldati D53F viva) → SÍ. Sin el par: Z1-Z1 activo, 3,4 km ≤ 8. Tanda típica del sur.
3. **Boedo + Pompeya → SÍ.** Capa 1: sin par (nunca cayeron juntos en la misma tanda; Boedo aparece con Flores en C08B). Capa 2: Z2-Z1 activo. Capa 3: 2,5 km ≤ 8 → SÍ. Es el caso donde la distancia le gana a la partición por sectores (que los separaba en F/B); si al dueño no le gusta, lo carga como NO y listo.
4. **Flores + Mataderos → SÍ.** Capa 1: par 'historial' n=2 → SÍ. Además Z3-Z3, 5,1 km.
5. **Devoto + Villa Luro → SÍ, pero sólo después de la carga inicial.** Capa 2: Z2-Z3 activo. Capa 3: 3,8 km ≤ 8 → SÍ… siempre que Devoto tenga coordenada: hoy NO tiene ningún punto en `PPP_Geo` (0/118) → sin `GV_Barrios_Geo` cae en Capa 4 (zonas distintas, sin ubicación) → NO y aparece en `gv_barrios_sin_geo`. Es el ejemplo honesto de por qué la carga de ~50 barrios `manual_aprox` no es opcional. Historial: 0.
6. **Lanús + Soldati → NO por defecto.** Capa 1: sin par. Capa 2: Z1-Z4 cargado `activo=false` (regla vigente del dueño "el resto sola") → NO, aunque estén a 4,3 km y el historial tenga Z1+Z4 en 5 tandas. Muestra que la zona filtra ANTES que la distancia; con un toggle el dueño lo prende y pasa a SÍ (4,3 ≤ 8).
7. **Belgrano + Palermo → SÍ.** Z2-Z2 activo, 1,8 km. Historial: Z2-Z2 21 pares, Belgrano+Recoleta D56A viva. Ojo cadena: Palermo+P.Patricios (9,3 km) es NO salvo par cargado, así que aunque Belgrano+Palermo sea SÍ, {Belgrano, Palermo, P.Patricios} no forman tanda: el tercero tiene que ser compatible con los dos.
8. **Quilmes + Avellaneda → SÍ.** Z4-Z4 activo con km_max 20, 12,8 km ≤ 20. Historial: Lanús–Quilmes 2, Bernal–Quilmes 2, Z4-Z4 mediana 15 km. Con un radio único de 8 km sería NO y rompería el sur del GBA → por eso el radio es por par de zonas, no global.

**Backend.** Todo con prefijo GV_/gv_, RLS on (select anon+authenticated; insert/update/delete sólo los mails de supervisor, misma policy que `GV_Clientes_Reglas`), sin triggers en compartidas, vistas `security_invoker=true`. `PPP_Geo` y `Zonas_Barrios` sólo se LEEN.

```sql
-- 1) Tablas
create table public."GV_Zonas_Pares" (
  zona_a text not null, zona_b text not null,          -- clave corta: '1'..'7','Retira','Super','Expo'; zona_a <= zona_b
  activo boolean not null default true,
  km_max numeric(5,1) not null default 8.0,
  motivo text, actualizado timestamptz default now(), actualizado_por text,
  primary key (zona_a, zona_b), check (zona_a <= zona_b));

create table public."GV_Barrios_Geo" (
  barrio_norm text primary key,                         -- public._norm_barrio(barrio), misma clave que Zonas_Barrios
  barrio_canon text not null,                           -- alias -> canónico ('p.patricios' -> 'parque patricios')
  lat numeric(9,6), lng numeric(9,6),
  fuente text not null check (fuente in ('ppp_geo','manual','manual_aprox','alias')),
  n_puntos int default 0, actualizado timestamptz default now(), actualizado_por text);

create table public."GV_Barrios_Pares" (
  barrio_a text not null, barrio_b text not null,       -- canónicos, barrio_a < barrio_b
  permitido boolean not null,
  fuente text not null default 'dueño',                 -- 'historial' | 'dueño'
  n_hist int default 0, km numeric(5,1), motivo text,
  actualizado timestamptz default now(), actualizado_por text,
  primary key (barrio_a, barrio_b), check (barrio_a < barrio_b));

insert into public."PPP_Web_Config"(clave, valor, descripcion)
values ('tanda_regla_cercania', 1, '1 = regla por pares/distancia; 0 = agrupar sólo por gv_ppp_web_grupo_zona (comportamiento anterior)')
on conflict (clave) do nothing;

-- 2) Funciones (todas stable/immutable, grant execute a anon, authenticated, service_role)
create or replace function public.gv_ppp_web_zona_key(p_zona text) returns text immutable ...;
  -- 'Zona 3 - CABA Oeste' -> '3'; 'Retira'/'Super'/'Expo' -> tal cual; '' -> null

create or replace function public.gv_barrio_canon(p_barrio text) returns text stable ...;
  -- coalesce((select barrio_canon from "GV_Barrios_Geo" where barrio_norm = _norm_barrio(p_barrio)), _norm_barrio(p_barrio))

create or replace function public.gv_km(lat1 numeric, lng1 numeric, lat2 numeric, lng2 numeric)
returns numeric immutable ...;   -- haversine 2*6371*asin(sqrt(...)), sin postgis

create or replace function public.gv_barrio_punto(p_direccion text, p_barrio text)
returns table (lat numeric, lng numeric, fuente text) stable ...;
  -- 1 PPP_Geo por dir_key = lower(regexp_replace(btrim(dir),'\s+',' ','g'))||'|'||lower(...barrio)  (emula _rtNorm del JS)
  -- 2 GV_Barrios_Geo fuente='manual'
  -- 3 centroide vivo: percentile_cont(0.5) de PPP_Geo where _norm_barrio(barrio)=canon and >=3 puntos y dentro del bbox AMBA
  -- 4 GV_Barrios_Geo ppp_geo / manual_aprox     5 null

create or replace function public.gv_ppp_web_pueden_compartir(
  p_zona_a text, p_barrio_a text, p_dir_a text,
  p_zona_b text, p_barrio_b text, p_dir_b text)
returns table (ok boolean, motivo text, km numeric) stable language plpgsql ...;
  -- kill switch -> ok := gv_ppp_web_grupo_zona(a) = gv_ppp_web_grupo_zona(b), motivo 'grupo'
  -- capa 0 mismo canon | capa 1 GV_Barrios_Pares (least/greatest) | capa 2 GV_Zonas_Pares (least/greatest de zona_key)
  -- capa 3 gv_km(gv_barrio_punto(a), gv_barrio_punto(b)) <= km_max | capa 4 sin punto: ok := zona_a = zona_b

create or replace function public.gv_ppp_web_grupo_zona(p_zona text) returns text stable ...;
  -- (es nuestra, 0 refs en Producción) pasa de regex fija a componente conexa de GV_Zonas_Pares activos
  -- via CTE recursiva; etiqueta = 'Zonas 1+2+3', 'Zonas 6+7', 'Zona 4 - GBA Sur', 'Retira'... Mismo contrato que hoy.

create or replace function public.gv_ppp_web_validar_tanda(p_items jsonb)   -- [{zona,barrio,direccion,np}]
returns table (i int, j int, ok boolean, motivo text, km numeric) stable ...;   -- todos los pares; para el tablero

create or replace function public.gv_ppp_web_sugerir_tandas(p_empresa text, p_fecha date, p_filas jsonb, p_forzar_cods text[] default '{}')
returns table (order_id bigint, np_idx int, tanda text, camion int, motivo text) ...;   -- dry-run: mismo núcleo, sin insertar

create view public.gv_barrios_sin_geo with (security_invoker = true) as
  select z.barrio_norm, z.zona, count(p.np) as pedidos_vivos
    from public."Zonas_Barrios" z
    left join public."GV_Barrios_Geo" g on g.barrio_norm = z.barrio_norm and g.lat is not null
    left join public."PPP_Programacion_Diaria" p on public._norm_barrio(p.barrio) = z.barrio_norm
   where g.barrio_norm is null and z.zona like 'Zona%'
   group by 1,2;
```

**Integración en `ppp_web_armar_tandas` (sql/ppp_web_tandas.sql:348-376).** Se extrae el bucle a `gv_ppp_web_armar_core(p_empresa, p_fecha, p_simular boolean)` que usan tanto `ppp_web_armar_tandas` (inserta) como `gv_ppp_web_sugerir_tandas` (no inserta). Lo que cambia dentro del bucle: la "tanda abierta" única (`v_code`) pasa a una lista de tandas abiertas por camión, y el cliente entra a la PRIMERA donde cabe y es compatible con todas sus NP; si ninguna, abre otra.

```sql
create temp table _tandas (camion int, ti int, code text, m3 numeric, cerrada boolean default false) on commit drop;
create temp table _tanda_np (code text, zona text, barrio text, direccion text) on commit drop;

for v_grupo in select distinct grupo from _sin_tanda order by 1 loop           -- camión = componente de GV_Zonas_Pares
  v_zn := v_zn + 1; v_ti := 0;
  for r_cli in select cliente, sum(m3) m3_cli, bool_or(va_solo) solo
                 from _sin_tanda where grupo = v_grupo group by cliente order by sum(m3) desc, cliente loop
    v_code := null;
    if not (v_grupo = 'Super' or r_cli.solo or r_cli.m3_cli >= v_tope) then
      select t.code into v_code from _tandas t
       where t.camion = v_zn and not t.cerrada and t.m3 + r_cli.m3_cli <= v_tope
         and not exists (                                                       -- compatible con TODAS las NP de la tanda
           select 1 from _tanda_np c, _sin_tanda s
            where c.code = t.code and s.cliente = r_cli.cliente and s.grupo = v_grupo
              and not (select ok from public.gv_ppp_web_pueden_compartir(c.zona, c.barrio, c.direccion, s.zona, s.barrio, s.direccion)))
       order by t.ti limit 1;
    end if;
    if v_code is null then                                                      -- abre tanda: misma codificación de hoy
      v_code := case when v_pref <> '' then v_pref else public.ppp_web_letra(v_letra) end
                || lpad(v_zn::text,2,'0') || public.ppp_web_letra(v_ti);
      insert into _tandas values (v_zn, v_ti, v_code, 0, false); v_ti := v_ti + 1;
    end if;
    insert into _asig select s.order_id, s.np_idx, v_code from _sin_tanda s where s.grupo = v_grupo and s.cliente = r_cli.cliente;
    insert into _tanda_np select v_code, s.zona, s.barrio, s.direccion from _sin_tanda s where s.grupo = v_grupo and s.cliente = r_cli.cliente;
    update _tandas set m3 = m3 + r_cli.m3_cli, cerrada = (v_grupo = 'Super' or r_cli.solo or r_cli.m3_cli >= v_tope) where code = v_code;
  end loop;
end loop;
```
Con `tanda_regla_cercania = 0` `pueden_compartir` devuelve siempre ok dentro del mismo grupo y el resultado es el de hoy (única diferencia: first-fit sobre varias tandas abiertas en vez de una; si se quiere byte a byte, el kill switch también fuerza `order by t.ti desc limit 1`). La selección diaria (322-341), el cupo de 5 m³, la letra global y el upsert en `PPP_Web_Programacion` no se tocan. La Edge Function `gv-ppp-web-tandas-diarias` no cambia (sigue llamando a `ppp_web_armar_tandas` con las mismas 13 columnas; `direccion` y `barrio` ya viajan). El motivo de cada tanda se agrega al `GV_Tandas_Auto_Log` (r_zona ya existe; sumar `r_motivo`).

Coste de la consulta: por cada cliente candidato se evalúa `pueden_compartir` contra las NP de las tandas abiertas del camión; con 10-15 clientes/día y ≤7 tandas son < 200 llamadas, cada una 3-4 lookups indexados. Irrelevante.

**Tablero.** Hoy `_pppCamiones` (index.html:29355-29370) arma un camión por ZONA suelta (`_pppZonaPed`) y la tanda es sólo una etiqueta acumulada. Con la regla nueva el tablero tiene que mostrar lo mismo que decide el backend, sin recalcularlo a mano:

1. **Camión = grupo del backend.** Al abrir la PPP el front llama una vez a `gv_ppp_web_grupos()` (RPC nueva, devuelve `(zona, grupo, orden_ruta)` para las 10 zonas) y `_pppCamiones` agrupa por `grupo` en vez de por zona. Cabecera: "Camión 01 · Capital (Z1+Z2+Z3) · 3 tandas · 2,1 m³". Adentro, chips por tanda (E01A, E01B…) con sus barrios. Cuando el dueño apaga Z1-2 en `GV_Zonas_Pares`, el tablero vuelve solo a mostrar dos camiones. Las rutas `RT_RUTAS` (so/n/sup/ret) siguen sirviendo para ordenar los camiones.

2. **Semáforo de tanda.** Para cada tanda dibujada (automática o armada a mano en la PPP Web) se llama a `gv_ppp_web_validar_tanda(items)` (una llamada por tanda, en batch al render; ≤ 20 tandas por día). Si algún par devuelve `ok=false`, la tanda se pinta con borde rojo y tooltip "Núñez ↔ Lugano: 14,8 km (máx 8) — no compatible" o "Zona 1 ↔ Zona 4 apagado en Reglas". No bloquea: el dueño puede dejarla (es su decisión), pero queda a la vista. El mismo texto `motivo` viene del backend, así que front y job dicen lo mismo.

3. **Sugeridor.** `pppSugerirTandas` (27307-27361) deja de agrupar por zona con T_MAX 1,00 y llama a `gv_ppp_web_sugerir_tandas(empresa, fecha, filas)` (dry-run del mismo núcleo). Con eso desaparece la segunda regla de agrupación que hoy vive en el front. `pppGuardarWeb` (25879) antes de persistir corre `validar_tanda` y muestra el aviso; guarda igual si el usuario confirma.

4. **UX offline (opcional, no fuente de verdad).** El front puede cachear `GV_Zonas_Pares`, `GV_Barrios_Pares` y `GV_Barrios_Geo` (<300 filas) y evaluar la misma cascada con `_rtHav` para pintar en caliente mientras la persona arrastra un pedido de una tanda a otra, y pedir la confirmación al RPC al soltar. Mismo patrón que la conversión MC↔Uni: el front duplica, el backend manda.

5. **Orden de carga y mapa.** `_pppOrdenCarga` sigue usando `_rtOptimize` sobre `PPP_Geo`; ahora además puede caer a `GV_Barrios_Geo` cuando la dirección exacta no está geocodificada (hoy sólo 24/83 direcciones tienen punto, así que la mayoría de las paradas quedan sin ordenar). Y hay que arreglar de paso el fallback del depósito (-34.6037,-58.4 = Obelisco) por Virgilio 2788 (-34.636,-58.505).

6. **Pantalla "⚙ Reglas de tandas"** (nueva, supervisor): tres pestañas — Zonas (grilla 10×10 con toggle y km por par), Pares de barrios (buscador + dos selects desde `Zonas_Barrios`, muestra km, n_hist y quién lo cargó; botón SÍ/NO), Barrios sin ubicación (lista de `gv_barrios_sin_geo`, botón "📍 Ubicar" que geocodifica y guarda en `GV_Barrios_Geo`, mapa Leaflet ya existente v9.75 para arrastrar el pin).

**Mantenimiento.** **Carga inicial (es la parte pesada, hay que decirla completa):**

1. `GV_Barrios_Geo`: (a) 48 barrios con centroide de `PPP_Geo` por `insert … select _norm_barrio(barrio), percentile_cont(0.5)…` — 30 de esos 48 salen de UNA sola dirección, o sea que son la casa de un cliente, no el barrio; (b) ~50 barrios sin ningún punto (Núñez, Caballito, Colegiales, Devoto, Villa Crespo, Villa Ortúzar, Microcentro, Monserrat, P.Chacabuco, Liniers, Villa del Parque, Lomas, Banfield, Morón, Castelar, Hurlingham, Munro, San Isidro, Olivos, Pilar, etc.) con coordenadas `manual_aprox` de la tabla del informe de geodatos, que NO están verificadas contra ningún geocoder (el sandbox no sale a internet); (c) 13 alias. Trabajo: ~2 h de una persona mirando los ~50 pines en el mapa de zonas antes de darles `manual`. Sin (b) los ejemplos 5 y 1 no funcionan (Devoto y Núñez no tienen punto).
2. `GV_Zonas_Pares`: 14 filas activas + 3 apagadas. 10 minutos. Antes de prender la Z3 en el job, `zonas_automaticas` → '1,2,3'.
3. `GV_Barrios_Pares` con `fuente='historial'`: re-correr `analisis.py` (scratchpad de esta sesión, sobre `np_tanda.csv` + `prog_cod.csv` + `geo_centroids.csv`) y cargar los pares barrio-barrio vistos en la misma tanda con km ≤ radio del par de zonas (≈60-90 pares, casi todos Capital y GBA Sur). Los que superan el radio (Constitución+V.Pueyrredón, Constitución+V.Urquiza, Pompeya+Ciudadela, Mataderos+Núñez, Palermo+P.Patricios, todos 1 vez) NO se cargan: se le muestran al dueño en una lista para que diga sí o no. Los bloqueos explícitos del dueño (3 barrios norte × 4 barrios sur = 12 filas `permitido=false`, fuente 'dueño') se cargan de entrada. Ojo: el historial mapea barrio por MODA del código de cliente (un cliente con 2 sucursales se asigna a la más frecuente) y 206 NP usan domicilio fiscal de ISIS; los pares de historial son evidencia, no verdad. Se cargan con `n_hist` y `km` para que el dueño vea de dónde salen.
4. Backup previo de nada: son tablas nuevas. Pero el `create or replace` de `gv_ppp_web_grupo_zona` y de `ppp_web_armar_tandas` se guarda antes con `pg_get_functiondef` en `docs/` (rollback = volver a ejecutar). Todo anotado el mismo día en `docs/SUPABASE-GESTION-VIRGILIO.md` con la prueba: correr `gv_ppp_web_sugerir_tandas` sobre las filas de hoy con el switch en 0 y en 1 y pegar las dos salidas.

**Día a día:**
- Barrio nuevo que aprende Producción en `Zonas_Barrios` (su trigger): sin coordenada cae en Capa 4 (se programa sólo con su misma zona, igual que hoy) y aparece en `gv_barrios_sin_geo` → contador en el tablero → botón Ubicar. Cero riesgo, un clic.
- Dirección nueva geocodificada por cualquiera de las dos apps en `PPP_Geo`: la Capa 3 la usa al instante (dir_key exacto o centroide vivo si ya son ≥3), sin cron. No hace falta refresco.
- Pares: el dueño agrega/quita desde la pantalla. Cada fila guarda `actualizado_por` y `motivo`. Un par cargado como SÍ con km > 2×radio se marca en amarillo en la pantalla, para que no quede un error tipeado escondido.
- Re-sembrado del historial: script `sql/gv_barrios_pares_seed.sql` idempotente (`on conflict do nothing`: nunca pisa lo que cargó el dueño).
- Nada automático nuevo: sin cron, sin Edge Function, sin trigger. `PPP_Geo`/`Zonas_Barrios` siguen igual para Producción.

**Estimación:** SQL (3 tablas, 8 funciones, 1 vista, refactor del bucle) ~350 líneas, 1 día con pruebas dry-run sobre los datos vivos; tablero + sugeridor + pantalla de reglas ~500 líneas de front, 1-1,5 días; carga inicial + revisión de pines con el dueño, ~2-3 h. Antes de nada: preguntarle al dueño backend vs front (protocolo) y pedir permiso para crear objetos; la respuesta esperada es backend, y este diseño lo asume.

**Riesgos.** 1. **Centroide ≠ dirección.** Palermo, Villa Lugano, Flores o Quilmes miden 5-8 km de punta a punta; dos clientes "de Palermo" pueden estar a 6 km entre sí y uno de Palermo a 3 km de uno de Villa Crespo. La regla mira barrio salvo que la dirección exacta esté en `PPP_Geo` (hoy sólo 24 de 83 direcciones vivas). Mitigación: el tablero v13.03 y Carga Camión ya geocodifican direcciones al rutear; cuanto más se use, más precisa. Mientras tanto la lista blanca/negra por barrio tapa los casos que la distancia calcule mal.
2. **Coordenadas `manual_aprox` no verificadas.** Vienen de conocimiento general (±0,5-1 km). Un error de 1 km en un par que está en 7,5 km lo da vuelta. Por eso la pantalla obliga a mirar el pin y la fuente `manual` gana sobre todo.
3. **Historial flaco y sesgado.** Sólo 27 tandas mezclan zonas de Capital, 117 tienen ≥2 barrios conocidos, y el 49 % de las NP históricas son de clientes del interior sin hub conocido (~80 % Zona 1 según Programación). Los radios 8/20 km son una lectura de eso, no una regla que el dueño enunció. Hay que validarlos con él; el kill switch y `km_max` por par existen para eso.
4. **La lista blanca gana sin red.** Un par cargado como SÍ por error permite juntar cualquier cosa. Mitigación: aviso amarillo si km > 2×radio, `actualizado_por`, y que el motivo sea obligatorio.
5. **Cambia la numeración de camiones.** Capital pasa de 2-3 grupos (Z1 / Zonas 2+3) a 1 (Zonas 1+2+3) → menos números NN y más letras por camión. Si el dueño manda DOS camiones físicos a Capital, la regla no lo modela (la cantidad de camiones es capacidad, no compatibilidad): las tandas se reparten a mano entre camiones como hoy. Además `ppp_web_letra(v_ti)` con más de 26 tandas en un camión: imposible con cupo 5 m³/0,80, pero conviene un `check`.
6. **First-fit sobre varias tandas puede dejar huecos.** El greedy depende del orden (`sum(m3) desc`): un cliente compatible con dos tandas medio llenas entra en la primera y la segunda queda chica. No optimiza; reproduce lo que haría una persona rápida. Si molesta, ordenar los clientes por barrido geográfico (ángulo desde el depósito) dentro del camión: cambio de una línea, pero es otra decisión del dueño.
7. **Interacción con cupo y Z3.** La regla no toca el cupo de 5 m³/día ni `zonas_automaticas`='1,2'. Para que Z3 se mezcle en el job hay que pasar a '1,2,3', y eso mete más m³ en la cola diaria compartida por las dos empresas. "Zona 1 y 2 todos los días" (idea 7317, armar apenas llega a 0,80) es un cambio de disparo aparte; este diseño no lo resuelve ni lo bloquea.
8. **Cliente multi-sucursal.** `barrio` se evalúa por NP (cada fila lleva el suyo), pero el armado entra por CLIENTE entero: si un cliente tiene NP en Colegiales y en Soldati el mismo día, la exigencia "compatible con todos" no encuentra tanda y abre una nueva sólo para él (correcto pero raro). Hoy pasa lo mismo sin regla.
9. **Producción Virgilio.** Objetos nuevos GV_/gv_, `ppp_web_armar_tandas` y `gv_ppp_web_grupo_zona` tienen 0 referencias en su repo (HEAD e15b682); `PPP_Geo` y `Zonas_Barrios` sólo lectura; la emulación de `_rtNorm` en SQL para el `dir_key` es sólo para leer. Impacto medible: cero filas suyas tocadas. El único riesgo real es que alguien, por comodidad, meta un barrio pelado en `PPP_Geo` (una fila `|nuñez` la vería el ruteo de Producción como una dirección): la pantalla escribe únicamente en `GV_Barrios_Geo`.
10. **Rollback.** `tanda_regla_cercania = 0` devuelve el armado a la lógica de grupos; `gv_ppp_web_grupo_zona` pasa a leer `GV_Zonas_Pares` (semilla = regla actual 2+3/6+7 si se carga así) y la definición anterior queda guardada para restaurarla con un `create or replace`. Las tablas nuevas pueden quedar sin dropear sin afectar a nadie.
11. **Sólo lectura en esta sesión.** No se creó ni ejecutó nada: las distancias de los ejemplos se calcularon en Python sobre los centroides del informe de geodatos (scratchpad `dist.py`, `geo_centroids.csv`); la co-ocurrencia histórica sale de `out1.txt`/`out2.txt` de `analisis.py`.

## Hallazgos de la fase de entendimiento

### Historial de tandas

## Resumen ejecutivo

La decisión "estos dos pedidos comparten tanda" vive HOY en UN solo lugar del backend: la función `public.ppp_web_armar_tandas` (sql/ppp_web_tandas.sql:227-396; verificado que el cuerpo vivo en Supabase es el mismo, md5 3b7ae2a5…, 7.425 chars). Ahí la única noción de "cercanía" es la columna `grupo`, que sale de `gv_ppp_web_grupo_zona(zona)` (sql/gv_tandas_diarias.sql:166-182): un string por zona ("Zonas 2+3", "Zonas 6+7", o la zona tal cual). Dos clientes pueden ir juntos si y sólo si tienen el mismo `grupo` Y suman ≤ 0,80 m³. NO hay barrio, dirección ni coordenada en esa decisión: `barrio` y `direccion` llegan a la temporal `_sin_tanda` (líneas 271-272) pero sólo se copian a `PPP_Web_Programacion`; nunca se leen para agrupar.

El front NO llama a `ppp_web_armar_tandas` (0 referencias en index.html). Hay un segundo armador, sólo front y sólo para el modo manual: `pppSugerirTandas` (index.html:27307-27361) + `_pppBalancearZona` (~27255-27306), que agrupa por `pppZonaDeBarrio(p.localidad)` zona por zona (SIN 2+3 ni 6+7, T_MAX=1,00, SOFT=1,10) y escribe en edits locales; después `pppGuardarWeb` (25879-25930) persiste tanda/zona/barrio/dirección tal cual las eligió la persona en `PPP_Web_Programacion`. O sea: hoy conviven DOS reglas de agrupación distintas (backend 0,80 con grupos; front 1,00 sin grupos), y la de cercanía tendría que aplicarse en las dos o —mejor— exponer la del backend como RPC y que el sugeridor del front la consuma.

## (a) Datos de ubicación por fila

**Backend, al armar (Edge Function → `ppp_web_armar_tandas`)** — supabase/functions/gv-ppp-web-tandas-diarias/index.ts:282-291 arma `filasTanda` con: `order_id, np_idx, np, zona, cod, razon_social, direccion, barrio, fecha_recep, m3, m3_parcial, lineas, cajas`.
- `zona`: resuelta antes por `gv_ppp_web_zona_lote` (index.ts:274-279 → sql/gv_tandas_diarias.sql:141-149), que aplica la cascada `zona_expreso → localidad → gv_ppp_web_barrio_de(direccion)` y después `gv_zona_de_barrio` (sql/gv_overrides.sql:95-103: override `GV_Zonas_Barrios` (vacía) → `Zonas_Barrios` compartida, 115 filas, matching por `_norm_barrio`).
- `barrio`: `barrioCrudo(n).barrio` (index.ts:191-197) = `zona_expreso` si hay (ojo: guarda el BARRIO del punto de entrega pese al nombre), si no `localidad`, si no la dirección cruda entera.
- `direccion`: `direccionDe(n)` (index.ts:179-185) = dirección del cliente o "Exp. <expreso> — <dir expreso> (<dir>)" si va por expreso.
- Las RPC de LK/Chef (`gv_pedidos_web_np_lk` / `gv_pedidos_web_np_chef`) devuelven 24 columnas iguales; de ubicación traen `direccion, zona_expreso, localidad, provincia, nombre_expreso, direccion_expreso`. `provincia` NO se usa en el armado.
- Lo que NO hay en el backend al armar: lat/lng, partido, sector. `PPP_Geo` no se consulta desde ninguna función SQL (0 referencias en sql/).
- Dentro de `_sin_tanda` (sql/ppp_web_tandas.sql:263-291) quedan: `zona, grupo, cliente (=cod o razon_social), razon_social, direccion, barrio, fecha_recep, m3, va_solo, prioritario`.

**Front, tablero v13.03** — `_pppRowFromSupa` (index.html:26413-26423) mapea cada fila de `gv_ppp_programacion_diaria` (ISIS) a `{np, tanda, cod, razon_social, m3, localidad (=barrio||direccion), zona, direccion, barrio, fecha_entrega}`; las web entran a la misma lista con `_web`, `_wDir`, `localidad`, `zona`. El tablero:
- `_pppZonaPed(p)` (29319-29323): `Súper` si `pppEsSuper`, si no `p.zona` o `pppZonaDeBarrio(localidad||barrio)`.
- `_pppCamiones(ped)` (29355-29370): **un camión = una ZONA suelta por día** (Map por `_pppZonaPed`), ordenados por ruta `RT_RUTAS` (so: Z1-4 · n: Z5-7 · sup · ret). No usa grupos 2+3 ni tandas: la tanda es sólo una etiqueta acumulada en `c.tandas`.
- `_pppOrdenCarga(cam)` (29374-29387): busca `_pppGeo[_rtDirKey(p.direccion, p.localidad||p.barrio)]` (cache de `PPP_Geo` cargada por `pppRefreshGeo` → `_rtCacheAll` 29033-29040, sólo `dir_key,lat,lng`), corre `_rtOptimize(depot, stops)` (28785-28805: nearest-neighbor + 2-opt con haversine `_rtHav` 28779-28783) y numera LIFO. Depósito = `_pppGeo[RT_DEPOT_KEY]` o fallback (-34.6037,-58.4) que es Obelisco, no Villa Luro (`_rtEnsureDepot` 28905-28917 sí geocodifica "Virgilio 2788" pero lo llama Carga Camión, no el tablero).
- Geodatos disponibles: `PPP_Geo` = 118 filas, todas con lat/lng (fuente nominatim, 2026-07-16..08-21), 99 con `comp` (Nominatim address), 78 con `comp->>'suburb'`. Cobertura sobre las 83 direcciones distintas de `PPP_Programacion_Diaria`: sólo 24 con geo. Cobertura por barrio del diccionario (agregando `_norm_barrio(PPP_Geo.barrio)`): Z1 10/14, Z2 11/23, Z3 4/9, Z4 10/23, Z5 5/19, Z6 6/15, Z7 1/6. Sin geo en Z2: caballito, colegiales, devoto/villa devoto/v.devoto, microcentro, monserrat, **nuñez**, puerto madero, villa crespo, villa ortuzar.

## (b) Algoritmo actual de armado, paso a paso (`ppp_web_armar_tandas`)

0. Disparo: cron jobid 71 (`1 3 * * 1-5`) → Edge Function → `gv_es_dia_habil` → lee LK y Chef → `gv_pedidos_web_excluidos` → `gv_ppp_web_np_asignar` → `ppp_web_resync` → `gv_ppp_web_zona_lote` → `ppp_web_armar_tandas` (LK primero, después Chef con `p_forzar_cods` = códigos Chef de los clientes LK que entraron hoy) → `PPP_Web_Base` → `GV_Tandas_Auto_Log`. Corre UNA vez por día por empresa (no "apenas llegan").
1. Config (líneas 236-242): `tanda_m3_max_mezcla`=0,80 · `m3_max_dia`=5 · `dias_hasta_entrega`=0 · `saltar_fin_de_semana`=1 · `tanda_prefijo`='' · letra = `ppp_web_proxima_letra()` (mira las DOS tablas de programación). Valores vivos verificados en `PPP_Web_Config`.
2. Fecha de entrega (254-257) = hoy + dias, corrida al lunes si cae fin de semana (no saltea feriados).
3. `_sin_tanda` (263-291): sólo las NP de `p_filas` que NO tienen tanda en `PPP_Web_Programacion`. `cliente` = cod (o razón social). `grupo` = `gv_ppp_web_grupo_zona(zona)`. `va_solo` / `prioritario` desde `GV_Clientes_Reglas` (+ `p_forzar_cods`).
4. Filtros (294, 310): fuera las sin zona; fuera las zonas que no estén en `zonas_automaticas` (hoy '1,2' → `gv_ppp_web_zona_automatica`, gv_tandas_diarias.sql:643-652). Zona 3, Retira, Súper, Expo hoy NUNCA llegan al bucle automático (van a mano por el front).
5. Cupo (314-317): `v_resta` = 5 − m³ ya programados para esa fecha (las dos empresas).
6. **Selección por CLIENTE** (322-341): orden `prioritario desc, min(fecha_recep), sum(m3) desc, cliente`. Entra si es prioritario, o si es el primero y hay cupo (aunque solo se pase), o si `acum + m3_cli ≤ resta`. El resto queda sin tanda (= la cola/demora). Se borra de `_sin_tanda` lo no seleccionado.
7. **Armado por GRUPO** (348-376): `for v_grupo in select distinct grupo order by 1` → cada grupo es un número de camión `v_zn` (lpad 2). Dentro del grupo, clientes en orden `sum(m3) desc, cliente` (first-fit decreasing; NO es el orden de antigüedad del paso 6). Se abre tanda nueva (`LETRA + NN + letra_tanda`) si: grupo='Super', o `va_solo`, o `m3_cli ≥ 0,80`, o no hay tanda abierta, o `acum + m3_cli > 0,80`. Todas las NP del cliente entran a la misma tanda. Después de un Súper/solo/≥tope se cierra la tanda (`v_code := null`).
   ⚠ Es un bin-packing lineal: la tanda abierta se cierra sólo por tope; NO hay "buscar la tanda abierta donde mejor encaje" (una sola tanda abierta por grupo a la vez). Con `order by 1` de los grupos, el número de camión depende del orden alfabético de los nombres de grupo.
8. Persistencia (378-389): `insert … on conflict (empresa, order_id, np_idx) do update` en `PPP_Web_Programacion` con tanda, zona, fecha_entrega, m3, direccion, barrio. Devuelve resumen por tanda con `min(grupo)` como `r_zona`.
9. Idempotente: lo que ya tiene tanda no se toca; lo que quedó sin tanda se vuelve a mirar en la próxima corrida. Reacomodar lo ya programado es `ppp_web_resync` (sql/ppp_web_programacion.sql §3; agrega NP nuevas a la MISMA tanda de sus hermanas, no decide agrupación).

Evidencia histórica que respalda "cercanía real" (PPP_Programacion_Diaria, 61 tandas, 182 filas vivas, hasta 2026-10-28): 18 tandas con más de un barrio, todas pares vecinos (pompeya+soldati ×6, p.patricios+soldati ×4, barracas+soldati, belgrano+recoleta, villa crespo+villa ortuzar, olivos+tigre, castelar+merlo, caseros+moron, bella vista+villa ballester). Sólo 3 mezclan zonas: D55A y D55B = **Zona 1 + Zona 3 (flores + p.patricios / flores + soldati)** y D57B = 6+7. Es decir: la gente ya junta 1 con 3 cuando son barrios linderos, cosa que la regla 2+3/6+7 prohíbe hoy. Distancias entre centroides de barrio (desde PPP_Geo): Lugano–Palermo 13,1 km, Lugano–Belgrano 12,8, La Boca–Villa Urquiza 13,3, Barracas–Villa Pueyrredón 12,3; Núñez no tiene geo todavía.

## (c) Dónde enchufar una regla "estos dos pueden compartir tanda"

**Punto 1 — reemplazo directo, mínimo cambio: la clave `grupo` (sql/ppp_web_tandas.sql:268).** Hoy `grupo = gv_ppp_web_grupo_zona(zona)`. Si la regla se puede expresar como una PARTICIÓN (cada barrio pertenece a exactamente un "sector" y dos sectores nunca se mezclan), alcanza con cambiar esa línea por un `gv_ppp_web_sector(zona, barrio, direccion)` que devuelva la clave del sector; el bucle de 348-376 no se toca y el número de camión pasa a ser el sector. Firma sugerida:
```sql
create or replace function public.gv_ppp_web_grupo_tanda(
  p_zona text, p_barrio text, p_direccion text default null)
returns text language sql stable;   -- clave de agrupación ('Sector Sur-Este', 'Zona 4 - GBA Sur', 'Super', ...)
```
Limitación: una partición no modela "Núñez va con Belgrano y Belgrano va con Almagro pero Núñez no con Almagro"; para eso hace falta el punto 2.

**Punto 2 — complemento, la condición de apertura de tanda (líneas 359-360 y el orden 353).** Ahí es donde la relación PAR A PAR entra: además de `acum + m3 > tope`, exigir que el cliente sea "compatible" con TODOS los que ya están en la tanda abierta. Requiere llevar el estado de la tanda abierta (lista de barrios o centroide y m³) y, para no cerrar tandas prematuramente, cambiar "una tanda abierta por grupo" por "elegir entre las tandas abiertas del grupo la primera compatible con lugar" (first-fit sobre varias tandas, no sobre una). Firma sugerida (par a par, cargable con cualquier criterio: adyacencia, km, sector):
```sql
create or replace function public.gv_ppp_web_pueden_compartir(
  p_zona_a text, p_barrio_a text, p_zona_b text, p_barrio_b text)
returns boolean language sql stable;
-- o, para compatibilidad con una tanda ya abierta:
create or replace function public.gv_ppp_web_compatible_con_tanda(
  p_barrio text, p_barrios_tanda text[]) returns boolean;
```
Implementación natural: `gv_ppp_web_barrio_dist_km(a, b)` (haversine sobre centroides de `GV_Barrios_Geo`, ver d) y un parámetro nuevo en `PPP_Web_Config` (`tanda_km_max_barrios`, p.ej. 4-5 km) más una tabla de excepciones `GV_Barrios_Vecinos(barrio_a, barrio_b, permitido bool)` que mande por encima de la distancia.

**Punto 3 — el orden de recorrido dentro del grupo (línea 353) y la selección diaria (328).** Hoy el armado toma los clientes `sum(m3) desc`: dos clientes de Lugano y uno de Barracas en el medio se van cerrando por tope sin mirar dónde están. Si se ordena por sector/proximidad (p.ej. `order by sector, sum(m3) desc`, o por distancia al depósito / por barrido geográfico) el first-fit produce tandas compactas casi sin tocar la condición de apertura. Y si se quiere "zona 1 y 2 se arma apenas llega a 0,80" (idea 7317), la selección de 322-341 y el cupo de 5 m³ tienen que exceptuar esas zonas (o correr el job más de una vez por día con `p_fecha` = próximo día hábil), que es un cambio aparte del de cercanía.

Además, `gv_ppp_web_grupo_zona` tiene un consumidor implícito: el `r_zona` del `return query` (392) y la etiqueta 'Zonas 2+3' del log/tablero. Y el sugeridor del front (`pppSugerirTandas` 27344-27357) agrupa `byZ` por zona suelta: para que la regla sea una sola, habría que exponer el armado como RPC "dry" (`ppp_web_armar_tandas` con un flag que no inserte, o una `gv_ppp_web_sugerir_tandas(p_filas)` que devuelva `(order_id, np_idx, tanda)`) y que el front la llame en vez de `_pppBalancearZona`.

## (d) Qué hace falta para tener coordenadas / sector por barrio en el backend

Estado: `Zonas_Barrios` (compartida, 115 filas, `barrio_norm, zona, creado`; la escribe el trigger `trg_ppp_autozona` de Producción sobre `PPP_Programacion_Diaria`) no tiene lat/lng ni sector. `GV_Zonas_Barrios` (nuestra, override de zona, vacía) tiene la misma forma. `PPP_Geo` es COMPARTIDA: Producción la usa (10 referencias en su index.html: ruteo `_rtOptimize`, `_rtCachePut`, `_zgCachePut`), con RLS abierta a `anon` para insert/update (`ppp_geo_ins/upd/sel using(true)`), y las escribe el navegador con la anon key; key = `_rtNorm(direccion)|_rtNorm(barrio)` (index.html:28777), distinta a `_norm_barrio` de SQL (no saca tildes igual). Cobertura: 118 direcciones, 48 de 115 barrios con al menos una.

Propuesta que respeta la regla del repo (sólo agregar, prefijo GV_, RLS, sin triggers en compartidas):
1. **Tabla nueva `public."GV_Barrios_Geo"`** (`barrio_norm text pk` — misma normalización `_norm_barrio` que `Zonas_Barrios`—, `lat, lng double precision`, `sector text` (clave de agrupación, p.ej. 'S-Sur', 'S-Centro', 'S-Norte', 'S-Oeste'), `fuente text` ('centroide_ppp_geo' | 'nominatim' | 'manual'), `motivo text`, `actualizado timestamptz`). RLS on; select `anon, authenticated`; escritura sólo los 3 mails de supervisor (misma policy que `GV_Clientes_Reglas`). Nada de esto toca `Zonas_Barrios` ni `PPP_Geo`.
2. **Tabla opcional `GV_Barrios_Vecinos`** (`barrio_a, barrio_b, permitido bool, motivo`, pk sobre el par ordenado) para excepciones explícitas del dueño ("Núñez no va con Lugano" aunque un radio los junte, o "Flores sí con Pompeya" aunque sean zonas distintas).
3. **Poblado inicial** (a mano, INSERT-only, con backup): (i) centroides de `PPP_Geo` agrupados por `_norm_barrio(barrio)` → 48 barrios; (ii) los 67 restantes por geocodificación de "<barrio>, Buenos Aires, Argentina" — se puede hacer desde el navegador con `_zgGeocode` (ya respeta 1 req/s) y un botón nuevo, o una vez con un script local; (iii) `sector` lo define el dueño (una vista `gv_barrios_sin_geo` para ver qué falta). Los alias (`p.patricios`/`parque patricios`, `soldati`/`villa soldati`, `lugano`/`villa lugano`, `jose c paz`/`jose c. paz`) hay que unificarlos o cargar los dos.
4. **Mantenimiento**: cuando Producción aprende un barrio nuevo en `Zonas_Barrios` (trigger suyo), nosotros NO podemos reaccionar con trigger; alternativa: la vista `gv_barrios_sin_geo` (security_invoker) + aviso en el tablero ("N barrios sin ubicación") y, si se quiere automático, un cron `gv_*` propio que geocodifique con `pg_net` a Nominatim (respetando su política, 1/s y user-agent) — o dejarlo manual, que es lo que hace hoy el 📍 Mapa de zonas.
5. **Funciones nuevas**: `gv_ppp_web_barrio_geo(p_barrio) returns (lat, lng, sector)`, `gv_ppp_web_barrio_dist_km(a, b)`, `gv_ppp_web_pueden_compartir(...)` (c). Todas `gv_`, `stable`, con `grant execute` a `anon, authenticated, service_role` como las actuales.
6. Alternativa sin coordenadas (más rápida): sólo `sector` en `GV_Barrios_Geo` (o una columna nueva nullable `gv_sector` en `Zonas_Barrios` — permitido por la regla, pero mezcla nuestro dato en tabla suya; mejor tabla aparte) y `gv_ppp_web_grupo_tanda` devuelve el sector. Cubre "Capital junta pero Núñez ≠ Lugano" con 3-4 sectores, sin geocodificar nada.
7. El front puede duplicar la lógica como UX (colorear camiones por sector en `_pppCamiones`), pero la fuente de verdad queda en `ppp_web_armar_tandas`.

## (e) Riesgos para Producción Virgilio (misma base)

- `PPP_Geo` es compartida y la escribe Producción desde el navegador con `anon` (`resolution=ignore-duplicates` en `_rtCachePut`, `merge-duplicates` en `_zgCachePut`): NO cambiar columnas, PK ni policies; leerla está bien; agregar filas sólo con `on conflict do nothing` (y un `dir_key` que respete su normalización JS). Si Gestión geocodifica barrios "pelados", guardarlos en `GV_Barrios_Geo`, no en `PPP_Geo` (una fila `"|lugano"` ahí la vería el ruteo de Producción como una dirección).
- `Zonas_Barrios`: sólo lectura (Producción la lee 6 veces en su index.html y la escribe su trigger). Cualquier "sector" va en tabla `GV_*`.
- `ppp_web_armar_tandas`, `gv_ppp_web_grupo_zona`, `PPP_Web_Programacion`, `GV_Clientes_Reglas`: 0 referencias en el repo de Producción (grep HEAD e15b682) → se pueden cambiar libremente. Ojo: `ppp_web_armar_tandas` no tiene prefijo `gv_` pero es nuestra (creada 2026-09-04).
- Códigos de tanda: si la regla nueva cambia el número de "camión" (`v_zn`) o crea más grupos, no colisiona con Producción porque `ppp_web_proxima_letra` sigue avanzando la letra global; pero el monitor de Gestión agrupa por código de tanda mostrando las dos PPP juntas (v12.69) — sólo cosmético.
- `PPP_Programacion_Diaria` tiene 4 triggers de Producción (`trg_ppp_autozona`, `trg_ppp_zona_canonica`, `trg_norm_*`): no agregar ninguno ni escribir ahí; el armado no lo hace.
- Nominatim desde un cron/Edge Function: si se automatiza la geocodificación, va con prefijo `gv-`, rate-limit ≤1/s y sin tocar `PPP_Geo`; la política de uso de Nominatim prohíbe bulk sin identificación.
- Cambiar `zonas_automaticas` a '1,2,3' o armar "apenas llega" (idea 7317) NO afecta a Producción (sólo `PPP_Web_Programacion`), pero sí al cupo diario compartido de 5 m³ y a `PPP_Web_Base` (foto de artículos) que la Edge Function escribe con service_role.
- Todo cambio en Supabase se anota el mismo día en docs/SUPABASE-GESTION-VIRGILIO.md con impacto medido y rollback; backup antes de cualquier INSERT masivo (protocolo del CLAUDE.md).

**Números clave**

Funciones/archivos/líneas:
- sql/ppp_web_tandas.sql:227-396 `ppp_web_armar_tandas(p_empresa, p_fecha, p_filas jsonb, p_forzar_cods text[])` — :236-242 config · :263-291 temporal `_sin_tanda` (grupo en :268 = `gv_ppp_web_grupo_zona`; direccion/barrio en :271-272 sólo se copian) · :294 y :310 filtros sin zona / `gv_ppp_web_zona_automatica` · :314-317 cupo diario · :322-341 selección por cliente (orden :328) · :348-376 bucle por grupo (orden clientes :353; apertura de tanda :359-360; cierre :372-374) · :378-389 upsert en PPP_Web_Programacion · :392 `min(grupo)` como r_zona.
- sql/gv_tandas_diarias.sql:166-182 `gv_ppp_web_grupo_zona(text)` (2+3, 6+7) · :90-109 `gv_ppp_web_barrio_de` · :115-134 `gv_ppp_web_zona(ze, loc, dir)` · :141-149 `gv_ppp_web_zona_lote(jsonb)` · :190-222 `GV_Clientes_Reglas` (solo/prioritario; 4 filas) · :48-57 `gv_es_dia_habil` · :636-652 `zonas_automaticas`='1,2' y `gv_ppp_web_zona_automatica`.
- sql/gv_overrides.sql:59-64 `GV_Zonas_Barrios` (vacía) · :95-103 `gv_zona_de_barrio` (override → Zonas_Barrios, `_norm_barrio`).
- sql/autozona.sql: `Zonas_Barrios` compartida (115 filas), trigger `trg_ppp_autozona` de Producción sobre PPP_Programacion_Diaria (4 triggers vivos ahí).
- sql/ppp_web_programacion.sql:155-177 `PPP_Web_Programacion` (direccion, barrio, zona, tanda) · §3 `ppp_web_resync` (no decide agrupación).
- supabase/functions/gv-ppp-web-tandas-diarias/index.ts:179-185 `direccionDe` · :191-197 `barrioCrudo` · :201-208 `resolverZonas` · :265-271 resync · :274-279 zonas · :282-294 llamada a armar (columnas de la fila) · :435-456 LK primero, Chef con `forzarChef`.
- index.html: `pppSugerirTandas` 27307-27361 (front, por zona suelta, T_MIN 0,60 / T_IDEAL cfg / T_MAX 1,00) · `_pppBalancearZona` ~27255-27306 (SOFT 1,10) · `pppGuardarWeb` 25879-25930 · `pwebZonaSugerida` 25852-25857 · `pppZonaDeBarrio` 27650 · `_pppRowFromSupa` 26413-26423 (v13.03 agrega direccion/barrio) · `RT_RUTAS` 28767-28770 · `_rtHav` 28779 · `_rtOptimize` 28785-28805 · `_rtGeocode` 28838-28848 · `_zgGeocode` 28863-28874 (addressdetails → comp) · `_zgCachePut` 28897-28901 · `_rtEnsureDepot` 28905-28917 · `_zgOfficialNames`/`_zgZonaSug` 28928-28943 · `_rtCacheAll` 29033-29040 · `_rtCachePut` 29041-29045 · tablero v13.03 29267+ : `_pppZonaPed` 29319, `_pppRutaZona` 29324, `_pppCamiones` 29355-29370, `_pppOrdenCarga` 29374-29387 (fallback depósito -34.6037,-58.4), `_pppPlanDiaHtml` 29454+.
- Datos vivos (2026-09-05): PPP_Web_Config → tanda_m3_max_mezcla 0,80 · m3_max_dia 5 · dias_hasta_entrega 0 · zonas_automaticas '1,2' · tanda_prefijo '' · numeracion_activa 1. PPP_Web_Programacion 0 filas. PPP_Programacion_Diaria 182 filas, 61 tandas, 18 multi-barrio, 3 multi-zona (D55A/D55B = Z1+Z3, D57B = Z6+Z7). PPP_Geo 118 filas (118 lat/lng, 99 comp, 78 suburb; RLS anon insert/update/select using true; Producción la usa: 10 refs). Zonas_Barrios 115 (Z1 14, Z2 23, Z3 9, Z4 23, Z5 19, Z6 15, Z7 6, Super 4, Retira 1, Expo 1); barrios con geo 48/115. Direcciones distintas en PPP_Programacion_Diaria 83, con geo 24. Centroides: Lugano–Palermo 13,1 km, Lugano–Belgrano 12,8, La Boca–V.Urquiza 13,3. Producción repo HEAD e15b682: 0 refs a ppp_web_armar_tandas / gv_ppp_web_grupo_zona / PPP_Web_Programacion / GV_*.

**Caveats.** - Sólo lectura: no se ejecutó nada que escriba; las consultas fueron SELECT sobre Virgilio. No se tocaron archivos del repo.
- El clon de Producción estaba en /home/user/produccion-virgilio (no en /home/user/loekemeyer/produccion-virgilio como dice el CLAUDE.md); HEAD e15b682, shallow. No se llamó a register_repo_root.
- La búsqueda de código en GitHub devolvió 0 con incomplete_results=true (no concluyente); la confirmación de que Producción usa PPP_Geo viene del grep local sobre el clon.
- La matriz de distancias es entre CENTROIDES promedio de las direcciones geocodificadas de cada barrio (1 a ~10 puntos por barrio, Nominatim), no centroides oficiales; sirve para dimensionar, no como dato final. Núñez, Caballito, Villa Crespo, Colegiales, Devoto, Microcentro, Monserrat, Puerto Madero y Villa Ortúzar no tienen ninguna coordenada.
- `_rtDirKey` (JS: lower + colapsar espacios, conserva tildes) y `_norm_barrio` (SQL: además saca tildes) normalizan distinto; cualquier cruce PPP_Geo ↔ Zonas_Barrios desde SQL tiene que pasar por `_norm_barrio` de los dos lados (así se hizo en las consultas de cobertura).
- El sugeridor del front (`pppSugerirTandas`) sigue con T_MAX 1,00 y sin grupos 2+3/6+7: no es un bug reportado aquí, pero es un segundo lugar donde se decide agrupación y hoy difiere del backend.
- El tablero v13.03 usa fallback de depósito en el Obelisco si `PPP_Geo` no tiene `__deposito_virgilio_2788__`; no se verificó si esa fila existe (no se consultó por clave).
- Historial disponible para "cercanía real" es corto: PPP_Programacion_Diaria tiene 182 filas vivas (fechas hasta 2026-10-28); PPP_Entregados_Meta/Facturacion_NP/Entregas_Virgilio no traen barrio, así que las ~640 NP históricas no sirven para inferir pares de barrios sin cruzar con el padrón de LK.
- Idea 7317 (zona 1 y 2 "apenas llegan a 0,80") es un cambio de disparo/cupo, distinto del de cercanía; queda pendiente en docs/IDEAS-USUARIO.md:24.

### Código del armado

## 1) PPP_Geo — qué hay

- **118 filas**, todas `fuente='nominatim'`, geocodificadas del 2026-07-16 al 2026-08-21. Columnas: `dir_key` (= `_rtNorm(direccion)|_rtNorm(barrio)`, minúsculas + espacios colapsados, SIN quitar tildes ni puntos), `direccion`, `barrio`, `lat`, `lng`, `fuente`, `geocoded_at`, `comp` jsonb. RLS: select/insert/update abiertos a anon+authenticated. Sin triggers.
- **Barrios distintos**: 54 grafías crudas → **48 `barrio_norm`** (con `_norm_barrio`). 117/118 puntos caen en el bbox AMBA; el único "afuera" es Guernica (-34.91), que está bien.
- **`comp`** (address de Nominatim, `addressdetails=1`) está en **99/118**; los 19 sin `comp` son de la primera tanda de geocoding (v4.84, `_rtGeocode` sin addressdetails; casi todos Soldati/Pompeya/Barracas). Lo que trae:
  - `suburb` en 78 → para CABA es el **barrio oficial** ("Villa Soldati", "Nueva Pompeya", "Balvanera", "Villa Lugano"...). En GBA a veces trae la localidad (Crucecita, Bernal Sud) o nada.
  - `state_district` en 93 → en CABA es la **Comuna** ("Comuna 4", "Comuna 8"…); en GBA el **Partido** ("Partido de Lanús", "Partido de La Matanza"…). **Es el mejor "sector" gratis que hay**: comuna/partido es exactamente una partición geográfica compacta.
  - `city` en 85 ("Buenos Aires" en CABA; localidad en GBA), `town` en 14 (GBA), `quarter` en 16 (sub-barrio), `postcode` en 99 pero **con formato mixto** (`1437`, `C1437`, `B1846`, incluso `0237` para Moreno) → usable sólo con `regexp_replace(postcode,'\D','','g')` y no como clave principal.
- **¿Sirve para centroide por barrio?** Sí para los 48 que tienen puntos: dispersión intra-barrio ≤0,03° (~3 km) salvo Ituzaingó (0,048°) y Esteban Echeverría (0,033°). Pero 30 de los 48 tienen **1 solo punto** (el centroide es esa dirección, no el barrio). Los buenos: soldati 23, pompeya 11, barracas 10, villa soldati 7, boedo/constitucion/flores/nueva pompeya/parque patricios/martinez 3.
- **Cobertura de PPP_Geo sobre lo que está programado hoy** (`PPP_Programacion_Diaria`, 182 filas, 83 direcciones distintas): sólo **24/83 direcciones (29%)** tienen punto. Barrios con pedidos vivos y CERO puntos: colegiales (10 pedidos), p.patricios (10), lugano (6), villa crespo (6), flores (5 pedidos / 0 match por dir), moron (5), villa luro (4), villa ortuzar (4), almagro (4)… Es decir: la cache está sesgada a Soldati/Pompeya y a lo que se rutéo en julio-agosto.

**Barrios de `Zonas_Barrios` (115 filas) SIN ningún punto en PPP_Geo — 67** (48 con puntos):
- No geográficos (5): santa cruz de la sierra (Expo), retira, campo de mayo, tortuguita, tortuguitas (Super). Nota: `esteban echeverria` está como Super y SÍ tiene 2 puntos.
- Z1 (4): p. patricios, p.patricios, parque avellaneda, villa riachuelo.
- Z2 (12): caballito, colegiales, devoto, micro centro, microcentro, monserrat, nuñez, puerto madero, v.devoto, villa crespo, villa devoto, villa ortuzar.
- Z3 (5): liniers, mataderos (8:30 a 14), parque chacabuco, villa del parque, villa general mitre.
- Z4 (13): banfield, berazategui, f.varela, florencio varela, lanus este, lanus oeste, lomas de zamora, longchamps, platanos, rafael calzada, remedios de escalada, v.alsina, valentin alsina.
- Z5 (14): caseros, castelar, gonzalez catan, gregorio de laferrere, hurlingham, laferrere, lujan, mercado central, merlo, moron, palomar, san antonio de padua, v.bosch, villa sarmiento.
- Z6 (9): bella vista, jose c. paz, jose leon suarez, muñiz, munro, san miguel, v. maipu - san martin, villa adelina, villa lynch.
- Z7 (5): garin, olivos, pilar, san isidro, vicente lopez.
- De esos 67, **13 son alias de grafía** de un barrio que sí tiene punto (p.patricios/p. patricios→parque patricios; devoto/villa devoto/v.devoto entre sí; micro centro↔microcentro; f.varela↔florencio varela; v.alsina↔valentin alsina; laferrere↔gregorio de laferrere; jose c. paz→jose c paz; v.bosch→villa bosch; mataderos (8:30 a 14)→mataderos; lanus este/oeste→lanus). Con un `barrio_canon` la lista real de barrios sin coordenadas baja a ~50.

## 2) Otras fuentes de coordenadas / CP en la base — NO hay

- `information_schema` con `lat|lng|lon|latitud|longitud|cp|codigo_postal|postal|geo|coord|zip`: sólo **`PPP_Geo.lat/lng/geocoded_at`** y **`Proveedores.codigo_postal`** (1.513 filas, pero son PROVEEDORES, con `localidad`/`provincia`; no sirve para clientes).
- Tablas de clientes locales: `clientes_dto` (2.035: cod_cliente, dto_vol, empresa — sin dirección), `clientes_vendedor` (1.245: cod, vend), `whatsapp_clientes` (610: cod, teléfono), `cobranzas_*` / `deudores_condiciones` (sin dirección), `errores_cliente` (114, sin dirección). El padrón con dirección vive en LK (`customer_delivery_addresses.zona_expreso` = barrio del punto de entrega), no acá.
- Tablas con `barrio`/`direccion` textual pero sin coordenadas: `PPP_Programacion_Diaria` (182 filas, 78 con zona geográfica), `PPP_Web_Programacion` (0 filas hoy; trae direccion/barrio/zona), `wa_np_snapshot` (254 filas, 56 barrios distintos — misma población que la PPP, útil como segundo histórico de barrio×NP), y las vistas `gv_ppp_programacion_diaria`, `gv_ppp_en_salida`, `vista_grupo_pedido`, `vista_np_factura`. `Entregas_Virgilio` (9.739), `Facturacion_NP` (1.187) y `PPP_Entregados_Meta` NO tienen barrio ni dirección: sólo se pueden ubicar cruzando `cod_cliente` → última dirección conocida en la PPP.
- `GV_Zonas_Barrios` existe (override de zona para Gestión) y está **vacía a propósito** (`sql/gv_overrides.sql`); `gv_zona_de_barrio()` ya la consulta antes que `Zonas_Barrios`.
- Extensiones: `postgis`, `earthdistance` y `cube` están **disponibles pero NO instaladas**; `unaccent` y `pg_trgm` sí. Para distancias entre centroides alcanza haversine en SQL puro (`2*6371*asin(sqrt(...))`), no hace falta instalar nada.
- Inconsistencias vistas de paso (sólo reporte, no toqué nada): `PPP_Programacion_Diaria` tiene **burzaco → "Zona 2 - CABA Centro"** en 3 pedidos vivos (1 cliente; el error conocido de la lista canónica, el trigger no pisa zona cargada); `wa_np_snapshot` tiene **villa lugano → Zona 3** en 4 filas mientras `Zonas_Barrios` dice Zona 1.

## 3) Propuesta: centroide por barrio en el backend (la más simple y robusta)

**Regla de la base compartida**: `PPP_Geo` y `Zonas_Barrios` las creó el Virgilio original (v4.84/v4.99) y las usa el ruteo de Producción → **no** se les pone trigger. No pude confirmarlo greppeando el repo de Producción porque no está clonado en `/home/user/loekemeyer/produccion-virgilio`; asumir compartida.

**a) Tabla nueva `public."GV_Barrios_Geo"`** (prefijo GV_, RLS on, select anon+authenticated, write sólo supervisores por mail — misma reja que `GV_Zonas_Barrios`):
```
barrio_norm text primary key   -- clave = public._norm_barrio(barrio) (igual que Zonas_Barrios)
barrio_canon text not null     -- 'p.patricios' → 'parque patricios'; 'lugano' → 'villa lugano' (colapsa alias)
zona        text               -- copia informativa; la fuente sigue siendo Zonas_Barrios / gv_zona_de_barrio
lat numeric(9,6), lng numeric(9,6) not null
sector      text not null      -- código del §4 (ej. 'SUR_POMPEYA')
comuna_partido text            -- 'Comuna 8' / 'Partido de Lanús' (lo que trae comp->>'state_district')
fuente      text not null check (fuente in ('ppp_geo','manual','manual_aprox'))
n_puntos    int default 0, actualizado timestamptz default now()
```
Se siembra con la tabla del `key_numbers` (48 desde PPP_Geo + ~62 a mano). Los alias se cargan como filas propias con `barrio_canon` apuntando al canónico y **las mismas coordenadas** (así el join por `barrio_norm` nunca falla).

**b) Vista `gv_barrio_geo_vivo`** (`security_invoker=true`): centroide **en vivo** desde PPP_Geo, sin mantenimiento:
```sql
select public._norm_barrio(barrio) barrio_norm, count(*) n,
       percentile_cont(0.5) within group (order by lat) lat,   -- mediana, no avg: aguanta 1 geocode malo
       percentile_cont(0.5) within group (order by lng) lng,
       mode() within group (order by comp->>'state_district') comuna_partido
  from public."PPP_Geo"
 where lat between -35.2 and -34.2 and lng between -59.3 and -57.9   -- descarta geocodes fuera de AMBA
 group by 1;
```
**c) Función `gv_barrio_geo(p_barrio text) returns (lat, lng, sector, fuente)`** (stable, sql): `coalesce` de (1) fila `manual` de GV_Barrios_Geo (la gana siempre, es lo que corrigió una persona), (2) `gv_barrio_geo_vivo` si tiene ≥3 puntos, (3) fila `ppp_geo`/`manual_aprox` de GV_Barrios_Geo, (4) null → el pedido queda "sin ubicación" y se programa a mano (igual que hoy "sin zona"). Con esto **el front no tiene que llamar nada**: cuando geocodifica una dirección nueva y la mete en PPP_Geo, la vista ya la ve.

**d) Refresco opcional `gv_barrios_geo_recalcular()`** (security definer, sólo `service_role`/cron `gv_barrios_geo_diario` a las 01:00): `insert … on conflict (barrio_norm) do update set lat, lng, n_puntos, fuente='ppp_geo' where GV_Barrios_Geo.fuente <> 'manual'` desde la vista, para que la tabla quede materializada y auditable y el `sector` se pueda derivar de `comuna_partido` cuando aparece un barrio nuevo. Nunca pisa `manual`. Alternativa sin cron: llamarla como RPC desde el front al terminar `_zgCachePut` (optimización, no fuente de verdad).

**e) Cómo lo consume el armado de tandas**: hoy `ppp_web_armar_tandas` agrupa por `gv_ppp_web_grupo_zona(zona)` (sql/ppp_web_tandas.sql L268) y sólo zonas de `zonas_automaticas` = '1,2'. Cambio propuesto (backend, preguntar al dueño antes de implementar por protocolo): (i) la temp `_sin_tanda` suma `sector` y `lat/lng` vía `gv_barrio_geo(barrio)`; (ii) se reemplaza el `grupo` por una función `gv_ppp_web_compatibles(sector_a, sector_b) returns bool` = mismo sector **o** vecinos según `GV_Sectores_Vecinos` (§4), con `zonas_automaticas` pasando a '1,2,3'; (iii) como red de seguridad, además `dist_km(centroide_a, centroide_b) <= tanda_km_max` (nuevo `PPP_Web_Config.tanda_km_max`, sugerido 6,0 — Flores↔P.Patricios, que el dueño ya mezcló en D55A, son ~6 km; Núñez↔Lugano ~15 km; Palermo↔Barracas ~10 km). La regla de distancia sola ya resuelve "Núñez con Villa Lugano no", pero la de sectores es la que una persona puede leer y discutir.

## 4) Alternativa "sectores": partición propuesta (CABA + primer cordón)

Sectores compactos, con los barrios tal cual están escritos en `Zonas_Barrios` (los alias van con su canónico). Depósito Virgilio 2788 = sector OESTE_SUR.

**CABA (8)**
- **A · SUR_ESTE (Comuna 1 sur + 4 este)**: barracas, la boca, constitucion, parque patricios, p.patricios, p. patricios. [+ san telmo si aparece]
- **B · SUR_POMPEYA_SOLDATI (Comuna 4 sur + 8)**: pompeya, nueva pompeya, soldati, villa soldati, villa lugano, lugano, villa riachuelo.
- **C · OESTE_SUR (Comuna 9 + 10 sur)**: mataderos, mataderos (8:30 a 14), parque avellaneda, liniers, villa luro. [+ versalles, villa real, floresta, velez sarsfield si aparecen]
- **D · OESTE_CENTRO (Comuna 6 + 7)**: flores, parque chacabuco, caballito.
- **E · OESTE_NORTE (Comuna 11 + Paternal)**: villa del parque, villa devoto, devoto, v.devoto, villa general mitre, paternal. [+ villa santa rita, monte castro, agronomia]
- **F · CENTRO (Comunas 1 norte, 2, 3, 5)**: once, balvanera, san cristobal, boedo, almagro, monserrat, microcentro, micro centro, puerto madero, retiro, recoleta. [+ san nicolas, san telmo]
- **G · NORTE_PALERMO (Comuna 14 + 15 + Colegiales)**: palermo, villa crespo, colegiales, villa ortuzar. [+ chacarita]
- **H · NORTE_BELGRANO (Comuna 12 + 13)**: belgrano, nuñez, villa urquiza, villa pueyrredon. [+ saavedra, coghlan]

**Primer cordón (5)**
- **J · GBA_SUR_ESTE (Avellaneda–Lanús–Quilmes)**: avellaneda, valentin alsina, v.alsina, lanus, lanus este, lanus oeste, remedios de escalada, bernal, quilmes, quilmes oeste, berazategui, platanos, florencio varela, f.varela.
- **K · GBA_SUR_OESTE (Lomas–Alte. Brown–E. Echeverría)**: lomas de zamora, banfield, temperley, adrogue, burzaco, longchamps, rafael calzada, monte grande, esteban echeverria, guernica.
- **L · GBA_OESTE (La Matanza–3 de Febrero–Morón–Merlo–Moreno)**: ciudadela, ramos mejia, san justo, mercado central, gregorio de laferrere, laferrere, gonzalez catan, villa sarmiento, moron, castelar, ituzaingo, hurlingham, palomar, caseros, villa bosch, v.bosch, san antonio de padua, merlo, moreno, lujan.
- **M · GBA_NORTE (San Martín–San Miguel–J.C.Paz)**: san martin, v. maipu - san martin, villa lynch, villa ballester, chilavert, jose leon suarez, munro, villa adelina, san miguel, muñiz, bella vista, jose c paz, jose c. paz, campo de mayo, tortuguitas, tortuguita.
- **N · GBA_NORTE_RIBERA (Vte. López–San Isidro–Tigre–Pilar)**: vicente lopez, olivos, martinez, san isidro, tigre, garin, pilar.

**Vecindad (simétrica)** — pares que pueden compartir tanda:
- A ↔ B, F, J  (Barracas–Pompeya; Constitución–Once/Monserrat; Barracas–Avellaneda por Pte. Pueyrredón)
- B ↔ A, C, D, J  (Soldati–Mataderos/P.Avellaneda; Pompeya–Flores/P.Chacabuco; Pompeya–V.Alsina por Pte. Alsina)
- C ↔ B, D, E, L  (Villa Luro–Villa del Parque; Liniers–Ciudadela por Gral. Paz)
- D ↔ B, C, E, F, G  (Caballito–Almagro; Caballito–Villa Crespo)
- E ↔ C, D, G, H, L, M  (Devoto–Villa Pueyrredón; Devoto–Caseros/V. Lynch por Gral. Paz)
- F ↔ A, D, G  (Recoleta–Palermo; Almagro–Villa Crespo)
- G ↔ D, E, F, H  (Colegiales–Belgrano)
- H ↔ E, G, M, N  (Núñez–Vicente López; Villa Urquiza–Munro/Villa Adelina)
- J ↔ A, B, K  ·  K ↔ J  ·  L ↔ C, E, M  ·  M ↔ E, H, L, N  ·  N ↔ H, M
- **No vecinos que hoy la regla 1+2+3 juntaría y el dueño no quiere**: H (Núñez/Belgrano) con B (Lugano/Soldati); H con A; G con B; F con B es dudoso (Boedo–Pompeya son vecinos reales: si el dueño los quiere juntos, mover boedo a A o declarar F↔B).
- La partición respeta lo que el dueño ya hace a mano en las tandas vivas: D55B flores+soldati (D↔B), D55A flores+p.patricios (D↔A no está declarado → sería el único caso histórico que la vecindad estricta NO permite; con `tanda_km_max`=6,5 sí pasa), D57B chilavert+olivos+tigre (M↔N), D53F barracas+soldati (A↔B), D56A belgrano+recoleta (H↔F tampoco declarado — otro caso a decidir con el dueño: Belgrano–Recoleta son ~7 km por Libertador).

Para persistirlo: tabla `GV_Sectores` (sector, nombre, orden) + `GV_Sectores_Vecinos` (sector_a, sector_b) + columna `sector` en `GV_Barrios_Geo`. Todo con prefijo GV_, RLS, sin tocar `Zonas_Barrios` ni `PPP_Geo`.

**Números clave**

PPP_Geo: 118 filas · 54 grafías de barrio · 48 barrio_norm · 99 con comp (78 suburb, 93 state_district=Comuna/Partido, 99 postcode formato mixto, 85 city, 14 town) · 19 sin comp · 117/118 en bbox AMBA · 30 barrios con 1 solo punto.
Zonas_Barrios: 115 filas (109 geográficas + Retira/Expo/4 Super) · 48 con ≥1 punto en PPP_Geo · 67 sin punto (62 geográficos; 13 de ellos alias de otro que sí tiene) · GV_Zonas_Barrios: 0 filas.
PPP_Programacion_Diaria: 182 filas · 83 direcciones distintas · 24 (29%) con punto en PPP_Geo · 78 dir con zona geográfica, 23 con punto.
Otras fuentes de lat/lng/CP: ninguna (sólo Proveedores.codigo_postal, 1.513 proveedores). Extensiones postgis/earthdistance disponibles, no instaladas.
Historial cruzado de zonas en una misma tanda (PPP viva): Z1+Z3 en 2 tandas (D55A, D55B), Z6+Z7 en 1 (D57B). Nunca Z1+Z2.

TABLA PROPUESTA GV_Barrios_Geo (barrio_norm → lat, lng, sector, fuente). fuente=ppp_geo = centroide medido (n puntos); manual_aprox = coordenada aproximada de conocimiento general (±500 m, verificar en mapa antes de sembrar):
-- Zona 1
barracas -34.6427 -58.3827 A ppp_geo(10) · la boca -34.6433 -58.3593 A ppp_geo(1) · constitucion -34.6245 -58.3828 A ppp_geo(3) · parque patricios -34.6394 -58.3961 A ppp_geo(3) · p.patricios / p. patricios = parque patricios (alias) · pompeya -34.6532 -58.4172 B ppp_geo(11) · nueva pompeya -34.6541 -58.4189 B ppp_geo(3) · soldati -34.6640 -58.4328 B ppp_geo(23) · villa soldati -34.6645 -58.4326 B ppp_geo(7) · villa lugano -34.6778 -58.4742 B ppp_geo(2) · lugano -34.6764 -58.4832 B ppp_geo(1) · villa riachuelo -34.6900 -58.4680 B manual_aprox · parque avellaneda -34.6440 -58.4790 C manual_aprox
-- Zona 2
almagro -34.6021 -58.4309 F ppp_geo(1) · balvanera -34.6108 -58.4072 F ppp_geo(2) · once -34.6050 -58.3995 F ppp_geo(1) · san cristobal -34.6250 -58.4018 F ppp_geo(2) · boedo -34.6311 -58.4162 F ppp_geo(3) · monserrat -34.6130 -58.3800 F manual_aprox · microcentro / micro centro -34.6050 -58.3760 F manual_aprox · puerto madero -34.6110 -58.3630 F manual_aprox · retiro -34.5974 -58.3855 F ppp_geo(1) · recoleta -34.5957 -58.3915 F ppp_geo(2) · caballito -34.6180 -58.4400 D manual_aprox · palermo -34.5639 -58.4392 G ppp_geo(1) · villa crespo -34.5990 -58.4380 G manual_aprox · colegiales -34.5750 -58.4500 G manual_aprox · villa ortuzar -34.5810 -58.4680 G manual_aprox · belgrano -34.5635 -58.4590 H ppp_geo(1) · nuñez -34.5450 -58.4630 H manual_aprox · villa urquiza -34.5779 -58.4811 H ppp_geo(1) · villa pueyrredon -34.5817 -58.4949 H ppp_geo(1) · villa devoto / devoto / v.devoto -34.5990 -58.5130 E manual_aprox
-- Zona 3
flores -34.6216 -58.4604 D ppp_geo(3) · parque chacabuco -34.6350 -58.4390 D manual_aprox · mataderos -34.6517 -58.5027 C ppp_geo(2) · mataderos (8:30 a 14) = mataderos (alias) · liniers -34.6420 -58.5230 C manual_aprox · villa luro -34.6319 -58.5015 C ppp_geo(1) [depósito -34.636 -58.505] · paternal -34.5966 -58.4667 E ppp_geo(2) · villa del parque -34.6050 -58.4900 E manual_aprox · villa general mitre -34.6120 -58.4690 E manual_aprox
-- Zona 4
avellaneda -34.6561 -58.3658 J ppp_geo(1) · valentin alsina / v.alsina -34.6700 -58.4100 J manual_aprox · lanus -34.6969 -58.4087 J ppp_geo(1) · lanus este -34.7000 -58.3900 J manual_aprox · lanus oeste -34.7050 -58.4120 J manual_aprox · remedios de escalada -34.7240 -58.4000 J manual_aprox · bernal -34.7160 -58.2966 J ppp_geo(2) · quilmes -34.7358 -58.2651 J ppp_geo(1) · quilmes oeste -34.7393 -58.2784 J ppp_geo(1) · berazategui -34.7640 -58.2100 J manual_aprox · platanos -34.7820 -58.1930 J manual_aprox · florencio varela / f.varela -34.8270 -58.2760 J manual_aprox · lomas de zamora -34.7610 -58.4020 K manual_aprox · banfield -34.7440 -58.3960 K manual_aprox · temperley -34.7711 -58.3802 K ppp_geo(1) · adrogue -34.7974 -58.3939 K ppp_geo(1) · burzaco -34.8321 -58.4069 K ppp_geo(1) · longchamps -34.8570 -58.3900 K manual_aprox · rafael calzada -34.7900 -58.3540 K manual_aprox · monte grande -34.8168 -58.4681 K ppp_geo(1) · guernica -34.9106 -58.3707 K ppp_geo(1)
-- Zona 5
ciudadela -34.6319 -58.5404 L ppp_geo(1) · ramos mejia -34.6424 -58.5751 L ppp_geo(1) · villa sarmiento -34.6300 -58.5800 L manual_aprox · san justo -34.6863 -58.5596 L ppp_geo(2) · mercado central -34.7050 -58.4970 L manual_aprox · gregorio de laferrere / laferrere -34.7480 -58.5880 L manual_aprox · gonzalez catan -34.7680 -58.6500 L manual_aprox · caseros -34.6060 -58.5620 L manual_aprox · palomar -34.6100 -58.5900 L manual_aprox · hurlingham -34.5890 -58.6350 L manual_aprox · moron -34.6530 -58.6190 L manual_aprox · castelar -34.6500 -58.6440 L manual_aprox · ituzaingo -34.6374 -58.6916 L ppp_geo(2) · san antonio de padua -34.6650 -58.7000 L manual_aprox · merlo -34.6650 -58.7270 L manual_aprox · moreno -34.6268 -58.7979 L ppp_geo(1) · lujan -34.5700 -59.1050 L manual_aprox (lejos, 60 km) · v.bosch = villa bosch (alias, ver Z6)
-- Zona 6
san martin -34.5773 -58.5364 M ppp_geo(1) · v. maipu - san martin -34.5800 -58.5300 M manual_aprox · villa lynch -34.5950 -58.5290 M manual_aprox · villa ballester -34.5484 -58.5527 M ppp_geo(2) · chilavert -34.5344 -58.5641 M ppp_geo(1) · jose leon suarez -34.5330 -58.5760 M manual_aprox · villa bosch -34.5866 -58.5769 M ppp_geo(1) · munro -34.5290 -58.5210 M manual_aprox · villa adelina -34.5220 -58.5470 M manual_aprox · san miguel -34.5430 -58.7130 M manual_aprox · muñiz -34.5570 -58.7050 M manual_aprox · bella vista -34.5450 -58.6800 M manual_aprox · jose c paz / jose c. paz -34.5266 -58.7596 M ppp_geo(1)
-- Zona 7
vicente lopez -34.5260 -58.4790 N manual_aprox · olivos -34.5090 -58.4910 N manual_aprox · martinez -34.5021 -58.5335 N ppp_geo(3) · san isidro -34.4720 -58.5270 N manual_aprox · tigre -34.4199 -58.5726 N ppp_geo(1) · garin -34.4230 -58.7400 N manual_aprox · pilar -34.4580 -58.9140 N manual_aprox
-- Super / Retira / Expo
esteban echeverria -34.7981 -58.4896 K ppp_geo(2) · campo de mayo -34.5330 -58.6700 M manual_aprox · tortuguitas / tortuguita -34.4740 -58.7530 M manual_aprox · retira = depósito -34.6360 -58.5050 · santa cruz de la sierra (Expo) sin coordenada AMBA.
Total: 48 barrio_norm con fuente ppp_geo, ~50 manual_aprox, 13 alias.

Distancias de referencia (haversine sobre estos centroides): Núñez–Villa Lugano ≈ 14,8 km · Palermo–Barracas ≈ 10 km · Belgrano–Recoleta ≈ 7 km · Flores–P.Patricios ≈ 6,3 km · Flores–Soldati ≈ 5,4 km · Barracas–Pompeya ≈ 3,4 km · Pompeya–Soldati ≈ 1,9 km · Once–Constitución ≈ 2,6 km.

**Caveats.** - Todo fue SELECT; no se creó ni modificó nada. Las coordenadas `manual_aprox` son de conocimiento general (centro del barrio/localidad, ±500 m–1 km), NO verificadas contra Nominatim desde acá (el sandbox no sale a internet); antes de sembrar GV_Barrios_Geo conviene que el front las geocodifique una vez ("<barrio>, Buenos Aires, Argentina") o que una persona las mire en el mapa de zonas (v9.75).
- 30 de los 48 centroides "ppp_geo" salen de 1 sola dirección (un cliente), no del barrio; los sólidos son Soldati, Pompeya, Barracas, Villa Soldati. Por eso la función propuesta prioriza `manual` > vivo con ≥3 puntos > ppp_geo(1 punto).
- `dir_key` de PPP_Geo no quita tildes ni puntos ("constitución 1665|burzaco"), y `_norm_barrio` sí quita tildes pero deja puntos ("p.patricios") → el join barrio a barrio debe hacerse siempre con `_norm_barrio(PPP_Geo.barrio)`, nunca con `split_part(dir_key,'|',2)`.
- Los 19 puntos sin `comp` (primer geocoding v4.84) no traen Comuna/Partido; si se quiere `state_district` para todos hay que re-geocodificarlos desde el front (el mapa de zonas ya lo hace con `merge-duplicates`).
- No pude confirmar con grep si Producción usa `PPP_Geo` (repo no clonado en el sandbox); por CLAUDE.md se asume compartida → sin trigger, se propone vista + RPC/cron `gv_`. Confirmar antes de cualquier DDL.
- La partición en sectores y la vecindad son una propuesta para discutir con el dueño: dos tandas reales (D55A flores+p.patricios, D56A belgrano+recoleta) cruzan sectores que no declaré vecinos; o se agregan esos pares (D↔A, H↔F) o se confía en el umbral de km (≥6,5) como segunda regla. Boedo–Pompeya también son vecinos reales y hoy caen en sectores F y B no vecinos.
- Datos sucios detectados y NO corregidos (protocolo): `PPP_Programacion_Diaria` burzaco→Zona 2 (3 pedidos vivos), `wa_np_snapshot` villa lugano→Zona 3 (4 filas), `Zonas_Barrios` tiene `mataderos (8:30 a 14)` con horario pegado y `v.devoto` hoy en Zona 2 (ya alineado con devoto/villa devoto).
- Cambiar la regla de agrupación es lógica de negocio → va al backend (`ppp_web_armar_tandas` / `gv_ppp_web_grupo_zona`) y por protocolo hay que preguntarle al dueño backend vs front y pedir permiso antes de implementar; también implica subir `zonas_automaticas` de '1,2' a '1,2,3' si quiere que la Z3 entre al job de las 00:01.

### Geodatos

## Reconstrucción de cómo armó tandas el dueño (sólo SELECT, Supabase hrxfctzncixxqmpfhskv)

### 1) Fuentes y cobertura
- **NP↔tanda**: unión de `PPP_Entregados_Meta` (2.783 NP, 1.117 tandas, ene→sep 2026) + `Facturacion_NP` (+88 NP nuevas) + `Entregas_Virgilio` (+78). Total 2.898 pares NP-tanda; **2.454 con tanda válida `LETRA+NN+LETRA`** (el resto son códigos raros tipo `1240B`, `T 27/03`). Registros CCN aportaban sólo 48 NP más; no se usaron.
- ⚠ **Los códigos de tanda NO son únicos entre LK y Chef**: 29 códigos (p.ej. `D47B`) los usan las dos empresas con fechas distintas (Chef lleva su propia serie D47 a la vez que LK va por D53/D55). Todo se agrupó por **(empresa, tanda)** → **1.018 tandas**, 710 con ≥2 NP, **359 con ≥2 clientes distintos**.
- **Barrio/zona por NP**: las tablas históricas no traen barrio. Se mapeó por código de cliente (empresa+cod) con esta precedencia:
  1. `PPP_Programacion_Diaria` (dirección de ENTREGA real, 92 clientes; barrio moda por cod) → 494 NP.
  2. `lk_pedidos_match.sucursal_entrega` ("Calle 123- Barrio") sólo si el barrio es del AMBA → 547 NP.
  3. `isis_lk/isis_ch.documentos.contraparte_localidad` (+CP de CABA) — **domicilio fiscal**, menor confianza → 206 NP.
  - **1.207 NP (49 %) quedan sin barrio: son clientes del interior** (Tucumán, Mar del Plata, Rosario, Bahía Blanca, Mendoza…). Se entregan en un **expreso/transporte** cuya dirección está sólo en el padrón LK. Donde Programación sí lo muestra, el hub del interior es **Zona 1 en ~80 %** (Soldati 18, Pompeya 5, P.Patricios 4, Barracas/La Boca 2; Avellaneda 2; Flores, Chilavert, V.Ortúzar, Lugano, Belgrano, Luján 1 c/u). En las tablas de abajo figuran como `Int` (= "hub de transporte, probablemente Z1").
- Coordenadas: centroides por barrio desde `PPP_Geo` (48 barrios, avg lat/lng por `split_part(dir_key,'|',2)`); para ~50 barrios sin punto (Caballito, Colegiales, Devoto, Núñez, Microcentro, Lanús Este, Lomas, Morón, Hurlingham, Munro, San Isidro, Pilar, etc.) usé coordenadas aproximadas de conocimiento general (±1 km). Depósito = (-34.636,-58.505).

### 2) Cómo se ven las tandas
- De las 359 tandas multi-cliente, **134 tienen todos los barrios conocidos: 21 son de un solo barrio y 113 mezclan barrios distintos** → el dueño SÍ junta clientes de barrios distintos en una tanda, pero la mayoría de las tandas multi-cliente son 2 clientes (249), 3 (82), 4 (23), 5+ (5).
- Tandas de una sola etiqueta (todas las NP misma zona): Z2 63, Z1 42, Z5 28, Z4 25, Z6 16, Z3 6, Z7 5, Retira 33, Super 13, Int 302.
- El número de camión (letra+NN) **no es "el camión del día"**: 236 números tienen 1 fecha, 87 tienen 2, 51 tienen 3+ (D53A/B salieron 01-09, D53C 02-09, D53D 03-09). Es más un "lote/carga"; por eso la co-ocurrencia por camión es evidencia débil y se reporta con la versión estricta (mismo nro + misma fecha).

### 3) Co-ocurrencia de zonas (ver tabla en key_numbers)
- **En la misma tanda** (359 tandas multi-cliente): Z1+Z2 **13**, Z1+Z3 **9**, Z2+Z3 **8**, Z5+Z6 9, Z6+Z7 7, Z2+Z6 6, Z1+Z4 5, Z2+Z4 4. Int (hub, ~Z1) + Z1 43, +Z2 27, +Z3 18, +Z5 10, +Z4 9.
- Las tres zonas de Capital se mezclan entre sí con frecuencia parecida; la regla vigente (2+3 sí, 1 con nadie) **no coincide** con la práctica: Z1+Z2 (13) es incluso más frecuente que Z2+Z3 (8).
- Las mezclas fuera de Capital que existen: Z5+Z6 (Oeste con Norte: Hurlingham/San Justo/Morón con Martínez/San Martín), Z6+Z7, Z1+Z4 (Soldati/Pompeya con Avellaneda/Lanús/Quilmes), Z2+Z6.
- **Camión-día estricto** (224 grupos): Z1+Z2 23, Z1+Z3 15, Z2+Z3 10; Z5+Z6 10, Z6+Z7 7; Z2+Z5 8, Z1+Z5 7, Z1+Z6 7.

### 4) Qué barrios junta de verdad (misma tanda, 27 tandas que mezclan Z1/Z2/Z3, todas listadas)
- **Z1+Z2 = costura "centro-sur"**: Constitución/P.Patricios con Balvanera/Once/San Cristóbal/Microcentro (B39B 1,7 km; B39F, C28F, C40B, C42E 2,7 km; B68J 2,3 km; C99I 7,5 km). Parque Patricios con Palermo (B65K 9,3) y con Villa Crespo (B88A 5,9). Soldati con Recoleta (B86A 8,5).
- **Z1+Z3 = Soldati/Pompeya/P.Patricios con Flores/Mataderos/Paternal** (5,4–8,1 km; B64C con Ciudadela 11,5).
- **Z2+Z3 = Flores con Palermo/Recoleta/Boedo, Villa del Parque con Once** (4–8 km; C10C Mataderos+Núñez 12,3 km es el peor).
- Top pares de barrios en la misma tanda: Pompeya–Soldati 6, Flores–Soldati 3, Balvanera–Constitución 3, Balvanera–San Martín 3, Bernal–Temperley 2, Lanús–Quilmes 2, Flores–Recoleta 2, Flores–Palermo 2, Flores–Mataderos 2, Constitución–Microcentro 2, Constitución–Soldati 2, Chilavert–San Martín 2, San Martín–Tigre 2, Ciudadela–Mataderos 2, Hurlingham–San Justo 2, Martínez–Morón 2, Monte Grande–Temperley 2, P.Patricios–Soldati 2, Flores–P.Patricios 2.
- **Pares lejanos que el dueño menciona**: Núñez/Belgrano/Colegiales con Lugano/Soldati/Pompeya en la misma tanda: **0 veces en 8 meses** (lo más cercano: Palermo+P.Patricios 1 vez, 9,3 km). Constitución con Devoto/Villa del Parque: 0; Constitución con Villa Pueyrredón 1 (B28A, 11,3 km) y con Villa Urquiza 1 (D42A, 10,4 km) — son las 2 únicas tandas "norte+sur" y ambas ≤ 11,5 km. En el mismo camión-lote (más laxo) sí aparecen Palermo+Soldati 5 veces y Belgrano+Soldati 3 — pero en tandas separadas.

### 5) Distancias (117 tandas con ≥2 barrios conocidos distintos)
- Máxima entre paradas: **p50 8,1 km, p75 14,3, p90 21,6, p95 29,9, máx 42,5**. % de tandas con dmax ≤ 5 km: 23 %; ≤ 8: 50 %; ≤ 10: 59 %; ≤ 12: 66 %; ≤ 15: 76 %; ≤ 20: 88 %.
- Máxima al depósito: p50 11,3 km, p75 20,5, p90 24,8, máx 42,3.
- Pares barrio-barrio observados en la misma tanda (169): p50 8,4 km, p90 19,6. Por par de zonas (mediana/máx): Z1-Z1 1,9/6,3; Z2-Z2 5,3/9,8; **Z1-Z2 3,3/11,3; Z1-Z3 6,2/8,1; Z2-Z3 6,9/12,3**; Z3-Z5 4,1/7,4; Z5-Z6 11,7/18,5; Z2-Z6 12,4/29,6; Z1-Z4 15,1/23,2; Z6-Z7 17,8/38,2; Z2-Z4 19,0/25,0.
- Las tandas extremas son casi todas **GBA lejos** (Pilar+Núñez 42,5; Pilar+Villa Lynch 38; Guernica+Mataderos 31; Balvanera+Burzaco+San Martín 31; José C. Paz+Palermo 30; Hurlingham+Pilar 29; Berazategui+Recoleta 25; D47B Microcentro+Soldati+Temperley+Monte Grande 25; Lugano+Muñiz 24). La única extrema de Capital, A79A (Soldati+V.Ballester+Flores+Berazategui, 39,5 km), es sospechosa: 6 NP con 2 fechas distintas dentro de la misma tanda.
- Centroides de zona y distancias: Z1-Z2 7,1 km, Z1-Z3 6,0, Z2-Z3 6,4 (todo Capital dentro de ~7 km entre centroides); Z1-Z4 12,9; Z5-Z6 13,8; Z6-Z7 12,1; Z2-Z6 14,5; Z4-Z5 32,5; Z4-Z7 43,1.
- "Zona 1 y 2 todos los días": de 149 fechas con reparto en 2026, hubo Z1 en 84 y Z2 en 75 (Z5 49, Z4 44, Z6 43, Z3 32, Z7 16). Con los NP del interior sin hub (mayoría Z1) el número real de días con Z1 es mayor.

### 6) Conclusión / regla que reproduce lo hecho
- Dentro de Capital el dueño mezcla las 3 zonas, pero **siempre entre barrios contiguos o a ≤ ~12 km**: de las 27 tandas que mezclan Z1/Z2/Z3 (excluida A79A), la máxima entre paradas va de 1,7 a 12,3 km, mediana ≈ 6,5 km. Nunca juntó el corredor norte (Núñez/Belgrano/Colegiales/Devoto/V.Urquiza) con el sur (Lugano/Soldati/Pompeya/Barracas) en una tanda; sí junta Constitución/San Cristóbal/Balvanera/Once/Microcentro entre sí, y Soldati/Pompeya/P.Patricios con Flores/Mataderos/Paternal.
- **Regla propuesta (cercanía real, no número de zona)**: dos pedidos pueden compartir tanda si (a) están en el mismo grupo de zonas actual, o (b) ambos en Capital (Z1/Z2/Z3) **y la distancia haversine entre sus barrios (centroide PPP_Geo o punto geocodificado) es ≤ 10–12 km**, y además la distancia máxima entre todas las paradas de la tanda no supera ese radio. Con 12 km se reproduce el 100 % de las tandas mixtas de Capital observadas y se bloquea Núñez–Lugano (~15,5 km), Belgrano–Soldati (~14,5), Devoto–Constitución (~13,5), Villa Urquiza–Lugano (~14). Con 10 km caen 3 de 27 casos históricos (B28A 11,3; B64C 11,5; C10C 12,3), todos casos borde.
- Para todo el AMBA, un radio único no reproduce lo hecho (p90 = 21,6 km porque GBA es disperso); si se quiere generalizar: Capital ≤ 12 km, GBA ≤ ~20 km dentro del mismo corredor (Sur / Oeste / Norte), que es lo que hoy hacen los grupos 6+7 y lo que en la práctica también aparece en 5+6 (9 tandas) y 1+4 (5).
- Implementación: en `gv_ppp_web_grupo_zona` / `ppp_web_armar_tandas` el criterio "mismo grupo" debería reemplazarse (o complementarse) por una función de distancia entre barrios; hace falta primero completar coordenadas para los ~110 barrios de `Zonas_Barrios` sin punto (hoy sólo 48 tienen centroide en `PPP_Geo`). Preguntar al dueño si la regla va en backend (función SQL) o en el front antes de tocar nada.

### Consultas usadas (resumidas)
- Unión NP-tanda: `select np,tanda,cod,fecha_entrega from "PPP_Entregados_Meta" where tanda<>'' union select np,tanda,cod_cliente,fecha_salida::text from "Facturacion_NP" union select distinct np,tanda,cod_cliente,fecha_salida from "Entregas_Virgilio"` (2.898 pares; 0 discrepancias de tanda entre Meta y Facturación en 1.099 NP comunes).
- Barrio por cliente: `select cod, lower(unaccent(barrio)), zona, direccion from "PPP_Programacion_Diaria"`; `select cod_cliente, regexp_replace(sucursal_entrega,'^.*-\s*','') from lk_pedidos_match`; `select distinct on (contraparte_codigo) contraparte_codigo, contraparte_localidad, contraparte_cp from isis_lk.documentos order by contraparte_codigo, fecha desc` (ídem `isis_ch`).
- Centroides: `select lower(unaccent(split_part(dir_key,'|',2))), avg(lat), avg(lng), count(*) from "PPP_Geo" group by 1`.
- Zonas: `select barrio_norm, zona from "Zonas_Barrios"` (con alias normalizados a mano: p.patricios→parque patricios, villa soldati→soldati, v.crespo→villa crespo, etc.).
- Co-ocurrencias, haversine y percentiles calculados en Python sobre esos extractos (scripts en el scratchpad de la sesión: `analisis.py`, `analisis2.py`).

**Números clave**

COBERTURA
NP-tanda válidas 2.454 | tandas (empresa+código) 1.018 | con ≥2 clientes 359 | con ≥2 barrios conocidos distintos 117
NP con barrio 1.247 (Programación 494, lk_pedidos_match 547, ISIS fiscal 206) | sin barrio 1.207 = clientes del interior (hub de transporte desconocido, ~80 % Zona 1 según Programación)

MATRIZ ZONA x ZONA — MISMA TANDA (359 tandas multi-cliente; celda = tandas con ambas; diagonal = tandas con la zona; Int = interior/hub)
        Z1   Z2   Z3   Z4   Z5   Z6   Z7  Ret  Int
Z1      76   13    9    5    3    2    .    3   43
Z2      13   67    8    4    .    6    2    6   27
Z3       9    8   37    2    3    3    .    4   18
Z4       5    4    2   32    1    2    .    3    9
Z5       3    .    3    1   29    9    1    4   10
Z6       2    6    3    2    9   34    7    6    4
Z7       .    2    .    .    1    7   13    1    2

MATRIZ — CAMIÓN-DÍA ESTRICTO (mismo nro + misma fecha, ≥2 tandas, 224 grupos)
        Z1   Z2   Z3   Z4   Z5   Z6   Z7  Ret  Int
Z1      75   23   15    6    7    7    1    8   58
Z2      23   66   10    5    8    6    1    6   49
Z3      15   10   31    3    5    6    4    3   25
Z4       6    5    3   30    5    .    .    1   17
Z5       7    8    5    5   31   10    4    5   15
Z6       7    6    6    .   10   29    7    8   12
Z7       1    1    4    .    4    7   11    2    5

PARES LEJANOS (misma tanda, ene–sep 2026)
Núñez/Belgrano/Colegiales ↔ Lugano/Soldati/Pompeya: 0 | Palermo↔P.Patricios: 1 (9,3 km)
Constitución ↔ Devoto/V.del Parque: 0 | Constitución↔V.Pueyrredón 1 (11,3 km) | Constitución↔V.Urquiza 1 (10,4 km)
Mismo camión-lote (tandas separadas): Palermo+Soldati 5, Belgrano+Soldati 3

DISTANCIAS — TANDAS (117 con ≥2 barrios conocidos)
dmax entre paradas: p50 8,1 | p75 14,3 | p90 21,6 | p95 29,9 | máx 42,5 km
dmax al depósito:   p50 11,3 | p75 20,5 | p90 24,8 | máx 42,3 km
% tandas con dmax ≤ 5 km 23 % | ≤ 8 km 50 % | ≤ 10 km 59 % | ≤ 12 km 66 % | ≤ 15 km 76 % | ≤ 20 km 88 %
Sólo tandas que mezclan Z1/Z2/Z3 (27, sin A79A): dmax 1,7–12,3 km, mediana ≈ 6,5 km → 100 % ≤ 12,3 km, 89 % ≤ 10 km
Pares de barrios en misma tanda por par de zonas (n / mediana / máx km): Z1-Z1 11/1,9/6,3 · Z2-Z2 21/5,3/9,8 · Z1-Z2 15/3,3/11,3 · Z1-Z3 9/6,2/8,1 · Z2-Z3 8/6,9/12,3 · Z3-Z5 3/4,1/7,4 · Z5-Z6 14/11,7/18,5 · Z2-Z6 7/12,4/29,6 · Z1-Z4 6/15,1/23,2 · Z6-Z7 13/17,8/38,2 · Z2-Z4 4/19,0/25,0
Camiones-lote (132): dmax p50 13,5 | p75 24,5 | p90 34,0 | máx 65,4

TOP 10 TANDAS EXTREMAS (dmax km): C05A Núñez+Pilar 42,5 · A79A Soldati+V.Ballester+Flores+Berazategui 39,5 (2 fechas, sospechosa) · C90D Pilar+V.Lynch 38,2 · B59A Campo de Mayo+E.Echeverría 31,7 · C01B Guernica+Mataderos 31,2 · B46A Balvanera+Burzaco+San Martín 30,7 · D32C(Chef) J.C.Paz+Palermo 29,6 · C35A Hurlingham+Pilar 29,2 · C03L Berazategui+Recoleta 25,0 · D47B Microcentro+Soldati+Temperley+Monte Grande 25,0

CENTROIDES DE ZONA (km): dist. al depósito Z3 2,3 · Z1 7,5 · Z2 8,7 · Z6 11,7 · Z5 14,9 · Z4 19,7 · Z7 23,8 | entre zonas: Z1-Z2 7,1 · Z1-Z3 6,0 · Z2-Z3 6,4 · Z6-Z7 12,1 · Z1-Z4 12,9 · Z5-Z6 13,8 · Z2-Z6 14,5 · Z2-Z4 18,8 · Z4-Z5 32,5 · Z4-Z7 43,1
DÍAS 2026 con reparto 149: Z1 84 · Z2 75 · Z5 49 · Z4 44 · Z6 43 · Z3 32 · Z7 16 (Z1 subestimado: interior sin hub)
TOP PARES DE BARRIOS (misma tanda): Pompeya–Soldati 6 · Flores–Soldati 3 · Balvanera–Constitución 3 · Balvanera–San Martín 3 · Bernal–Temperley 2 · Lanús–Quilmes 2 · Flores–Recoleta 2 · Flores–Palermo 2 · Flores–Mataderos 2 · Constitución–Microcentro 2 · Constitución–Soldati 2 · Chilavert–San Martín 2 · San Martín–Tigre 2 · Ciudadela–Mataderos 2 · Hurlingham–San Justo 2 · Martínez–Morón 2 · Monte Grande–Temperley 2 · P.Patricios–Soldati 2 · Flores–P.Patricios 2

**Caveats.** - 49 % de las NP históricas (1.207) son de clientes del interior que se entregan en un expreso/transporte cuya dirección vive en el padrón LK (sin acceso). Quedan como "Int" sin coordenadas; por Programación se sabe que ~80 % de esos hubs están en Zona 1 (Soldati/Pompeya/P.Patricios), así que Z1 está subrepresentada en las matrices y en "días con Z1".
- Barrio por cliente = moda por código; un cliente con varias sucursales (p.ej. 1792 Colegiales/V.Crespo/Almagro, 2444 Soldati/Tortuguitas) se asignó a la más frecuente. 206 NP usan domicilio FISCAL de ISIS (puede diferir de la entrega). Códigos de cliente de LK y Chef se trataron por separado (empresa por rango de NP: <50000 = Chef).
- Coordenadas: 48 barrios con centroide real de PPP_Geo; ~50 barrios (Caballito, Colegiales, Devoto, Núñez, Microcentro, Lanús, Lomas, Morón, Hurlingham, Munro, San Isidro, Pilar, etc.) con coordenadas aproximadas de conocimiento general (error ±1 km; PPP_Geo tiene 118 direcciones, Zonas_Barrios ~110 barrios sin punto). Distancias son en línea recta (haversine), no de ruta.
- Los códigos de tanda se repiten entre LK y Chef (29 colisiones); se separaron por empresa. Algunas tandas tienen NP con 2 fechas de entrega (A79A) → posible reuso de código o entrega parcial; los datos de `PPP_Entregados_Meta` vienen del Sheet del dueño y pueden tener errores de carga (p.ej. Burzaco cargado como Zona 2 en Programación).
- "Camión del día": el número (letra+NN) suele abarcar 1–3 fechas, así que la co-ocurrencia por camión es evidencia débil; se dio la versión estricta (mismo nro + misma fecha).
- Muestra chica para pares raros: sólo 27 tandas mezclan zonas de Capital y 117 tienen ≥2 barrios conocidos; los percentiles se mueven con pocos casos. El umbral 10–12 km es una lectura de lo observado, no una regla explicitada por el dueño: validar con él antes de implementarla, y preguntar si va en backend (función SQL) o en el front.
- No se modificó nada en Supabase ni en el repo; sólo SELECT.
