# Cómo funciona HOY el circuito de faltantes

> Relevado el 2026-09-07 sobre el código desplegado y los datos reales, a pedido del dueño
> ("busca el funcionamiento actual") antes de decidir qué se toca. **No se cambió nada.**

---

## 1. Dónde nace un faltante

El faltante lo produce el **armado**, no el picking. Al terminar de armar una NP, el armador
carga qué salió de cada artículo y queda una fila por artículo en **`Entregas_Virgilio`**:

| columna | qué es |
|---|---|
| `cajas_pedidas` | lo que pedía la NP |
| `cajas_entregadas` | lo que realmente se armó |
| `cajas_falto` | la diferencia — **esto es el faltante** |

No hay tabla de faltantes aparte: el faltante es una columna de la entrega.

## 2. Quién los completa: el módulo CP (Completar Pedido)

**`cpLoadFaltantes()`** arma la lista de lo pendiente con dos condiciones:

```
cajas_falto > 0   Y   la NP NO está en Facturacion_NP
```

O sea: **facturar una NP la saca del CP para siempre.** Esa es la regla que más manda, y explica
la diferencia entre el total histórico y lo que ve el operario.

Detalles que ya están resueltos y conviene no romper:
- **Pagina con `supaFetchAllSafe`** (v12.21). PostgREST corta en 1000 filas y `Facturacion_NP`
  pasó ese tope; sin paginar, las NP facturadas fuera del corte se contaban como "sin facturar"
  y el badge del CP salía inflado (32 contra 9 reales).
- **Resuelve el código por empresa y por corrección** (v8.04): muestra `809E CH` / `438E LK` en
  vez del código pelado, igual que el picking.

## 3. Qué escribe cuando el operario completa

`cpConfirm()` hace cinco cosas, **en este orden**, y el orden es deliberado:

1. **Baja el faltante primero, con tope**, vía la RPC atómica **`cp_reducir_faltante_cap`**, que
   devuelve cuánto se pudo aplicar. Si el faltante ya estaba completo devuelve 0, avisa y **no
   mueve stock**. Esto es de la v11.02 y viene de un incidente real: antes se movía el stock
   primero y se bajaba el faltante después, así que un doble toque descontaba dos veces (NP 44551).
2. **Mueve el stock**: `−qty` del depósito de origen (`a_guardar` o `terminado`/góndola) y `+qty`
   a `a_facturar`.
3. **Emite el evento `CP`** (`texto = NP|cod|qty|GONDOLA\|AGUARDAR|lío`), con `ts_inicio` para que
   el tiempo del CP entre al dashboard de Rendimiento.
4. **Si la NP ya estaba facturada**, drena esas cajas de `a_facturar` en el acto — si no, quedarían
   ahí para siempre, porque el drenaje normal ocurre al tildar Facturación y eso ya pasó.
5. **Actualiza el lío** de la NP (lío existente o uno nuevo) y refresca la lista.

También avisa por Telegram si se retira de góndola con saldo 0 (idea 6497).

## 4. El recordatorio de las 15:30

`cpRecordCheck()` corre **cada 25 s** desde que carga la página y dispara un `alert()`
+ abre el modal de CP. Dos destinatarios:

- **Camino 1** — operario cuyo legajo esté en `CP_RECORD_LEGAJOS`, hoy **`["104"]`
  (Jhonny Moncayo)**, y sólo si está en la botonera.
- **Camino 2** — supervisor cuyo mail sea `FAC_OPERADORA_EMAIL`, hoy
  **`loekemeyer.n8n@gmail.com`** — que es **el mail con el que entra el dueño**. Por eso le llega
  a él.

### Lo que está mal, confirmado leyendo el código

1. **No tiene tope superior.** El filtro es `if (!t.habil || t.min < CP_RECORD_MIN) return;` —
   sólo piso. **Dispara de 15:30 a 23:59.**
