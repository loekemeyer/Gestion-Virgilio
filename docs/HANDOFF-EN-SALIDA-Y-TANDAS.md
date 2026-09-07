# Traspaso — tandas automáticas apagadas + En Salida (2026-09-07)

> Escrito a pedido del dueño para derivar a otro chat. Es el estado real al momento de
> escribirlo, verificado contra la base, no de memoria. Lo hecho está en `main` hasta la
> **v13.62**; lo pendiente está sin empezar.
>
> ⚠ **Hay más de una sesión trabajando sobre `main` en paralelo.** Durante esta sesión otra
> pusheó v13.60, v13.61 y v13.63. Antes de tocar nada: `git pull --rebase origin main` y
> mirar `docs/SUPABASE-GESTION-VIRGILIO.md` por si el estado cambió.

---

## 1. LO URGENTE — el automático de tandas está APAGADO

**Estado en Supabase (`hrxfctzncixxqmpfhskv`), verificado:**

```
cron 71  gv-ppp-web-tandas-diarias    active = false
cron 73  gv-ppp-web-tandas-intradia   active = false
```

Los apagó esta sesión, con permiso del dueño. **Nada se programa solo.** Los pedidos web
se siguen viendo en "A Programar" y se pueden armar a mano.

Para volver a prenderlos:

```sql
select cron.alter_job(71, active := true);
select cron.alter_job(73, active := true);
```

### Por qué se apagaron

Dueño (2026-09-06): *"No se tiene que programar nada de manera automática, salvo que
logremos que se vaya programando y que hasta que se llegue a 0,80 —o un poquito más, no hay
problema que se zarpe un poquito— ya se cierra la tanda y ahí sí no se agreguen nuevos
pedidos a esa tanda."*

O sea: **la tanda tiene que ACUMULAR entre corridas hasta 0,80 m³, y ahí cerrarse.**
Hoy el código hace lo contrario.

### El hallazgo (verificado sobre la función DESPLEGADA, no sobre el archivo del repo)

En `ppp_web_armar_tandas`, la temp table `_open` —la lista de tandas que pueden recibir un
cliente más— **se crea vacía en cada corrida** y sólo se llena con lo que esa misma corrida
arma:

```sql
create temp table _open (code text primary key, camion text, m3 numeric, cerrada boolean, seq int) on commit drop;
...
if v_code is null then ... insert into _open ... end if;
```

`PPP_Web_Programacion` se lee en dos lugares y en **ninguno** siembra `_open`: en el
`where not exists` que saca lo ya programado, y desde `gv_ppp_web_letra_y_camion()` para
seguir la numeración. **Una tanda escrita en una corrida anterior nunca es candidata a
recibir un pedido nuevo.** Con el intradía cada 15 min y `intradia_umbral_m3 = 0,001`, cada
pedido que entra solo se lleva su propio camión.

Medido el 06/09:

| corrida | tandas | clientes por tanda |
|---|---|---|
| 00:20 (varios pedidos juntos) | E01B, E01C, E01D | **2** |
| 16:15 y 20:30 (de a 1 pedido) | E03A, E04A, E05A, E06A, E08A | **1** |

⚠ **Ojo**: la v13.60 de la otra sesión (§3.at, `gv_ppp_web_camion_del_dia`) cambió el
reuso de **camión** por día y zona. Eso es el número `NN` del código de tanda, **no** es lo
mismo que reusar la **tanda**. Hay que releer la función antes de tocarla: puede que parte
del problema ya esté resuelto o que el diagnóstico de arriba haya quedado viejo.

### Lo que NO era el problema (para no perder tiempo)

El caso que lo destapó fue Muller y Muller (Pompeya) yéndose a tanda propia teniendo a
Distribuidora Cuyana (Soldati) el mismo día y en la misma zona. **No fue la cercanía**:
Pompeya y Soldati están los dos en el sector `B` de `GV_Barrios_Sector`, y de hecho ya
comparten tanda en E01C. Fue la regla del dueño del 2026-09-04:

