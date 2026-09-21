/* Regresión v20.53 — LA PASTILLA Y EL COLOR NETEAN LO QUE SALIÓ, IGUAL QUE LAS COLUMNAS.

   Luis, 2026-09-21, con la pantalla al lado: *"fijate que el color-coding no coincide y el badge
   tampoco (esta 'Salio' pero figura 'Facturado')"*. La tanda E12E mostraba SALIÓ 100 % y
   FACTURADO 0 % en las columnas —porque desde la v20.11 los porcentajes netean lo que ya se
   cargó al camión— y al mismo tiempo la pastilla decía *Facturado* con la fila azul. Dos
   lecturas distintas de la misma fila.

   Chequea, con el árbol renderizado y las fuentes de «salió» inyectadas:
   - la NP que ya salió lleva pastilla «Salió» (violeta), y el estado de abajo queda en el title;
   - la tanda con TODAS sus NP salidas lleva pastilla «Salió» y la fila en violeta, no en azul;
   - una tanda con algunas salidas y otras no NO dice Salió: manda el estado de abajo;
   - `est` sigue CRUDO: los porcentajes no cambian (SALIÓ 100 % y Facturado vacío);
   - `salio` NO entra en PGA_EST (esa lista son las 4 columnas, y SALIÓ ya tiene la suya).
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const fallos = [];
  const html = fs.readFileSync(path.join(root, "index.html"), "latin1");
  if (!/\.pga-pill\.e-salio\{/.test(html)) fallos.push("falta el CSS de la pastilla e-salio");
  if (!/\.pga-t\.e-salio>td\{/.test(html)) fallos.push("falta el CSS de la fila de tanda e-salio");

  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = {};
    out.pgaEst = PGA_EST.slice();
    const F = "2026-09-25";
    const fila = (np, tanda, estado) => ({
      fecha: F, tanda, np, cod: "958", razon_social: "Cliente", localidad: "Soldati",
      barrio: "Soldati", zona: "Zona 3", zona_corta: "Zona 3", empresa: "LK", origen: "isis",
      m3: 0.1, estado, estado_orden: 1, clave: np,
    });
    // E12E: las 3 facturadas y las 3 ya salieron.  E12F: 2 facturadas, 1 sola salió.
    const filas = [fila("98605", "E12E", "facturado"), fila("98606", "E12E", "facturado"),
                   fila("98607", "E12E", "facturado"),
                   fila("98701", "E12F", "facturado"), fila("98702", "E12F", "facturado")];
    _pgaDest = new Map();
    _pppSearch = "";
    _pppEnSalida = new Map([["98605", { cargada: true }], ["98606", { cargada: true }],
                            ["98607", { cargada: true }], ["98701", { cargada: true }]]);
    _pppLoadMs = new Map();
    _pgaOpenD = { "20260925": true };
    _pgaOpenT = { "20260925|E12E": true, "20260925|E12F": true };
    const arbol = _pgaArbol(filas);
    const h = _pgaCuerpoHtml(arbol, {});
    out.html = h;
    const t = arbol[0].tandasArr;
    out.e12e = { nps: t[0].nps, salio: t[0].salio, est: _pgaEstadoGrupo(t[0].est, t[0].nps, t[0].salio),
                 crudoFac: t[0].est.facturado };
    out.e12f = { nps: t[1].nps, salio: t[1].salio, est: _pgaEstadoGrupo(t[1].est, t[1].nps, t[1].salio) };
    return out;
  });
  await b.close();
  if (errs.length) fallos.push("errores de página: " + errs.join(" | "));

  if (r.pgaEst.indexOf("salio") >= 0)
    fallos.push("`salio` entro en PGA_EST: eso agrega una quinta columna de estado");
  if (r.e12e.est !== "salio")
    fallos.push("la tanda con las 3 NP salidas dice '" + r.e12e.est + "' en vez de 'salio'");
  if (r.e12e.crudoFac !== 3)
    fallos.push("`est` dejo de estar crudo (facturado=" + r.e12e.crudoFac + "): los porcentajes netean sobre eso");
  if (r.e12f.est !== "facturado")
    fallos.push("la tanda con 1 de 2 salidas dice '" + r.e12f.est + "': con algunas si y otras no manda el estado de abajo");

  const h = r.html || "";
  const pills = h.match(/class="pga-pill e-[a-z]+"/g) || [];
  const conTitle = h.match(/class="pga-pill e-salio"[^>]*title="[^"]*Facturado/g) || [];
  if (!/<tr class="pga-t e-salio"/.test(h))
    fallos.push("la fila de la tanda no lleva la clase e-salio (queda pintada de facturado)");
  if (!/class="pga-pill e-salio"[^>]*>Salió</.test(h))
    fallos.push("falta la pastilla «Salió» en la fila");
  if (!conTitle.length)
    fallos.push("la pastilla «Salió» no conserva en el title el estado de abajo");
  if (/<tr class="pga-t e-facturado"[^>]*>(?:(?!<\/tr>)[\s\S])*E12E/.test(h))
    fallos.push("E12E sigue pintada como facturada");
  if (!pills.length) fallos.push("no se renderizo ninguna pastilla");

  if (fallos.length) { console.error("pga-salio-badge FALLA:\n - " + fallos.join("\n - ")); process.exit(1); }
  console.log("pga-salio-badge OK — la pastilla y el color dicen lo mismo que la columna SALIÓ.");
})();
