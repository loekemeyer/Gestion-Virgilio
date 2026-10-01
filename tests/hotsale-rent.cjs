/* v25.91 — Hot Sale: rentabilidad ponderada del período (Thomas, 01/10/2026).
   Corre la pantalla de verdad (hotsale.js dentro de index.html) y mide:
     (a) el botón está en los secundarios del panel supervisor y abre el overlay con los 6 datos
         de la planilla de Thomas (HotSale %, Semanas HotSale, Rent c/AP, Rent Pta Pta, Semanas a
         Ponderar, cuánto más se vende);
     (b) la planilla de 4 semanas (100 % · 20 % · 2 HS · ×2) da 73,33 % y la de 16 semanas 91,11 %;
     (c) el ítem real (recibo 922, costo 986 → −6,49 %, 12 sem) da −11,83 %: la rentabilidad
         negativa se admite;
     (d) importados y nacionales salen por separado (los defaults de la planilla: 65,00 % y 3,71 %);
     (e) semanas de hot sale > semanas a ponderar → aviso y la tabla se vacía (no queda un
         resultado viejo que contradiga los datos);
     (f) el botón Cerrar no hereda el button{width:100%} global (regla v23.93 / v23.98);
     (g) hsCalc es pura y el costo no entra;
     (h) a 390 px (celular) la tabla de resultados entra entera, sin cortar Nacionales. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await (await b.newContext({ viewport: { width: 1400, height: 900 }, serviceWorkers: "block" })).newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    for (let i = 0; i < 50 && typeof window.openHotSale !== "function"; i++) await espera(100);
    window.requireSupervisor = () => true;
    try { localStorage.removeItem("gv_hotsale_params_v1"); } catch (_e) {}
    const out = {};
    const btn = [...document.querySelectorAll(".sup-actions.sup-secondary .sup-action-btn")].find((x) => /openHotSale/.test(x.getAttribute("onclick") || ""));
    out.boton = !!btn && /Hot Sale/.test(btn.textContent);
    window.openHotSale();
    await espera(100);
    const ov = document.getElementById("hsOv");
    out.visible = !!ov && getComputedStyle(ov).display === "flex";
    out.inputs = ov ? ov.querySelectorAll("#hsForm input").length : 0;
    const set = (v) => { for (const k in v) { document.getElementById("hs" + k).value = v[k]; } document.getElementById("hsForm").dispatchEvent(new Event("input", { bubbles: true })); };
    const pond = () => [document.getElementById("hsPondImp"), document.getElementById("hsPondNac")].map((t) => t ? t.textContent : null);
    out.def = pond();
    set({ MI: 100, MN: 50, A: 20, H: 2, P: 4, K: 2 }); out.p4 = pond();
    set({ P: 16 }); out.p16 = pond();
    set({ MI: 100, MN: -6.49, A: 20, H: 2, P: 12, K: 2 }); out.real = pond();
    out.filasSem = document.querySelectorAll("#hsSem table tbody tr").length;
    set({ H: 5, P: 4 });
    out.errMsg = document.getElementById("hsMsg").textContent;
    out.tablaVacia = document.getElementById("hsT").innerHTML === "" && document.getElementById("hsSem").innerHTML === "";
    set({ H: 2, P: 12 });
    const cerrar = ov.querySelector(".hs-x");
    out.cerrarAncho = cerrar ? cerrar.getBoundingClientRect().width : 0;
    const c1 = window.hsCalc(1, 0.2, 4, 2, 2), c2 = window.hsCalc(-0.0649, 0.2, 12, 2, 2), c3 = window.hsCalc(0.5, 0, 10, 0, 2);
    out.calc = [c1.pond, c2.pond, c3.pond, c1.mHS];
    window.hsClose();
    out.cerrado = getComputedStyle(ov).display === "none";
    return out;
  });
  /* (h) celular */
  const pm = await (await b.newContext({ viewport: { width: 390, height: 800 }, serviceWorkers: "block" })).newPage();
  await pm.route("**/rest/v1/**", (x) => x.abort());
  await pm.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const m = await pm.evaluate(async () => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    for (let i = 0; i < 50 && typeof window.openHotSale !== "function"; i++) await espera(100);
    window.requireSupervisor = () => true;
    try { localStorage.removeItem("gv_hotsale_params_v1"); } catch (_e) {}
    window.openHotSale(); await espera(100);
    const t = document.getElementById("hsT").getBoundingClientRect();
    const body = document.querySelector(".hs-body");
    return { right: t.right, w: innerWidth, scroll: body.scrollWidth <= body.clientWidth };
  });
  const fails = [];
  if (!(m.right <= m.w && m.scroll)) fails.push("(h) a 390 px la tabla llega a " + m.right + " px de " + m.w);
  if (!r.boton) fails.push("(a) falta el botón en los secundarios");
  if (!r.visible || r.inputs !== 6) fails.push("(a) overlay/inputs " + r.visible + " " + r.inputs);
  if (r.p4[0] !== "73,33 %") fails.push("(b) 4 semanas: " + r.p4[0]);
  if (r.p16[0] !== "91,11 %") fails.push("(b) 16 semanas: " + r.p16[0]);
  if (r.real[1] !== "-11,83 %") fails.push("(c) ítem real nacional: " + r.real[1]);
  if (r.def[0] !== "65,00 %" || r.def[1] !== "3,71 %") fails.push("(d) defaults: " + r.def);
  if (r.filasSem !== 2 * (12 + 1)) fails.push("(d) semana por semana: " + r.filasSem + " filas");
  if (!/Revisá/.test(r.errMsg) || !r.tablaVacia) fails.push("(e) error: '" + r.errMsg + "' tablaVacia=" + r.tablaVacia);
  if (!(r.cerrarAncho > 0 && r.cerrarAncho < 200)) fails.push("(f) Cerrar mide " + r.cerrarAncho + " px");
  if (Math.abs(r.calc[0] - 0.7333333) > 1e-6 || Math.abs(r.calc[1] + 0.118342) > 1e-5 || Math.abs(r.calc[2] - 0.5) > 1e-12 || Math.abs(r.calc[3] - 0.6) > 1e-12) fails.push("(g) hsCalc " + r.calc);
  if (!r.cerrado) fails.push("(f) no cierra");
  if (errs.length) fails.push("errores: " + errs.join(" | "));
  await b.close();
  if (fails.length) { console.error("FALLA hotsale-rent:\n  " + fails.join("\n  ")); process.exit(1); }
  console.log("OK hotsale-rent");
})();
