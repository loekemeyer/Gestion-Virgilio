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

**2a. El punto medio.** Dejar de truncar en `·`, o restringirlo a `deposito <> 'insumos'`.
Hay que decidir con el dueño qué significa `·` (parece separador de variante). Afecta 14
códigos / 33 filas. **Es el único punto del plan que necesita una decisión de negocio.**

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

### Etapa 4 — El front

`codBase()` de `index.html` (67 call sites) pasa a ser lo que dice el protocolo del repo:
una duplicación de UX de la regla del backend, no una quinta regla. Y el payload del PKC
(`index.html` ~10851) deja de mandar el código crudo con sufijo.

**Va última, y sólo cuando las etapas 1-3 estén hechas**: con el backend garantizado, que el
front mande sucio deja de ser un problema de integridad y pasa a ser sólo cosmético. Al
revés (tocar el front primero) se pierde la red de abajo.

---

## 4. Orden, riesgo y cuándo

| etapa | toca escritura | cambios medidos | cuándo |
|---|---|---|---|
| 0 · centinelas | no | 0 | **ya** |
| 1 · fusionar los 3 idénticos | no | **0** (verificado) | **ya** |
| 2a · punto medio en `gv_cod_stock` | sí (indirecto) | 14 cód / 33 filas | necesita decisión del dueño + ventana |
| 2b · ceros en `gv_cod_stock` | sí (indirecto) | 43 cód | ventana |
| 3 · `gv_cod_canon` única | sí | a medir en su momento | ventana |
| 4 · front | sí | — | después de 1-3 |

**Recomendación: hacer 0 y 1 ya** (riesgo medido = cero, y la 0 es lo único que corta el
ciclo de que el problema vuelva por un lugar nuevo). **2, 3 y 4 en ventana**, de a una, con
la medición delante.

Lo que NO hay que hacer: las 6 etapas juntas "porque total es el mismo tema". Cada una tiene
su propia verificación y su propio rollback.
