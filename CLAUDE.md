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

## Estructura: dos apps en un repo (Virgilio + Cervantes + selector)

Este repo junta **las dos plantas** (reemplaza al viejo repo `App-Produccion`, que se
borró). Layout:

- **Raíz** → app **Virgilio** (sin cambios; la usa también la app de Play Store/TWA).
- **`/cervantes/`** → **copia** de la app Cervantes (repo fuente `Registro-Produccion-2.0`).
- **`/selector/`** → pantalla **"¿Dónde vas a trabajar hoy?"** que linkea a ambas:
  Virgilio `../` y Cervantes `../cervantes/`. Recuerda la última planta usada
  (`localStorage` `appprod_ultima_planta`, marca "Última vez"), **no redirige solo**.
- Botón **"← Cambiar planta"** en la pantalla inicial de cada app → va al `selector/`.
- `selector/sw.js` y `cervantes/sw.js` no cachean (mismo patrón que Virgilio). Las dos
  apps conviven sin pisarse: tablas Supabase distintas (`Registros_Produccion_Virgilio`
  vs `Registros Produccion Cervantes`), IndexedDB y claves `localStorage` con prefijos
  distintos. Cervantes usa rutas relativas y SW con scope `/cervantes/`.
- **Entrada por defecto = Virgilio (raíz)**, no el selector (para no romper la URL
  actual ni la app de Play Store). Si se quisiera el selector como entrada, mover el
  selector a la raíz y Virgilio a `/virgilio/` (revisar TWA).
- ⚠ **`/cervantes/` es una copia**: si Cervantes cambia en `Registro-Produccion-2.0`,
  hay que **re-traer** los archivos (`app.js`, `index.html`, `manifest.json`,
  `styles.css`, `sw.js`) y volver a poner el botón "Cambiar planta". Último sync desde
  commit `d2d6a59` (2026-06-04).

## Agentes diarios + código de 4 dígitos (Telegram)

Loop de dos etapas (tareas programadas, sesión nueva; **solo proponen**, no tocan código):

- **Cada 2 h** — dos agentes generan ideas y las acumulan en `agente_propuestas`
  (`estado='pendiente'`, `enviado_en=null`), sin molestar al usuario:
  - **`mejoras-virgilio`** → mejoras/funcionalidades.
  - **`revisor-logica`** → bugs, casos borde e inconsistencias de lógica.
- **A las 8:00 AR** — el **`curador-telegram`**, parado sobre el repo y sobre todo
  la `GUIA-PROYECTO.md` (lo que pidió el usuario), revisa TODO lo acumulado sin
  enviar, **descarta ruido/duplicados/lo que contradice la guía**, arma **una
  lista definitiva** y la manda por Telegram al privado del usuario (bot
  `@Faltantes_Virgilio_bot`). Marca las enviadas con `enviado_en=now()` y las
  descartadas con `estado='descartada'` + `curador_nota`.

Cada propuesta tiene un **código de 4 dígitos** único.

**⚠ Regla para CUALQUIER chat**: si el usuario manda un **código de 4 dígitos**
(ej. `4837`, "hacé el 4837", "código 4837"), buscá esa fila:

```sql
select codigo, agente, titulo, detalle, ubicacion, impacto, esfuerzo, estado
from public.agente_propuestas where codigo = '4837';
```

Trabajá sobre esa propuesta. Los cambios de código van **a `main` SOLO con
aprobación explícita del usuario** (él decide qué código encarar). Al terminar y
con su OK, marcá `update public.agente_propuestas set estado='hecha',
actualizado_en=now() where codigo='4837';` (o `'descartada'` si el usuario la
descarta). Detalle del sistema en `docs/AGENTES-DIARIOS.md`.

## Git

- **Este es un repo de PRUEBA** (`tv-v`), espejo de Producción Virgilio. Trabajar
  **directo en `main`**: commitear y pushear ahí sin preguntar.
- Estilo de commits: `vX.YZ: descripción` cuando hay bump de versión.
