/* v20.76 — EL ARBOL DE PROGRAMACION VA CENTRADO, NO PEGADO A LA IZQUIERDA.

   Luis, 2026-09-21, sobre la pantalla de Programacion: *"mucho espacio vacio a la derecha en
   esa pantalla. centra mas la tabla en la pantalla"*.

   `.pga-blk` mide lo que mide la tabla (`width:fit-content`, a proposito: asi los botones del
   encabezado quedan pegados a SU borde derecho y se mueven con ella al abrir o cerrar un dia).
   Un bloque angosto dentro de un contenedor ancho queda pegado a la izquierda — de ahi el
   hueco. Se centra con `margin-inline:auto`, sin estirarlo: estirarlo dejaria columnas vacias,
   que es justo lo que la v13.65 habia arreglado del otro lado.

   Mide de verdad en el navegador: mismo hueco a los dos lados, y el bloque NO estirado al
   ancho del contenedor. Sale 1 si falla. */
const path = require("path");
let chromium; try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (e) { ({ chromium } = require("playwright")); }
(async () => {
  const b = await chromium.launch(); const pg = await b.newPage({ viewport: { width: 1900, height: 900 } });
  await pg.goto("file:///home/user/Gestion-Virgilio/index.html");
  await pg.waitForTimeout(900);
  const r = await pg.evaluate(() => {
    // se arma el mismo anidado real: .planim-body > #pppPreview > .pga-blk > tabla
    const body = document.createElement("div");
    body.className = "planim-body";
    const ov = document.createElement("div"); ov.id = "pppOverlay"; ov.appendChild(body);
    ov.style.cssText = "position:fixed;inset:0;display:block";
    const prev = document.createElement("div"); prev.id = "_testPrev"; body.appendChild(prev);
    prev.innerHTML = '<div class="pga-blk"><div class="pga-wrap">' +
      '<table style="width:1100px"><tr><td>x</td></tr></table></div></div>';
    document.body.appendChild(ov);
    const blk = prev.querySelector(".pga-blk");
    const rb = blk.getBoundingClientRect(), rp = prev.getBoundingClientRect();
    const out = {
      anchoContenedor: Math.round(rp.width), anchoBloque: Math.round(rb.width),
      huecoIzq: Math.round(rb.left - rp.left), huecoDer: Math.round(rp.right - rb.right),
    };
    out.centrado = Math.abs(out.huecoIzq - out.huecoDer) <= 2;
    out.noSeEstiro = out.anchoBloque < out.anchoContenedor;
    ov.remove();
    return out;
  });
  console.log(JSON.stringify(r, null, 1));
  await b.close();
  process.exit(r.centrado && r.noSeEstiro ? 0 : 1);
})();
