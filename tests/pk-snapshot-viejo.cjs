/* Regresión v18.53 — un picking guardado ANTES del fix de la base se re-baja, no se reabre.
   Hasta la v18.43 la base de picking se pedía con `limit=20000` y PostgREST la cortaba en 1000
   filas, así que a una tanda le podían faltar renglones. El fix arregló la consulta pero no lo
   ya guardado: `showPickingList` reabre el snapshot local SIN tocar la red (offline-first a
   propósito), así que una tanda abierta antes del fix seguía mostrando la lista corta aunque el
   celular ya tuviera la versión nueva. Es lo que se vio el 15/09 después del deploy.
   Chequea:
     1) la clasificación de versiones (sin sello y anteriores a 18.43 = desactualizado);
     2) el snapshot viejo NO reabre de memoria: va por la carga de red con seedFromServer;
     3) el snapshot nuevo sí reabre al instante (no se rompe el offline-first);
     4) lo que se guarda hoy lleva el sello de versión.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    const leg = "277", T = "E03F";
    legajoInput.value = leg;
    window.alert = function () {};

    // ---- 1) clasificación de versiones ----
    out.sinSelloEsViejo = pkSnapshotDesactualizado({});
    out.v1756EsViejo    = pkSnapshotDesactualizado({ app: "v17.56" });
    out.v1842EsViejo    = pkSnapshotDesactualizado({ app: "v18.42" });
    out.v1843EsBueno    = !pkSnapshotDesactualizado({ app: "v18.43" });
    out.v1899EsBueno    = !pkSnapshotDesactualizado({ app: "v18.99" });
    out.v19EsBueno      = !pkSnapshotDesactualizado({ app: "v19.02" });

    const guardar = function (app) {
      const s = { day: getTodayKey(), tanda: T, legajo: leg, idx: 1, mode: "item",
                  items: [{ art: "505", key: "505", esp: 4 }], results: { "505": 4 }, forced: {} };
      if (app) s.app = app;
      localStorage.setItem("vir_pk_" + leg, JSON.stringify(s));
    };

    // ---- 2) el viejo NO reabre de memoria: pide la lista de nuevo ----
    let pedida = null;
    const realShow = window.showPickingList;
    window.showPickingList = function (t, l, o) { pedida = [t, l, o && o.seedFromServer]; };
    guardar("v18.18");
    pkResume(leg);
    out.viejoRebaja      = !!(pedida && pedida[0] === T && pedida[2] === true);
    out.viejoNoAbreModal = !document.getElementById("tandaModal").classList.contains("show");

    // ---- 3) el nuevo sí reabre al instante (offline-first intacto) ----
    pedida = null;
    guardar("v18.53");
    pkResume(leg);
    out.nuevoAbreDeMemoria = !pedida && !!(_pk && _pk.tanda === T && _pk.results["505"] === 4);
    try { document.getElementById("tandaModal").classList.remove("show"); } catch (_e) {}
    window.showPickingList = realShow;

    // ---- 4) lo que se guarda hoy lleva el sello ----
    _pk = { tanda: T, legajo: leg, items: [{ art: "505", key: "505", esp: 4 }], idx: 0, results: {}, mode: "item" };
    pkSave();
    const guardado = JSON.parse(localStorage.getItem("vir_pk_" + leg) || "{}");
    out.guardaSello      = !!guardado.app;
    out.selloEsLaVersion = guardado.app === APP_VERSION;
    out.guardadoHoyEsBueno = !pkSnapshotDesactualizado(guardado);
    return out;
  });
  const pass = Object.keys(r).every(k => r[k]) && errs.length === 0;
  console.log("pk-snapshot-viejo:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
