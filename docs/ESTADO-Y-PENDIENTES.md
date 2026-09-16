# Estado y pendientes — al 2026-09-16 (última actualización: v18.87)

> **2026-09-16, tanda de Luis (v18.87) — las dos alertas de la PPP.**
>
> **1. Tanda por CAMIÓN (v18.87, §3.ib).** `D69F` del 21/09 llevaba 8 NP de Jazquel en Balvanera/Once
> (Capital) metidas en un camión de GBA Oeste. Regla de Luis: *"¿lo pondrías en el mismo camión?"* →
> **el DÍA sigue siendo uno solo por cliente, la TANDA se parte por camión**. La causa **no** era
> `gv_ppp_web_tanda_abierta_cliente` ni el pase (a1) —que fue lo primero que se arregló y no
> alcanzó— sino `ppp_web_armar_tandas`, que agrupaba `group by cliente` y tomaba `min(camion)`.
> Centinela nuevo: `select * from public.gv_ppp_tanda_camion_mezclado;`
>
> **2. Súper mezclado (v18.87, §3.ic, problema 334).** La tabla que usa el aviso **era la correcta**
> (`GV_Supers`, 19 activas; `gv_clientes_horario` habría sido la equivocada). Pero **quedaba una
> cuarta puerta abierta**: `_open` —las tandas que todavía acumulan— filtraba súper por ZONA, y un
> súper con zona numérica (Dorinka, Diarco: *"Zona 5 - GBA Oeste"*) pasaba de largo. Medido: un
> cliente común caía **en la misma tanda** del súper. Cerrada con `gv_es_super`. Y el aviso ahora
> dice **AUTOMÁTICA / MANUAL / ISIS** con quién y cuándo; para E11 del 16/09 la respuesta es
> **AUTOMÁTICA** (15/09, el día antes de que la v18.60 tapara la puerta anterior).
>
> **Lo que queda para una persona, no para el código:**
> - **`D69F` (21/09)**: las 8 NP de Jazquel de CABA Centro siguen en el camión de GBA Oeste. Es dato
>   real de una tanda ya programada: moverlas es decisión de un supervisor.
> - **Camión `E11` (16/09)**: Dorinka (súper) sigue con Todo Bazar y Goldar. Igual, se mueve a mano.
> - **Problema 327** (abierto): 9 NP de agosto facturadas que volvieron al depósito (CCN + FSS, sin
>   CRN) y desaparecieron de todas las pantallas.

> **2026-09-15, revisión general pedida por Thomas (v18.51, §3.hi de la doc de Supabase).**
> *"Está andando mal en general la app y su paso a paso."* Seis agentes sobre `main` + los 10
> chats del día. **Lo que NO es:** la suite está toda en verde, ninguna sesión pisó código de otra
> (70 commits de 6 sesiones, 0 líneas perdidas), el motor de stock cierra (0 diferencias en 485
> códigos). **Lo que SÍ es:**
> 1. **La vista de Pedidos Entregados tiraba HTTP 500 por timeout** (236 en 6 h; 7,97 s contra un
>    tope de 8 s) y la pantalla caía en silencio a un fallback de 60 días → arreglada (222 ms).
> 2. **Tocar una NP web en la tabla de la PPP no abría el detalle** (42 errores en un día) → arreglado.
> 3. **El chip «▶ seguir» del picking (v18.46) abría la tanda sin lo ya pickeado** → arreglado.
> 4. **Lecturas cortadas en 1000 filas** (RT ya perdía 524; reparto y faltantes a 50 del corte) → paginadas.
> 5. **Los operarios corrieron 25 versiones en un día** (v17.87 → v18.47, un reload cada 15–20 min) y
>    **la versión fue para atrás 3 veces** por una sesión sobre `main` viejo (problema 290). Esto es
>    de proceso, no de código: seis sesiones a `main` en paralelo. **Propuesta:** una sola sesión
>    "de guardia" bumpea y pushea a `main`; las demás entregan en rama y se mergean de a una.
> 6. **Hoy no se facturó nada** (0 tics; ayer 38; 24 NP armadas sin facturar). No es un bug: la
>    pantalla se abrió 1.282 veces y nadie tildó. Avisar a Marianela.
>
> **Para Luis, mañana 16/09:** el camión **E11 mezcla el súper Dorinka (E11B) con 3 clientes
> comunes** (E11A/C/D). Se armó automático el 15/09 (§3.hl). El automático ya no programa súper (v18.31)
> ni suma clientes al camión de un súper (v18.60); mover a Dorinka es a mano y el panel de errores de la
> PPP lo muestra en rojo (v18.59). Y **D71 lleva 9,25 m³ en una sola NP** (154 % del tope).
> **116 (E11A) ya está corregido** (Thomas dio el OK con la captura de la tarea 3424): góndola 0, Pickeados 0.
> **119 (E11A) también corregido** con el OK de Thomas (*"sí, el 119 también"*, tarea 3460): el picking
> escribió −50 con 49 en góndola y nadie marcó el "de menos" → `a_facturar −1` y `terminado +1`
> (`fix119_E11A_20260915_*`). Góndola 0, a facturar 49. `vista_saldos_stock` sin góndolas negativas.
> **"Mes en curso" de Proyección:** restituido en v18.58 (Luis: lo había sacado otra persona en su sesión).
> **Las tres tareas que Luis dejó para después se hicieron en v18.66** (§3.hn): v18.31 parte 3 aplicada
> (el guard con `LIKE` la saltaba), Cervantes sin CDN, y los 5 arreglos de celular. Detalle: §3.hi.