2. **El dedup vive en `localStorage`**, así que es **una vez por dispositivo y navegador**, no por
   persona: celular + monitor + PC = tres avisos.
3. **El mismo recordatorio está en Producción Y en Gestión** (verificado en el repo de Producción,
   commit `e15b682`: bloque idéntico, mismos legajos, misma hora). Son dominios distintos → dos
   `localStorage` → **avisa dos veces**.
4. **No sabe de feriados.** Sólo mira lunes a viernes; no consulta `GV_Dias_No_Habiles`.
5. **Marca "ya avisé" ANTES de abrir el modal.** Si `showCPModal` falla, el error se traga en un
   `try/catch` vacío: el operario ve el cartel, no se abre nada, y **no reintenta en todo el día**.

**Sin explicar:** el dueño reportó que le disparó un **lunes ~10:20**. El filtro de hora es lo
primero que corre y se verificó en V8 barriendo las 24 h (devuelve bien, sin el bug de `"24:00"`).
Las hipótesis vivas son un `index.html` viejo cacheado en el navegador, o el reloj del dispositivo
corrido — el cálculo convierte un instante absoluto a hora argentina, así que un reloj adelantado
mueve todo.

## 5. La maquinaria de coordinación está APAGADA (y dejó residuo)

Existe un circuito completo de coordinación en vivo —`Faltantes_Tareas`, el popup
"¡Llegó un faltante! ¿Quién lo hace?", "✋ Me lo asigno", las RPC `faltante_tarea_crear` /
`_asignar` / `_completar` / `_soltar`— pero **está desactivado**:

```js
const FALT_POPUP_ENABLED = false;   // v6.15, pedido del dueño
```

`faltPollStart()` sale en la primera línea, así que **no hay polling ni popup**. La carga de
faltantes se hace toda por el módulo CP.

**El residuo:** `Faltantes_Tareas` tiene **73 filas en `pendiente`** (del 24/07 al 04/09) y **1
sola en `completado`**. Las tareas se siguieron creando pero nadie las cierra, porque el que las
cerraba era el popup. Son inofensivas —no las lee ninguna pantalla viva— pero ensucian la tabla.

## 6. Estado real hoy (2026-09-07)

| dato | valor |
|---|---|
| Líneas con `cajas_falto > 0` (histórico) | **815** |
| De ésas, **pendientes de CP** (sin facturar) | **5** |
| NP involucradas | **1** |
| Cajas a completar | **10** |

La única NP pendiente es **98542 · Pro Tatiana Ethel · tanda D57B · 04/09**:

| artículo | pedidas | entregadas | falta |
|---|---|---|---|
| 231 | 1 | 0 | 1 |
| 232 | 1 | 0 | 1 |
| 233 | 1 | 0 | 1 |
| 566E | 5 | 2 | 3 |
| 583E | 10 | 6 | 4 |

Es la misma que ya figura en `docs/PRIMEROS-DIAS-CON-GESTION.md` como armada sin facturar.

**O sea que el recordatorio de las 15:30 está avisando por 10 cajas de un solo pedido.** Con
tan poco volumen, el aviso diario a toda hora es más ruido que ayuda.

---

## Si se decide arreglarlo

Los cinco defectos del punto 4 son todos de arreglo chico y de bajo riesgo:

- ponerle **tope de hora** (ej. `CP_RECORD_MAX`, 15:30–18:00);
- mover el **dedup** a algo compartido (una tabla o el propio evento `CP`) en vez de `localStorage`;
- decidir si **Producción sigue avisando** ahora que los operarios están en Gestión;
- consultar **`GV_Dias_No_Habiles`** para los feriados;
- marcar "ya avisé" **después** de que el modal abra, no antes.

Y aparte, sin relación con el recordatorio: **limpiar las 73 tareas huérfanas** de
`Faltantes_Tareas`, o reactivar el popup si se lo quiere usar de nuevo.
