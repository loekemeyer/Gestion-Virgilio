# CLAUDE.md — Producción Virgilio

App web (PWA, sin framework) para registrar producción de depósito (picking,
armado, carga de camión, recepción). La usan operarios desde el celular y
supervisores desde un monitor. Se sirve por GitHub Pages desde `main`.

## ⚠ Antes de responder preguntas sobre datos o funcionamiento

**Leé `GUIA-PROYECTO.md`** (en la raíz del repo). Es la guía viva del proyecto:
modelo de datos, códigos de acción, flujo, de dónde salen los m³, cómo se calculan
las horas, recetas de SQL y reglas de inconsistencia. Respondé **basado en eso, no
inventes**.

**Mantené `GUIA-PROYECTO.md` actualizada** cuando cambie el código o los datos
(nuevos códigos `opcion`, tablas, flujo, versión, etc.).

## Quick-ref

- **Datos**: Supabase, proyecto `Control Partes Talleristas`, id
  `hrxfctzncixxqmpfhskv`. Consultar con la herramienta MCP `execute_sql`
  (`project_id = hrxfctzncixxqmpfhskv`).
- **Tabla central**: `Registros_Produccion_Virgilio` (log de eventos; `opcion` =
  código de acción, `texto` = código de tanda/pedido, `ts_inicio` no nulo = cierre).
- **m³ NO están en Supabase**: salen del Google Sheet "PPP Pedidos Entregados 2026"
  (col `Mt3`, NO col H). No se pueden calcular desde el sandbox (Google bloqueado);
  sí desde el navegador / monitor.
- **Zona horaria**: `America/Argentina/Buenos_Aires`, UTC-3 fijo.
- **Versión**: `APP_VERSION` en `index.html` y `SW_VERSION` en `sw.js`.
- Legajos `0` y `1` (Pruebas) son test/basura: excluir de reportes.

## Selector de planta (`/selector/`)

Subcarpeta con un **selector "¿Dónde vas a trabajar hoy?"** (Virgilio / Cervantes).
Rescatado del repo `App-Produccion` (que combinaba ambas apps **por copia**; se
descartó por la pena de mantener copias viejas). Acá el selector **NO copia las
apps: linkea a las publicadas**, así nunca quedan viejas:

- **Virgilio** → `../` (la raíz de este repo).
- **Cervantes** → `https://loekemeyer.github.io/Registro-Produccion-2.0/` (constante
  `CERVANTES_URL` en `selector/index.html`; ajustar si cambia la URL/repo de Cervantes).
- Recuerda la última planta usada (`localStorage` `appprod_ultima_planta`) y la marca
  "Última vez", pero **no redirige solo** (la asignación cambia día a día).
- `selector/sw.js` no cachea (mismo patrón que las apps). Archivos: `index.html`,
  `manifest.json`, `sw.js`, `icon.svg`.
- La app Virgilio (raíz) tiene un botón **"← Cambiar planta"** en `#legajoScreen` que
  va a `selector/`.
- El selector NO es la entrada por defecto (la raíz sigue siendo la app Virgilio). Si
  algún día se quiere que sea la entrada, mover el selector a la raíz y Virgilio a una
  subcarpeta (cambia la URL actual y la app de Play Store).
- Para verlo online: `https://loekemeyer.github.io/<repo>/selector/`. Requiere que
  **Cervantes** tenga su propio GitHub Pages activo para que su tarjeta no dé 404.

## Git

- **Este es un repo de PRUEBA** (`tv-v`), espejo de Producción Virgilio. Trabajar
  **directo en `main`**: commitear y pushear ahí sin preguntar.
- Estilo de commits: `vX.YZ: descripción` cuando hay bump de versión.
