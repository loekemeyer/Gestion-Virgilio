# Estado y pendientes — al 2026-09-13 (última actualización: v16.60)

> **Para quien abra una sesión nueva:** esto es la foto del estado. Lo que falta de verdad está
> en la base, no acá: `select * from github_repo_problemas.v_problemas where estado='abierto'`.
> Este archivo dice **qué decidió el dueño**, **qué sólo puede hacer él**, y **qué quedó a medias**,
> que es lo que la tabla no cuenta.

## 1. Lo que sólo puede hacer Thomas (nadie más lo destraba)

| Qué | Dónde | Por qué está frenado |
|---|---|---|
| **Redeploy de Vercel** | dashboard de Vercel → Deployments → Redeploy | El sitio quedó en 2.3.374 y el repo va por 2.3.375. Hay 6 commits sin publicar desde el 11/09 18:30, pero **sólo uno toca la página** (`64f98ba`, el aviso de renglones sin match en OC de súper); los otros 5 son backend y andan igual. **Al 13/09 hay dos commits más en LK** (`d4f79e7` doc de Cloudflare y `68c676e` el fix de `krikos-ingest`), los dos backend/doc: no cambian la página. Se confirma arreglado cuando `https://loekemeyer.com/version.js` devuelva 2.3.375. **No hay acceso a Vercel desde la sesión.** Problema 16. |
| **Rotar el token de Meta WhatsApp y la API key de OpenAI** | consolas de Meta y de OpenAI | Ver la decisión en el punto 2. Problema 20. |
| **Correr de nuevo el workflow `build-deploy.yml` de Planify** | GitHub Actions de `loekemeyer/Planify` | Es lo ÚNICO que falta para poder apagar las claves legacy. La excepción del Storage **ya no existe** (medida el 13/09, v16.56): con la `sb_publishable_` el Storage escribe bien en los dos proyectos. Lo que no se pudo re-medir desde acá son las `sb_secret_`, y ese workflow es el caso testigo que falló (runs 112-115 del 11/09). Si pasa, se aprieta `Disable JWT-based API keys`. Problema 12. |
| **Decidir qué hacer con los 10 pedidos ya programados de clientes con deuda** | con Vivi / cobranzas | Salen en rojo arriba de la columna Cuarentena (v16.57). Torres y Liva $32,1M entrega el lunes 14. **No se retiran solos a propósito**: sacar un pedido de una tanda armada rompe el picking. Problema 14. |
| ~~Cargar `KRIKOS_IMAP_PASS` en el Vault de LK~~ | — | **YA ESTÁ** (comprobado 2026-09-13): el secreto está en el Vault de LK desde el 11/09 y la rama de Krikos ya está en `main`. El ingest corre: 21 OC en la bandeja y `ok:true` en cada corrida. |

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
8. **187 mails viejos de Krikos nunca ingresados**: el cron mira 90 días y ésos son más viejos.
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
