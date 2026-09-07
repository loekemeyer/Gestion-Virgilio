/* Regresión v13.62 — "En Salida" tiene que mostrar la FECHA EN QUE SE CARGÓ EL CAMIÓN
   y el ESTADO de cada nota de pedido (pedido del dueño, 2026-09-06), y tiene que listar
   también las NP facturadas SIN evento CCN (98665 / 98502 / 98569), que antes se perdían.
   Además: la Recepción de Remitos embebida (tildar Controlado, ↩ s/salida) sólo aparece
   para supervisores; el módulo RR de arriba no se toca.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado (/opt/node22/lib/node_modules/playwright)."); process.exit(2); }
}

(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    // Dos filas como las que devuelve gv_ppp_en_salida v13.60: una cargada al camión y
    // una facturada sin registro de carga (el caso que motivó el cambio).
    const filas = [
      { np: "98602", empresa: "lk", es_web: false, tanda: "D53F", cod_cliente: "3915",
        razon_social: "Haidezer Sa", m3: 0.224, fecha_entrega: "2026-09-03", zona: "Zona 1 - CABA Sur",
        barrio: "Barracas", fecha_carga: "2026-09-03", cargado_at: "2026-09-03T17:20:00-03:00",
        facturada: true, armada: true, armado_at: "2026-09-03T11:00:00-03:00",
        cargada: true, control_previo: true, facturada_el: "2026-09-02",
        estado: "cargada", dias_sin_controlar: 3 },
      { np: "98665", empresa: "lk", es_web: false, tanda: "D50E", cod_cliente: "2193",
        razon_social: "Merajver Marcelo Fabian", m3: 0.042, fecha_entrega: "2026-09-02", zona: "Zona 1 - CABA Sur",
        barrio: "Pompeya", fecha_carga: null, cargado_at: null,
        facturada: true, armada: true, armado_at: "2026-09-02T10:00:00-03:00",
        cargada: false, control_previo: false, facturada_el: "2026-09-01",
        estado: "facturada_sin_cargar", dias_sin_controlar: 4 }
    ];
    // OJO: estas son `let` en el <script> (binding global declarativo), NO propiedades
    // de window. Hay que asignarlas SIN `window.` o el módulo sigue viendo su null.
    _pppEnSalida = new Map(filas.map((f) => [String(f.np), f]));
    _pppDelivered = [];
    _pppMetaEntSet = new Set();
    _pppSearch = "";
    _pppEsSel = new Set();

    // ── 1) Como OPERARIO (no supervisor): datos sí, acciones no ──────────────
    window.__isSupervisor = false;
    const hOp = _pppEnViajeHtml();

    // ── 2) Como SUPERVISOR: aparece la Recepción de Remitos embebida ─────────
    window.__isSupervisor = true;
    const hSup = _pppEnViajeHtml();

    // ── 3) Tildar una y ver que el botón de confirmar la cuenta ──────────────
    _pppEsSel = new Set(["98602"]);
    const hSel = _pppEnViajeHtml();

    return {
      // lo que pidió el dueño: fecha de carga y estado, visibles
      fechaCarga:      hOp.indexOf("03/09") >= 0,
      sinCargaVisible: hOp.indexOf("sin carga") >= 0,
      chipCargado:     hOp.indexOf("Cargado al camión") >= 0,
      chipSinRegistro: hOp.indexOf("Sin registro de carga") >= 0,
      chipArmada:      hOp.indexOf("Armada") >= 0,
      chipDias:        hOp.indexOf("4 días sin controlar") >= 0,
      // la NP sin CCN tiene que estar listada
      traeLaSinCCN:    hOp.indexOf("98665") >= 0,
      traeLaCargada:   hOp.indexOf("98602") >= 0,
      // gate: el operario NO ve las acciones de control
      opSinControl:    hOp.indexOf("Controlado</th>") < 0 && hOp.indexOf("pppEsToggle") < 0,
      // supervisor SÍ las ve
      supConControl:   hSup.indexOf("Controlado</th>") >= 0 && hSup.indexOf("pppEsToggle") >= 0,
      supConSinSalida: hSup.indexOf("pppEsSinSalida") >= 0,
      supConAyuda:     hSup.indexOf("Recepción de Remitos") >= 0,
      // el botón de confirmar arranca deshabilitado y cuenta lo tildado
      botonVacioOff:   hSup.indexOf("disabled ") >= 0 && hSup.indexOf("Marcar 0 controlada(s)") >= 0,
      botonCuenta:     hSel.indexOf("Marcar 1 controlada(s)") >= 0 && hSel.indexOf("ppp-es-row on") >= 0,
      // los emisores que reusa son los MISMOS del módulo RR de arriba
      reusaCRN:        typeof window.crSendDetail === "function",
      reusaFSS:        typeof window.crSendSinSalida === "function",
      // el módulo RR de arriba sigue intacto
      rrIntacto:       typeof window.showControlRemitos === "function" && typeof window.crFinish === "function"
    };
  });

  await b.close();
  const fails = Object.keys(r).filter((k) => !r[k]);
  const ok = fails.length === 0 && errs.length === 0;
  console.log("ppp-ensalida-estado:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none", ok ? "· ✓ OK" : "· ✗ FALLA: " + fails.join(", "));
  process.exit(ok ? 0 : 1);
})();
