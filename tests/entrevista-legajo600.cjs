/* Regresión v14.62 — Legajo 600 = ENTREVISTA / PRUEBA con nombre.

   El 600 es un legajo COMPARTIDO: cada candidato entra con 600, pone su nombre y
   hace la prueba REAL (persiste + descuenta stock, NO es como el 0/1). Para saber
   QUIÉN hizo cada prueba, cada evento del 600 se sella con gv_nombre_prueba.

   Cubre:
     · esLegajoEntrevista() distingue 600 de operarios reales y del 0/1.
     · el 600 NO es esLegajoPrueba (persiste), a diferencia del 0/1.
     · _enqueueReportRaw sella el nombre de la sesión en el payload del 600.
     · trySendOneReport manda gv_nombre_prueba (y null para un operario real).
     · bulkSendDayReplay (Terminar Día) también sella el nombre en el 600.

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

    // 1) clasificación
    out.e600  = esLegajoEntrevista("600") === true;
    out.e600b = esLegajoEntrevista(" 600 ") === true;   // trim
    out.eReal = esLegajoEntrevista("277") === false;
    out.e0    = esLegajoEntrevista("0") === false;
    // el 600 persiste (NO es prueba/basura 0/1)
    out.persiste = esLegajoPrueba("600") === false && esLegajoPrueba("0") === true;

    // 2) sesión de entrevista → el nombre queda disponible (la escribe el módulo de
    //    auth vía saveLegajoSession bajo la clave vir_legajo_auth; acá la simulamos)
    localStorage.setItem("vir_legajo_auth", JSON.stringify({ legajo: "600", nombre: "Juan Perez", day: "2026-09-10" }));
    out.nombreSesion = _gvNombrePrueba() === "Juan Perez";

    // 3) _enqueueReportRaw sella el nombre en el payload del 600
    try { localStorage.removeItem("vir_reportQueue"); } catch (_e) {}
    const pl = { id: "test_ent_1", legajo: "600", opcion: "TP", descripcion: "x", texto: "Z99Z", ts: Date.now() };
    _enqueueReportRaw(pl);
    out.enqueueSella = pl.gv_nombre_prueba === "Juan Perez";

    // 4) envío individual: manda gv_nombre_prueba
    posts.length = 0;
    await trySendOneReport(pl, 5000);
    out.unoManda = ((posts[0] || {}).body || {}).gv_nombre_prueba === "Juan Perez";

    // 4b) operario real: gv_nombre_prueba null (no se ensucia)
    posts.length = 0;
    await trySendOneReport({ id: "test_ent_real", legajo: "277", opcion: "TP", texto: "Z99Z", ts: Date.now() }, 5000);
    out.realNull = ((posts[0] || {}).body || {}).gv_nombre_prueba == null;

    // 5) replay masivo del día del 600: todas las filas con el nombre
    posts.length = 0;
    await bulkSendDayReplay("600", [
      { id: "test_ent_2", opcion: "TP",  texto: "Z99Z", ts: Date.now() },
      { id: "test_ent_3", opcion: "TAP", texto: "Z99Z", ts: Date.now() }
    ]);
    const bulk = (posts[0] || {}).body || [];
    out.bulkTodas = Array.isArray(bulk) && bulk.length === 2 &&
      bulk.every(function (f) { return f.gv_nombre_prueba === "Juan Perez"; });

    return out;
  });

  const pass = Object.keys(r).every(function (k) { return r[k] === true; }) && errs.length === 0;
  console.log("entrevista-legajo600:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
