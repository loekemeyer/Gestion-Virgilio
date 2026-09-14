# Plan "A" — una sola definición de código canónico

**Escrito el 2026-09-14 (v17.44), después de aplicar la opción B.** Pedido del dueño:
*"medí el costo de A y plan de implementación contemplando que el depósito está en
operación ahora y no quiero que nada se rompa"*.

Problema de fondo en la auditoría: *"No existe UNA definición de código canónico: 5 reglas
distintas repartidas en 25 objetos"* (`github_repo_problemas`, severidad alto, abierto).

---

## 1. Lo que ya se hizo (opción B, v17.44) — y qué NO arregló

`fn_canon_cod_art` separa el sufijo de empresa antes de buscar la grafía. Eso destrabó la
resolución de grafía para los 4 duales, que estaba de hecho apagada.

**Sobre los datos de hoy cambia 0 códigos de 392.** Es una garantía contra la variante
sucia futura (`0437E LK`, `437e lk`), no un cambio de comportamiento.

Lo que B **no** toca: las otras 5 canonizadoras siguen dando resultados distintos entre sí.

---

## 2. El costo medido de A

### 2.1 Superficie

**73 objetos** de `public` tocan canonización de código de artículo:

| | funciones | vistas |
|---|---|---|
| Copian el regexp **a mano** | 19 | 6 |
| Llaman a `gv_cod_stock` | 8 | 14 |
| Llaman a otra canonizadora | 16 | 10 |

De los 25 que copian el regexp a mano, **sólo 2 sacan el sufijo de empresa**
(`gv_cod_stock` y `trg_normalizar_empresa_stock`). Los otros 23 no.

### 2.2 Cuánto difieren DE VERDAD

Corriendo las 6 canonizadoras sobre los **520 códigos crudos reales** (campo 2 del `texto`
de todo evento PKC/CP + todo `cod_art` distinto de `Movimientos_Stock`):

| par | códigos en desacuerdo |
|---|---|
| `norm_cod` vs `canon_cod` | **0** |
| `norm_cod` vs `cob_norm_cod` | **0** |
| `gv_cod_stock` vs `norm_cod` | 24 |
| `canon_cod_art_val` vs `resolver_equiv` | 34 |
| `canon_cod_art_val` vs `norm_cod` | 43 |
| `gv_cod_stock` vs `canon_cod_art_val` | 67 |

**`norm_cod`, `canon_cod` y `cob_norm_cod` son la MISMA función escrita tres veces.**
Unificarlas es gratis y verificable: 0 diferencias sobre los 520.

O sea que las 6 canonizadoras son en realidad **4 comportamientos**, no 6.

### 2.3 Por qué difieren los 4 que quedan (clasificado sobre los códigos reales)

| # | motivo | códigos | qué pasa |
|---|---|---|---|
| C | resolver grafía contra `OC_Maximos` | **43** | `007`: `canon_cod_art_val`→`007`, `gv_cod_stock`/`norm_cod`→`7` |
| E | punto medio `·` (insumos) | **14** | `FLEJE ESPIRAL·1`: `gv_cod_stock`→`FLEJE ESPIRAL` (pierde la variante) |
| D | resolver `Equivalencias_Codigos` | **12** | `727EN`: sólo `resolver_equiv` lo lleva a `727E` |
| A | sufijo de empresa | **8** | `437E LK`: sólo `gv_cod_stock` lo lleva a `437E` |
| B | variante `L` | **2** | `438EL`: `gv_cod_stock` y `resolver_equiv`→`438E`, los demás no |

**El hallazgo incómodo: la función "más completa" es la MENOS correcta en 2 de los 5 grupos.**

- Grupo C: `gv_cod_stock` saca los ceros a la izquierda **sin volver a resolver contra el
  catálogo**, así que produce `7` — un código que no existe en `OC_Maximos` (donde es `007`).
  Sirve como **clave de join** (si los dos lados pasan por ella, `7 = 7`), no como **valor**.
  Cualquier consumidor que compare `gv_cod_stock(a)` contra un `b` crudo se rompe.