> **2026-09-15, tanda de la tarde (v18.16 / v18.17).** Se cerró el handoff
> `docs/HANDOFF-OC-Y-PROYECCION-20260915.md` entero: los códigos NNNL salieron de la pantalla
> Stocks y dejaron de subcontarse en el generador de OC, la proyección pasó a vivir en **una sola
> tabla** (se borró `GV_Proyeccion_Emp`, el cron 40 y el motor por empresa) y se encendió el
> desglose de ventas por cliente del pop-up de Proyección. Problemas **218** y **222** cerrados;
> tareas Planify 3405, 3409 y 3412 cerradas.
> **Lo único que quedó esperando a Thomas: prender el cron 50 `ocs-auto-miercoles`** (hoy en
> `active=false`; generaría 95 líneas / 14 proveedores / 3.586 cajas). Ya no está frenado por
> datos malos — el uni×caja se arregló —, es una decisión de plata.
> Y quedaron **dos problemas nuevos `abierto`**: el excedente de una OC no queda registrado en
> ningún lado, y 104 de 354 filas de `OC_Maximos` no tienen proveedor.

> **2026-09-15, tanda de la noche (v18.19 → v18.48, con Luis).** Se construyó entera la pestaña
> **Modificar Pedidos** de la PPP y quedó cerrada de punta a punta: se edita la **dirección de
> entrega** (dando de alta la nueva como opción elegible del cliente) y el **contenido**
> (cantidades, sacar renglones, agregar códigos) de los pedidos de **LK**, de **Chef** y de las
> **NP de ISIS**, con **quién** y **justificativo obligatorios**, log en `GV_Pedido_Mod_Log`
> (Gestión, escrito por LK vía FDW en la misma transacción que el cambio), **badge ✏ MOD en la
> columna NP de Facturación** con el detalle —para tipearlo igual en ISIS—, recálculo de NP y
> tanda (web, vía el `ppp_web_resync` que ya existía), recálculo de **m³ por delta** (ISIS) y
> prompt para devolver el pedido a *A Programar* si le cambia la zona. Tarea Planify **3416
> cerrada**.
>
> **Para Chef hizo falta que Thomas tocara el otro proyecto**: el FDW de LK podía leer pero no
> escribir. Corrió dos `grant` (uno **por columna**, sólo `sheets_payload`) y tres `policy` —las
> policies hacen falta además de los grants porque en Chef esas tablas tienen RLS—. ⚠ Y ojo:
> `has_table_privilege(…,'UPDATE')` devuelve **false** con un grant por columna aunque esté bien;
> se verifica con `has_column_privilege(…)` o con el `update` de prueba en transacción abortada.
>
> **Cuatro problemas cerrados en el camino, los cuatro encontrados midiendo, no buscándolos:**
> · el FDW de LK a Chef se conectaba con el **password de ejemplo del instructivo** (literal,
>   adivinable) — rotado en las dos puntas y verificado;
> · `GV_Web_Cancelados` tenía **RLS sin ninguna policy**, así que la app **no veía las
>   anulaciones** (la misma NP leía `desarmado` como `postgres` y `sin_programar` como la app);
> · por lo mismo, **LK no podía leer `gv_pedido_web_estado_pagina`** y eso rompía `edit_order_fast`,
>   o sea que **un cliente no podía editar su pedido desde la página**;
> · **`vista_tanda_m3` ignoraba todos los overrides**: una NP movida de tanda seguía sumando su m³
>   en la vieja. 14 tandas con m³ ajeno y 14 sin el suyo; el total pasó de 1041,978 a 1045,631 m³.
>
> **Las 8 tablas con RLS y sin policies detrás de vistas `security_invoker` (problema 236) eran
> FALSA ALARMA, medido el 15/09 (v18.63).** La app no lee esas vistas: llama ocho RPC `SECURITY
> DEFINER` y las ocho devuelven filas, como `anon` y como `authenticated`. El patrón es
> deliberado —la RLS sin policies es lo que impide que la anon key, que es pública, lea en crudo
> los pagos a proveedores—, así que **no se agregaron policies**. Lo que sí se corrigió es el
> silencio: esas 7 vistas eran legibles por `anon` y devolvían **0 filas sin dar error**, que es
> justo lo que hace que una pantalla nueva parezca rota sin decir por qué. Se les revocó el
> SELECT. **La trampa de lectura, para no repetirla:** "tabla con RLS sin policies detrás de una
> vista que anon puede leer" **no** es pantalla rota — hay que mirar si el front llama la vista o
> el RPC, y acá existen **una vista y una función con el mismo nombre** (PostgREST resuelve la
> función). §3.hm.
>
> **Lo único que quedó esperando a Thomas de esta tanda:** la tarea Planify **3366** — que los
> pedidos facturados pasen solos a *En Salida* con el badge «Esperando carga / Esperando retiro».
> Lo pide Luis; **existía en la v13.62 y Thomas lo hizo sacar en la v15.85**, así que no se toca
> sin que él confirme. La propuesta está lista: sólo los pedidos con fecha ≥ hoy (22 de 30), un
> `UPDATE` de `PPP_Web_Config.en_salida_solo_cargadas` y renombrar un chip que ya existe.

