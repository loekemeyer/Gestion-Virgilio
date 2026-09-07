# Estado al lunes 2026-09-07 — todo junto

> Este archivo junta lo que quedó desparramado en cuatro sesiones distintas que trabajaron el
> mismo día. Cada una dejó su handoff y ninguna veía a las otras. Acá está ordenado por **quién
> tiene que hacer qué**, que es lo que importa para arrancar el martes.
>
> Los números están **medidos hoy**, no supuestos. Cada uno dice contra qué se midió.
>
> Handoffs originales, si hace falta el detalle: `docs/HANDOFF-EN-SALIDA-Y-TANDAS.md`,
> `docs/PENDIENTES-PIPELINE-GESTION.md`, §3.bc/§3.bd/§3.bl de `docs/SUPABASE-GESTION-VIRGILIO.md`.

---

## A · Del dueño, nadie más lo puede hacer

| # | Qué | Por qué no lo puede hacer otro |
|---|---|---|
| **A1** | **Rotar `isis_supabase_service_key` y `LK_WA_TOKEN`** | Se rotan desde el dashboard de Supabase / Meta. La lectura pública ya se tapó (ver abajo), pero las claves siguen quemadas |
| **A2** | Cargar `KRIKOS_IMAP_PASS` en el Vault de LK: `select vault.create_secret('<password>', 'KRIKOS_IMAP_PASS');` | Es la password de `ventas@loekemeyer.com` |
| **A3** | Mergear a `main` la rama `claude/krikos-tema-anterior-v0l88o` de **`pagina-LK-copia`** | Ese repo no está atado a la sesión de Gestión |
| **A4** | Chequear la PC de la oficina **el martes después de las 10** | Acceso físico. **No hoy** — ver E1 |
| **A5** | Los descuentos de cadena que Gestión no tiene cargados (Cencosud 2444, Dorinka 2686, Superimperio 961, 1806, 4254) | Hay que pedirle la lista a quien maneja esos acuerdos — ver §"Los $10,7 M" |

### El agujero (A1) — es lo primero

`public.app_settings` del proyecto **LK** tiene una policy `SELECT` para `anon` con `using (true)`.
Adentro hay dos secretos:

- **`isis_supabase_service_key`** (arranca con `sb_sec…`) — el service key de
  **`hrxfctzncixxqmpfhskv`**, la base que comparten Gestión y Producción.
- **`LK_WA_TOKEN`** — 200 caracteres, el token de Meta del bot.

La anon key de LK es **pública**: está en `admin/admin.js`, servido por GitHub Pages. Cualquiera
que la tenga lee esa tabla y se lleva la llave maestra de nuestra base, salteando toda la RLS. Es
la misma clase de problema que el incidente del 2026-09-04.

Se verificó quién lee `app_settings` desde el front: los tres lugares del panel piden **una sola
clave**, `web_order_discount` (`admin/sugerencias.js:31`, `admin/osa/js/app.js:1515`,
`admin/admin.js:10358`). O sea que tapar las dos secretas no rompe nada visible.

**Mitigación — ✅ APLICADA el 07/09 16:54.** Verificado después con `set local role anon`: las dos
secretas ya no salen y `web_order_discount` sí, así que el front quedó intacto.
Rollback: `create policy app_settings_select_all on public.app_settings for select to anon, authenticated using (true);`

```sql
drop policy app_settings_select_all on public.app_settings;
create policy app_settings_select_all on public.app_settings
  for select to anon, authenticated
  using (key not in ('isis_supabase_service_key','LK_WA_TOKEN'));
```

**Pero eso solo no alcanza.** Las dos claves ya están quemadas: hay que **rotarlas** y guardarlas
en el Vault, no en una tabla. Eso es A1 y es del dueño.

---

## B · Esperan un sí o un no

| # | Qué | Cuándo vence |
|---|---|---|
| **B1** | Luján (Extralimp, 4114, NP 98651, 0,745 m³): ¿queda el mar 15 en camión propio, o se pasa al vie 11 con Dorinka (Moreno)? | Antes del mar 15 |

