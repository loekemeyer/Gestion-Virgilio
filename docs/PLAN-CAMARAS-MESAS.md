# Plan: cámaras de las mesas de armado — medir acomodar y mesa libre (2026-10-05)

**Estado: EN ESPERA.** Luis, 05/10/2026: *"ponelo como plan, no se va a poder resolver ahora"*. Era la decisión
**D25** de la sesión `session_01RKK9tZBzyXRapn3eie8TZn`; queda retirada como decisión y vive acá.
Tarea de Planify: **«Picking: acomodar en mesa (cola) vs cajas/NP/mesas, y cámaras»** (Luis, abierta).

## Para qué

Medir dos cosas que hoy el sistema no ve:

1. **Cuánto tardan en acomodar en la mesa** lo pickeado (del último PKC al TP y del TP a la próxima tarea).
2. **Si había mesa libre al terminar el picking**, y dónde quedaron las cajas: mesa, carro o pallet.

El análisis de `docs/PICKING-ACOMODAR-MESA.md` (03/10) midió que acomodar **no sigue a las cajas ni a las mesas
ocupadas** (R² 0,008 en dos semanas) y que **lo que manda es el operario**. Lo que no pudo medir es justamente
dónde quedaron las cajas y cuántas mesas había: eso es lo que agregan las cámaras.

## Lo que falta para arrancar (lo destraba Luis o quien instaló las cámaras)

| # | dato | dónde está |
|---|---|---|
| 1 | marca y modelo del grabador (NVR) | etiqueta del aparato o la app con que miran las cámaras (Hikvision, Dahua u otra) |
| 2 | una captura de cada cámara que ve las mesas de armado | la app de las cámaras |
| 3 | quién tiene el usuario y la clave del NVR | quien instaló. **No se manda por el chat ni va al repo** (es público): se carga en la PC del depósito |
| 4 | aviso por escrito a los operarios de que las cámaras se usan para medir tiempos | Luis / RRHH, antes de la etapa 2 |

## Etapas

| etapa | qué | resultado |
|---|---|---|
| 0 | los 4 datos de arriba | se sabe qué cámara ve qué mesa y si el NVR da RTSP en la red local |
| 1 | prueba de lectura: un programa en una PC del depósito (como el helper de impresión) toma **una foto por cámara** desde el NVR | confirma que se lee sin cortar la grabación del NVR |
| 2 | detector: se marcan las zonas (cada mesa, dónde para el carro) y anota **mesa ocupada/libre, carro llega/sale** con la hora. **No guarda video** y nadie mira grabaciones | una tabla nueva en Gestión (`GV_Mesa_Evento`: cámara, zona, estado, hora), escrita por una RPC |
| 3 | cruce con el picking y el armado (TP / TAP, la cola de `gv_monitor_horas_operario_dia`) | minutos de acomodar con y sin mesa libre; mesas ocupadas al dar el TP |
| 4 | validación: una semana contra observación a mano | se decide si entra al puntaje o queda como dato |

## Alternativa sin cámaras (más barata, menos dato)

Al dar el **TP**, el celular pregunta con un toque *«¿dónde quedaron las cajas? mesa / carro / pallet»*. Contesta
dónde quedaron, pero no cuánto tardó en acomodar ni cuántas mesas había libres. Se puede hacer en cualquier momento
y no depende del NVR.

## Para reusar

- [Probable, no revisado] El repo **`loekemeyer/CamarasPanaderia`** (Thomas) ya tiene detección con YOLOv8, un
  asistente que busca cámaras/NVR en la red y prueba URLs RTSP, e instalador para una PC existente (tareas de
  Planify de Thomas: «Sistema analítica de video retail», «Autodetección de cámaras + instalador sin costo + móvil»).
  Antes de escribir la etapa 1, mirar qué sirve de ahí.
- El helper de impresión (`tools/helper-impresion/`) es el molde de «programa chico en una PC del depósito».

## Riesgos

- Una cámara que no ve la mesa entera o la ve tapada por el carro: la etapa 0 lo dice antes de escribir nada.
- Los operarios tienen que saber para qué se usan (punto 4): sin eso no se arranca la etapa 2.
- La PC del depósito tiene que quedar prendida en horario de trabajo (igual que el helper).