> **Para quien abra una sesión nueva:** esto es la foto del estado. Lo que falta de verdad está
> en la base, no acá: `select * from github_repo_problemas.v_problemas where estado='abierto'`.
> Este archivo dice **qué decidió el dueño**, **qué sólo puede hacer él**, y **qué quedó a medias**,
> que es lo que la tabla no cuenta.

## 1. Lo que sólo puede hacer Thomas (nadie más lo destraba)

| Qué | Dónde | Por qué está frenado |
|---|---|---|
| **Redeploy de Vercel** | dashboard de Vercel → Deployments → Redeploy | El sitio quedó en 2.3.374 y el repo va por 2.3.375. Hay 6 commits sin publicar desde el 11/09 18:30, pero **sólo uno toca la página** (`64f98ba`, el aviso de renglones sin match en OC de súper); los otros 5 son backend y andan igual. **Al 13/09 hay dos commits más en LK** (`d4f79e7` doc de Cloudflare y `68c676e` el fix de `krikos-ingest`), los dos backend/doc: no cambian la página. Se confirma arreglado cuando `https://loekemeyer.com/version.js` devuelva 2.3.375. **No hay acceso a Vercel desde la sesión.** Problema 16. |
| **Revocar la API key de OpenAI** `sk-proj-FBnb7LWW…` | consola de OpenAI | **Cambió el 13/09 de madrugada.** Thomas dijo *"2 borralo"* y la clave **ya no está en ningún deploy**: `leer-factura` pasó a ser un tapón que contesta 410 y `leer-produccion-foto` la lee sólo del secret `OPENAI_API_KEY` (que hoy NO está cargado, así que contesta 500 claro). Falta lo único que no puedo hacer yo: **revocarla en platform.openai.com**, porque quien la haya copiado antes la sigue teniendo. Y si querés que la foto de planilla vuelva a andar, cargar ese secret. Problema 106 cerrado (GP2 `8e7dfce`). |
| **Rotar el token de Meta WhatsApp** | consola de Meta | Ver la decisión en el punto 2. Problema 20, que baja de 11 Edge Functions a 9: el token de Meta en 3 de Gestión y 6 credenciales de LK. |
| **Correr de nuevo el workflow `build-deploy.yml` de Planify** | GitHub Actions de `loekemeyer/Planify` | Es lo ÚNICO que falta para poder apagar las claves legacy. La excepción del Storage **ya no existe** (medida el 13/09, v16.56): con la `sb_publishable_` el Storage escribe bien en los dos proyectos. Lo que no se pudo re-medir desde acá son las `sb_secret_`, y ese workflow es el caso testigo que falló (runs 112-115 del 11/09). Si pasa, se aprieta `Disable JWT-based API keys`. Problema 12. |
| **Decidir qué hacer con los 10 pedidos ya programados de clientes con deuda** | con Vivi / cobranzas | Salen en rojo arriba de la columna Cuarentena (v16.57). Torres y Liva $32,1M entrega el lunes 14. **No se retiran solos a propósito**: sacar un pedido de una tanda armada rompe el picking. Problema 14. |
| ~~Cargar `KRIKOS_IMAP_PASS` en el Vault de LK~~ | — | **YA ESTÁ** (comprobado 2026-09-13): el secreto está en el Vault de LK desde el 11/09 y la rama de Krikos ya está en `main`. El ingest corre: 21 OC en la bandeja y `ok:true` en cada corrida. |

