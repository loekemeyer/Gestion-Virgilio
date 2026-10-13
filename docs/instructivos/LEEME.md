# Instructivos gráficos para el depósito

Hojas de **40 × 50 cm** para colgar en la pared: el paso a paso de un módulo, pantalla por
pantalla, con las capturas **de la app de verdad**.

| archivo | qué es |
|---|---|
| `recepcion-tallerista.pdf` | el que se imprime (40 × 50 cm, una hoja) |
| `recepcion-tallerista.html` | el mismo, autocontenido, para mirarlo en el navegador |
| `caps-recepcion/` | las capturas + los dos scripts que las sacan |

## Al cambiar una pantalla, se rehace el instructivo

Las capturas **no se dibujan a mano**: salen de correr la app con Playwright, así que si una
pantalla cambia, el instructivo se regenera y queda igual a lo que ve el operario.

```bash
node docs/instructivos/caps-recepcion/_generar-capturas.cjs          # el módulo de recepción (recepcion.js)
node docs/instructivos/caps-recepcion/_generar-capturas-botonera.cjs # la botonera (index.html)
node scripts/instructivo-recepcion.cjs                               # arma el HTML y el PDF
```

El generador imprime cuántas páginas salieron: **tiene que decir 1**. Si dice 2, el contenido no
entra — se achica el texto (`.dsc` / `.tit` en el CSS de `scripts/instructivo-recepcion.cjs`), no
se parte en dos hojas.

## Cómo está armado (para hacer otro)

- Los pasos son una lista (`PASOS`) con la captura, el título y la explicación. Agregar o sacar un
  paso es editar esa lista.
- El reparto en 5 columnas lo calcula solo (partición lineal por DP) y después **ajusta el ancho
  de cada columna** hasta que las cinco terminan parejas: sin eso quedan hasta 8 cm de hoja en
  blanco al pie de media hoja.
- Los datos de las capturas son **de ejemplo** (tallerista Lucho, remito 40873, códigos 505/518/586
  con sus OC): salen del mock del script, no de la base.
- ⚠ El `input type=date` de Chromium headless pinta `MM/DD/AAAA`; en el celular se ve `DD/MM/AAAA`.
  El script lo reemplaza antes de la captura, para que la hoja muestre lo que ve el operario.