### Los $10,7 M del cruce de facturación — no eran un problema, eran tres

El handoff decía "145 NP con diferencia, −$10.675.643" y lo dejaba ahí. Abierto, se parte así:

| grupo | NP | $ | qué es |
|---|---|---|---|
| **A** · mismas cajas, descuento > 5 % | 13 | **−7.383.286** | **Descuentos de cadena que Gestión no tiene cargados.** Cinco clientes: **2444 Cencosud, 2686 Dorinka, 961 Superimperio, 1806, 4254**. La factura sale bien; lo que está mal es nuestro precio. No es un error de facturación → **A5** |
| **B** · mismas cajas, diferencia chica | 90 | **+1.652.037** | Ruido de redondeo de precio, y encima **a favor**. No hay nada que mirar |
| **C** · **cajas distintas** | 42 | **−4.944.393** | **Esto sí hay que mirarlo.** O se facturó de menos, o `cajas_ent` viene inflada (devoluciones o faltantes mal cerrados) |

**Hecho el 07/09:** se marcaron como avisadas las **103 de A y B** (las explicadas) para que el
digest del cron 77 no empiece tirando todo junto. **Las 42 de C quedan vivas** y salen mañana
18:30 — que es exactamente la lista que hay que revisar.
Rollback: `delete from public."GV_Cruce_Avisadas";`

---

## C · Corriendo solo, no hay que tocar nada

| # | Qué | Estado medido hoy |
|---|---|---|
| **C1** | Geocodificación de **todo** el padrón (v14.16) | ~104 de 2.307 al momento de escribir esto · ~200/h · termina esta noche. Mirar con `select * from public.gv_geo_cobertura;` |
| **C2** | Cron 75 acelerado a `*/10 * * * *` para drenar | **Hay que devolverlo a `20 */6 * * *`** cuando C1 termine. Ya hay un recordatorio puesto |
| **C3** | Cron 79 `gv-sync-padron-direcciones`, 05:40 ART | Refresca el padrón todos los días |
| **C4** | Crons 77 y 78 (cruce de facturación e ingesta de ISIS) | Activos y bien hechos: los dos chequean `gv_es_dia_habil` antes de avisar |

---

## D · Lo que se cerró hoy — no rehacer

- **v14.12** — la regla del agregado: va en tanda nueva **sólo si mezclaría ISIS con web**. El
  corte es el **origen**, no "¿ya se pickeó?". Osa quedó `E09A` (ISIS) + `E09B` (web), mismo
  camión, mismo día, picking separado.
- **v14.16** — se ubica **todo el padrón**, no sólo lo programado. Tabla
  `GV_Clientes_Direcciones` (2.307 direcciones), Edge Fn `gv-sync-padron-direcciones`, vistas
  `gv_geo_faltantes_padron` y `gv_geo_cobertura`. Y se cargó el **depósito**, que no estaba:
  `PPP_Geo.__deposito_virgilio_2788__` = `-34.6157998, -58.5252267`. Antes el front caía a un
  fallback a 11 km.
- **v14.17** — mergeada la rama de la Bandeja Krikos de **este** repo. Se ve por
  🌐 Panel Web LK → PDF Krikos → Bandeja Krikos. Vacía hasta A2.
- **v14.18** — la hoja de ruta del fletero lleva **columna Viaje**: el manejo acumulado desde el
  depósito hasta cada parada, sin la descarga. Es lo que había pedido el dueño y no se podía hacer
  hasta que el depósito quedó geocodificado en la v14.16.
- **Tapada la lectura pública de las dos claves** en `app_settings` de LK (ver A1).
- **Cruce Facturación ↔ ISIS** con asignación 1-a-1: ambiguos **52 → 0**, 0 facturas duplicadas.
- **Tests**: las 2 fallas de `ppp-plan-nueva` que arrastraban los handoffs **ya no existen**. Eran
  aserciones de la v13.33 ("sin Atrasados en Programación") que contradecían la corrección del
  dueño de hoy. Suite entera en verde.