- Grupo E: `gv_cod_stock` corta en `·` y **colapsa 10 insumos distintos en 4 claves**
  (33 filas: los 4 flejes de Chef cuentan como uno). Registrado aparte como problema
  *"gv_cod_stock trunca el código en el punto medio…"* (medio, abierto). Hoy es **latente**
  — `vista_stock_procesada` muestra el código entero — pero es una bomba para el próximo
  consumidor que agrupe por esa clave.

**Conclusión de la medición: A NO es "hacer que todos llamen a `gv_cod_stock`".**
Esa función tiene dos defectos propios. A es: **definir primero cuál es la regla correcta,
arreglar la función canónica, y recién entonces migrar los consumidores.**

---

## 3. Plan de implementación, con el depósito operando

Regla que gobierna todo el plan: **ningún paso se aplica sin haber medido antes que cambia
0 filas, o sin saber exactamente cuáles cambian y por qué.** Es lo que se hizo en B (392
códigos, 0 cambios) y es lo que hizo que se pudiera aplicar un martes a la mañana.

### Etapa 0 — Centinela primero (riesgo cero, sin tocar nada)

Antes de mover un solo consumidor, una vista que avise cuándo las canonizadoras divergen y
cuándo aparece un objeto nuevo con el regexp copiado a mano. Sin esto, cada etapa siguiente
es a ciegas.

```sql
create or replace view public.gv_canon_divergencias with (security_invoker = true) as ...
create or replace view public.gv_canon_sin_funcion   with (security_invoker = true) as ...
```

La segunda es la que corta el ciclo de las ~50 sesiones: hoy no hay nada que avise que
alguien agregó el objeto n.º 74 con su propio regexp.

**Se puede hacer hoy mismo. No toca ningún camino de escritura.**

### Etapa 1 — Fusionar los tres idénticos (riesgo cero, ya medido)

`canon_cod` y `cob_norm_cod` pasan a ser envoltorios de `norm_cod`. Verificado: 0
diferencias sobre los 520 códigos.

- Toca: 9 funciones + 13 vistas, **todas de sólo lectura**.
- Verificación: `md5` del resultado de cada vista antes y después. Tienen que dar igual.
- Rollback: una línea por función.
- **No toca ningún trigger ni ninguna escritura.** Se puede aplicar con operarios pickeando.

### Etapa 2 — Arreglar los dos defectos de `gv_cod_stock`

Dos cambios independientes, uno por vez:

**2a. El punto medio — DESCARTADA. Decisión del dueño (Thomas, 2026-09-14), no revisitar.**
Textual: *"ese punto no significa nada. No hay tanto quilombo con los códigos de insumos,
dejalo ahí"*. `gv_cod_stock` sigue truncando en `·` y los 4 flejes de Chef siguen colapsando
en una clave. Medido que es **inocuo hoy**: ningún consumidor vivo agrupa por esa clave —
`vista_stock_procesada` muestra el código entero, y `gv_planimetria_celda` y
`gv_lugar_articulo` tienen 0 filas con `FLEJE`. Queda **vigilado** por el motivo `B` de
`gv_canon_divergencias` (14 códigos, línea de base al 14/09): si ese número sube, o si algún
día aparece un consumidor que agrupe por `gv_cod_stock`, ahí se ve. Problema 169 → `descartado`.

**2b. Los ceros a la izquierda.** Que resuelva contra `OC_Maximos` como hace
`canon_cod_art_val`, en vez de pelar ceros a ciegas. Afecta 43 códigos.

Los dos se miden igual que B: correr vieja vs nueva sobre los 520 y listar las diferencias
**una por una** antes de aplicar. Si una diferencia no se explica, no se aplica.

Riesgo: `gv_cod_stock` la usan `vista_stock_procesada` (matview) y `gv_lugar_item_guardar`
(que **escribe**). Esta etapa **no** va un día de semana a la mañana — va sábado o después
de las 19:00, con `vista_stock_procesada` refrescada y comparada contra su foto previa.

### Etapa 3 — Una sola función canónica

Recién acá existe una función que hace las 5 cosas bien. Se llama `gv_cod_canon(p_cod)` (nombre
nuevo a propósito: no se pisa ninguna de las que ya están en uso) y las 6 existentes pasan a
ser envoltorios suyos.

