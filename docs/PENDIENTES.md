# Pendientes — Producción Virgilio (inventario)

Snapshot: **2026-07-30**. Origen: inventario traído de otro chat. Lo construido
hasta acá está completo y pusheado (v6.41→v6.49 + Supabase + guía). Esto es lo que
queda abierto, para que **no se olvide**. No borres entradas: se tildan (`[x]`) o se
tachan (`~~…~~`).

> ⚠ **#7 y #8 se están haciendo en OTRO chat** (el usuario dio el OK allá). No
> tocarlos desde acá para no pisar el trabajo (el #7 es un revoke en Supabase en vivo).

## ✅ Insumos 505C/CB01/523C/H201Lever — HECHO (31/07, prop. 2769)

Pedido del usuario: *"505C / CB01 borrar stock y colocar en insumos"* + conteo físico.
**RESUELTO 31/07** (decisión del dueño en el chat: **saldo en unidades**, desglose "MC×UNI"
como dato en la descripción, bajo **códigos numéricos**). Se puso en 0 lo viejo (505C insumos
168000, CB01 insumos 2950, 523C racks 240) y se cargó en `insumos` (unidad `Uni`,
ubicación=sector): **2955**=142000 (X20) · **4626**=2950 (N7) · **1685**=6000 (W1) ·
**2815**=26400 (O1). Cabezal (H201Lever/2815) confirmado **distinto** del Espiral 2805.
⚠ Quedan aparte los negativos compuestos `505C·CUCHILLA CHINA` (−16000/−6) y `523C·CREMALLERA`
(−30 MC) — sub-ledger de entregas, cleanup separado. Debajo, la reconciliación original y el
SQL de referencia (el ejecutado fue la variante **unidades**, no MC).

Reconciliación conteo ↔ `Movimientos_Stock` (al momento del pedido):

| Sector | cod | Modelo | Descripción | Conteo pedido | Estado hoy en el ledger |
|---|---|---|---|---|---|
| X20 | 2955 | 505C | Cuchilla 505 Ac Inox | 35·4000 + 1·2000 = **142000 u** | `505C` insumos **168000** (fijar, 24/07) · `505C·CUCHILLA CHINA` −6 MC / −16000 u (entregas) · `2955` no existe |
| N7 | 4626 | CB01 | Mariposa Mgo Plano | 14·200 + 1·150 = **2950 u** | `CB01` insumos **2950** (fijar, 24/07) = **coincide** · `4626` no existe |
| W1 | 1685 | 523C | Cremallera Doble Aleta | 25·240 = **6000 u** | `523C` **racks 240** "inner" (ingreso W1, 23/07) · `523C·CREMALLERA` −30 MC (entrega) · `1685` no existe |
| O1 | 2815 | H201Lever | Cabezal Importado | 22·1200 = **26400 u** | ⚠ `H201` tuvo "fijar en 26400" (24/07) **pero hoy 31/07** `fix_recatalog_espiral` lo puso en 0 (junto con H201 PART 46000→0 → creó `2805` Espiral=63 MC). Cabezal (H201Lever) vs Espiral (H201Part) ¿misma pieza o distinta? |

**Decisión que falta (2 ejes):**
1. **Unidad del saldo** → *unidades crudas* (505C=142000, como están hoy 505C/CB01) **o** *master-cartons* (505C=36 MC con "(4000 u/MC)" en la desc, convención nueva 007/2805).
2. **Código** → *numéricos* 2955/4626/1685/2815 (migrar + poner en 0 las entradas viejas 505C/CB01/523C) **o** *mantener códigos-modelo*.
3. **H201Lever/2815**: confirmar que es **distinto** del Espiral 2805 antes de crearlo (no pisar el recatalogueo de hoy).

**SQL listo — interpretación más probable (unidades crudas + códigos numéricos).** Ejecutar
lo que corresponda tras el OK. Deja las entregas compuestas (`505C·CUCHILLA CHINA`,
`523C·CREMALLERA`) intactas (son su propio sub-ledger de consumo; revisar aparte).

```sql
-- 505C → 2955 (Cuchilla 505 Ac Inox), sector X20
insert into "Movimientos_Stock" (ts,cod_art,descripcion,deposito,delta,tipo,ref,legajo,creado,ubicacion,client_id) values
 (now(),'2955','Cuchilla 505 Ac Inox (505C) — 35 MC×4000 + 1 MC×2000','insumos', 142000,'ajuste','conteo fisico 31/07','ajuste',now(),'X20','fix_2955_insumos_20260731'),
 (now(),'505C','retira entrada modelo (migra a 2955)','insumos',-168000,'ajuste','migra a 2955','ajuste',now(),null,'fix_505C_zero_20260731')
on conflict (client_id) where client_id is not null do nothing;

-- CB01 → 4626 (Mariposa Mgo Plano), sector N7  [conteo = saldo actual 2950]
insert into "Movimientos_Stock" (ts,cod_art,descripcion,deposito,delta,tipo,ref,legajo,creado,ubicacion,client_id) values
 (now(),'4626','Mariposa Mgo Plano (CB01) — 14 MC×200 + 1 MC×150','insumos', 2950,'ajuste','conteo fisico 31/07','ajuste',now(),'N7','fix_4626_insumos_20260731'),
 (now(),'CB01','retira entrada modelo (migra a 4626)','insumos', -2950,'ajuste','migra a 4626','ajuste',now(),null,'fix_CB01_zero_20260731')
on conflict (client_id) where client_id is not null do nothing;

-- 523C → 1685 (Cremallera Doble Aleta), sector W1  [saca de racks, pone en insumos]
insert into "Movimientos_Stock" (ts,cod_art,descripcion,deposito,delta,tipo,ref,legajo,creado,ubicacion,client_id) values
 (now(),'1685','Cremallera Doble Aleta (523C) — 25 MC×240','insumos', 6000,'ajuste','conteo fisico 31/07','ajuste',now(),'W1','fix_1685_insumos_20260731'),
 (now(),'523C','retira de racks (migra a insumos 1685)','racks', -240,'ajuste','migra a 1685','ajuste',now(),null,'fix_523C_racks_zero_20260731')
on conflict (client_id) where client_id is not null do nothing;

-- H201Lever → 2815 (Cabezal Importado), sector O1  ⚠ SOLO si se confirma que NO es el Espiral 2805
-- insert into "Movimientos_Stock" (ts,cod_art,descripcion,deposito,delta,tipo,ref,legajo,creado,ubicacion,client_id) values
--  (now(),'2815','Cabezal Importado (H201Lever) — 22 MC×1200','insumos', 26400,'ajuste','conteo fisico 31/07','ajuste',now(),'O1','fix_2815_insumos_20260731')
-- on conflict (client_id) where client_id is not null do nothing;
```

Para la variante **MC** (eje 1 = master-cartons): mismos inserts pero `delta` = MC (505C=36,
CB01≈15, 523C=25, H201Lever=22), `unidad='MC'` y la desc con "(N u/MC)".

## ⚠ Revisar mañana (operativo) — anotado 2026-07-30

- [ ] **2 pedidos armados + facturados pero SIN despachar (del 29/07).** Las NP **98185**
  y **98186** (**Mundo Bazar S.R.L**, tanda **C98J**) se **armaron** el 29/07 16:51 (~216
  cajas) y se **facturaron/tildaron** el 29/07 17:24, pero **NO se cargaron al camión**
  (no hay evento `CCN`) ni entraron a ningún reparto (`Facturacion_NP.cierre_id` = null).
  Son los 2 que aparecen en "YA TILDADOS HOY" del Cierre de jornada de Facturación.
  **Acción:** verificar físicamente que esas cajas estén en el depósito y despacharlas en el
  próximo reparto (van a estar en el "Generar PDF"); si ya salieron por otro medio, cerrarlas
  / marcar la carga (CCN) para que salgan de la lista de pendientes.

## Grupo A — Requiere al usuario (Google/ARCA, fuera del alcance del agente)

- ~~**1. Deploy del Apps Script `ppp-a-excel.gs`**~~ — **DESCARTADO 2026-07-30** por
  decisión del usuario: se eliminó el script del repo. Queda solo el botón
  "⬇ Exportar Excel" de la app (que ya funciona).
- [ ] **2. Facturación ARCA** — conseguir certificado + PDV nuevo + definir de dónde
  sale el importe + OK del contador. **2026-07-30: la emisión ya está IMPLEMENTADA y
  deployada** (WSAA con firma CMS + cache TA, FECompUltimoAutorizado, FECAESolicitar,
  log en Comprobantes_ARCA), gateada por secrets + `ARCA_EMITIR=on`. Al llegar el
  certificado de homologación: cargar secrets y probar `action=ta` → `ultimo` → `emitir`.

## Grupo B — Decisiones en pausa (no son deuda; esperan tu decisión)

- [ ] **3. Capa 1b / split del 66** — dijiste "no hagamos el paso 4". El 66 sigue
  partido (6 cajas, cosmético); si una tanda vuelve a traer un código mal, el picking
  puede repetirlo.
- [ ] **4. Purga de los ~76 numéricos restantes** de la carga de insumos del 27/7 —
  solo se borraron los 13 confirmados; el CSV lo tenés para decidir.
  Decisiones 2026-07-30: **`0037` y `0087` QUEDAN como están** (el usuario no los
  reconoce; saldo 0, solo insumos, inofensivos — no volver a proponer borrarlos).
  Auditoría de patrones (2 díg / 0XX / 00XX) hecha: el único split real del stock
  era `66`↔`066` (tanda C94A, 5 filas, ids 7327/7328/7626/7627/8532) —
  **CONSOLIDADO 2026-07-30** con OK del usuario (UPDATE a `066`, verificado: sin
  variante `66`, góndola de `066` quedó en 212). Con esto el stock no tiene ningún
  código partido por padding.
- [ ] **5. Fase 2 del PPP** (programar desde la app / Supabase motor, sync con upsert)
  — diseño entregado, sin implementar. El Espejo quedó idéntico a PPP esperando esa
  divergencia.
- [ ] **6. Ajuste dinámico de espacio por proyección** — quedó en recomendación
  (Fase 1: cobertura en días); nunca se arrancó.

## Grupo C — Pendientes chicos (accionables)

- [ ] **7. Seguridad (el más importante)** — `anon` puede escribir/borrar en
  `Facturacion_NP`, `Facturacion_Cierres` y `Entregas_Virgilio` (pre-existente).
  Revoke cuidadoso (al menos `TRUNCATE`, que saltea RLS) sin romper lo que el armado
  escribe con `anon`. — ⏳ **EN CURSO en otro chat.**
- [ ] **8. `CLAUDE.md` desactualizado** — dice "los m³ NO están en Supabase", y eso ya
  no es cierto desde v5.33 (verificado). Corrección de 2 minutos. — ⏳ **EN CURSO en
  otro chat.**
- [ ] **9. (Menor) Instructivo de firma de commits** — quedó solo en el chat; guardarlo
  como `docs/firmar-commits.md`.