---

## E · Correcciones a lo que decían los handoffs

Cuatro cosas que llegaron mal escritas y conviene no repetir:

1. **"La ingesta de PDF está caída hace 52,6 h."** No está caída. Último PDF: **sábado 05/09
   08:31**. Después vino domingo, y **hoy lunes es feriado** (Día del Metalúrgico, está en
   `GV_Dias_No_Habiles`). No hay nadie en la oficina. El watchdog está bien hecho y por eso hoy no
   avisó. **La prueba real es el martes a las 10.**
2. **"`tests/run.sh` tiene 2 fallas preexistentes."** Ya no. Arregladas en la v14.16 (ver D).
3. **La v14.05 leyó la regla del agregado al revés** y metía pedidos de la página adentro de
   tandas de ISIS. Corregido en la v14.12. Si otra sesión vuelve a renombrar tandas, chequear que
   no vuelva a juntar Osa.
4. **"$3,88 M de diferencia por cajas distintas."** El número real es **−$4.944.393** en 42 NP, y
   la parte grande de los $10,7 M no es esa: son **$7,4 M de descuentos de cadena** que no tenemos
   cargados. Ver §"Los $10,7 M".

---

## F · Lo que queda, sin apuro

| Tema | Dónde está |
|---|---|
| **13 pedidos atrasados que nunca salieron** (6,98 m³): 9 de Cencosud (2444, sin tanda) + 4 con picking hecho y sin armado (D57C ×2, D57D ×2) | Los mira la administrativa el martes |
| **Recorridos feos**: D69 (mar 15, 55,7 km punta a punta por Luján) y D68 (lun 14, 38,9 km, mezcla GBA Sur con GBA Oeste). Los dos vienen armados así **desde ISIS**, no de la regla nuestra | Se rehace el análisis cuando termine C1, con todas las paradas y el tiempo desde el depósito |
| **Mostrar la fecha de entrega del súper** en "A Programar" (idea 9357) | Sin empezar **a propósito**: hoy viajarían 0 fechas y exponerla obliga a tocar la cadena `v_pedidos_web` → `v_pedidos_web_np`, que también usan el job de las 00:01 y el intradía. Se hace cuando entre la primera OC de verdad |
| **Idea 2482** — "➕ Agregar artículos" dentro de Gestión llamando a `edit_order_fast` de LK | Diferida por el dueño |
| **Auditoría del bot de WhatsApp**: 45 puntos, repo `loekemeyer/GestOpClientes` | Ese repo no está atado a esta sesión. Los puntos 2 a 6 (RLS de `wa_agente_*`, webhook sin firma, idempotencia por `wamid`, FAQs, escalaciones sin consumidor) son todos de allá |
| **Toledo** (Krikos): tiene regex de detección pero **no** parser | No agregar la regex sin escribir `parseToledo`. Falta una OC de muestra |
| **IMAP sin cifrar** (puerto 143): pedirle al hosting TLS/993 | Sin bloqueo urgente |
| **Planexware**: consulta de plan EDI enviada el 3/9 | Sin respuesta |
| **El script del agente de PDF de ISIS no está versionado** | Sólo existe en la PC de la oficina. Copiarlo y commitearlo |

---

## Para arrancar el martes, en orden

1. **A1** — rotar las dos claves. La lectura pública ya está tapada, pero siguen quemadas.
2. Después de las 10, mirar si entró algún PDF de ISIS. Si no entró, ahí sí ir a la PC (**A4**).
3. **A2** + **A3** para que Krikos empiece a andar.
4. A las 18:30 llega el digest con las **42 NP de cajas distintas**: esa es la lista a revisar.
5. **A5** — conseguir los descuentos de las cinco cadenas.
6. Cuando C1 termine: devolver el cron 75 y rehacer el análisis de recorridos con los tiempos.
