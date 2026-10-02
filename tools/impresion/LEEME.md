# GV · Programa de impresión (v26.12)

Imprime en una PC las hojas que manda Gestión Virgilio, cada una en la impresora que se
eligió en **GV → Configuración → 🧩 Impresoras**. No hace falta el kiosco de Chrome y no
aparece la ventana de impresión.

| hoja | cuándo sale |
|---|---|
| 📋 Picking | al terminar el picking de una tanda |
| 📦 Armado | al terminar el armado de cada NP |
| 🧾 Facturado | al exportar el Excel ISIS o al tildar la NP en Facturación |

## Instalación (una sola vez)

1. Copiar esta carpeta completa a la carpeta compartida de documentos. Todas las PCs usan la
   misma carpeta.
2. En la PC que tiene la impresora, doble clic en **`Iniciar GV-Impresion.bat`**.
3. La primera vez pide la **clave del programa**: está en GV → Configuración → 🧩 Impresoras
   → «Clave del programa» → 📋 Copiar. Se pega en la ventana y se aprieta Enter. Queda
   guardada en `clave.txt`, en esta carpeta, y sirve para todas las PCs.
4. En menos de un minuto la PC aparece en GV → 🧩 Impresoras, con sus impresoras.
5. En GV, para cada hoja: elegir la **PC**, la **impresora**, prender **Automático** y apretar
   **🖨️ Prueba**.
6. Para que el programa se abra solo al prender la PC: doble clic en **`Abrir al iniciar Windows.bat`**.

## Uso diario

- La ventana tiene que quedar **abierta**. Se puede minimizar. Si se cierra, en esa PC no sale
  ninguna hoja; lo que GV mande mientras tanto sale cuando se vuelva a abrir (hasta 12 horas).
- La ventana muestra cada hoja que imprime y cualquier error, por ejemplo una impresora apagada
  o un nombre que ya no existe.
- En GV → 🧩 Impresoras se ve si la PC está 🟢 conectada, lo que quedó pendiente y las últimas
  hojas, cada una con su estado. Las que dieron error se pueden reintentar desde ahí.

## Qué necesita la PC

- Windows 7 o superior. Funciona con el PowerShell que trae Windows, incluso el 2.0 de Windows 7.
- **Google Chrome** o **Microsoft Edge** instalado. Se usa sin abrir ninguna ventana, sólo
  para dibujar la hoja. Si está en otra ruta: `Iniciar GV-Impresion.bat -Chrome "C:\ruta\chrome.exe"`.
- Las impresoras instaladas en Windows. El programa las imprime **por nombre** y no cambia la
  predeterminada de Windows ni la de Chrome.

## Si algo no sale

| síntoma | qué mirar |
|---|---|
| La PC no aparece en GV | ¿la ventana está abierta? ¿pide la clave? |
| «La CLAVE no es la de GV» | volver a copiarla desde GV (borra `clave.txt` y la pide de nuevo) |
| «No encontré Chrome ni Edge» | instalar Chrome, o pasar la ruta con `-Chrome` |
| «La impresora "X" no existe en esta PC» | la impresora cambió de nombre: elegirla de nuevo en GV |
| Sale en blanco | correr `Probar impresora predeterminada.bat` y mirar el mensaje |

El registro de lo que hizo queda en `%TEMP%\gv-impresion\gv-impresion.log`.

## Cómo funciona

1. GV arma la hoja, que es la misma de siempre, y la guarda en la base (`gv_imp_encolar`).
   - Picking y armado los arma cualquier GV de supervisor abierto en una PC.
   - El facturado lo arma el equipo que exporta.
   - La base no deja que la misma hoja salga dos veces.
2. Este programa, cada 5 segundos:
   1. avisa que está vivo y qué impresoras tiene;
   2. toma las hojas de **su** PC;
   3. las dibuja con Chrome en modo invisible;
   4. las manda a la impresora elegida;
   5. confirma en la base si salieron.

   Recién con esa confirmación la hoja figura «impresa» en la Cola de impresión.

Un tipo de hoja **sin PC** en GV sigue como antes: lo imprime el navegador, con su cuadro.

Fuente: `loekemeyer/Gestion-Virgilio`, carpeta `tools/impresion/`. Base: `sql/gv_impresion_programa_v2611.sql`.
