/* (Luis, 16/10/2026) — pop-up "Cajas pedidas" con dos pestañas: «Hoy» (lo pendiente, abre ahí) e «Histórico»
   (Entregas_Virgilio: cuándo se pidió, cuándo se entregó, cuánto pidió y cuánto se entregó, por NP).
   Mide: abre en Hoy; Histórico suma por NP, saca las tandas anuladas (-X lo filtra el server: se mira la URL),
   no duplica la misma NP|art|tanda, filtra por empresa (código con L → LK) y marca lo que faltó.
   Y en los movimientos el supervisor «sup:<mail>» se muestra «Admin», sin el mail.
   fetch stubbeado (sin red). Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {}; window.alert = function () {};
    function J(data) { return Promise.resolve({ ok: true, status: 200, headers: { get: function () { return null; } }, json: function () { return Promise.resolve(data); }, text: function () { return Promise.resolve(JSON.stringify(data)); } }); }
    _stk = { movs: [], viewRows: [] };
    window.getEmpleadosNombres = async function () { return new Map(); };
    let entUrl = "";
    window.fetch = function (url) {
      url = String(url);
      if (url.indexOf("gv_demanda_pedidos") >= 0) return J([{ pedido: "LK 0439", cajas: 1, articulo: "982E", origen: "web" }]);
      if (url.indexOf("gv_np_prog_info") >= 0) return J([
        { np: "LK 0439", tanda: "F98A", razon_social: "Garbarino Franco Tomas", fecha_entrega: "2026-10-20", fecha_recep: "2026-10-15" },
        { np: "LK 0166", razon_social: "Cliente Uno", fecha_recep: "2026-10-03" }
      ]);
      if (url.indexOf("Facturacion_NP") >= 0) return J([{ np: "LK 0103", razon_social: "Cliente Dos" }]);
      if (url.indexOf("Entregas_Virgilio") >= 0) { entUrl = url; return J([
        { np: "LK 0166", cod_art: "982E", tanda: "F13E", cajas_pedidas: 4, cajas_entregadas: 0, fecha_salida: "2026-10-08" },
        { np: "LK 0166", cod_art: "982E", tanda: "F13E", cajas_pedidas: 4, cajas_entregadas: 0, fecha_salida: "2026-10-08" },  // duplicada
        { np: "LK 0103", cod_art: "982E", tanda: "F71A", cajas_pedidas: 7, cajas_entregadas: 7, fecha_salida: "2026-10-07" },
        { np: "CH 0058", cod_art: "982E", tanda: "F59A", cajas_pedidas: 12, cajas_entregadas: 12, fecha_salida: "2026-10-16" }   // empresa CH sin L: fuera del filtro LK
      ]); }
      return J([]);
    };
    await stkOpenCajasPedidasArt(encodeURIComponent("982E LK"));
    const hoy = document.getElementById("stkCpHoy"), hist = document.getElementById("stkCpHist");
    out.tabs = !!document.getElementById("stkCpTabHoy") && !!document.getElementById("stkCpTabHist");
    out.abreHoy = !!hoy && hoy.style.display !== "none" && hist.style.display === "none" && hoy.innerHTML.indexOf("LK 0439") >= 0;
    stkCajasPedTab("hist");
    for (let i = 0; i < 40 && !hist.dataset.ok; i++) await new Promise(function (res) { setTimeout(res, 50); });
    const h = hist.innerHTML;
    out.visible = hist.style.display !== "none" && hoy.style.display === "none";
    out.urlSinAnuladas = entUrl.indexOf("tanda=not.like.*-X") >= 0;
    out.filas = (h.match(/<tr/g) || []).length;   // encabezado + 2 NP + total
    out.dedupe = h.indexOf(">4<") >= 0 && h.indexOf(">8<") < 0;
    out.empresa = h.indexOf("CH 0058") < 0;
    out.orden = h.indexOf("LK 0166") < h.indexOf("LK 0103");   // entrega más reciente arriba
    out.rs = h.indexOf("Cliente Uno") >= 0 && h.indexOf("Cliente Dos") >= 0;
    out.fechaPedido = h.indexOf("3/10") >= 0;
    out.falto = /color:#b91c1c[^>]*>4</.test(h);
    out.total = h.indexOf("TOTAL (2 NP)") >= 0 && h.indexOf(">11<") >= 0 && h.indexOf(">7<") >= 0;
    out.volverHoy = (stkCajasPedTab("hoy"), hoy.style.display !== "none" && hist.style.display === "none");
    // (Luis, 16/10) celda en «—» (sin pendiente): abre directo en Histórico
    const fetch0 = window.fetch;
    window.fetch = function (url) { url = String(url); if (url.indexOf("gv_demanda_pedidos") >= 0) return J([]); return fetch0(url); };
    await stkOpenCajasPedidasArt(encodeURIComponent("982E LK"), "hist");
    const hist2 = document.getElementById("stkCpHist");
    for (let i = 0; i < 40 && !hist2.dataset.ok; i++) await new Promise(function (res) { setTimeout(res, 50); });
    out.abreHistSinPend = hist2.style.display !== "none" && document.getElementById("stkCpHoy").style.display === "none" && hist2.innerHTML.indexOf("LK 0166") >= 0;
    window.fetch = fetch0;
    // sup:<mail> → Admin
    const chip = _stkQuienChip({ legajo: "sup:loekemeyer.n8n@gmail.com", tipo: "ajuste" });
    out.admin = chip.indexOf(">Admin<") >= 0 && chip.indexOf("@gmail.com</") < 0 && chip.indexOf("sup:") < 0;
    return out;
  });
  const pass = r.tabs && r.abreHoy && r.visible && r.urlSinAnuladas && r.filas === 4 && r.dedupe && r.empresa && r.orden && r.rs && r.fechaPedido && r.falto && r.total && r.volverHoy && r.admin && r.abreHistSinPend && errs.length === 0;
  console.log("cajped-historico:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
