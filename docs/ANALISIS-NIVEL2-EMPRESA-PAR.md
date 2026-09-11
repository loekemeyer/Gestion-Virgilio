# Análisis de implementación — Nivel 2: `(cod, empresa)` como par, sin mutar el código

> **Estado: ANÁLISIS para implementar. Decidido por el dueño (09/09/2026): vamos a Nivel 2.**
> Este documento es el plan; la implementación es un paso aparte.

---

## 1. Qué es Nivel 2 (y qué NO es)

**Objetivo:** que la identidad de una línea sea el **par `(cod, empresa)`** de punta a punta —
`cod="438E"`, `empresa="LK"`— y que **nunca** se arme el string `"438E LK"` como código de
trabajo que fluye. Sin conversión ida-y-vuelta.

**Lo que HOY es `"438E LK"`** (lo relevé, no es lo que parecía):
- **NO** es el código que va a la factura / Excel ISIS / `Entregas_Virgilio` → ese ya va **crudo**
  (`pedidoFull`, `438EL` con L; el front lo separa a propósito).
- **SÍ** es la **clave de stock/góndola** interna: el front lo usa como clave para (a) ubicar la
  góndola física del dual, (b) leer el saldo de góndola, (c) agregar demanda, (d) drenar el
  facturado. Y es el campo 2 del evento PKC.
- Y es la **etiqueta física** en `Planimetria` (`438E LK`→sector F13, `438E CH`→L05).

**Consecuencia honesta:** el stock **guardado ya es `(cod, empresa)`** (el trigger pela el sufijo).
Nivel 2 **no arregla un dato** — hace que la **clave de trabajo** deje de ser un string que *parece
un código mutado* y pase a ser un par explícito. **El beneficio es prolijidad/claridad, no
corrección de datos.** Hay que entrar sabiendo eso, porque el costo es un refactor del picking en vivo.

**Lo irreducible:** para un dual, en UN punto hay que combinar `(cod, empresa)` para pegarle a la
góndola física (`Planimetria` está keyeada por `438E LK`). En Nivel 2 eso es un **lookup**
(`gondolaKey(cod,emp)` arma la clave y consulta), no un código que fluye. La `Planimetria` **se
mantiene** como está (etiquetas físicas); re-keyearla sería un cambio de datos aparte y no se hace.

---

## 2. Mapa de touch points

### Front (`index.html`) — el grueso del trabajo

| función / línea | qué hace hoy con `"438E LK"` | cambio en Nivel 2 |
|---|---|---|
| `empresaDeNp` / `pkEmpresaArt` / `pkStripL` / `pkCodEmpresa` / `pkResolveArt` (8274-8317) | toolkit que arma/pela el sufijo | se conserva `empresaDeNp` (resuelve la empresa); se agrega `gondolaKey(cod,emp)` (arma la clave sólo para el lookup); `pkResolveArt` deja de usarse como identidad |
| `aggFrom` (9019) | key del agg = `pkCodEmpresa(...)` = `"438E LK"` | key = par `(cod, emp)` (interno `cod+"\|"+emp`, que **es una clave, no un código**) |
| `gOf`/`gOrden`/`dualOf` (9029-9048) | lookup `GONDOLA["438E LK"]` | `gondolaKey(cod,emp)` → `GONDOLA[...]`; item pasa a `{cod, empresa, sector, esp, ...}` |
| display del picking (9214) | muestra `it.art` = `"438E LK"` al operario | muestra `cod` + **badge** de empresa (`438E` · LK) |
| `pkOk`/`pkSinStock`/`rec` (9463-9480) | `rec = it.art` (suffixado) → `pkSendDetail` | pasa `(cod, empresa)` a `pkSendDetail` |
| **`pkSendDetail` (9689)** | `texto = TANDA\|438E LK\|esp\|real`; `client_id` incluye el suffixado | `texto = TANDA\|438E\|esp\|real\|LK`; `client_id` incluye `cod`+`emp` (para dedup distinto de CH) |
| `_pkItemCodes` (9486), historial (9971), `_pvFaltanteFactores` (13809) | pelan/toleran | menor: ya usan `codBase`/campo 1/campo 2-para-m³; tolerar 5 campos |
| **4 consumidores de stock** (10167 "qué bajar", 12733 demanda, 29212 need/faltantes, 23802 drenaje facturado) | keyean saldo/demanda por `pkResolveArt`/`pkCodEmpresa` = `"438E LK"` | keyear por el par `(cod, emp)`; leer los saldos de stock por el par |

### Backend (Supabase)

