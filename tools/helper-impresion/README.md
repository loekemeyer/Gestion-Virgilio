# Helper de impresión — Gestión Virgilio

Versión: **1.2.0**

Programa local (un solo `.exe`, sin instalar, sin permisos de administrador) que corre en la
PC de depósito e imprime **solas** las hojas de picking / armado / facturado que genera Gestión
Virgilio, cada una en la impresora que el usuario le asigne, sin el cuadro de impresión y sin
tocar la impresora predeterminada de Windows. Reemplaza el "modo kiosco" de Chrome.

El `.exe` abre un servidor HTTP local en `http://127.0.0.1:17777`. La web de Virgilio, cuando
genera una hoja, le hace un `fetch` con el PDF + el tipo, y el helper lo imprime con SumatraPDF.

## Estructura

    tools/helper-impresion/
      src/ImpresionVirgilio.cs          # código fuente (C# WinForms)
      compilar.bat                      # compila el .exe con el csc.exe de Windows
      virgilio-impresion-EJEMPLO.json   # ejemplo de configuración (reglas tipo -> impresora)
      README.md                         # este archivo
      LEEME.txt                         # instructivo para el que lo instala (va en la carpeta de distribución)

> **SumatraPDF.exe** (binario, ~20 MB) **no** está en el repo. Es una dependencia externa: ver
> abajo de dónde bajarlo. Para distribuir se arma una carpeta con `Impresion Virgilio.exe` +
> `SumatraPDF.exe`.

## Qué necesita instalado

