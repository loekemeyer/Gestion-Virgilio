/* v24.80 (Luis, 30/09) — Pedidos Importación:
   A. un código que junta varios artículos del maestro (323ES = 323ES + 838E CH + 323E LK) tiene
      UN 📦 y UN 📥, no un par por artículo;
   B. el 📥 abre un selector con los pedidos en viaje de todos sus artículos;
   C. la recepción se carga en cajas o en UNIDADES: 3.000 u con UxB 144 → 21 cajas y avisa la diferencia;
      cambiar la UxB recalcula; lo que se manda a gv_imp_recibir son cajas enteras.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const ITEMS = [
  { cod: "323ES", desc: "RALLADOR SUELTO", prov: "Hugo Wong", proyUni: 1032, objetivoUni: 10320, stockUni: 0, enCurso: 8472,
    aPedirUni: 1848, uniMaster: 144, fobUni: 0.225, m3Master: 0.06,
    det: [{ id: 167, cod: "323ES", curso: 3000, marca: "LK" }, { id: 78, cod: "838E", curso: 1008, marca: "CH" }, { id: 79, cod: "323E", curso: 4464, marca: "LK" }] }
];
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async function (items) {
    window.__calls = [];
    const BACHES = { 167: [{ id: 134, estado: "en_curso", pendiente: 3000, pedido_ref: "323ES suelto" }],
      78: [{ id: 96, estado: "en_curso", pendiente: 1008, pedido_ref: "PI NY26" }],
      79: [{ id: 97, estado: "en_curso", pendiente: 4464, pedido_ref: "PI NY26" }, { id: 47, estado: "llegado", pendiente: 0 }] };
    const CTX = { bache_id: 134, cod_art: "323ES", cod_stock: "323ES", descripcion: "RALLADOR SUELTO", proveedor: "Hugo Wong",
      pedido_ref: "323ES suelto", unidades: 3000, llegadas: 0, pendiente: 3000, estado: "en_curso", dual: false, empresa: "LK",
      uni_x_caja: 144, uni_master: 144, gondola: [], racks: [], insumos_pos: [], insumos_cods: [] };
    _pedImpRpc = async function (fn, body) {
      window.__calls.push({ fn: fn, body: JSON.parse(JSON.stringify(body || {})) });
      if (fn === "gv_importado_baches") return BACHES[body.p_importado_id] || [];
      if (fn === "gv_imp_recibir_contexto") return CTX;
      if (fn === "gv_imp_recibir") return body.p_simular ? { ok: true, conflictos: [] } : { ok: true, recepcion_id: 1, unidades: 3024, cajas: 21, estado: "llegado", sobra: 24 };
      return null;
    };
    _pedImpAccionConfirmar = function (a, c, fn) { fn(); };
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items: items, meses: 10 }, soloPedir: false, mcOverride: {} };
    _pedImpRender();
    const out = {};
    const tr = document.querySelector(".mva-tbl.wide tbody tr");
    const btns = [...tr.querySelectorAll("button")];
    out.nRecibir = btns.filter((x) => /impRecibirCodigo/.test(x.getAttribute("onclick") || "")).length;
    out.nBaches = btns.filter((x) => /pedImpBachesDe/.test(x.getAttribute("onclick") || "")).length;
    const rb = btns.find((x) => /impRecibirCodigo/.test(x.getAttribute("onclick") || ""));
    rb.click(); await new Promise((res) => setTimeout(res, 100));
    const ov = () => document.getElementById("impRecOv");
    out.opciones = [...ov().querySelectorAll("button.irc-b.pri")].map((x) => x.textContent.trim());
    await impRecibirBache(134);
    impRecLinea(0, "modo", "u");
    impRecLinea(0, "uni", 3000);
    out.cajas = _impRec.lineas[0].cantidad;
    out.avisaDif = /no da cajas enteras/.test(ov().innerHTML) && /\+24 u/.test(ov().innerHTML);
    impRecSet("uxc", 100);
    out.cajas100 = _impRec.lineas[0].cantidad;
    out.sinDif100 = !/no da cajas enteras/.test(ov().innerHTML);
    impRecSet("uxc", 144);
    window.confirm = () => true;
    await impRecRevisar(); await impRecGrabar();
    const real = window.__calls.filter((c) => c.fn === "gv_imp_recibir" && c.body.p_simular === false)[0];
    out.mandado = real ? real.body.p_destinos.map((x) => x.destino + ":" + x.cantidad).join(",") + "|uxc" + real.body.p_uni_x_caja : null;
    // D (v24.83): un importado que es INSUMO (323ES suelto) entra en la unidad del insumo, sin UxB ni cajas
    CTX.uni_x_caja = null; CTX.insumos_cods = ["323ES"]; CTX.insumos_unidad = { "323ES": "Uni" };
    CTX.insumos_pos = [{ sector: "R01AD", insumos: "" }];
    await impRecibirBache(134);
    out.insDest = _impRec.lineas[0].destino;
    out.insCant = _impRec.lineas[0].cantidad;
    out.insSinUxb = !/Unidades por caja/.test(ov().innerHTML);
    out.insSinSelect = !ov().querySelector('select[title="Cargar en cajas o en unidades"]');
    out.insLabel = /unidades →/.test(ov().innerHTML);
    return out;
  }, ITEMS);
  await b.close();
  const fail = [];
  if (r.nRecibir !== 1) fail.push("A: botones 📥 = " + r.nRecibir);
  if (r.nBaches !== 1) fail.push("A: botones 📦 = " + r.nBaches);
  if (r.opciones.length !== 3 || !/323ES/.test(r.opciones[0]) || !/838E CH/.test(r.opciones.join("|"))) fail.push("B: selector " + JSON.stringify(r.opciones));
  if (r.cajas !== 21) fail.push("C: 3000 u / 144 = " + r.cajas);
  if (!r.avisaDif) fail.push("C: no avisa la diferencia");
  if (r.cajas100 !== 30 || !r.sinDif100) fail.push("C: con UxB 100 → " + r.cajas100);
  if (r.mandado !== "a_guardar:21|uxc144") fail.push("C: mandado " + r.mandado);
  if (r.insDest !== "insumos" || r.insCant !== 3000) fail.push("D: insumo arranca en " + r.insDest + ":" + r.insCant);
  if (!r.insSinUxb || !r.insSinSelect || !r.insLabel) fail.push("D: insumo con UxB/cajas " + JSON.stringify([r.insSinUxb, r.insSinSelect, r.insLabel]));
  if (errs.length) fail.push("pageerrors: " + errs.join(" | "));
  if (fail.length) { console.log("imp-recibir-codigo-unidades: ✗ " + fail.join(" · ")); process.exit(1); }
  console.log("imp-recibir-codigo-unidades: OK — 1 📥 por código, selector de pedidos, carga en unidades → cajas · insumo en su unidad");
})();
