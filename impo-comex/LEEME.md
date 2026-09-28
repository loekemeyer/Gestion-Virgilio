# IMPO COMEX (versión web) — COPIA ARMADA, no se edita acá

El fuente vive en el repo **privado** `loekemeyer/Impo-Comex` (`client/`). Esto es el resultado de
`npm run build:web` (carpeta `client/dist-web`), copiado tal cual.

- Se abre desde Pedidos Importación → **🛃 IMPO COMEX** (`openImpoComex`, `index.html`).
- Entra sólo un **supervisor** con la sesión de Google de Gestión (mismo origin, misma sesión).
- Los pedidos van a la function **`Impo_Comex_web`**, que valida `es_supervisor_virgilio()` y reenvía
  a las `Impo_Comex_*` con el token del servidor. El token no está en este código.
- Los datos personales de la DDJJ no están en este código: los entrega la puerta.

Para publicar una versión nueva: armar en `Impo-Comex` (`cd client && npm run build:web`), reemplazar
esta carpeta por `client/dist-web` (conservando este LEEME) y subir la versión de Gestión.
Lo sostiene `tests/impo-comex-web.cjs`.