- **Windows 10/11.**
- **.NET Framework 4** — solo para *compilar* (`csc.exe` ya viene con Windows en
  `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\`). Para *correr* el `.exe` ya compilado,
  cualquier Windows 10/11 lo ejecuta sin instalar nada.
- **SumatraPDF 3.6.1 portable (64 bits)** — del sitio oficial, `SumatraPDF-3.6.1-64.zip`
  (https://www.sumatrapdfreader.org/). Renombrar el `.exe` a `SumatraPDF.exe`. El helper lo
  busca **junto al propio `.exe`** y, si no está ahí, en una subcarpeta `.\dist\`.
- **No usa Node ni PowerShell** en tiempo de ejecución. Es un ejecutable nativo de Windows.

## Compilar

Doble clic en `compilar.bat` (o el comando que está adentro). Genera `Impresion Virgilio.exe`.

## Instalar / distribuir

1. Armar una carpeta con `Impresion Virgilio.exe` + `SumatraPDF.exe`.
2. Copiarla a la PC de depósito (ej. `C:\Impresion Virgilio\`). No se instala: se copia.
3. Doble clic en `Impresion Virgilio.exe`. Se abre la ventana.
4. En la ventana hay una fila por hoja (Picking · Armado · Facturado): tildarla, elegir la
   impresora y las copias. **Se guarda sola** con cada cambio. El cartel de arriba dice si la PC
   está lista (`✓ TODOS LOS DOCUMENTOS CONFIGURADOS`) y el puerto.
5. Para probar una impresora: **Opciones avanzadas… → Probar impresión** (manda un PDF elegido a mano).

### Ventana (v1.2.0)

- **Principal:** el cartel de estado + el puerto, y la tabla hoja → impresora → copias.
- **Opciones avanzadas…:** puerto, **tamaño de hoja (uno para todas las hojas)**, tamaño en la
  hoja (ajustar / real / reducir), Iniciar con Windows, Probar impresión, rutas de la
  configuración y del registro, y la actividad en vivo.
- **Al cerrar** (X o Alt+F4) pregunta si minimizar: cerrado, las hojas dejan de imprimirse en
  esa PC (Gestión Virgilio las manda al cuadro de impresión del navegador).
- Si el puerto está ocupado (casi siempre, el programa ya abierto en otra ventana) lo dice y
  ofrece **Reintentar**.

## Iniciar solo con Windows

Tildar **"Iniciar con Windows"** en **Opciones avanzadas…**. Crea un acceso directo en la carpeta de inicio
del usuario (`shell:startup`), sin admin. Destildar para sacarlo.

## Actualizar

Reemplazar el `Impresion Virgilio.exe` por la versión nueva (cerrando antes la ventana). La
configuración (`virgilio-impresion-<PC>.json`) queda intacta: no se pisa.

## Configuración

Archivo **`virgilio-impresion-<NOMBRE-PC>.json`**, en la **misma carpeta que el `.exe`**. Uno por
PC (los nombres de impresora son de cada máquina). Lo escribe la ventana al Guardar; no hace
falta editarlo a mano. Formato (ver `virgilio-impresion-EJEMPLO.json`):

    {
      "pc": "NOMBRE-DE-LA-PC",
      "actualizado": "2026-10-02 12:00:00 por usuario",
      "puerto": 17777,
      "ajuste": "fit",
      "papel": "A4",
      "reglas": [
        { "tipo": "picking", "impresora": "Impresora Deposito 1", "copias": 1, "papel": "A4", "activa": true }
      ]
    }

- `puerto`: puerto del servidor local (default 17777).
- `ajuste`: `fit` (ajustar a la hoja) | `noscale` (tamaño real) | `shrink` (reducir solo si no entra).
- `papel` (v1.2.0, **global**): `A4` | `A5` | `A3` | `letter` | `legal` | `""` (el del PDF). Vale
  para todas las hojas. Un archivo viejo sin `papel` global toma el de la primera regla, o A4.
- `reglas[].tipo`: `picking` | `armado` | `facturado` (debe coincidir con el `tipo` que manda Virgilio).
- `reglas[].papel`: se sigue escribiendo igual al global, por compatibilidad con la v1.0.
- `reglas[].copias`: 1 a 5. · `activa`: `true`/`false`.
- Varios tipos pueden apuntar a la misma impresora; **una impresora por hoja** (si el archivo
  trae dos reglas para la misma hoja se usa la primera). Reglas de otros tipos se respetan tal cual.

## Contrato HTTP

Base: `http://127.0.0.1:17777` (el puerto es configurable).

### `GET /`
Ping de salud. Responde `200` con el texto `Impresion Virgilio OK v1.2.0`. Virgilio da vivo por el `200`, no por el texto.

### `OPTIONS /print`
Preflight CORS. Responde `204` con los headers CORS (ver abajo). Lo maneja el helper solo.

### `POST /print?tipo=<picking|armado|facturado>`
- **Body:** el PDF de la hoja. Puede ir:
  - **crudo** (empieza con `%PDF`), con `Content-Type: application/pdf`, o
  - en **base64** como texto (con o sin prefijo `data:...;base64,`), con `Content-Type: text/plain`
    (evita el preflight CORS).
- **tipo:** por query `?tipo=` o por header `X-Virgilio-Tipo`.
- **Respuesta `200`** (JSON):

      {
        "ok": true,
        "tipo": "picking",
        "impreso": ["Impresora Deposito 1"],
        "errores": [],
        "motivo": ""
      }

  - `ok`: `true` si imprimió en al menos una impresora.
  - Si no hay regla activa para ese tipo en esa PC: `ok:false`, `motivo:"sin regla activa para el tipo \"...\""`.
  - Si el body no es un PDF válido: `400` con el mismo formato JSON y `motivo`.

### Headers CORS (en todas las respuestas)

    Access-Control-Allow-Origin: *
    Access-Control-Allow-Methods: GET, POST, OPTIONS
    Access-Control-Allow-Headers: Content-Type, X-Virgilio-Tipo
    Access-Control-Allow-Private-Network: true
    Access-Control-Max-Age: 86400

Funciona desde una página `https://` pública porque `127.0.0.1` no cuenta como contenido mixto
y el helper responde el preflight + Private Network Access.

## Cómo lo llama Virgilio (lado web)

> En `index.html` esto vive en `imprimirLocal` / `helperVivo` (bloque «HELPER LOCAL DE IMPRESIÓN»),
> con timeout, fila de a una hoja y vuelta al cuadro del navegador si el helper no imprimió. Lo
> mide `tests/imp-helper-local.cjs`. Abajo, la versión mínima del contrato.

    // tipo: "picking" | "armado" | "facturado"; pdfBlob: Blob/ArrayBuffer con el PDF
    async function imprimirLocal(tipo, pdfBlob) {
      const url = "http://127.0.0.1:17777/print?tipo=" + encodeURIComponent(tipo);
      try {
        const resp = await fetch(url, {
          method: "POST",
          headers: { "Content-Type": "application/pdf" },
          body: pdfBlob
        });
        const r = await resp.json();
        if (!r.ok) console.warn("No se imprimió:", r.motivo || r.errores);
        return r;
      } catch (e) {
        console.warn("Helper de impresión no disponible:", e);
        return { ok: false, motivo: "helper no disponible" };
      }
    }

    async function helperVivo() {
      try { const r = await fetch("http://127.0.0.1:17777/"); return r.ok; }
      catch { return false; }
    }

> **Requisito:** la hoja debe salir como **PDF** para mandarse al helper. Si hoy es HTML impreso
> con `window.print()`, usar el endpoint PDF del server si existe, o generar el PDF en el cliente
> (html2pdf.js / jsPDF) antes del `fetch`.

## Seguridad / alcance

- El servidor escucha **solo en loopback** (`127.0.0.1`): no es accesible desde la red.
- Usa `TcpListener`, no `HttpListener`, así que **no requiere** reservar la URL con `netsh` ni admin.
- No maneja credenciales ni datos de Virgilio: recibe un PDF ya armado y lo manda a imprimir.
