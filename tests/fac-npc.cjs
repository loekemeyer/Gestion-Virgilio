/* Regresión v5.36 — dos features:
   F1) Facturación: una NP con faltantes (Entregas_Virgilio.cajas_falto>0) muestra
       badge ⚠ en la fila y PIDE CONFIRMACIÓN antes de facturar (facTickNP). Cancelar
       = no postea; aceptar = postea.
   F2) Consulta NP/Líos: npcLoad arma _npcRows cruzando TAL + Entregas + PPP; npcApply
       filtra en vivo; el render marca los artículos faltantes en la composición.
   Todo con fetch stubbeado (sin red). Sale 1 si falla. */
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
    const posts = [];
    window.alert = function () {};
    function J(data) { return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve(data); } }); }
    window.fetch = function (url, opts) {
      url = String(url);
      const method = (opts && opts.method) || "GET";
      if (method === "POST" && url.indexOf("Facturacion_NP") >= 0) { posts.push({ url: url, body: opts && opts.body }); return J([]); }
      if (url.indexOf("opcion=eq.TAL") >= 0) {
        return J([
          { texto: "97957|28|C75B|A=570X3;G=315X4;L=595X1,596X5|LIO", ts_cliente: "2026-07-15T13:00:00Z", legajo: "122" },
          { texto: "97958|16|C75B|A=100X2;B=200X3|NADA", ts_cliente: "2026-07-15T12:00:00Z", legajo: "122" }
        ]);
      }
      if (url.indexOf("Entregas_Virgilio") >= 0 && url.indexOf("cajas_falto=gt.0") >= 0) {
        // F1: facFetchFaltantes
        return J([
          { np: "97957", cod_art: "315", cajas_falto: 10, cajas_pedidas: 13 },
          { np: "97957", cod_art: "561", cajas_falto: 1, cajas_pedidas: 5 }
        ]);
      }
      if (url.indexOf("Entregas_Virgilio") >= 0) {
        // F2: enriquecimiento por np=in.()
        return J([
          { np: "97957", cod_cliente: "2533", tanda: "C75B", fecha_salida: "2026-07-15", cod_art: "315", cajas_pedidas: 13, cajas_falto: 10 },
          { np: "97957", cod_cliente: "2533", tanda: "C75B", fecha_salida: "2026-07-15", cod_art: "561", cajas_pedidas: 5, cajas_falto: 1 },
          { np: "97958", cod_cliente: "2533", tanda: "C75B", fecha_salida: "2026-07-15", cod_art: "100", cajas_pedidas: 2, cajas_falto: 0 }
        ]);
      }
      if (url.indexOf("PPP_Entregados_Meta") >= 0) return J([]);
      if (url.indexOf("PPP_Programacion_Diaria") >= 0) {
        return J([
          { np: "97957", cod: "2533", razon_social: "Osa Distribuidora", fecha_entrega: "2026-07-15 00:00:00", tanda: "C75B" },
          { np: "97958", cod: "2533", razon_social: "Osa Distribuidora", fecha_entrega: "2026-07-15 00:00:00", tanda: "C75B" }
        ]);
      }
      if (url.indexOf("opcion=in.(EP,TP)") >= 0) {   // picking → quién pickeó la tanda
        return J([
          { opcion: "EP", texto: "C75B", legajo: "55", ts_cliente: "2026-07-15T08:00:00Z" },
          { opcion: "TP", texto: "C75B", legajo: "55", ts_cliente: "2026-07-15T09:00:00Z" }
        ]);
      }
      if (url.indexOf("Empleados") >= 0) {           // legajo → nombre
        return J([{ Legajo: "122", Empleado: "Juan Pérez" }, { Legajo: "55", Empleado: "Pedro Gómez" }]);
      }
      return J([]);
    };

    // ===== F1: faltantes badge + confirm guard =====
    await facFetchFaltantes();
    out.faltInfo = !!facFaltInfo("97957");
    out.faltBadge = facFaltBadge("97957");     // "⚠ FALTA 11 cj: 315×10, 561×1"
    out.faltBadgeEmpty = facFaltBadge("99999");

    let confirmMsg = "";
    window.confirm = function (m) { confirmMsg = String(m); return false; };
    const btn = document.createElement("button");
    btn.dataset.args = JSON.stringify({ np: "97957", tanda: "C75B", m3: 1, rs: "Osa", cod: "2533", feRaw: "2026-07-15" });
    await window.facTickNP(btn);
    out.confirmShown = /FALTANTES/.test(confirmMsg);
    out.postAfterCancel = posts.length;        // 0
    out.btnNotDisabled = btn.disabled === false;

    window.confirm = function () { return true; };
    window.facAuthWriteHeaders = async function () { return { apikey: "x", Authorization: "Bearer x", "Content-Type": "application/json" }; };
    const btn2 = document.createElement("button");
    btn2.dataset.args = JSON.stringify({ np: "97957", tanda: "C75B", m3: 1, rs: "Osa", cod: "2533", feRaw: "2026-07-15" });
    await window.facTickNP(btn2);
    out.postAfterOk = posts.length;            // 1

    // ===== F2: consulta =====
    await npcLoad(true);
    out.rowCount = _npcRows.length;
    const row57 = _npcRows.find(function (x) { return x.np === "97957"; });
    out.row57 = row57 ? { tanda: row57.tanda, cod: row57.cod, rs: row57.rs, fecha: row57.fecha, lios: row57.lios, falt: row57.falt ? row57.falt.cajas : 0, salePpp: row57.salePpp, armadorLeg: row57.armadorLeg, pickerLeg: row57.pickerLeg } : null;
    npcApply();
    out.contHtml = (document.getElementById("npcContainer") || {}).innerHTML || "";
    // Buscador único: matchea contra todos los campos, multi-término = AND.
    document.getElementById("npcQ").value = "97958"; npcApply();
    out.filterNp = (document.getElementById("npcCount") || {}).textContent;      // 1 / 2 (NP)
    document.getElementById("npcQ").value = "osa"; npcApply();
    out.filterRs = (document.getElementById("npcCount") || {}).textContent;      // 2 / 2 (razón social)
    document.getElementById("npcQ").value = "15/07"; npcApply();
    out.filterFecha = (document.getElementById("npcCount") || {}).textContent;   // 2 / 2 (fecha dd/mm)
    document.getElementById("npcQ").value = "osa 97958"; npcApply();
    out.filterMulti = (document.getElementById("npcCount") || {}).textContent;   // 1 / 2 (AND multi-término)
    document.getElementById("npcQ").value = "c75b"; npcApply();
    out.filterTanda = (document.getElementById("npcCount") || {}).textContent;   // 2 / 2 (tanda)
    document.getElementById("npcQ").value = "pedro"; npcApply();                 // nombre del picker en el haystack
    out.filterPicker = (document.getElementById("npcCount") || {}).textContent;  // 2 / 2
    return out;
  });

  const okF1 = r.faltInfo === true && /FALTA/.test(r.faltBadge) && /11/.test(r.faltBadge) &&
    r.faltBadgeEmpty === "" && r.confirmShown === true && r.postAfterCancel === 0 &&
    r.btnNotDisabled === true && r.postAfterOk === 1;
  const okF2 = r.rowCount === 2 && r.row57 && r.row57.tanda === "C75B" && r.row57.cod === "2533" &&
    /Osa/.test(r.row57.rs) && r.row57.fecha === "2026-07-15" && r.row57.lios === 28 && r.row57.falt === 11 &&
    r.row57.salePpp === "2026-07-15" && r.row57.armadorLeg === "122" && r.row57.pickerLeg === "55" &&
    /315/.test(r.contHtml) && /npc-item f/.test(r.contHtml) &&
    /Pickeó/.test(r.contHtml) && /Pedro Gómez/.test(r.contHtml) && /Juan Pérez/.test(r.contHtml) && /Sale/.test(r.contHtml) &&
    /^1 \//.test(String(r.filterNp)) && /^2 \//.test(String(r.filterRs)) && /^2 \//.test(String(r.filterFecha)) &&
    /^1 \//.test(String(r.filterMulti)) && /^2 \//.test(String(r.filterTanda)) && /^2 \//.test(String(r.filterPicker));
  const pass = okF1 && okF2 && errs.length === 0;
  console.log("fac-npc:", JSON.stringify(r).slice(0, 600));
  console.log("  pageerrors:", errs.length ? errs.join("|") : "none");
  console.log(" ", okF1 ? "F1 faltante ✓" : "F1 faltante ✗", "·", okF2 ? "F2 consulta ✓" : "F2 consulta ✗", "·", pass ? "OK" : "FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