Loop mecánico, el mismo que se usó el 12/09 para renombrar las 3 tablas PPP:
`pg_get_functiondef` → `replace()` → `execute`, **todo en UNA transacción** con el nombre de
la función en el `raise exception`. Si una no compila, no queda nada a medias.

⚠ Y lo que ese día enseñó: después del loop hay que **llamar de verdad a cada función**.
Postgres no revalida el cuerpo de una función hasta la primera llamada.

### Etapa 4 — El front — **DESCARTADA. Habría roto los duales.**

Decía: *"el payload del PKC deja de mandar el código crudo con sufijo"*. **Medido el 14/09, eso
rompe el pipeline de los 4 duales.**

De los **120 eventos PKC con sufijo, 114 tienen el campo 6 (empresa) VACÍO** — sólo 6 la traen
ahí. Y el reconciliador lo confirma: `reconciliar_pipeline_stock_etapa1` toma la empresa del
campo 6 **sólo si viene y es única**; si no viene, el código entra entero a `Movimientos_Stock`
y ahí `trg_normalizar_empresa_stock` lo separa (`437E LK` → `cod_art='437E'`, `empresa='LK'`).

→ **El sufijo del código NO es "una quinta regla del front": es el CANAL por el que viaja la
empresa.** Sacarlo sin llenar el campo 6 primero pierde la empresa en el 95% de los eventos.

Y llenar el campo 6 tampoco aporta: el front sólo sabe la empresa **por ese mismo sufijo**, así
que sería derivarla en el front para volver a mandarla — duplicar en el front lo que el backend
ya hace bien desde la v17.44. El protocolo del repo dice exactamente lo contrario.

`codBase()` (67 call sites) queda como está: es **display**. Sobre un código que viene del
backend ya canonizado es no-op.

**Conclusión: la etapa 4 no se hace.** Igual que 2a y 2b, el plan original sobreestimó el
problema: el sufijo está resuelto en el backend y funciona.

---

## 5. Lo que QUEDA de verdad: los candados que faltan (medido el 14/09)

Después de descartar 2a, 2b y 4, lo único que sigue abierto del problema de fondo es esto.

**El riesgo de los 22 objetos con regexp propio NO es que busquen con su propia regla** — es qué
pasa con lo que **escriben**. De los 22, **8 escriben**, y lo que importa es si la tabla destino
tiene candado:

| tabla destino | candado | quién escribe ahí |
|---|---|---|
| `Movimientos_Stock` | ✅ `fn_canon_cod_art` + `trg_normalizar_empresa_stock` | etapa1, etapa2, `_rt`, `aceptar_conteo`, `faltante_resolver` |
| `Capacidad_Sector` | ✅ `fn_canon_col_cod` | las RPC del mapa |
| `GV_Lugar_Item` | ✅ `fn_canon_col_cod` (v17.51) | las RPC del mapa |
| `Ordenes_Compra` | ✅ `fn_canon_col_codigo` | — |
| **`stocks_carga_rapida`** | ❌ | `refresh_stocks_carga_rapida`, `actualizar_saldo_trigger` |
| **`OC_Maximos`** | ❌ | (el **catálogo madre**) |
| **`Correcciones_Pedido`** | ❌ | `corregir_pedido_secundario_auto` |
| `Conteo_Stock` · `Faltantes_Revisados` | ❌ | `aceptar_conteo`, `faltante_resolver` |

**Lo que escribe a `Movimientos_Stock` ya está cubierto**: aunque la función busque con su regexp,
lo que guarda sale canonizado por los dos triggers. Ése es el 62% de los escritores.

**Cuánto cambiaría poner el candado que falta** (`canon_cod_art_val` vs. lo guardado):

| tabla | filas | cambiarían |
|---|---|---|
| `stocks_carga_rapida` | 399 | **22** |
| `OC_Maximos` | 354 | **0** |
| `Correcciones_Pedido` (las 2 columnas) | 274 | **0** |
| `Conteo_Stock` | 2 | 0 |
| `Faltantes_Revisados` | 0 | 0 |