| objeto | cambio en Nivel 2 |
|---|---|
| **`reconciliar_pipeline_stock_etapa1`** | leer `cod` (campo 2, crudo) + `emp` (campo 5); agrupar por `(tanda, cod, emp)`; insertar `cod_art=cod` + `empresa=emp` **explícito**. **Aceptar también el formato viejo** (sufijo en campo 2) → filas guardadas idénticas. **No aplicar el default-empresa de `Equivalencias`** a los duales (la empresa ahora viene del campo). |
| `trg_normalizar_empresa_stock` | **sin cambios.** Su pela-sufijo queda casi sin uso (eventos nuevos ya vienen crudos + empresa), pero se mantiene para: eventos viejos, la regla `L→LK`, no-dual→`Mixto`, y el drenaje `facturado` del front. |
| `Movimientos_Stock` | **sin cambios.** La clave de conflicto ya es `(ref, cod_art, empresa, deposito, tipo)`; los eventos nuevos producen exactamente las mismas filas. |
| `Equivalencias_Codigos` | las 4 filas de default-empresa (`437E→437E LK`…) quedan **muertas** para el reconciliador (la empresa viene del campo). Se pueden **borrar** esas 4 (dejar las de L/727, que son unificación de código real). Cambio de datos → backup + ROLLBACK. |
| `reconciliar_..._etapa2` | **sin cambios** (lee `Movimientos_Stock`, no el evento). |

### Datos
- **`Planimetria`**: se mantiene keyeada por `438E LK`/`438E CH` (etiquetas físicas). El lookup las
  arma en el momento. **No se re-keyea.**

---

## 3. Lo que NO se toca (confirmado en el relevamiento)
- Todo lo que lee `Movimientos_Stock.cod_art` (ya pelado) + columna `empresa`: `vista_stock_procesada`,
  `vista_saldos_stock`, `vista_generador_oc`, `vista_faltantes_sin_completar`, `gv_lk_np_feed`,
  `gv_ppp_web_entregados`, `gv_conciliacion_registrar`, `actualizar_saldo_trigger`, etc.
- `monitor/` y `recepcion.js` (no parsean PKC).
- Facturación / Excel ISIS / `Entregas_Virgilio` (usan el código **crudo**, no la clave de stock).
- El código **crudo con L** (`438EL`) que va al pedido/factura — la L es identidad, se conserva.

---

## 4. Rollout SEGURO (fases, backend primero)

**Fase 2.1 — Backend acepta las dos formas (compat, riesgo bajo).**
`etapa1` lee `(cod campo2, emp campo5)` para eventos nuevos y sigue leyendo el sufijo (campo 2) para
los viejos, produciendo **filas idénticas**. Deploy + verificación: correr `etapa1/etapa2` en seco y
comparar `Movimientos_Stock` por `(cod_art, empresa)` **antes vs después** sobre el histórico → deben
ser idénticos. Con esto el front viejo **sigue andando** (no rompe nada aún).

**Fase 2.2 — Front al par (riesgo alto: picking en vivo).**
Refactor del picking a `{cod, empresa}` + emisión del par. Como el backend ya acepta las dos formas,
se puede desplegar y, si algo falla, el evento sigue siendo válido. Test headless del picking + un
picking real de un dual + smoke `tests/`. Idealmente detrás de un flag (`PPP_Web_Config` o const) para
poder volver al formato viejo sin redeploy del front.

**Fase 2.3 — Limpieza (opcional).**
Borrar las 4 filas default-empresa de `Equivalencias_Codigos` (con backup). Marcar la pela-sufijo del
trigger como legacy-compat.

---

## 5. Riesgo, esfuerzo, rollback

- **Esfuerzo:** front = **grande** (≈10 funciones del núcleo de picking + 4 consumidores + display +
  emisión, varios cientos de líneas); backend = **mediano** (1 función, `etapa1`); datos = chico.
- **Riesgo:** **alto en el front** (toca el flujo que usan los operarios en vivo). Backend = medio
  (mitigado por compat de dos formatos). Datos = bajo.
- **Mitigaciones:** backend-first + dos formatos + flag en el front + test headless + picking real +
  verificación idempotente del reconciliador + rollback por fase.
- **Rollback:** Fase 2.1 → restaurar `etapa1` (backup `pg_get_functiondef` en ROLLBACK-PRODUCCION.md).
  Fase 2.2 → revertir el commit del front (o apagar el flag). Fase 2.3 → restore de las filas de
  `Equivalencias`.

---

## 6. Recomendación honesta

Nivel 2 es **la** versión limpia (par de punta a punta, sin código mutado), **pero** el beneficio es
**claridad**, no corrección — el stock guardado ya es `(cod, empresa)`. El costo es un refactor del
**picking en vivo** (riesgo alto). 

Si se hace, **hacerlo por fases con el backend primero y un flag en el front**, y no meterlo el mismo
día que otra cosa del picking. Si en algún momento el apetito de riesgo baja, **Nivel 1** (evento
limpio, sin tocar el motor) sigue siendo una parada intermedia válida.
