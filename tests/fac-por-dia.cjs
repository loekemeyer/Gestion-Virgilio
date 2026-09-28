/* v23.59 (Luis, 28/09) — Facturación POR DÍA, como la Programación de la PPP.
   A. una fila de cabecera por fecha de entrega (las sin fecha al final), con su casilla;
   B. la casilla de un día marca SÓLO las NP web de ese día; dos días marcados = las de los dos;
   C. NP de LK y de CH marcadas juntas → aviso y el botón dice «2 archivos»;
   D. bajar con LK + CH → 2 archivos (uno LK, uno CH). Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async function () {
    const out = {};
    let c = document.getElementById("facContainer");
    if (!c) { c = document.createElement("div"); c.id = "facContainer"; document.body.appendChild(c); }
    ["facCntTandas", "facCntPend", "facCntDone", "facBtnCierre", "facBtnRevertir", "facBtnXlsIsis"].forEach(function (id) {
      if (!document.getElementById(id)) { const e = document.createElement(id.indexOf("Btn") > 0 ? "button" : "span"); e.id = id; document.body.appendChild(e); }
    });
    window.facEstaArmada = () => true; window.facFaltInfo = () => null; window.facTareaActiva = () => null;
    window.facFaltAgregDist = () => ""; window.facPaintNeto = () => {}; window.facFetchNeto = () => {};
    window.facRenderTicked = () => {}; window.facRenderNc = () => {}; window.facAjustesIsisCargar = () => {}; window.facCruceBadge = () => {};
    window.facSinTandaCargar = () => Promise.resolve([]); window.facNuevosCargar = () => Promise.resolve(new Map());
    _facLios = new Map(); _facCajas = new Map([["LK 0073", 29], ["LK 0074", 4], ["CH 0022", 25]]); _facClase = new Map();
    _facXlsSel = new Set();
    const ped = (np) => ({ np: np, cod: "1", razonSocial: "X", direccion: "x", m3: 0.1, barrio: "", zona: "" });
    facRender([
      { tanda: "E30A", fechaEntrega: "30/09/2026", fechaEntregaRaw: "2026-09-30", pedidos: [ped("LK 0090"), ped("98700")] },
      { tanda: "E29A", fechaEntrega: "29/09/2026", fechaEntregaRaw: "2026-09-29", pedidos: [ped("CH 0022"), ped("LK 0073"), ped("LK 0074")] },
      { tanda: "E00Z", fechaEntrega: "", fechaEntregaRaw: "", pedidos: [ped("LK 0099")] }
    ]);
    const h = c.innerHTML;
    out.cabs = [...c.querySelectorAll("tr.fac-dia-row .fac-dia-lbl")].map((x) => x.textContent.replace(/\s+/g, " ").trim());
    out.sinFechaUltima = h.indexOf("Sin fecha de entrega") > h.indexOf('data-fac-np="98700"');
    out.sinGlobal = !document.getElementById("facXlsChkAll");
    const dia = (k) => c.querySelector('input.fac-dia-chk[data-dia="' + k + '"]');
    dia("2026-09-29").checked = true; dia("2026-09-29").dispatchEvent(new Event("change"));
    out.selDia29 = [..._facXlsSel].sort();
    out.mixVisible = document.getElementById("facXlsMix").style.display !== "none" && /2 archivos/.test(document.getElementById("facXlsMix").textContent);
    out.boton = document.getElementById("facBtnXlsIsis").textContent;
    dia("2026-09-30").checked = true; dia("2026-09-30").dispatchEvent(new Event("change"));
    out.selDosDias = [..._facXlsSel].sort();
    dia("2026-09-29").checked = false; dia("2026-09-29").dispatchEvent(new Event("change"));
    out.selSolo30 = [..._facXlsSel].sort();
    out.sinMix = document.getElementById("facXlsMix").style.display === "none";
    // D. bajar LK + CH → 2 archivos
    const archivos = [];
    window.requireSupervisor = () => true;
    window.facAuthWriteHeaders = async () => ({ apikey: "x" });
    window.facMarcarFacturada = async () => true; window.facShowToast = () => {}; window.facDescRegistrar = async () => {};
    window._facXlsArmar = async (nps) => nps.map((np) => ({ np: np, lineas: [] }));
    window._facXlsDescargarXlsx = (f, emp) => { archivos.push(emp + ":" + f.map((x) => x.np).join(",")); return {}; };
    window._facXlsDescargar = window._facXlsDescargarXlsx;
    _facXlsSel = new Set(["LK 0073", "CH 0022", "LK 0074"]);
    await facXlsBajar();
    out.archivos = archivos;
    return out;
  });
  const f = [];
  if (JSON.stringify(r.cabs.map((x) => x.split(" ·")[0])) !== '["📅 Martes 29/09","📅 Miércoles 30/09","📅 Sin fecha de entrega"]') f.push("A cabeceras: " + JSON.stringify(r.cabs));
  if (!/3 NP · 58 cajas/.test(r.cabs[0] || "")) f.push("A totales del día: " + r.cabs[0]);
  if (!r.sinFechaUltima || !r.sinGlobal) f.push("A sin fecha al final / sin casilla global");
  if (JSON.stringify(r.selDia29) !== '["CH 0022","LK 0073","LK 0074"]') f.push("B día 29: " + JSON.stringify(r.selDia29));
  if (JSON.stringify(r.selDosDias) !== '["CH 0022","LK 0073","LK 0074","LK 0090"]') f.push("B dos días: " + JSON.stringify(r.selDosDias));
  if (JSON.stringify(r.selSolo30) !== '["LK 0090"]') f.push("B desmarcar día: " + JSON.stringify(r.selSolo30));
  if (!r.mixVisible || !/2 archivos/.test(r.boton) || !r.sinMix) f.push("C aviso mezcla: " + JSON.stringify([r.mixVisible, r.boton, r.sinMix]));
  if (JSON.stringify(r.archivos) !== '["LK:LK 0073,LK 0074","CH:CH 0022"]') f.push("D archivos: " + JSON.stringify(r.archivos));
  if (errs.length) f.push("pageerror: " + errs.join(" | "));
  await b.close();
  if (f.length) { console.log("fac-por-dia: ✗ " + f.join(" · ")); process.exit(1); }
  console.log("fac-por-dia: OK — cabecera por día · casilla marca sólo su día · aviso LK+CH · 2 archivos");
})();