**Ninguno de los tres que importan es aplicable a ciegas:**

- **`OC_Maximos`** cambia 0 filas hoy, pero el candado sería **recursivo**: `fn_canon_col_cod` →
  `canon_cod_art_val` → *busca en `OC_Maximos`*. No es recursión infinita (es un `SELECT`), pero
  **cambia el alta de artículos**: dar de alta `0999` con `999` ya existente pasaría a chocar
  contra la PK en vez de crear una segunda grafía. Probablemente sea lo deseado — pero es una
  decisión de negocio, no una limpieza.
- **`stocks_carga_rapida`** son **22 filas** que cambian, y es una tabla **caché** que refresca
  `refresh_stocks_carga_rapida`. Canonizarla por trigger puede desalinearla de su fuente.
  Hay que mirar las 22 una por una antes de nada.
- **`Correcciones_Pedido`** tiene **dos** columnas de código, y `fn_canon_col_cod` sólo toca
  `NEW.cod`. Haría falta una función nueva — o sea **más proliferación**, justo lo que este plan
  quiere evitar. Conviene un trigger genérico parametrizado por `TG_ARGV`, no uno por tabla.

`Conteo_Stock` (2 filas) y `Faltantes_Revisados` (0) no mueven la aguja: poner el candado ahí es
gratis pero no protege nada hoy.

**Va última, y sólo cuando las etapas 1-3 estén hechas**: con el backend garantizado, que el
front mande sucio deja de ser un problema de integridad y pasa a ser sólo cosmético. Al
revés (tocar el front primero) se pierde la red de abajo.

---

---

## 5. Cruce con Planimetría (leído después: los dos handoffs del 14/09)

`docs/HANDOFF-PLANIMETRIA-20260914.md` y `docs/HANDOFF-PLANIMETRIA-20260914-SESION-LUIS.md`
describen el mapa de góndolas. **Tocan este mismo problema y conviene leerlos juntos con esto.**

### 5.1 La regla 6 del handoff de Thomas dice menos de lo que pasa

Dice *"la RPC canoniza con `canon_cod_art_val`"*. Es verdad a medias: **`gv_lugar_item_guardar`
usa las DOS canonizadoras, y en mitades distintas de la misma función**:

- escribe con `v_cod := canon_cod_art_val(p_cod)` → **estricto**, y el `on conflict (sector, cod)`
  compara **texto crudo**;
- borra el espejo con `gv_cod_stock(cod) = gv_cod_stock(v_cod)` → **laxo** (matchea `7` con `007`,
  y además pela la variante `L` y el sufijo de empresa).

O sea: **borrar sí encuentra la grafía vieja, pero escribir no la pisa — crea una SEGUNDA fila**
en `Capacidad_Sector` para el mismo artículo y el mismo sector. Que es exactamente la divergencia
del problema 84 que la RPC debería evitar, y el mismo mecanismo que duplicó el picking de `D72C`.

**Estado: LATENTE, no activo.** Medido el 14/09: 0 filas duplicadas por
`(sector, gv_cod_stock(cod))` en las dos tablas, y 0 filas con una grafía distinta de la que
devuelve `canon_cod_art_val`. Hoy no hay con qué dispararlo.

### 5.2 El hueco que lo puede activar

**`Capacidad_Sector` tiene trigger de canonización** (`trg_canon_capacidad_sector_cod` →
`fn_canon_col_cod` → `canon_cod_art_val`). **`GV_Lugar_Item` no tiene ninguno** — y es la tabla
MADRE del mapa, la que lee el picking vía `gv_lugar_articulo`.

El espejo está protegido y la fuente no. Depende 100% de que todo el mundo entre por la RPC, y el
handoff documenta que **se escribió a mano por SQL**.

**Fix medido, NO aplicado:** ponerle a `GV_Lugar_Item` el mismo trigger que ya tiene
`Capacidad_Sector`. Sobre las 790 filas actuales **cambian 0**. No se aplicó por dos razones:
había dos sesiones editando esa tabla ese día, y `canon_cod_art_val` resuelve contra `OC_Maximos`
(catálogo de artículos) — hoy `GV_Lugar_Item` tiene **0 filas con `clase='insumo'`**, pero si entra
una la canonizaría contra el catálogo equivocado. Va junto con alinear las dos mitades de la RPC.

