# HANDOFF — Planimetría de góndola, 2026-09-14 · dos sesiones en paralelo

> **Para quien siga.** Escrito por Claude en la sesión de **Thomas**
> (`https://claude.ai/code/session_01JLTzJMkpksfyKDubMVn636`) para reconciliarse con la sesión
> **"Luis planimetría 14.09"**. Las dos tocaron lo mismo el mismo día, **se pisaron una vez**, y
> este archivo es lo que hay que leer antes de seguir. App en **v17.33** al escribirlo.
>
> Antes de tocar nada: `CLAUDE.md`, `GUIA-PROYECTO.md` (nota v17.31) y
> `docs/SUPABASE-GESTION-VIRGILIO.md` **§3.eq**.

---

## 1. En 30 segundos

| | |
|---|---|
| Mapa vivo | **`GV_Lugar` + `GV_Lugar_Item`** → vista `gv_lugar_articulo` (lo que usa el picking) |
| Capacidad (cajas por celda) | **`Capacidad_Sector`** — todavía separada; `GV_Lugar_Item.cajas_max` sigue casi todo en NULL |
| Las dos juntas, dibujables | **`gv_planimetria_celda`** (v17.23) — una fila por celda × código, con la capacidad resuelta y un `estado` |
| Pantalla | **🗺️ Mapa de góndolas** (⚙️ Configuración) — dibuja **y edita** |
| `Planimetria` (tabla vieja) | **no la lee el picking** (v15.77) ni la escribe la app (v17.26). **No se borra**: la leen `gv_codigos_multigrafia` y `vista_nc_loeke_chef` |
| "Editar Planimetría" (pantalla) | **retirada** en la v17.31 |

**Números al 14/09 ~15:30 UTC** (mirar de nuevo antes de decidir, esto se mueve solo):
`GV_Lugar_Item` 790 filas · `Capacidad_Sector` 736 · `gv_gondola_divergente` **31**
(21 `solo_mapa` + 10 `solo_capacidad`; venía de 107) · celdas libres 49.

---

## 2. Qué hizo cada sesión

### Sesión de Thomas (esta)

| v | Qué |
|---|---|
| 17.23 | Vista **`gv_planimetria_celda`** + módulo **🗺️ Mapa de góndolas** (sólo lectura) |
| 17.25 | El mapa ocupa toda la pantalla; módulos de 5 en grilla; celda de altura fija |
| 17.28 | Los cuatro estados se distinguen de lejos; leyenda grande con el conteo de la góndola abierta |
| 17.31 | **El mapa se edita**: 3 RPC (`gv_lugar_item_guardar` / `_sacar` / `gv_lugar_orden`). Se retira "Editar Planimetría". 📍 Lugares pasa por las mismas RPC. **Problema 160** |
| 17.33 | Se traen 2 de los 10 códigos del 11/09 y se revierten 8 (ver §3). El espejo de capacidad deja de escribir filas vacías |

### Sesión de Luis (la otra)

| v | Qué |
|---|---|
| 17.26 | Borra las 7 funciones de **escritura** del editor viejo de Planimetría (**problema 85**) |
| 17.32 | Sube el **relevamiento del depósito** con la columna amarilla llena + `docs/relevamiento-lugares-deposito-20260911.md`. Ñ53 → 439E de Chef (**problema 88**). M34/M35/M36 con la **E** |
| — | **Problema 162, ABIERTO y `alto`**: esa misma v17.32 dejó sin lugar de góndola a **634, 635 y 636**, que son los que tienen el stock. Al escribir esto ya volvieron a M35/M35/M36 — **confirmarlo antes de darlo por cerrado** |

---

## 3. El choque, y cómo quedó

**Thomas preguntó por qué no se podían traer al mapa los 9 códigos que alguien cargó en la
planimetría vieja el 11/09 entre las 16:07 y las 16:13.** Se midió: los sectores existen, ninguno
de esos códigos tenía lugar en el mapa (era **alta**, no mudanza) y el modelo admite varios códigos
por celda (42 ya los tienen). **Nada fallaba**, así que se trajeron (10, contando 368E).

**Y sí chocaban** — pero eso no lo dice la base: lo dice la planilla del relevamiento que la otra
sesión subió esa misma tarde, **la única fuente que dice qué vio una persona parada delante de la
góndola**:

| Código | Iba a | Ahí hay |
|---|---|---|
| 233 | `G06` | 208 |
| 232 / 231 | `G07` / `G08` | 355 |
| 567 | `H60` | 592E |
| 537 | `C01` | 547 |
| 997E / 998E | `A65` | 396 + 556 |
| 368E | `H29` | 581 (y no está en la lista relevada) |

El `insert` no falla: **manda al operario a buscar un palo de amasar donde hay otra cosa**. Se
revirtieron los 8 con `gv_lugar_item_sacar`. Backups:
`zz_backups."GV_Backup_Lugar_Item_pre_v1731_20260914"` y `..."GV_Backup_Capacidad_pre_v1731_20260914"`.