| ~~Sacar la app VIEJA (`Produccion-Virgilio`) de las máquinas~~ **DECIDIDO 15/09** | avisado al equipo | **Thomas, 15/09: *"nueva página para mañana, no usen más la otra, usá esta"* → `https://loekemeyer.github.io/Gestion-Virgilio/`, desde el 16/09.** | **Medido el 15/09: esa app sigue en uso** (33 eventos con `gv_app` NULL en 3 días, el último el 15/09 08:02) y por eso Franco recibió remitos con `Cliente —` durante 3 días: el rename de las tablas PPP del 12/09 le rompió los endpoints. Lo tapé con dos vistas de compatibilidad (§3.gc), así que **hoy imprime bien** — pero esa app está 5 versiones mayores atrás y cada cambio de base la puede volver a romper. Las dos vistas son un **puente**: se borran cuando `select count(*) from public."Registros_Produccion_Virgilio" where gv_app is null and ts_cliente >= now() - interval '7 days'` dé 0. Problema 202. |

## 2. Decisiones del dueño que NO hay que revisitar

- **2026-09-13 — las credenciales de terceros NO se rotan por ahora.** Textual: *"No la cambiemos
  por ahora"*. El problema 20 queda **abierto a propósito**. Contexto medido antes de decidir:
  esas credenciales **no están en ningún repo público** (se barrió todo el historial de los dos:
  0 claves de OpenAI, 0 tokens de Meta, 0 `service_role`), o sea que la exposición es al bundle de
  la función, que sólo lee quien ya tiene acceso al proyecto. **Riesgo que queda mientras tanto:**
  quien tenga acceso al proyecto puede mandar WhatsApps como la empresa y gastar crédito de OpenAI.
- **El orden correcto cuando se retome** (no invertirlo): rotar en la consola del tercero →
  `select vault.create_secret('<valor nuevo>', 'META_WA_TOKEN');` → redeployar la función leyendo
  `gv_secret()`. Al revés obliga a copiar el secreto viejo a mano para una credencial que igual
  hay que tirar. **El habilitador ya está hecho y probado**: `gv_secret(p_name)` en Gestión
  (v16.47, sólo `service_role`) y `krikos_secret` en LK.
