/* Regresión v20.86 — EL ARMADO QUE ESPERA CAMIÓN ENTRA AL BADGE DE LA PPP.

   Thomas, 2026-09-21: *"debería aparecer discriminado en el badge del icono de PPP en la
   página principal del admin (un número rojo con los pendientes)"*.

   Iro Iro (98626/98627) estaba armado, FACTURADO y sin día de entrega desde el 18/09:
   `gv_ppp_programacion_diaria` le vacía la fecha a lo que esté en `GV_PPP_Armados_Espera`,
   así que las dos NP no caían en ningún día de la Programación y nada avisaba.

   Chequea, con la red simulada (sin tocar Supabase):
   - el badge SUMA los armados en espera (antes los ignoraba);
   - el pop-up los muestra como grupo propio, con el cliente, los m³ y los días;
   - se ve que ya está facturado sin salir, que es lo que apura;
   - y el candado invertido: el tipo `armado_espera` no puede desaparecer del front.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}

/* lo que devuelve gv_ppp_avisos (el número del badge) */
const AVISOS = [
  { tipo: "armado_espera", orden: 4, titulo: "Pedidos armados esperando camión (sin día)", n: 1 },
  { tipo: "retenido_sin_fecha", orden: 5, titulo: "Pedidos sacados a mano, esperando fecha", n: 2 },
];
/* lo que devuelve gv_ppp_avisos_detalle (el desglose) */
const DET = [
  { tipo: "armado_espera", orden: 4, titulo: "Pedidos armados esperando camión (sin día)",
    fecha: "2026-09-18", que: "Iro Iro S.R.L",
    detalle: "2 NP (98626, 98627) · tanda E39A, E40A · 0.483 m³ · Zona 4 - GBA Sur · " +
             "espera hace 3 día(s) · ⚠ YA FACTURADO sin salir · no quedó registrado quién ni por qué",
    accion: "Está armado en el pallet sin día de entrega. Darle día con camión a su zona, o fundar uno." },
  { tipo: "retenido_sin_fecha", orden: 5, titulo: "Pedidos sacados a mano, esperando fecha",
    fecha: "2026-09-21", que: "LK pedido 1448", detalle: "3 NP · salió de la tanda D69H",
    accion: "Está en A Programar esperando día." },
  { tipo: "retenido_sin_fecha", orden: 5, titulo: "Pedidos sacados a mano, esperando fecha",
    fecha: "2026-09-24", que: "CH pedido 218", detalle: "1 NP · salió de la tanda E26B",
    accion: "Está en A Programar esperando día." },
];

(async () => {
  const root = path.join(__dirname, "..");
  const fallos = [];

  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async (data) => {
    const out = {};
    const urls = [];
    window.fetch = async function (url) {
      const u = String(url);
      urls.push(u);
      const filas = u.indexOf("gv_ppp_avisos_detalle") >= 0 ? data.det
                  : u.indexOf("gv_ppp_avisos") >= 0        ? data.avisos
                  : [];
      return { ok: true, status: 200, json: async () => filas };
    };
    // el panel de supervisor tiene que estar a la vista o pppFetchAvisos no pide nada
    const sup = document.getElementById("supervisorPanel");
    if (sup) sup.classList.remove("hidden");

    // 1) el NÚMERO del badge
    _pppAvisos = await pppFetchAvisos();
    pppAlertBadgeUpdate();
    const badge = document.getElementById("pppAlertBadge");
    out.badgeTxt = badge ? (badge.textContent || "").trim() : "(no existe)";
    out.badgeTitle = badge ? (badge.title || "") : "";

    // 2) el DESGLOSE
    await pppAvisosAbrir();
    const ov = document.getElementById("pppAvisosPop");
    out.html = ov ? ov.innerHTML : "";
    out.urls = urls;
    return out;
  }, { avisos: AVISOS, det: DET });
  await b.close();
  if (errs.length) fallos.push("errores de página: " + errs.join(" | "));

  // ── el número rojo suma los armados en espera ────────────────────────────────
  if (r.badgeTxt !== "3")
    fallos.push('el badge dice "' + r.badgeTxt + '" y tiene que decir 3 (1 armado en espera + 2 retenidos)');
  if (!/armados esperando/i.test(r.badgeTitle || ""))
    fallos.push("el title del badge no desglosa los armados en espera: " + (r.badgeTitle || "(vacío)"));

  // ── el desglose lo muestra como grupo propio ─────────────────────────────────
  const h = r.html || "";
  if (!/Pedidos armados esperando camión/.test(h))
    fallos.push("el pop-up no muestra el grupo de armados esperando camión");
  if (!/Iro Iro/.test(h)) fallos.push("no muestra de qué cliente es");
  if (!/0\.483 m³/.test(h)) fallos.push("no muestra los m³ del pedido");
  if (!/espera hace 3 día\(s\)/.test(h)) fallos.push("no dice hace cuántos días espera");
  if (!/YA FACTURADO sin salir/.test(h))
    fallos.push("no avisa que ya está facturado sin salir — es lo que apura el caso");
  if (!/98626/.test(h) || !/98627/.test(h)) fallos.push("no nombra las NP concretas");
  const grupos = (h.match(/class="pav-grupo"/g) || []).length;
  if (grupos !== 2) fallos.push("agrupó en " + grupos + " grupos (esperado 2)");

  // ── candado invertido: el tipo no puede desaparecer ──────────────────────────
  if (!(r.urls || []).some((u) => /gv_ppp_avisos_detalle/.test(u)))
    fallos.push("no lee gv_ppp_avisos_detalle");

  if (fallos.length) { console.error("ppp-armado-espera-badge FALLA:\n - " + fallos.join("\n - ")); process.exit(1); }
  console.log("ppp-armado-espera-badge OK — el armado que espera camión suma al badge y se ve con cliente, m³ y días.");
})();