### 5.3 Y una tercera regla en el mismo módulo

`gv_lugar_articulo` (lo que lee el picking) usa **regex propio**; `gv_planimetria_celda` (lo que se
dibuja) usa **`gv_cod_stock`**. **Lo que se dibuja y lo que lee el picking se canonizan distinto.**
Esa es otra vía por la que el problema 84 puede fabricar divergencias solo.

### 5.4 Lo que el handoff de Luis ya había anotado, y es esto

§6, textual: *"`634` y `634E` son el mismo artículo con el stock partido en dos grafías (12 cajas
en el pelado, 0 en el que tiene nombre). Eso no es planimetría: es `gv_codigos_multigrafia`, y es
más grande que todo lo demás de esta lista."* **Coincide**: es este problema, visto desde el mapa.

### 5.5 Consecuencia para el orden de las etapas

La etapa **2b** (que `gv_cod_stock` resuelva contra el catálogo en vez de pelar ceros a ciegas)
**sube de prioridad**: `gv_cod_stock` está en un camino de ESCRITURA vivo
(`gv_lugar_item_guardar`), no sólo en lecturas. Y las etapas 0 y 1 no cambian.

---

## 4. Orden, riesgo y cuándo

| etapa | toca escritura | cambios medidos | cuándo |
|---|---|---|---|
| 0 · centinelas | no | 0 | **ya** |
| 1 · fusionar los 3 idénticos | no | **0** (verificado) | **ya** |
| ~~2a · punto medio~~ | — | 14 cód | **DESCARTADA** — decisión del dueño 14/09, no revisitar |
| 2b · ceros en `gv_cod_stock` | sí (indirecto) | 43 cód | ventana |
| 3 · `gv_cod_canon` única | sí | a medir en su momento | ventana |
| 4 · front | sí | — | después de 1-3 |

> **Estado al 14/09 (v17.46): las etapas 0 y 1 están HECHAS** (`sql/gv_canon_centinelas_v1746.sql`,
> §3.fe). La 1 se hizo por la mitad a propósito: `cob_norm_cod` fusionada, `canon_cod` no —
> está dentro del índice único `gv_precios_cliente_canon_uk` y ya es idéntica, así que la
> vigila la fila `Z` del centinela. **La 2a está DESCARTADA** por decisión del dueño.
> Quedan la 2b, la 3 y la 4.

**Recomendación original: hacer 0 y 1 ya** (riesgo medido = cero, y la 0 es lo único que corta el
ciclo de que el problema vuelva por un lugar nuevo). **2, 3 y 4 en ventana**, de a una, con
la medición delante.

Lo que NO hay que hacer: las 6 etapas juntas "porque total es el mismo tema". Cada una tiene
su propia verificación y su propio rollback.

---

## 6. Las tres decisiones del 14/09 sobre los candados que faltaban

### 6.1 `OC_Maximos` — **NO ahora.** Decisión del dueño

Textual: *"lo de OC_Maximos de momento no, entiendo que se puede comer códigos válidos a futuro
eso, y si la posibilidad de que en la estructura actual joda es 0, dejémoslo y lo vemos más
adelante"*.

Exacto: cambia 0 filas hoy, pero el candado **cambiaría el alta de artículos** — dar de alta
`0999` con `999` ya existente pasaría a chocar contra la PK en vez de crear una segunda grafía.
Eso puede comerse un código válido si alguna vez dos códigos legítimos difieren sólo en un cero.
Es decisión de negocio, no limpieza. **Queda para más adelante, sin hacer.**

### 6.2 `stocks_carga_rapida` — **SALE DE LA LISTA. No tiene problema propio**

Estaba en la lista como "399 filas, 22 cambiarían". **Medido: no es una tabla sin candado que
haya que candar — es un ESPEJO FIEL de `vista_stock_procesada`.**