- **La hoja "PPP Pedidos Entregados" no existe más** y `PPP_Entregados_Meta` no se usa (v16.44).
  Está en el Quick-ref del `CLAUDE.md`; no volver a escribir que el Sheet es el upstream.

- **2026-09-15 — la ubicación del armado (AUB) se cargaba de rebote, por un bug.** Hasta la v12.98
  el modal salía porque el operario tocaba DOS veces «terminar» (el botón viejo que quedaba en
  pantalla). Al tapar ese doble TAP se apagó la pregunta: **0 eventos AUB entre el 04/09 y el
  15/09**, con ~10 armados por día. Arreglado en la v18.00 (`compTerminar` pregunta él mismo) con
  regresión en `tests/comp-terminar-unificado.cjs`. Si vuelve a aparecer en 0, mirar ahí primero.

## 3. Lo que quedó a medias (deuda que dejé yo, no está en la tabla)

1. **4 de las 5 Edge Functions de LK del problema 21 no están versionadas.** Sólo existen
   deployadas. `notify-tracking-status` ya está en `pagina-lk-copia` (`e221d81`); faltan
   `sheets-entregas-proxy`, `procesar-pedidos-web`, `procesar-pedidos-v2` y `procesar-pedidos-db`.
   No hay CI que las deploye, así que nada las va a pisar — pero si alguien las redeploya desde
   cero, se pierde el guard de seguridad.
2. **`SHEETS_SECRET` sigue hardcodeado** en `sheets-entregas-proxy`. Moverlo al Vault exige tocar
   también el Apps Script de Google del otro lado, que no se puede editar desde acá.
3. **`osa/js/app.js` y `script.js` (repo LK)** mandan `Bearer (token || ANON_KEY)`. Esa rama no se
   usa en la práctica (sin sesión el pedido tampoco se crea) y está dentro de un `.catch()`, pero
   **si aparece un 403 en la Base Picking, ése es el lugar a mirar**.
4. **98139/590E en `Entregas_Virgilio`**: el pedido trae 1 línea de 10 y Entregas tiene 8+10. El 8
   sobra, pero es un caso aislado sin segunda fuente que lo confirme, así que se dejó (v16.46).
5. **Avisarle a Compras** que 55 códigos de Despiece que antes no calculaban consumo de cartón
   ahora sí, así que van a empezar a aparecer en las alertas de compra (v16.42).
6. **Góndola: el mapa y la capacidad no coinciden en 107 celdas** (problema 84, mitad abierta).
   `Capacidad_Sector` manda la capacidad y `GV_Lugar_Item` manda el mapa, y la migración quedó a
   medias (`GV_Lugar_Item.cajas_max` está en NULL en las 782 filas). Medido: 40 códigos afectados,
   **832 cajas de capacidad fantasma** y 26 códigos en el mapa sin capacidad, 21 con stock real.
   **No lo puedo resolver yo**: cuál de los dos mapas manda es de quien cargó la góndola (Luis, el
   11/09). Está a la vista con `select * from public.gv_gondola_divergente;` (vacía = todo bien).
7. **Las 14 líneas `(pedido, articulo)` duplicadas de `GV_PPP_Base_Pedidos`** (problema 80) siguen
   ahí: son datos reales y el protocolo pide permiso explícito. La tabla hoy es histórica.
8. **La pantalla de Facturas del admin viejo quedó rota por matar la clave de OpenAI.**
   `cervantes-admin/entero/Facturas/index.html` llama a la Edge Function `leer-factura`, que desde
   el 13/09 es un tapón que contesta **410**. Está linkeada desde
   `cervantes-admin/entero/Inicio/index.html:1256` ("Lectura de Facturas Entrantes") y ese admin se
   abre desde el panel supervisor, o sea que **es alcanzable y hoy no lee ninguna factura**. Es
   consecuencia aceptada de sacar la clave, no un descuido. La copia gemela de `gp2/` ya se borró
   (v16.75), porque su origen la había borrado. **Decide Thomas:** sacarle el botón del menú de
   `entero/` (sería el cuarto parche propio de esa copia) o dejarlo hasta apagar el admin viejo.
   `GestionProductivaEntero` no está en el alcance de esta sesión. Problema 79, **sigue abierto**.