```sql
v_cierra := r_cli.es_super or r_cli.solo or r_cli.m3_cli >= v_tope;
```

Cuyana sola suma **0,938 m³ ≥ `tanda_m3_max_mezcla` (0,80)** → **E03A nació cerrada** y no
admite a nadie. Eso funciona como está pedido.

### Lo que hay que implementar

Decidido con el dueño: **va en el BACKEND**, en `ppp_web_armar_tandas`.

1. Sembrar `_open` con las tandas **ya programadas del mismo día** que sigan abiertas
   (m³ < tope) y no las haya empezado nadie.
2. La tanda que cruza 0,80 **se cierra** y no recibe más pedidos. El pedido que la cruza
   entra igual (el dueño dijo explícitamente que puede pasarse un poco).
3. **Sin timeout.** El dueño: *"no va a pasar, salvo que sea zona diferente a 1, y eso se
   programa manual por ahora."* O sea que una tanda que no se llena no es un caso a resolver.
   ⚠ Esto sugiere que `zonas_automaticas` debería quedar en `'1'` y no en `'1,2,3'` cuando se
   vuelva a prender — **confirmar con el dueño antes**.
4. Ojo con las tandas que un operario ya empezó a pickear: no se les puede agregar nada.

**Config relevante hoy:** `tanda_m3_max_mezcla = 0.80`, `intradia_umbral_m3 = 0.001`,
`zonas_automaticas = '1,2,3'`, `sectores_activos = 1`.

Probar sin escribir: `select * from gv_ppp_web_armar_simular('lk', current_date, '[…]'::jsonb);`

### Decisión abierta que quedó sin responder

**El botón de "regenerar" de la pantalla rearma TODO el tablero**, no agrega: renombra
tandas y mueve fechas ya comunicadas al depósito. El 06/09 a las 20:40:59 lo tocó el dueño y
las 26 filas de `PPP_Web_Programacion` quedaron con ese `actualizado_at` — E02A→E01F,
E04A→D68G, E05A→D69D, E06A→D69E, E08A→E03B, y las fechas del vie 11 al lun 14 / mar 15.

Se le ofreció al dueño cambiarlo a "que sólo agregue lo pendiente" y **no llegó a contestar**.

---

## 2. HECHO — En Salida (v13.62, commit `eccdb52`)

Ya está en `main` y funcionando. Documentado en `docs/SUPABASE-GESTION-VIRGILIO.md` **§3.au**.
Se lista acá sólo para que no se rehaga.

- `gv_ppp_en_salida` reescrita (`sql/gv_ppp_en_salida.sql`): el universo pasó de "tiene CCN"
  a **"está facturada y no tiene CRN"**. De 13 a **54 NP**, con **0 perdidas**.
- Entraron las tres que el dueño reclamaba: **98665** Merajver (0,042, 02/09), **98502**
  Clapera (0,011, 03/09), **98569** Pezzali (0,005, 03/09) — todas facturadas y armadas pero
  **sin evento CCN**.
- Columnas nuevas: `armada`, `armado_at`, `cargada`, `control_previo`, `facturada_el`,
  `estado`, `dias_sin_controlar`.
- Front: tabla propia por día (NP · Cliente · Tanda · m³ · **Cargado** · **Estado**) con la
  fecha y hora reales del CCN y chips de estado.
- **Recepción de Remitos embebida, sólo supervisores**: tildar Controlado → CRN → Entregados,
  y ↩ s/salida → FSS. Reusa `crSendDetail` / `crSendSinSalida` con legajo `"0"`, igual que
  `openRemitosAdmin()`. **El módulo RR de arriba quedó intacto.**
- Test: `tests/ppp-ensalida-estado.cjs` (17 chequeos).

---

## 3. PENDIENTE — anomalía de datos, sin tocar

**8 NP tienen `CCR` (control de remito ANTES de cargar) pero no `CCN` (carga al camión):**

```
98474, 98509, 98585, 98586, 98587, 98588, 98589, 98590
```

