/* v19.01 (Thomas, 2026-09-16: *"el cliente 4181 de LK no tiene razón social en el módulo de
   facturación, ¿por qué?"*) — una NP ARMADA cuya tanda ya no está en la PPP entra a Facturación
   por `_facSinTanda` (vista `gv_fac_armado_sin_facturar`), y los dos lugares que después usan los
   datos del pedido miraban SÓLO `_facLastTandas`:
     · lo que se ESCRIBE en `Facturacion_NP` al bajar el Excel → fila sin rs, sin cod, sin tanda;
     · la lista «Ya tildados hoy» → el número pelado, sin cliente.
   Caso real: LK 0034 / LK 0035 (Mitre Hugo Alberto, cod 4181), únicas 2 filas de 1.305 sin razón
   social en `Facturacion_NP`.

   Chequea:
     (a) `facInfoNp` resuelve por la tanda cuando la NP está en una tanda;
     (b) y por `_facSinTanda` cuando NO está — con razón social, código y tanda del armado;
     (c) devuelve null para una NP que no está en ninguna de las dos (el llamador decide);
     (d) «Ya tildados hoy» muestra el cliente y la tanda de una NP sin tanda en la PPP;
     (e) el que baja el Excel usa `facInfoNp`, no la búsqueda vieja sólo-tandas.
   Sin red. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.fetch = function () {
      return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve([]); },
                               text: function () { return Promise.resolve("[]"); } });
    };

    // La NP que SÍ está en una tanda de la PPP, y la que quedó armada sin tanda.
    _facLastTandas = [{ tanda: "E30A", fechaEntrega: "17/09", fechaEntregaRaw: "2026-09-17", pedidos: [
      { np: "LK 0099", cod: "1840", razonSocial: "Bazar Y Cia S.A", m3: 0.09 }] }];
    _facSinTanda = [{ np: "LK 0034", cod: "4181", razon_social: "Mitre Hugo Alberto",
                      tanda_armado: "E01G", fecha_salida: "2026-09-17", cajas: 42,
                      por_que_no_se_ve: "la NP esta en la PPP pero sin tanda" }];

    // (a) por la tanda
    const a = facInfoNp("LK 0099") || {};
    out.porTanda = a.rs === "Bazar Y Cia S.A" && a.cod === "1840" && a.tanda === "E30A";

    // (b) por la lista de armadas sin tanda — es lo que faltaba
    const c = facInfoNp("LK 0034") || {};
    out.porSinTanda = c.rs === "Mitre Hugo Alberto" && c.cod === "4181"
                      && c.tanda === "E01G" && c.feRaw === "2026-09-17";

    // (c) una que no está en ninguna
    out.desconocidaNull = facInfoNp("LK 9999") === null;

    // control de no-trivialidad: sin `_facSinTanda` la de (b) no se resuelve
    const guardado = _facSinTanda; _facSinTanda = [];
    out.sinLaFuenteNoResuelve = facInfoNp("LK 0034") === null;
    _facSinTanda = guardado;

    // (d) «Ya tildados hoy»
    _facNpsHoyReal = new Set(["LK 0034"]);
    try { facRenderTicked(); } catch (_e) { out.errRender = String(_e && _e.message || _e); }
    const box = document.getElementById("facTickedList");
    const html = (box && box.innerHTML) || "";
    out.tildadosDiceCliente = /Mitre Hugo Alberto/.test(html);
    out.tildadosDiceTanda   = /E01G/.test(html);

    // (e) cableado: el Excel escribe Facturacion_NP con facInfoNp
    const fn = String(window.facXlsBajar || "");
    out.excelUsaHelper = /facInfoNp\(np\)/.test(fn);
    out.excelSinBusquedaVieja = !/const pp = \(t\.pedidos \|\| \[\]\)\.find/.test(fn);
    return out;
  });
  await b.close();

  const fails = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fails.push(m); };
  chk(r.porTanda, "(a) facInfoNp resuelve por la tanda de la PPP");
  chk(r.porSinTanda, "(b) y por las armadas SIN tanda: razón social, código, tanda del armado y fecha");
  chk(r.desconocidaNull, "(c) una NP que no está en ninguna fuente devuelve null");
  chk(r.sinLaFuenteNoResuelve, "control: sin `_facSinTanda` esa NP no se resuelve (la prueba no es trivial)");
  chk(r.tildadosDiceCliente, "(d) «Ya tildados hoy» muestra el cliente de una NP sin tanda en la PPP");
  chk(r.tildadosDiceTanda, "(d) y su tanda de armado");
  chk(r.excelUsaHelper, "(e) la bajada del Excel arma los datos con facInfoNp");
  chk(r.excelSinBusquedaVieja, "(e) y ya no lleva la búsqueda vieja sólo-tandas");
  if (r.errRender) { console.log("MAL  facRenderTicked tiró: " + r.errRender); fails.push("render"); }
  if (errs.length) { console.log("MAL  errores de página: " + errs.join(" | ")); fails.push("pageerror"); }
  if (fails.length) { console.error("\nFALLÓ: " + fails.length); process.exit(1); }
  console.log("\nfac-rs-sin-tanda: OK");
})();