**Quedaron los 2 que el relevamiento confirma:** `A60` estaba libre → **989E y 992E**. Entran como
`solo_mapa` (ámbar, "sin capacidad cargada"), porque la tabla vieja no traía cajas.

> **Lección para las dos sesiones:** que una celda *acepte* otro código no significa que *esté*
> libre. Antes de dar un lugar, mirar el relevamiento.

---

## 4. Reglas acordadas — NO volver a discutirlas

1. **Toda escritura del mapa va por RPC.** `gv_lugar_item_guardar(sector, cod, clase, cajas_max)` /
   `gv_lugar_item_sacar(sector, cod, clase)` / `gv_lugar_orden(sector, orden)`.
   ⚠ **Escriben `GV_Lugar_Item` Y `Capacidad_Sector` juntas.** Un `insert`/`delete` suelto a una
   sola —da igual si es desde el front o por SQL a mano— **fabrica una divergencia del problema
   84**: eso es exactamente lo que hacían los editores viejos (problema 160). Si hay que tocar a
   mano por SQL, usar las RPC igual: `select public.gv_lugar_item_guardar('M35','635E','articulo',5);`
2. **Sin número no hay fila de capacidad.** Si `cajas_max` es null, la RPC **borra** el espejo, y la
   celda queda en `solo_mapa` (ámbar). Una fila de capacidad vacía pintaba la celda de verde y
   escondía que falta cargarla.
3. **Si la planilla del relevamiento y la base se contradicen, manda la base** (Luis, 14/09). La
   planilla explica *por qué* algo quedó como quedó; no se vuelve a decidir con ella.
4. **Pero para saber si una celda está ocupada, la planilla es la mejor fuente** — es lo único que
   mira el depósito físico. Ver §3.
5. **`Planimetria` no se borra** y **no se escribe**. Es historia + la leen dos vistas.
6. **Los códigos de la góndola llevan su grafía canónica** (`066`, no `66`; `635E`, no `635` cuando
   el par con E es el que tiene nombre en el maestro). La RPC canoniza con `canon_cod_art_val`.

---

## 5. Lo que queda abierto

| # | Qué | Cómo se ve | Quién |
|---|---|---|---|
| **162** | 634/635/636 sin lugar de góndola tras la v17.32 | `select * from gv_planimetria_celda where gondola='M' and celda between 34 and 36;` | sesión de Luis — **alto**, confirmar que ya está |
| **84** | 31 celdas donde mapa y capacidad no coinciden | `select * from gv_gondola_divergente;` | el relevamiento contesta las 35 originales: **el patrón es que la capacidad quedó pegada al código viejo y el mapa al nuevo** (`E10` 225→312, `F49` 574→574E, `G13` 823→509, `G15` 509→256, `J44` 335→599E, `M10` 702→702E, `C10` 071→547, `C02` 601E→510T+581T). **No hay que elegir quién manda: hay que mover el `cajas_max`** con la RPC |
| **156** | 15 códigos siguen sólo en `Planimetria` | el propio mapa los lista arriba, con un botón para traerlos de a uno | 6 son de baja (071, 124, 580E, 592E, 702, 724), 2 tienen sufijo N (702EN, 727EN), `LIBRE` no es código. Los 7 que importan (231, 232, 233, 537, 567, 997E, 998E) **necesitan que el depósito diga en qué celda van** — las que decía la tabla vieja están ocupadas |
| — | `GV_Lugar_Item.cajas_max` sigue en NULL salvo lo nuevo | `select count(*) from "GV_Lugar_Item" where cajas_max is not null;` | cuando los 5 consumidores de `Capacidad_Sector` (generador de OC, `gondola_return_check`, conteo cíclico, `aceptar_conteo`, `vista_generador_oc`) lean `gv_planimetria_celda`, se borra el espejo de la RPC y `Capacidad_Sector` se retira |

---

## 6. Cómo mirar el estado sin abrir la app

```sql
-- el dibujo entero, una fila por celda × código
select * from public.gv_planimetria_celda where gondola = 'M' order by celda;
-- lo que no cierra
select * from public.gv_gondola_divergente;
-- lo que quedó sólo en la tabla vieja
select p.cod, p.sector from public."Planimetria" p
 where not exists (select 1 from public."GV_Lugar_Item" i
                    where gv_cod_stock(i.cod) = gv_cod_stock(p.cod) and i.activo);
```

Archivos: `sql/gv_planimetria_celda.sql` · `sql/gv_lugar_editar_v1731.sql` ·
`tests/pmap-gondolas.cjs` · `docs/relevamiento-lugares-deposito-20260911.md` ·
`docs/SUPABASE-GESTION-VIRGILIO.md` §3.eq.
