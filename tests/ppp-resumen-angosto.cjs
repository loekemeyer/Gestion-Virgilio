/* Regresión (v15.53): la tabla del Resumen de la PPP no se estira al ancho del
   contenedor. Con `width:100%` el navegador repartía el sobrante entre las 14
   columnas y cada celda quedaba con aire adentro (la de Fecha medía 171 px para
   un "09/09/2026" de ~62 px; la tabla entera, 1.558 px en un viewport de 1.600).
   Verifica, con el MISMO juego de datos, que:
   (a) la tabla mida bastante menos que el contenedor (no lo llena),
   (b) ninguna columna mida más de 40 px por encima de su contenido más ancho,
   (c) el marco (.ppp-restbl-wrap) termine con la tabla, no en el borde,
   (d) los dos carteles de arriba tampoco se estiren.
   El umbral de (a) es holgado a propósito: mide "no se estira", no un ancho exacto
   (que depende de la fuente del sistema donde corra el test). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.setViewportSize({ width: 1600, height: 900 });
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const Z = ["Zona 1 - CABA Sur", "Zona 2 - CABA Centro", "Zona 3 - CABA Oeste", "Zona 4 - GBA Sur",
               "Zona 5 - GBA Oeste", "Zona 6 - GBA Norte", "Zona 7 - GBA Norte Lejos"];
    const dias = ["09/09/2026","10/09/2026","11/09/2026","14/09/2026","15/09/2026","16/09/2026",
                  "17/09/2026","18/09/2026","29/09/2026","07/10/2026","28/10/2026"];
    const prog = [];
    dias.forEach(function (f, i) {
      prog.push({ np: "9" + (8700 + i), tanda: "E0" + i + "A", cod: "3958", razon_social: "Cliente " + i,
                  m3: (i % 7) + 0.57, localidad: "Mataderos", zona: Z[i % 7],
                  fecha: "01/09/2026", fecha_entrega: f, programmed: true });
      prog.push({ np: "4" + (4600 + i), tanda: "E1" + i + "A", cod: "801", razon_social: "Coto C.I.C.S.A.",
                  m3: 2.21, localidad: "Esteban Echeverria", zona: "Super",
                  fecha: "01/09/2026", fecha_entrega: f, programmed: true });
    });
    const ANCHO = 1560;
    const host = document.createElement("div");
    host.style.cssText = "position:absolute;left:0;top:0;width:" + ANCHO + "px;";
    host.innerHTML = pppResumenHtml(prog);
    document.body.appendChild(host);

    const tabla = host.querySelector(".ppp-restbl");
    const wrap  = host.querySelector(".ppp-restbl-wrap");
    const w = (el) => el ? el.getBoundingClientRect().width : 0;

    // ancho del contenido más ancho de cada columna, medido con un <span> suelto
    const regla = document.createElement("span");
    regla.style.cssText = "position:absolute;visibility:hidden;white-space:nowrap;font:" +
      getComputedStyle(tabla).font + ";";
    document.body.appendChild(regla);
    const medir = (txt) => { regla.textContent = txt; return regla.getBoundingClientRect().width; };

    const filas = [...tabla.querySelectorAll("tr")];
    const nCols = tabla.querySelectorAll("thead th").length;
    const sobra = [];
    for (let c = 0; c < nCols; c++) {
      let texto = 0;
      filas.forEach(function (tr) {
        const cel = tr.children[c]; if (!cel) return;
        // los <br> de los th parten el título: mide la línea más larga, no el texto pegado
        String(cel.innerHTML).split(/<br\s*\/?>/i).forEach(function (linea) {
          const t = linea.replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ").trim();
          if (t) texto = Math.max(texto, medir(t));
        });
      });
      const col = tabla.querySelectorAll("thead th")[c];
      sobra.push(Math.round(w(col) - texto));
    }

    return {
      contenedor: ANCHO,
      tabla: Math.round(w(tabla)),
      wrap: Math.round(w(wrap)),
      sobraMax: Math.max.apply(null, sobra),
      sobra: sobra,
      note: Math.round(w(host.querySelector(".ppp-res-note"))),
      leg: Math.round(w(host.querySelector(".ppp-res-leg")))
    };
  });

  const ok = r.tabla > 0
    && r.tabla < r.contenedor * 0.75            // (a) no llena el contenedor
    && r.sobraMax <= 40                          // (b) ninguna columna con aire de sobra
    && r.wrap - r.tabla <= 4                     // (c) el marco termina con la tabla
    && r.leg < r.contenedor && r.note < r.contenedor   // (d) los carteles tampoco se estiran
    && errs.length === 0;

  console.log("ppp-resumen-angosto:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none", ok ? "· ✓ OK" : "· ✗ FALLÓ");
  await b.close();
  process.exit(ok ? 0 : 1);
})();
