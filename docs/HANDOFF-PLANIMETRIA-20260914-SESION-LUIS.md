# HANDOFF — Planimetría de góndola · sesión de **Luis**, 2026-09-14

> **Complemento de `docs/HANDOFF-PLANIMETRIA-20260914.md`**, que escribió la sesión de Thomas.
> Ese cuenta el lado del **Mapa de góndolas**; éste cuenta el lado del **relevamiento del depósito
> y la tabla `Planimetria`**. Las dos sesiones trabajaron el mismo día sobre lo mismo y están
> reconciliadas. **Leer los dos.**
>
> Sesión: `https://claude.ai/code/session_01RdeUMNwTTmMyufP9LoCVTa` · app en **v17.40** al cerrar.

---

## 1. En 30 segundos

| | |
|---|---|
| Qué disparó todo | Luis: *"la tabla `Planimetria` sigue viva con data"* — y tenía razón |
| Qué se descubrió | El editor viejo escribía a una tabla que el picking dejó de leer en la v15.77. **Se perdió trabajo real**: 9 códigos cargados el 11/09 16:07–16:13 nunca llegaron al mapa |
| Qué lo destrabó | El **relevamiento del depósito** (xlsx) que subió Luis: la única fuente que dice qué vio una persona parada delante de la góndola |
| Dónde está ese archivo | `docs/relevamiento-lugares-deposito-20260911.xlsx` + su guía **`.md`** al lado |
| Estado del problema 84 | **31 → 15** divergencias. `solo_capacidad` en **CERO** |

**Números al 14/09, cierre de sesión** (volver a medirlos, se mueven solos):

```sql
select count(*) from public.gv_gondola_divergente;                  -- 15
select count(*) from public."GV_Lugar_Item";                        -- 790
select count(*) from public."Capacidad_Sector";                     -- 732
select count(*) from public."GV_Lugar_Item" where cajas_max is not null;  -- 6
```

---

## 2. Qué hizo esta sesión, versión por versión

| v | Qué |
|---|---|
| **17.26** | El editor viejo de Planimetría queda **sólo lectura** (se borran sus 7 funciones de escritura). Y `gv_gondola_divergente` se reescribe sobre `gv_planimetria_celda`: **decía 107, son 35** |
| **17.32** | Entra al repo el **relevamiento COMPLETADO** + su guía de lectura. **Ñ53 → 439E de Chef** (cierra el problema 88). M34/M35/M36 con la E |
| **17.36** | Arregla lo que rompió la 17.32: **634/635/636 se habían quedado sin lugar** (problema 162) |
| **17.38** | Se **mueve el `cajas_max`** al código que el depósito confirmó. Problema 84: **31 → 15** |

---

## 3. El relevamiento — lo que hay que saber antes de usarlo

**El archivo del repo era la versión ANTES de recorrer**, con la columna amarilla vacía. Luis subió
el bueno el 14/09: **41 respuestas escritas por quien caminó el depósito**, sobre 70 lugares en
conflicto. Las 29 sin contestar son los racks de insumos, excluidos a propósito.

⚠ **NO es la verdad de hoy.** Luis, textual: *"no la tomes como una revelación… ya la laburamos
antes y se hicieron correcciones que quedaron en el código pero no en el excel"*. **Si la planilla y
`GV_Lugar` / `GV_Lugar_Item` se contradicen, manda la base.** La guía `.md` lista los choques
conocidos para no rediscutirlos.

**Pero para saber si una celda está OCUPADA, la planilla es la mejor fuente.** Es lo único que mira
el depósito físico. Eso fue lo que frenó meter 8 códigos en celdas que ya tienen otra cosa.

⚠ **La celda U2 (A62) dice `355.06599999999997` y es un error de tipeo.** Son **dos códigos**
(`355, 066` escrito con punto en vez de coma). Y el primero **va `335`**, no 355 — confirmado por
Luis. Es lo que la base ya tiene. **A62 no se toca.** Si alguna vez se automatiza esa columna,
**leerla como texto**.

**Cómo leerlo sin Excel** (no hay `openpyxl` y el proxy no deja instalarlo): un `.xlsx` es un ZIP con
XML — `xl/sharedStrings.xml` + `xl/worksheets/sheet*.xml`, celdas con `t="s"` son índices contra los
strings compartidos. Con `zipfile` + `xml.etree` alcanza. **Ojo:** la columna de respuestas (`U`)
está **sólo en la hoja `A resolver`**; la hoja `Todos los lugares` trae el estado (`C`) y el artículo
cuando las tablas coinciden (`D`). Hay que cruzar las dos.

---

## 4. Tres lecciones que costaron caro

1. **Antes de renombrar un código, preguntarle al STOCK bajo qué grafía se mueve.** El maestro dice
   cuál *debería* ser; el picking usa la que *existe*. En M34/M35/M36 apuntaban a lados opuestos: el
   nombre está en `634E` y las 12 cajas en `634`. Renombrar el mapa dejó al código con stock sin
   sector — **problema 162, severidad alta**. Se arregló haciendo **convivir las dos grafías**.
   ```sql
   select v.cod_art, v.terminado,
          (select descripcion from vista_nombres_articulos n where n.cod = v.cod_art)
     from vista_saldos_stock v where gv_cod_stock(v.cod_art) in ('<cod>','<cod>E');
   ```
