/* Regresión v14.51 — el sello de app viaja en CADA evento de operario.

   `Registros_Produccion_Virgilio` es una tabla COMPARTIDA con Producción Virgilio, que
   no manda la columna `gv_app`. Por eso el contrato es: Gestión manda siempre
   "gestion@vX.YZ" y NULL significa "lo mandó Producción". Si Gestión dejara de mandarla
   —o la mandara vacía— sus eventos pasarían a contarse como de Producción y el control
   diario de "¿quién migró?" mentiría en silencio, que es exactamente lo que no se podía
   ver antes de esta versión.

   Cubre los DOS caminos de escritura, porque el bulk es fácil de olvidar:
     · trySendOneReport  — el envío de a uno (todos los botones)
     · bulkSendDayReplay — el replay del día entero al Terminar Día

   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}, posts = [];
    window.fetch = function (url, opts) {
      if (opts && opts.method === "POST") {
        try { posts.push({ url: String(url), body: JSON.parse(opts.body) }); } catch (_e) {}
      }
      return Promise.resolve({ ok: true, status: 201, headers: { get: function () { return null; } } });
    };

    // El tag se arma con la versión de la app, no con un literal suelto.
    out.tag = (typeof GV_APP_TAG === "string") ? GV_APP_TAG : null;
    out.tagEsGestion = out.tag === "gestion@" + APP_VERSION;
    out.tagNoVacio = !!out.tag && out.tag.length > "gestion@".length;

    // 1) envío individual
    await trySendOneReport({
      id: "test_gvapp_1", legajo: "999", opcion: "TP",
      descripcion: "Terminó picking", texto: "Z99Z", ts: Date.now(), ts_inicio_iso: null
    }, 5000);
    const uno = (posts[0] || {}).body || {};
    out.unoTieneTag = uno.gv_app === out.tag;
    out.unoMandaLegajo = uno.legajo === "999";   // sanity: no rompimos el payload

    // 2) replay masivo del día
    posts.length = 0;
    await bulkSendDayReplay("999", [
      { id: "test_gvapp_2", opcion: "TP", texto: "Z99Z", ts: Date.now() },
      { id: "test_gvapp_3", opcion: "TAP", texto: "Z99Z", ts: Date.now() }
    ]);
    const bulk = (posts[0] || {}).body || [];
    out.bulkFilas = Array.isArray(bulk) ? bulk.length : 0;
    out.bulkTodasConTag = Array.isArray(bulk) && bulk.length > 0 &&
      bulk.every(function (f) { return f.gv_app === out.tag; });

    return out;
  });

  const pass = r.tagEsGestion === true && r.tagNoVacio === true &&
    r.unoTieneTag === true && r.unoMandaLegajo === true &&
    r.bulkFilas === 2 && r.bulkTodasConTag === true && errs.length === 0;

  console.log("gv-app-tag:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