9. **`flejes_stock_planta` es huérfana y nadie lo había confirmado.** Verificado el 13/09:
   **0 funciones, 0 vistas, 0 referencias** en el front de Gestión y de GP2; 54 filas. O sea que las
   47 de 54 divergencias del problema 78 **no le hacen daño a nadie hoy** — pero el problema queda
   **abierto** a propósito: nadie arregló la divergencia, simplemente resultó inerte. Si algún día
   alguien la enchufa, arrastra los 47 valores malos.
10. **187 mails viejos de Krikos nunca ingresados**: el cron mira 90 días y ésos son más viejos.
   Traerlos es un `{"action":"sync","days":365}` a mano — decisión del dueño, no se hizo.

## 4. Tareas de Planify abiertas de esta sesión

- **3235** `Th Limpiar los datos duplicados de Supabase` — seguir con los problemas abiertos.
- **3237** `Th Unificar esquemas y borrar tablas al pedo` — 10 tablas huérfanas + 3 columnas de
  `uni_x_caja` que exigen tocar el front.

## 5. Qué se cerró en esta tanda (2026-09-12 / 13), por si hay que rastrear algo

| Problema | Qué era | Versión |
|---|---|---|
| 104 | el stock y las OC eran ciegos a 3.415 cajas de demanda web | v16.43 |
| 71 | espejo muerto de PPP; "entregado" pasa a salir de Recepción Remitos | v16.44 |
| 105 | 3 funciones que la v16.39 rompió al borrar `precios_venta.uxb` | v16.45 |
| 72 | 46 filas duplicadas en `Entregas_Virgilio` (las otras 16 eran legítimas) | v16.46 |
| 21 | **crítico** — 5 Edge Functions de LK abiertas sin autenticación | LK `e221d81` |
| 69 | comprar y cobrar usaban UxB distinto en 33 códigos | ya estaba, por v16.38 |
| 84 (mitad duales) | 3 tablas con la misma lista de duales; ahora 1 tabla + 2 vistas | v16.49 |
| 84 (mitad góndola) | **sigue abierta**; se midió bien (107, no 204) y se dejó el centinela | v16.50 |
| 92 | la capacidad de góndola de un dual sumaba las dos góndolas: por LK no avisaba nunca | v16.51 |
| 80 (parcial) | el detector de NP dobles sacaba la fecha de una tabla congelada | v16.51b |
| 27 | `krikos-ingest` armaba un `in()` con todos los `mail_uid` y moría con ventanas largas | LK `68c676e` |
| 19 | `admin-login-otp` mandaba la anon **legacy** de Gestión; el repo ya tenía la nueva y nunca se redeployó | v16.55 |
| 12 (avance) | **cayó el bloqueo del Storage**: con la clave nueva se escribe bien. Falta sólo el workflow de Planify | v16.56 |
| 14 | la Cuarentena no veía los pedidos que YA tienen tanda: 10 con deuda, $47M | v16.57 |
| 58 | una NP armada sin tanda no aparecía en Facturación: 8 invisibles, 638 cajas de Cencosud | v16.58 |
| 53 (avance) | la Conciliación leía el `precio_unit` malo de ISIS; ahora despeja el precio del importe | v16.59 |
| 76 | `wa_np_snapshot` fingía estar fresca: 14 direcciones viejas con `updated_at` de hoy | v16.60 |

### Segunda tanda, madrugada del 13/09 (v16.70 → v16.76)