2. **Que una celda ACEPTE otro código no significa que esté libre.** Ver el handoff de Thomas §3.
3. **Al editar `index.html` por script, trabajar en BYTES.** Tiene un byte NUL adentro. Un
   `open(p,"w")` con un `encoding` que no banque un carácter **trunca el archivo antes de fallar**:
   pasó en esta sesión, `index.html` quedó en **0 bytes** (se restauró con `git checkout`, no llegó a
   commitearse). El patrón seguro es: leer a bytes → armar todo → **asserts** → recién ahí escribir.

---

## 5. Problemas de la auditoría tocados acá

| # | Estado | Qué |
|---|---|---|
| **85** | corregido (2º pase) | El editor viejo escribía a una tabla que el picking no lee. La v15.91 lo "cerró" con un banner; la **v17.26 le sacó la escritura** |
| **88** | **corregido** | 439E de Chef sin lugar. **Ñ53 pasó a empresa CH** con el 439E (Luis: *"poné la Ñ53 al 439E de CH"*). Desbloquea migrar `vista_nc_loeke_chef`: los duales por `GV_Lugar` ya son los mismos 4 que en `Planimetria` (437E, 438E, 439E, 809E) |
| **156** | **abierto** | Códigos que viven sólo en `Planimetria`. Ver §6 |
| **162** | corregido | Lo que rompió la v17.32 (§4.1) |
| **84** | **abierto** | De 107 → 35 → **15**. Ver §6 |

---

## 6. Lo que queda abierto — con el número exacto

### Problema 84 — **15 filas · 14 códigos · 12 celdas**, todas `solo_mapa`

**No son 3.** Y ya no hay nada que decidir: el código está bien puesto, **falta MEDIR cuántas cajas
entran**. Es alguien con un metro en la góndola, no una decisión de escritorio.

`035E` · `335` · `363E` · `396` · `505I` · `509` · `510T` · `547` · `556` · `563` · `581T` · `838E` ·
`989E` · `992E`

```sql
select * from public.gv_gondola_divergente order by sector, cod;
```

**Y dos celdas a re-medir aunque no figuren ahí:** `E10` (225→312) y `G15` (509→256) se llevaron el
número del artículo viejo porque dejarlos en cero apaga *"Cap gónd."* y *"Llenar góndola"* para un
artículo que está en el generador de OC. Es reversible (backup abajo), pero el número es de otra caja.

### Problema 156 — **7 códigos**, y NO urge

`231` · `232` · `233` (Palos de Amasar) · `537` (Pela y Pica ajo) · `567` (Corta Palta) ·
`997E` · `998E`

- **El relevamiento no dice nada de ellos**: los 7 **no aparecen** en ninguna celda del Excel. Sólo
  dice que las celdas que reclamaban están ocupadas (G06=208, G07/G08=355, C01=547, H60=592E,
  A65=396+556).
- **Ninguno tiene stock.** Pero **5 de 7 están en el generador de OC** y se movieron el 10–11/09, así
  que **no están discontinuados** (997E/998E sí parecen línea Acacia de baja).
- **Decisión de Luis (14/09): no urge.** Si algún día entran y es un problema, **tiene que saltar
  solo** — y ya salta: `recepcion.js` emite el evento **`RSP` "Recepción sin planimetría"** cuando
  llega un código que no está en `window.GONDOLA`, con `trg_recepcion_sin_planim_telegram` → Telegram
  y la categoría `sin_planimetria` del tablero de Agentes. **Verificado vivo: 13 eventos, el último
  el 14/09 10:59.** No hay que construir nada.

### Lo que esta sesión agrega a la lista del handoff de Thomas

- **`vista_nc_loeke_chef` → migrar a `GV_Lugar`.** Recién destrabado por el 88. Es lo último que ata
  la tabla `Planimetria` a un camino de plata (notas de crédito Loeke↔Chef). Antes perdía el 439E;
  ahora no.
- **`634` y `634E` son el mismo artículo con el stock partido en dos grafías** (12 cajas en el
  pelado, 0 en el que tiene nombre). Eso no es planimetría: es `gv_codigos_multigrafia`, y es más
  grande que todo lo demás de esta lista.

---

## 7. Backups de esta sesión

Todos en `zz_backups`, con RLS y sin escritura para `anon`/`authenticated`:

| Tabla | Filas | Cuándo |
|---|---|---|
| `GV_Backup_Lugar_20260914` · `GV_Backup_Lugar_Item_20260914` | 5 · 11 | antes de Ñ53 y M34/M35/M36 (v17.32) |
| `GV_Backup_Capacidad_pre_84_20260914` | 736 | antes de mover los `cajas_max` (v17.38) |
| `GV_Backup_Lugar_Item_pre_84_20260914` | 790 | ídem |

---

## 8. Dónde está el detalle

`docs/SUPABASE-GESTION-VIRGILIO.md` **§3.et** (v17.26) · **§3.ev** (v17.32) · **§3.ex** (v17.36) ·
**§3.ey** (v17.38) · `docs/relevamiento-lugares-deposito-20260911.md` ·
`sql/gv_gondola_divergente_v1726.sql` · y el handoff de la otra sesión,
`docs/HANDOFF-PLANIMETRIA-20260914.md`.