O el operario saltea el CCN, o se está usando el CCR en su lugar. En la pantalla se ven con
el chip `CCR sin CCN`. **Hay que revisar el circuito con el dueño** — no es un bug de código,
es cómo se está operando.

Para verlas:

```sql
select np, tanda, razon_social, m3, fecha_entrega, estado
  from public.gv_ppp_en_salida where control_previo and not cargada order by np;
```

---

## 4. PENDIENTE — borrar el pedido de prueba 1352

Se cargó a mano el 06/09 para probar el circuito de punta a punta y **el dueño todavía no
dijo de borrarlo**. Estado hoy: **tanda E03B, entrega 2026-09-15**.

- **Muller y Muller S.R.L.** (cod 862), 100 cajas del artículo **505**, 0,24 m³, $1.206.046,80.
- Entrega "De L Americas 4384- Parana" → expreso Fontana, Pompeya → Zona 1.

**No salió a ISIS ni disparó WhatsApp**, a propósito. Para borrarlo, con backup previo:

| proyecto | tabla | filtro |
|---|---|---|
| Virgilio `hrxfctzncixxqmpfhskv` | `PPP_Web_Programacion` | `order_id = 1352` |
| Virgilio | `PPP_Web_Base` | `order_id = 1352` |
| Virgilio | `PPP_Web_NP` | `order_id = 1352` |
| LK `kwkclwhmoygunqmlegrg` | `order_items` | `order_id = 1352` |
| LK | `orders` | `id = 1352` |

`lk_pedidos_match` de Virgilio se limpia sola (el cron `sync-pedidos-match-virgilio` reescribe
una ventana móvil de 14 días).

### Si se hace otro pedido de prueba, repetir estas tres precauciones

1. Insertar con **`sheets_sent = true`**. El cron `retry-sheets` de LK (jobid 1, cada 5 min)
   levanta todo lo que tenga `sheets_sent = false` y lo empuja al Google Sheet → ERP.
2. Elegir un cliente **sin fila en `bot_customer_whatsapps`**, si no el trigger
   `orders_notify_whatsapp` le manda un "✅ Pedido recibido" real al cliente. Sólo 4 clientes
   de 1273 tienen teléfono: **288, 4197, 4234, 4260**.
3. `detectar_pedidos_anomalos` (cron cada 5 min) saltea los `cod_cliente` **1 y 3878** (los de
   prueba). Con otro cliente hay que mirar que el score dé < 5 o salta alerta a Virgilio.

---

## 5. PENDIENTE — las E01x se corrieron de fecha y el instructivo dice otra cosa

`docs/PRIMEROS-DIAS-CON-GESTION.md` dice que **E01A–E01E entregan el viernes 11**. Después del
rearmado del 06/09 pasaron al **lunes 14**, y la v13.60 de la otra sesión volvió a correr la
semana un día hábil (lun 7 feriado). **Hay que revisar contra qué dice hoy la base y actualizar
el instructivo**, que es el que se le pasó a los operarios.

El motivo del corrimiento original está medido: `gv_ppp_web_m3_isis('2026-09-11')` daba
**10,075 m³ contra un cupo de 6**, porque el override de Chango Mas (E07A, 4,31 m³, §3.ap) se
cargó ese día a la tarde. La cascada de cupo hizo lo que tiene que hacer.

---

## 6. Datos sueltos que se encontraron y no se tocaron

- **`bot_customer_whatsapps` tiene basura en `empresa`**: en vez de `LK`/`CH`, dos filas dicen
  `"Urriza Mariela"` y `"Lin Xiuhui"` (la razón social metida en el campo de empresa). Y la
  fila del 2º número de Lin Xiuhui tiene `cod_cliente` en null (el `customer_id` sí está).
  Es del proyecto **LK** (`kwkclwhmoygunqmlegrg`).
- **`98490` Salvetti** tiene CCN pero también un **FSS posterior** (facturado sin salida), así
  que la vista la saca a propósito. Está bien como está — no "arreglarla".