| Problema | Qué era | Dónde |
|---|---|---|
| 106 | la **clave de OpenAI** estaba pegada como fallback en dos Edge Functions. La expuesta de verdad no era `leer-factura` (verify_jwt=true, llamador huérfano) sino **`leer-produccion-foto`**, con `verify_jwt=false` y sin tope | GP2 `8e7dfce` |
| 113 | la matriz 78 del rompenueces modelada como dos pasos paralelos. **El síntoma registrado era falso** (no se cobraba dos veces: `v_costo_componente` agrupa la mano de obra por matriz); el problema real era estructural | GP2 `bc75f15` |
| 114 | el **pintado de Jade** cargado por mitad ($305 en B1 y en B2). Lo encontró Thomas preguntando por qué el 707 costaba $377 más que el 507. Corregido a $152,50: el 707 baja de 1.264,56 a **959,56** | GP2 `bc75f15` |
| 111 | el plan decía migrar `Racks_Planimetria` a `GV_Lugar` y eso perdía las cantidades | v16.63 `f11af92` |
| 46 | 7 artículos con una parte en la receta que ninguna rama de su ruta llevaba. De **13 pares a 2**, y los 2 que quedan son del tallerista "Fábrica" (legítimos) | GP2 `bc75f15` |
| 110 (avance) | el bloque 1: `1546903` y `VASTIDOR` unificados en **`546V`**, 891 cajas en AD12/AE09/X13. **Sigue abierto**: `Movimientos_Stock` de `546V` = 0, así que esas cajas todavía no se cuentan | v16.71 |

**Lo que se construyó en la misma tanda** (no son problemas, son pedidos):

- **El bump de versión dejó de ser a mano**: `scripts/bump-version.cjs` mueve `APP_VERSION`,
  `SW_VERSION` y el `?v=` de `recepcion.js` juntos, y `tests/version-tokens.cjs` lo vigila. Era la
  causa raíz de que `main` quedara en rojo dos veces la noche del 13/09 (v16.64 y v16.67). v16.70.
- **Jornada de camión**: `GV_Vehiculo_Propio` (la kangoo de Luján deja de contar como fletero), la
  zona de la NP 97889 corregida por override, 4 direcciones geocodificadas, y el recálculo del
  14-18/09 en `docs/JORNADA-CAMIONES-14-18-09.md`. v16.72 / v16.74.
- **Generador de OC**: los 5 `63xE` con proveedor `Log/ Fabr`, `Articulos_Cajas` como 4ª fuente de
  nombre y **`LIBRE` fuera del universo** (no es un artículo: es la celda vacía de
  `Capacidad_Sector`, y entraba porque A83 tiene 72 cajas). De 15 códigos sin nombre a **5**. v16.74.
- **Bandeja de Krikos**: el badge muestra los cuatro estados (LK `21ac9b0`, espejado en v16.73) y
  **las OC que FALLAN ahora viajan a Gestión** (LK `1e925c2`), con ventana de 30 días sobre la fecha
  del mail para que las 6 históricas de junio/julio no queden como avisos muertos. Antes, una OC
  que fallaba sólo se veía abriendo el panel de LK.
- **GP2**: la pantalla **Tablet** rehecha desde cero (su código se había perdido: la base tenía
  `tablet_bundle`/`tablet_registrar` vivas y `main` no tenía el front), el circuito del **pincel**
  documentado, y el cruce contra `loekemeyer.com` — **11 artículos activos en la página sin despiece
  en GP2**.
- **Planify**: `procesos.automatizaciones` (6 secciones del proceso escrito marcadas como ya
  automatizadas), 3 áreas y 9 responsables nuevos, la cola de revisión de **203 a 158**, y las 40
  preguntas de las 7 personas en `docs/PREGUNTAS-40-POR-PERSONA.md`.

Y las tablas `PPP_*` de la era ISIS pasaron a nombre `GV_*` sin perder el trabajo pendiente (v16.45).

**Hallazgo grande de esta tanda, que no es un bug pero hay que saberlo:** el **espejo de ISIS
entero está congelado desde el 04/09** (`GV_PPP_Base_Pedidos` y `GV_PPP_Programacion_Diaria`,
última NP 98704 Salvetti D60G). No hay cron que las alimente: se escribían desde afuera por
PostgREST, o sea desde el Apps Script de la hoja PPP, que ya no existe. Es la consecuencia
esperada de haber pasado todo a Gestión — pero **si ISIS volviera a cargar pedidos propios,
Gestión no se entera**.

