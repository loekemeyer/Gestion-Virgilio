/* Regresión v15.57 — dos pedidos del dueño sobre el RESUMEN de la PPP (11/09/2026):

   1) "elimina ese espacio entre fecha dd/mm/yy, también que sea solo dd/mm" → en la tabla
      Fecha × zonas (ppp-restbl) la fecha va "09/09" (sin año) y el día queda pegado: la tabla
      ya no se estira al 100% (width:auto) y Fecha/Día llevan padding chico entre sí.
   2) "si toco en el nro de NP quiero ver qué contenía esa NP (cod y cjas)" → en el detalle
      de una celda (pppResTgl → tabla NP · Tanda · Cliente · Localidad · m³) la celda NP es
      clickeable y abre pppChequeoNp (el mismo modal del ✓: artículo · cajas pedidas · góndola).
      Y ese modal ahora lee gv_np_items, así que una NP WEB ("LK 0024") también trae sus
      líneas (antes gv_ppp_base_pedidos no las tenía → "No encontré artículos").

   Chequea, con fetch stubbeado (sin red):
   a) td.f de la tabla = "dd/mm" y CSS width:auto + padding chico Fecha/Día,
   b) td.np del detalle lleva onclick a pppChequeoNp con la NP y el cliente,
   c) pppChequeoNp pide gv_np_items con la NP web ENTRECOMILLADA y pinta cod + cajas.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = { urls: [] };
    function J(data){ return Promise.resolve({ ok: true, status: 200, json: function(){ return Promise.resolve(data); } }); }
    window.fetch = function (url) {
      url = String(url); out.urls.push(url);
      if (url.indexOf("gv_np_items") >= 0) return J([{ pedido: "LK 0024", articulo: "505L", cajas: 5 }]);
      return J([]);
    };
    window.supaFetchAllSafe = async function () { return []; };
    window.loadArtNombres = async function () { return {}; };
    window.loadCodCanon = async function () { return {}; };
    window.getActivityStatus = async function () { return { pickingDone: new Set(), pickingEnCursoBy: new Map() }; };
    window.pppRenderProg = function () {};

    // --- (a) la tabla Fecha × zonas ---
    const prog = [
      { np: "LK 0024", tanda: "E09B", cod: "2533", razon_social: "Osa Distribuidora SRLChemelo", localidad: "Villa Lugano", m3: 0.03, fecha: "08/09/2026", fecha_entrega: "09/09/2026", zona: "Zona 1 - CABA Sur" },
      { np: "98532",   tanda: "E10A", cod: "3958", razon_social: "Betbeze Gimenez Nahuel",       localidad: "Palermo",      m3: 0.40, fecha: "08/09/2026", fecha_entrega: "10/09/2026", zona: "Zona 2 - CABA Centro" }
    ];
    const html = pppResumenHtml(prog);
    const host = document.createElement("div"); host.innerHTML = html; document.body.appendChild(host);
    const tdF = Array.prototype.slice.call(host.querySelectorAll(".ppp-restbl td.f")).map(function (td) { return td.textContent; });
    out.fechas = tdF.slice(0, 2);
    out.sinAnio = tdF.filter(function (t) { return t !== "TOTAL"; }).every(function (t) { return /^\d{2}\/\d{2}$/.test(t); });
    const tbl = host.querySelector(".ppp-restbl");
    const cs = getComputedStyle(tbl), csF = getComputedStyle(host.querySelector(".ppp-restbl td.f")), csD = getComputedStyle(host.querySelector(".ppp-restbl td.d"));
    out.widthAuto = cs.width !== "" && tbl.offsetWidth < host.offsetWidth;          // no se estira al ancho del contenedor
    out.pegados = parseFloat(csF.paddingRight) <= 4 && parseFloat(csD.paddingLeft) <= 4;

    // --- (b) el detalle de la celda: NP clickeable ---
    const dk = Object.keys(_pppResDet)[0];
    pppResTgl(dk, encodeURIComponent("__tot__"));
    const ov = document.getElementById("pppResPopOv");
    const npCell = ov.querySelector(".pppres-tbl td.np");
    out.npTexto = npCell ? npCell.textContent : "";
    out.npClick = !!npCell && /pppChequeoNp\(/.test(npCell.getAttribute("onclick") || "") && npCell.classList.contains("npc");
    out.npLlevaCliente = !!npCell && (npCell.getAttribute("onclick") || "").indexOf("Osa Distribuidora") >= 0;

    // --- (c) el modal trae las líneas de la NP web ---
    await pppChequeoNp("LK 0024", "Osa Distribuidora SRLChemelo", "E09B");
    const u = out.urls.find(function (x) { return x.indexOf("gv_np_items") >= 0; }) || "";
    out.pidioNpItems = !!u;
    out.entrecomillada = u.indexOf("%22LK%200024%22") >= 0;
    out.aliasPedido = u.indexOf("select=pedido:np,articulo,cajas") >= 0;
    const chk = document.getElementById("pppChkOv");
    out.pintaCod = !!chk && chk.textContent.indexOf("505L") >= 0;
    out.pintaCajas = !!chk && !!chk.querySelector(".pppchk-tbl") && /\b5\b/.test(chk.querySelector(".pppchk-tbl tbody tr td.num").textContent);
    return out;
  });

  const pass =
    r.sinAnio && r.fechas.length === 2 && r.widthAuto && r.pegados &&
    r.npClick && r.npLlevaCliente &&
    r.pidioNpItems && r.entrecomillada && r.aliasPedido && r.pintaCod && r.pintaCajas &&
    errs.length === 0;
  const { urls, ...vis } = r;
  console.log("ppp-res-np-fecha:", JSON.stringify(vis), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
