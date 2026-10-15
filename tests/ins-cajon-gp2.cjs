/* v31.00 (Luis, 15/10) — Stock y Compras → Insumos → Sector Crudo / Sector Procesado muestran el CAJÓN DE GP2
   ("un cajon de batidores son 29.99kg y cada unidad son 0.098kg… quiero que se vea esa conversion en GV").
   Contrato: columnas Cód C · Kg/caj · Kg/uni · Uni/caj · Uni (≈ cajones × uni/caj) sólo en esas dos categorías;
   un insumo sin vínculo dice «sin vincular en GP2»; si la RPC falla dice «no se pudo leer GP2» (no «sin vincular»);
   otra categoría (Flejes) no muestra las columnas. Sólo se muestra: no se postea nada. Sin red (fetch mockeado). */
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
  const p = await b.newPage({ viewport: { width: 1200, height: 900 } });
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {}; let posts = 0; let rotaGp2 = false;
    const J = (d, ok) => Promise.resolve({ ok: ok !== false, status: ok === false ? 500 : 200, headers: { get: () => null }, json: () => Promise.resolve(d) });
    const CATS = [
      { clave: "partes_crudo", nombre: "Sector Crudo", emoji: "🔩", unidades: ["Cajones"], orden: 1 },
      { clave: "parte_procesado", nombre: "Sector Procesado", emoji: "⚙", unidades: ["Cajones"], orden: 2 },
      { clave: "fleje", nombre: "Flejes", emoji: "🧵", unidades: ["Kg"], orden: 3 }
    ];
    const CAT = [
      { cod: "Batidor Pera p/Cromar", nombre: "Batidor Pera p/Cromar", categoria: "partes_crudo", ubicacion: "IN-J1" },
      { cod: "Z26", nombre: "Pieza sin vincular", categoria: "partes_crudo", ubicacion: "IN-K1" },
      { cod: "A1", nombre: "Mgo Plano 501 Pint.", categoria: "parte_procesado", ubicacion: "IN-A1" },
      { cod: "22", nombre: "121 X 1,20", categoria: "fleje", ubicacion: "V2" }
    ];
    const SAL = [
      { cod_art: "Batidor Pera p/Cromar", unidad: "Cajones", saldo: 15 },
      { cod_art: "Z26", unidad: "Cajones", saldo: 2 },
      { cod_art: "A1", unidad: "Cajones", saldo: 14 },
      { cod_art: "22", unidad: "Kg", saldo: 100 }
    ];
    const CAJ = [
      { cod: "Batidor Pera p/Cromar", cod_c: "GRJ10", desc_c: "Batidor Pera", kg_x_uni: 0.098, uni_x_cajon: 306, kg_x_cajon: 29.99 },
      { cod: "A1", cod_c: "A1", desc_c: "Mgo Plano 501 Pint.", kg_x_uni: 0.0397, uni_x_cajon: 756, kg_x_cajon: 30.01 },
      { cod: "22", cod_c: "IA1", kg_x_uni: null, uni_x_cajon: null, kg_x_cajon: null }
    ];
    window.fetch = function (url, opt) {
      url = String(url);
      const m = String((opt && opt.method) || "GET").toUpperCase();
      if (url.indexOf("/rpc/gv_insumo_gp2_info") >= 0) return rotaGp2 ? J({ message: "x" }, false) : J(CAJ);
      if (url.indexOf("/rpc/") >= 0) return J([]);
      if (m === "POST") { posts++; return J({}); }
      if (url.indexOf("Insumos_Categorias") >= 0) return J(CATS);
      if (url.indexOf("Insumos_Unidades") >= 0) return J(["Cajones", "Kg", "Uni"].map((n, i) => ({ nombre: n, orden: i })));
      if (url.indexOf("vista_saldos_insumos_x_unidad") >= 0) return J(SAL);
      if (url.indexOf("vista_insumos") >= 0) return J(CAT);
      return J([]);
    };
    const ov = document.createElement("div");
    ov.innerHTML = '<div class="stk-tabs" id="stkTabs"></div><div class="stk-body" id="stkBody"></div>';
    document.body.appendChild(ov);
    _stk = { tab: "insumos", filtro: "", arts: [], soloConteo: false, insLoaded: true };
    await stkInsLoad();
    const fila = (cod) => {
      const tr = Array.from(document.querySelectorAll("#stkInsCatPopBody tbody tr")).find(t => (t.cells[0] || {}).textContent === cod);
      return tr ? Array.from(tr.cells).map(td => td.textContent.trim()) : null;
    };
    stkInsCatPopup("partes_crudo");
    const head = document.querySelector("#stkInsCatPopBody thead").textContent;
    out.headCajon = /Cajón según GP2/.test(head) && /Cód C/.test(head) && /Kg\/caj/.test(head) && /Kg\/uni/.test(head) && /Uni\/caj/.test(head);
    out.batidor = (fila("Batidor Pera p/Cromar") || []).join(" | ");
    out.sinVinc = (fila("Z26") || []).join(" | ");
    // v31.02 (pase GV-UI): el que falta es «—» y el motivo va en el title
    out.sinVincTitle = Array.from(document.querySelectorAll("#stkInsCatPopBody [title]")).some(e => e.title === "sin vincular en GP2");
    stkInsCatPopup("parte_procesado");
    out.a1 = (fila("A1") || []).join(" | ");
    stkInsCatPopup("fleje");
    out.flejeSinCajon = !/Cajón según GP2/.test(document.querySelector("#stkInsCatPopBody thead").textContent);
    rotaGp2 = true; await stkInsRefresh(); stkInsCatPopup("partes_crudo");
    out.rota = (fila("Batidor Pera p/Cromar") || []).join(" | ");
    out.posts = posts;
    return out;
  });
  const pass = r.headCajon === true &&
    /GRJ10 \| 29,99 \| 0,098 \| 306 \| ≈ 4\.590/.test(r.batidor) &&
    /Z26 \| — \| Pieza sin vincular \| — \|/.test(r.sinVinc) && r.sinVincTitle === true &&
    /A1 \| 30,01 \| 0,0397 \| 756 \| ≈ 10\.584/.test(r.a1) &&
    r.flejeSinCajon === true && /no se pudo leer GP2/.test(r.rota) && !/sin vincular/.test(r.rota) &&
    r.posts === 0 && errs.length === 0;
  console.log("ins-cajon-gp2:", JSON.stringify(r));
  console.log("  pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