## 6. Reglas nuevas que salieron de esta tanda (ya están en `CLAUDE.md`)

- `DROP COLUMN` → barrer también `pg_proc.prosrc`, y **llamar** a las funciones después. Un
  `DROP COLUMN` limpio no prueba nada.
- Renombrar una tabla es mucho más barato que reescribir sus consumidores: **las vistas van por
  OID**, sólo las funciones y el front nombran por texto.
- El `CREATE` completo de cada vista va **en el repo**, no "aplicado en la base".
- El backup se guarda con la **clave primaria**; un join por columna no única multiplica.
- Medir con la **misma granularidad** con la que se va a escribir.
- **No creer el registro del problema: re-medirlo.** Tres veces en esta tanda la descripción vieja
  estaba mal — el 84 decía 204 divergencias (son 107; 97 eran racks), decía que `Codigos_Duales` la
  usaban `empresa_de_np()` y el front (no la usa nadie), y el 27 y el 92 ya estaban medio resueltos
  sin que el registro lo dijera.
- **Un pendiente viejo puede estar hecho.** `KRIKOS_IMAP_PASS` figuraba como pendiente del dueño en
  **cinco** archivos y estaba cargado desde el 11/09. Antes de pedirle algo, comprobarlo.
- **"Está en el repo" no es "está arreglado" para una Edge Function.** Se deployan a mano, sin CI:
  el problema 19 estaba corregido en el archivo desde el 11/09 y en producción seguía la clave
  vieja. Mirar `get_edge_function`, no el `git log`.
- **Un `updated_at` fresco no prueba que el contenido lo sea** (problema 76): el `ON CONFLICT`
  pisaba la fecha siempre y el dato nunca. Comparar contra la fuente, no contra el timestamp.
- **En un `ON CONFLICT ... DO UPDATE`, `s` (o como se llame el alias del INSERT) es la fila VIEJA**,
  no la que entra. `coalesce(s.x, excluded.x)` = "escribí sólo la primera vez".
- **La proyección de la Est Madre NO es evidencia de que algo se venda** `[Thomas, 2026-09-13,
  textual: "No hay chance que se venda 486 uni de 515"]`. `GP2.est_madre.proy_uni_mes` proyecta
  sobre lo vendido histórico y arrastra discontinuados. Antes de usar ese número para decidir un
  alta, mirar ventas reales o preguntar.
- **Cuando el dueño dice "formato X", mirar la tabla de formatos antes de buscar un componente.**
  "Cartón huevo" no era un cartón compartido: `Huevo` es un `carton_formato` (el troquel) que ya
  usaban 36 cartones. Cada artículo tiene el suyo; lo que se comparte es el formato.
- **Un cartón cuyo número no cruza con ningún artículo es un artículo que falta, no un cartón mal
  codificado.** De 152 cartones con número, 147 son un código de artículo; de las 5 excepciones,
  `C1B` (574) y `O6A` (809) son artículos del grupo A que todavía no existen — el cartón ya está.
- **`colgado = []` es inalcanzable en una convergencia.** `__sim_articulo` corre cada ruta entera,
  así que tres ramas producen tres veces la pieza de salida. El criterio correcto es "se comporta
  como el testigo 521", no "no cuelga nada".
- **`git add -A <ruta>` sobre una ruta ya borrada aborta el add ENTERO** y el commit sale con la
  mitad de lo que ibas a subir. Mirar `git status` DESPUÉS de commitear, no sólo antes (pasó en
  `329fe3f`, corregido en `fd03f99`).
- **Antes de hacer viajar algo a una pantalla, mirar qué ventana de fechas usa.** Al hacer que las
  OC en `error` lleguen a Gestión, el corte por `created_at` habría mandado 6 avisos muertos (su
  `created_at` es el del backfill, no el del mail). El corte va por la fecha del hecho real.
