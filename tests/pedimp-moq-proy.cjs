/* v23.90 (Luis, 29/09) — tres cosas del módulo Pedidos Importación, corriendo la pantalla:

   (A) el CÓDIGO abre el mismo pop-up de proyección que la pantalla de Stocks
       (`stkShowProyVentas`), y desde ahí se puede VOLVER al pedido — que es lo que
       `stkPopClose()` no hace: cierra todo.
   (B) el MOQ del proveedor (GV_Imp_Proveedor, default 1.000 u) marca por artículo:
       entra con el objetivo → sin chip · entra estirando hasta el tope (12 meses) → 🟡 ·
       ni con el tope → 🔴 · sin proyección → «MOQ ?» (no se inventa una cobertura).
       ⚠ El MOQ NO está escrito en index.html: sale de la vista. El test lo prueba
       sirviendo un MOQ distinto y viendo que la pantalla lo respeta.
   (C) el desglose de «Puesto en Arg» es de DOS columnas y la fórmula de cada concepto
       se abre al tocarlo (antes era una tercera columna con todas las cuentas a la vez).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };

// Kangli con MOQ 2.000 y tope 12; Frontier hereda 1.000 (así se ve que el número sale de acá).
const CFG_PROV = [
  { proveedor: "Frontier", importador: "Chef", usa_ntl: true, ntl_pct: 0.05, derechos_pct: 0.18,
    meses_objetivo: 10, min_usd: 25000, valor_m3: 110, moq: 1000, moq_meses_max: 12, activo: true, orden: 1,
    ntl_pct_propio: null, derechos_pct_propio: null, meses_objetivo_propio: null, min_usd_propio: null,
    valor_m3_propio: null, moq_propio: null, moq_meses_max_propio: null, codigos: 4 },
  { proveedor: "Kangli", importador: "Chef", usa_ntl: true, ntl_pct: 0.05, derechos_pct: 0.18,
    meses_objetivo: 10, min_usd: 25000, valor_m3: 110, moq: 2000, moq_meses_max: 12, activo: true, orden: 2,
    ntl_pct_propio: null, derechos_pct_propio: null, meses_objetivo_propio: null, min_usd_propio: null,
    valor_m3_propio: null, moq_propio: 2000, moq_meses_max_propio: null, codigos: 1 }
];
const CFG_NAC = [{ meses_objetivo: 10, derechos_pct: 0.18, ntl_pct: 0.05, iva_pct: 0.21, iva_adic_pct: 0.20,
  gcias_pct: 0.06, iibb_pct: 0.0017, estad_pct: 0.03, estad_fob_desde: 6000, estad_fob_hasta: 10000,
  estad_fijo: 180, valor_m3: 110, flete_full: 2000, min_usd: 25000, moq: 1000, moq_meses_max: 12 }];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 950 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", async (r) => {
    const u = r.request().url();
    let body = "[]";
    if (/gv_imp_proveedor_cfg/.test(u)) body = JSON.stringify(CFG_PROV);
    else if (/gv_imp_nac_config/.test(u)) body = JSON.stringify(CFG_NAC);
    else if (/\/rpc\//.test(u)) body = "[]";
    await r.fulfill({ status: 200, contentType: "application/json", body });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  await p.evaluate(() => _impCfgCargar());

  /* mc × uniMaster son las unidades del pedido; proyUni y stockUni deciden con cuántos
     meses de cobertura se llegaría al MOQ: (MOQ + stock + en curso) / proyección. */
  const it = (cod, prov, o) => {
    const base = Object.assign({
      cod, prov, key: cod, desc: cod, proyUni: 100, objetivoUni: 1000, stockUni: 0, enCurso: 0,
      meses: 10, aPedirUni: 500, uniMaster: 100, uxc: 10, fobUni: 1, m3Master: 0.05,
      det: [{ id: 1, curso: 0, marca: "" }]
    }, o || {});
    // las master cajas tienen que dar las unidades que dice el caso: uni = MC × uni/master
    base.aPedirCajas = Math.ceil(base.aPedirUni / base.uniMaster);
    return base;
  };

  const items = [
    // 1.500 u pedidas contra MOQ 1.000 → entra, sin chip
    it("111", "Frontier", { uniMaster: 500, aPedirUni: 1500, proyUni: 200 }),
    // 500 u contra MOQ 1.000, proy 100/mes → (1000+0+0)/100 = 10 meses ≤ 12 → 🟡
    it("222", "Frontier", { uniMaster: 250, aPedirUni: 500, proyUni: 100 }),
    // 500 u contra MOQ 1.000, proy 50/mes → 20 meses > 12 → 🔴
    it("333", "Frontier", { uniMaster: 250, aPedirUni: 500, proyUni: 50 }),
    // sin proyección: no se puede calcular cobertura
    it("444", "Frontier", { uniMaster: 250, aPedirUni: 500, proyUni: 0 }),
    // Kangli tiene MOQ 2.000 propio: 1.500 u ya NO alcanzan (con el de Frontier sí alcanzarían)
    it("555", "Kangli", { uniMaster: 500, aPedirUni: 1500, proyUni: 300 })
  ];
  const pintar = () => p.evaluate((its) => {
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items: its, meses: 10, minUsd: 25000, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: false, mcOverride: {} };
    _pedImpRender();
    const out = {};
    [...document.querySelectorAll(".mva-tbl.wide tbody tr")].forEach((tr) => {
      out[tr.cells[0].textContent.trim()] = tr.textContent;
    });
    return out;
  }, items);

  const filas = await pintar();
  if (/MOQ/.test(filas["111"] || "")) fail("(B) 1.500 u contra MOQ 1.000 no debía marcar nada: " + filas["111"]);
  if (!/🟡 MOQ 10m/.test(filas["222"] || "")) fail("(B) esperaba «🟡 MOQ 10m» (llega estirando a 10 meses) y dio: " + filas["222"]);
  if (!/🔴 MOQ/.test(filas["333"] || "")) fail("(B) con 20 meses necesarios tenía que salir 🔴 y dio: " + filas["333"]);
  if (!/MOQ \?/.test(filas["444"] || "")) fail("(B) sin proyección tenía que decir «MOQ ?» y dio: " + filas["444"]);
  if (!/🔴 MOQ|🟡 MOQ/.test(filas["555"] || "")) fail("(B) el MOQ propio de Kangli (2.000) no se aplicó: " + filas["555"]);

  // el MOQ sale de la VISTA, no del archivo: con otro MOQ, otro resultado
  await p.evaluate(() => { _impCfgProv["Frontier"].moq = 100; });
  const filas2 = await pintar();
  if (/MOQ/.test(filas2["222"] || "")) fail("(B) bajando el MOQ a 100 la fila no tenía que marcar nada: " + filas2["222"]);
  await p.evaluate(() => { _impCfgProv["Frontier"].moq = 1000; });

  // ── (A) la CELDA de la proyección abre el pop-up y se puede volver ────────────────
  //    v23.91 (Luis): el que se toca es el número de la proyección, no el código.
  await pintar();
  const cel = await p.evaluate(() => {
    const tr = document.querySelector(".mva-tbl.wide tbody tr");
    if (!tr) return { proy: "(sin fila)", cod: "" };
    return {
      proy: (tr.cells[2] && tr.cells[2].getAttribute("onclick")) || "(sin onclick)",
      cod: (tr.cells[0] && tr.cells[0].innerHTML) || ""
    };
  });
  if (!/pedImpProyAbrir\(/.test(cel.proy)) fail("(A) la celda de la proyección no abre el pop-up: " + cel.proy);
  if (/pedImpProyAbrir\(/.test(cel.cod)) fail("(A) el código volvió a ser clickeable: " + cel.cod);
  await p.evaluate(() => pedImpProyAbrir(encodeURIComponent("111"), 12.5));
  const proy = await p.evaluate(() => ({
    titulo: (document.querySelector("#stkPopModal .stkpop-title") || {}).textContent || "",
    volver: [...document.querySelectorAll("#stkPopModal .stkpop-head button")].map(x => x.textContent.trim())
  }));
  if (!/Proyección/.test(proy.titulo)) fail("(A) no se abrió el pop-up de proyección: " + proy.titulo);
  if (!proy.volver.some(t => /Volver al pedido/.test(t))) fail("(A) falta el «← Volver al pedido»: " + proy.volver.join(" | "));
  await p.evaluate(() => [...document.querySelectorAll("#stkPopModal .stkpop-head button")].find(x => /Volver al pedido/.test(x.textContent)).click());
  const volvio = await p.evaluate(() => ({
    titulo: (document.querySelector("#stkPopModal .stkpop-title") || {}).textContent || "",
    filas: document.querySelectorAll(".mva-tbl.wide tbody tr").length
  }));
  if (!/Pedidos Importación/.test(volvio.titulo) || volvio.filas !== items.length)
    fail("(A) al volver no se redibujó el pedido: " + JSON.stringify(volvio));

  // ── (C) el desglose es de DOS columnas y la fórmula se abre al tocar ──────────────
  const desg = await p.evaluate(() => {
    const nac = _pedImpNacionalizar(9475, 12.33, { modo: "consolidada", valorM3: 110, tn: 0, ntl: true, derechos: 0.35 });
    const d = document.createElement("div");
    d.innerHTML = _pedImpDesgDer(nac, 9475, 12.33);
    const tb = d.querySelector("table");
    const cols = [...tb.querySelectorAll("tbody tr")].map(tr => tr.cells.length);
    const det = [...tb.querySelectorAll("details")];
    return { maxCols: Math.max.apply(null, cols), detalles: det.length,
             primero: det.length ? det[0].querySelector("summary").textContent.trim() : "",
             cuerpo: det.length ? det[0].textContent.replace(det[0].querySelector("summary").textContent, "").trim() : "" };
  });
  if (desg.maxCols > 2) fail("(C) el desglose sigue teniendo " + desg.maxCols + " columnas");
  if (desg.detalles < 5) fail("(C) esperaba un desplegable por concepto y hay " + desg.detalles);
  if (!desg.cuerpo) fail("(C) el desplegable no trae la fórmula adentro");

  // ── (D) los DERECHOS bajan en cascada artículo → proveedor → general, y el embarque
  //        usa el promedio ponderado por FOB (Luis, 29/09: "derechos debería ser editable
  //        por artículo") ──────────────────────────────────────────────────────────────
  const der = await p.evaluate(() => {
    const out = {};
    out.sinPropio = _derechosArt("111", "Frontier");          // hereda el 18% del proveedor
    _impCfgArt["111"] = { derechos_pct: 0.35, prov: "Frontier" };
    out.conPropio = _derechosArt("111", "Frontier");          // ahora manda el del artículo
    // mitad y mitad por FOB: 35% y 18% → 26,5%
    const items = [{ cod: "111", prov: "Frontier", usdTotal: 1000, aPedirCajas: 1, uniMaster: 1, fobUni: 1000, aPedirUni: 1000 },
                   { cod: "222", prov: "Frontier", usdTotal: 1000, aPedirCajas: 1, uniMaster: 1, fobUni: 1000, aPedirUni: 1000 }];
    _stkPop = { kind: "pedImp", data: { items: items, meses: 10, minUsd: 25000, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: false, mcOverride: {} };
    out.pedido = _derechosPedido(items, "Frontier");
    delete _impCfgArt["111"];
    out.vuelve = _derechosArt("111", "Frontier");
    return out;
  });
  if (Math.abs(der.sinPropio - 0.18) > 1e-9) fail("(D) sin % propio tenía que heredar el del proveedor y dio " + der.sinPropio);
  if (Math.abs(der.conPropio - 0.35) > 1e-9) fail("(D) el % del artículo tiene que ganarle al del proveedor y dio " + der.conPropio);
  if (Math.abs(der.pedido - 0.265) > 1e-6) fail("(D) el embarque tiene que ponderar por FOB (35% y 18% → 26,5%) y dio " + der.pedido);
  if (Math.abs(der.vuelve - 0.18) > 1e-9) fail("(D) al sacarle el % propio tenía que volver al del proveedor y dio " + der.vuelve);

  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("pedimp-moq-proy: OK — celda de proyección (y vuelve) · MOQ 🟡/🔴/? desde la vista · desglose en 2 columnas · derechos por artículo, ponderados por FOB");
})();