- `refresh_stocks_carga_rapida` toma `cod` y `cod_base` de `vsp` = la matview;
- la matview tiene **las mismas 22** filas no canónicas (401 en total);
- la caché matchea **401 de 401** con la matview por `cod`;
- el refresh hace **`DELETE FROM` + reinsert**, no upsert.

→ **Poner un trigger ahí sería un error de diagnóstico.** Rompería la correspondencia 401 = 401
con su fuente, y como el refresh borra y reinserta, la caché quedaría **permanentemente** distinta
de la matview: cualquier join por `cod` entre las dos se cae.

Lo que sí es cierto: **el front lee `stocks_carga_rapida.cod`** (pantalla de Stock y badge), así
que esos 22 códigos se ven como `7` en vez de `007`. Es el mismo síntoma cosmético de la etapa 2b
—ya descartada— pero ahora se sabe que además llega a la pantalla de Stock, no sólo a 3 vistas de
análisis. El arreglo sigue siendo el de 2b (caro: `gv_cod_stock` pasaría a `STABLE`, 14 vistas +
matview) o tocar la matview (DROP + CREATE con CASCADE, que ya mordió dos veces). **Sin hacer.**

### 6.3 `Correcciones_Pedido` — el diseño, PROBADO pero NO aplicado

El problema era: tiene **dos** columnas de código y `fn_canon_col_cod` sólo toca `NEW.cod`, así que
haría falta una función nueva — o sea **más proliferación**, justo lo que este plan quiere evitar.

**La salida es un trigger genérico parametrizado por `TG_ARGV`**, que sirve para cualquier tabla y
cualquier cantidad de columnas:

```sql
create or replace function public.fn_canon_cols()
 returns trigger language plpgsql as $$
declare
  v_col text; v_rec jsonb := to_jsonb(NEW); v_val text;
begin
  foreach v_col in array TG_ARGV loop
    v_val := v_rec ->> v_col;
    if v_val is not null and btrim(v_val) <> '' then
      v_rec := jsonb_set(v_rec, array[v_col], to_jsonb(public.canon_cod_art_val(v_val)));
    end if;
  end loop;
  NEW := jsonb_populate_record(NEW, v_rec);
  return NEW;
end $$;

create trigger trg_canon_correcciones_pedido
  before insert or update of cod_principal, cod_secundario on public."Correcciones_Pedido"
  for each row execute function public.fn_canon_cols('cod_principal','cod_secundario');
```

**Probado el 14/09 en una transacción con `ROLLBACK`:**

| entró | quedó |
|---|---|
| `'  66 '` | **`066`** |
| `'7'` | **`007`** |
| `'599E'` | `599E` (sin cambio) |
| `'0437e lk'` | `0437E LK` ⚠ |

Y las 274 filas existentes: **0 desalineadas** — es `BEFORE INSERT OR UPDATE OF`, sólo actúa al
escribir, no reescribe lo viejo.

**Lo que hay que saber antes de aplicarlo — tres cosas:**

1. ⚠ **Hereda la limitación de `canon_cod_art_val`: NO resuelve el sufijo de empresa.** `0437e lk`
   quedó en `0437E LK`. El sufijo lo manejan `fn_canon_cod_art` (v17.44) y
   `trg_normalizar_empresa_stock`, que son de `Movimientos_Stock`. Para una tabla que pueda recibir
   códigos con sufijo, este trigger **no alcanza**. Para `Correcciones_Pedido` (códigos de pedido,
   sin sufijo) alcanza.
2. **Cuesta más que asignar una columna**: `to_jsonb` + `jsonb_populate_record` por fila. En una
   tabla de alta escritura (`Movimientos_Stock`) habría que medirlo antes; en las de baja no importa.
3. **Las columnas nombradas tienen que ser `text`.** `to_jsonb` sobre otro tipo rompería la fila.

**El beneficio de fondo**: esta función sola reemplaza a las **cinco** que hoy hacen lo mismo con
distinto nombre de columna — `fn_canon_col_cod`, `fn_canon_col_cod_art`, `fn_canon_col_codigo`,
`fn_canon_col_articulo`, `fn_canon_col_cod_art_quoted`. Ésa es la migración que de verdad baja la
proliferación, y es el paso que queda del problema de fondo.
