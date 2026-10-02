/* v24.42 — Pedidos Importación, corriendo la pantalla:
   (A) cada proveedor se ordena por PRIORIDAD: menos meses de stock (stock ÷ proy/mes) primero,
       sin proyección al final.
   (B) columna «Meses stock» con el número; < 4 meses va en rojo con ⚠, y el proveedor lleva el
       badge «⚠ N con < 4 meses» (también la ficha del filtro).
   (C) «📄 PDF para Damián»: columnas Código · Descripción · Foto · Stock · Máximo (meses arriba) ·
       Pedido (MC) · FOB (total arriba) · m³ (total arriba) + el resumen de cómo se compone.
   (E) v25.3 (Thomas): la hoja va VERTICAL (A4 portrait) y lleva la columna Marca (LK / CH / Loke)
       en las 3 hojas, en lugar de la chapa de planta pegada al código.
   (F) v25.13 (Thomas): agrupado por tipo de producto + «INAL» debajo del código.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 950 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => {
    const u = decodeURIComponent(r.request().url());
    // v24.55 — la hoja «Discontinuos» lee Importados.activo = false del proveedor
    if (/gv_importados_ordenes/.test(u) && /activo=eq\.false/.test(u) && /proveedor=eq\.Zeta/.test(u))
      return r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify([{ cod_art: "ZZ9", marca: "LK", descripcion: "Viejo", stock_total: 12 }]) });
    return r.fulfill({ status: 200, contentType: "application/json", body: "[]" });
  });
  await p.route("**/storage/v1/**", (r) => r.fulfill({ status: 404, body: "" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const it = (cod, prov, o) => {
    const x = Object.assign({ cod, prov, key: cod, desc: "Art " + cod, proyUni: 100, objetivoUni: 1000, stockUni: 0, enCurso: 0,
      meses: 10, aPedirUni: 500, uniMaster: 100, uxc: 10, fobUni: 1, m3Master: 0.05, det: [{ id: 1, curso: 0, marca: "" }] }, o || {});
    x.aPedirCajas = Math.ceil(x.aPedirUni / x.uniMaster); return x;
  };
  const items = [
    it("AAA", "Frontier", { stockUni: 900, aPedirUni: 100 }),   // 9 meses
    it("FFF", "Frontier", { stockUni: 100, enCurso: 500, reingresoEst: "2026-11-18", aPedirUni: 400 }),   // 1 mes de stock, 6 con lo en camino
    it("GGG", "Frontier", { stockUni: 1500, aPedirUni: 100, esParte: true }),   // insumo: 15 meses, va sin foto
    it("BBB", "Frontier", { stockUni: 250, aPedirUni: 800 }),   // 2,5 meses → alerta
    it("CCC", "Frontier", { stockUni: 50, proyUni: 0, aPedirUni: 300 }),   // sin proyección
    it("DDD", "Frontier", { stockUni: 350, aPedirUni: 700 }),   // 3,5 meses → alerta
    it("EEE", "Kangli", { stockUni: 600, aPedirUni: 400 })      // 6 meses
  ];
  const r = await p.evaluate(async (its) => {
    _NAC_TASAS.moq = 0;   // v24.55 — el MOQ (80 %) se prueba aparte, abajo: acá no toca las cantidades
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items: its, meses: 10, minUsd: 25000, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: false, mcOverride: {} };
    _pedImpRender();
    const trs = [...document.querySelectorAll(".mva-tbl.wide tbody tr")];
    const filas = trs.map((tr) => ({ cod: tr.cells[0].textContent.trim().split(" ")[0], meses: tr.cells[4].textContent.trim(), rojo: /b91c1c/.test(tr.cells[4].getAttribute("style") || "") }));
    const trF = trs.find((tr) => tr.cells[0].textContent.trim() === "FFF"); const camino = trF ? trF.cells[5].textContent.replace(/\s+/g, " ").trim() : "";
    const ths = [...document.querySelectorAll(".mva-tbl.wide")][0].querySelectorAll("thead th");
    const badges = [...document.querySelectorAll(".pedimp-alerta")].map((x) => x.textContent.trim() + " " + x.title);
    let html = ""; window._pedImpPrintConFotos = (h) => { html = h; };
    await pedImpPdfDamian(encodeURIComponent("Frontier"));
    const d = document.createElement("div"); d.innerHTML = html.replace(/^[\s\S]*<body>/, "").replace(/<\/body>[\s\S]*$/, "");
    const h1 = d.querySelector(".hoja");
    const trs0 = h1.querySelectorAll("thead tr");
    const top = [...trs0[0].children].map((x) => x.textContent.trim());
    const pdfTh = [...trs0[1].children].map((x) => x.textContent.trim());
    const pdfCods = [...h1.querySelectorAll("tbody tr")].map((tr) => tr.cells[0].textContent.trim());
    // v26.34 — la celda «Llegan» de FFF (500 u en camino × u$s 1) lleva el FOB abajo
    const trFFF = [...h1.querySelectorAll("tbody tr")].find((tr) => tr.cells[0].textContent.trim() === "FFF");
    const llegaFFF = trFFF ? [...trFFF.cells[6].querySelectorAll("small")].map((x) => x.className + ":" + x.textContent).join("|") : "";
    return { filas, camino, th4: ths[4].textContent.trim(), badges, top, pdfTh, pdfCods, llegaFFF, hojas: d.querySelectorAll(".hoja").length, txt: d.textContent,
      imgs: h1.querySelectorAll("tbody img").length, insumoFoto: ([...h1.querySelectorAll("tbody tr")].find((tr) => tr.cells[0].textContent.trim() === "GGG") || { cells: [0,0,0,{ textContent: "" }] }).cells[3].textContent };
  }, items);
  const cods = r.filas.map((f) => f.cod).join(",");
  if (cods !== "BBB,DDD,FFF,AAA,GGG,CCC,EEE") fail("(A) orden por prioridad (stock + en camino): esperaba BBB,DDD,FFF,AAA,GGG,CCC,EEE y dio " + cods);
  const fff = r.filas.find((x) => x.cod === "FFF");
  if (!fff || !/6,0/.test(fff.meses) || fff.rojo) fail("(A) FFF suma lo en camino: (100+500)/100 = 6,0 sin alerta: " + JSON.stringify(fff));
  if (!/500 18\/11/.test(r.camino)) fail("(A) la columna En camino muestra unidades y dd/mm: " + r.camino);
  if (!/Meses/.test(r.th4)) fail("(B) la 5.ª columna tiene que ser Meses stock: " + r.th4);
  const f = Object.fromEntries(r.filas.map((x) => [x.cod, x]));
  if (!/2,5/.test(f.BBB.meses) || !f.BBB.rojo || !/⚠/.test(f.BBB.meses)) fail("(B) BBB 2,5 meses en rojo con ⚠: " + JSON.stringify(f.BBB));
  if (!/9,0/.test(f.AAA.meses) || f.AAA.rojo) fail("(B) AAA 9,0 sin rojo: " + JSON.stringify(f.AAA));
  if (f.CCC.meses !== "—") fail("(B) sin proyección va —: " + f.CCC.meses);
  if (!r.badges.some((x) => /^⚠2 2 con < 4 meses/.test(x))) fail("(B) badge ⚠ 2 con < 4 meses en Frontier: " + JSON.stringify(r.badges));
  if (r.badges.some((x) => /⚠1 /.test(x))) fail("(B) Kangli no tiene alerta: " + JSON.stringify(r.badges));
  // v24.55 (Thomas) — hoja 1: título + totales en su propia fila; columnas compactas y 2 separadores finitos.
  const exp = ["Cód", "Mca", "Descripción", "Foto", "", "Stock", "Llegan", "Máx", "FOB", "m³"];   // v26.31: «Mca» (rótulo abreviado)
  exp.forEach((h, i) => { if (!(r.pdfTh[i] || "").startsWith(h) || (h === "" && r.pdfTh[i] !== "")) fail("(C) columna " + (i + 1) + " del PDF tiene que ser «" + h + "»: " + r.pdfTh[i]); });
  if (!/^Pedido Frontier \d{2}\/(ene|feb|mar|abr|may|jun|jul|ago|sep|oct|nov|dic)$/.test(r.top[0])) fail("(C) título «Pedido <prov> dd/mmm»: " + r.top[0]);
  // v26.34 (Luis) — arriba de «Llegan» va el FOB de lo que viene (500 u × u$s 1), para compararlo con el del pedido
  if (r.top[1] !== "500") fail("(C) arriba de Llegan, el FOB u$s de lo que viene (500): " + r.top[1]);
  if (!/FOB u\$s/.test(r.pdfTh[6] || "")) fail("(C) el rótulo de Llegan dice FOB u$s: " + r.pdfTh[6]);
  if (r.llegaFFF !== "fobl:500") fail("(C) la celda Llegan de FFF lleva su FOB abajo (fobl:500): " + r.llegaFFF);
  if (r.top[2] !== "10 m") fail("(C) los meses del máximo van arriba de Máx: " + r.top[2]);
  if (!/^Pedido/.test(r.top[3]) || r.top[4] !== "") fail("(C) Pedido (2 filas) y el separador: " + r.top.join(" | "));
  if (r.top[5] !== "2.400") fail("(C) FOB lleva el total arriba (2.400): " + r.top[5]);
  if (r.top[6] !== "1,2") fail("(C) m³ lleva el total arriba con 1 decimal (1,2): " + r.top[6]);
  if (/Cómo se compone|Para Damián|master cajas/.test(r.txt)) fail("(C) sin textos de explicación ni MC en el PDF");
  if (r.pdfCods.join(",") !== "BBB,DDD,FFF,AAA,GGG,CCC") fail("(C) PDF por prioridad y sólo Frontier: " + r.pdfCods.join(","));
  if (r.imgs !== 5 || !/insumo/.test(r.insumoFoto)) fail("(C) una foto por artículo: " + r.imgs);
  // (D) v24.55 — regla del 80 % del MOQ: se estira hasta el 80 % dentro del tope de meses; si no alcanza, no se pide
  //     y va a la hoja «Sin pedir». Y la hoja «Discontinuos» sale de Importados.activo = false.
  const r2 = await p.evaluate(async () => {
    _NAC_TASAS.moq = 1000; _NAC_TASAS.moq_pct = 0.8; _NAC_TASAS.moq_meses_max = 12;
    const mk = (cod, o) => Object.assign({ cod, prov: "Zeta", key: cod, desc: "Art " + cod, proyUni: 100, objetivoUni: 1000, stockUni: 0, enCurso: 0, meses: 10,
      aPedirUni: 500, uniMaster: 100, aPedirCajas: 5, uxc: 10, fobUni: 1, m3Master: 0.05, det: [{ id: 1, curso: 0, marca: "" }] }, o || {});
    const its = [mk("HHH"), mk("III", { proyUni: 10, aPedirUni: 200, aPedirCajas: 2 }), mk("JJJ", { aPedirUni: 900, aPedirCajas: 9 })];
    _stkPop = { kind: "pedImp", data: { items: its, meses: 10, minUsd: 25000, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: false, mcOverride: {} };
    const mc = its.map((x) => _pedImpMcOf(x));
    let html = ""; window._pedImpPrintConFotos = (h) => { html = h; };
    await pedImpPdfDamian(encodeURIComponent("Zeta"));
    const d = document.createElement("div"); d.innerHTML = html.replace(/^[\s\S]*<body>/, "").replace(/<\/body>[\s\S]*$/, "");
    const hj = [...d.querySelectorAll(".hoja")].map((h) => h.textContent);
    return { mc, hj };
  });
  if (r2.mc.join(",") !== "8,0,9") fail("(D) MOQ: HHH sube a 8 MC (80 %), III no se pide, JJJ queda en 9: " + r2.mc.join(","));
  if (r2.hj.length !== 3) fail("(D) tienen que ser 3 hojas (pedido · sin pedir · discontinuos): " + r2.hj.length);
  if (!/Sin pedir Zeta/.test(r2.hj[1] || "") || !/III/.test(r2.hj[1] || "") || !/< 80% MOQ/.test(r2.hj[1] || "")) fail("(D) hoja 2 con III y su motivo: " + r2.hj[1]);
  if (!/Discontinuos Zeta/.test(r2.hj[2] || "") || !/ZZ9/.test(r2.hj[2] || "")) fail("(D) hoja 3 con los discontinuos del proveedor: " + r2.hj[2]);
  if (!/↑ 80% MOQ/.test(r2.hj[0] || "")) fail("(D) el aviso del MOQ al lado del renglón estirado: " + r2.hj[0]);
  // (E) v25.3 (Thomas) — hoja vertical y columna Marca con el dato del maestro (LK / CH / Loke).
  const r3 = await p.evaluate(async () => {
    _NAC_TASAS.moq = 0;
    const mk = (cod, o) => Object.assign({ cod, prov: "Zeta", key: cod, desc: "Art " + cod, proyUni: 100, objetivoUni: 1000, stockUni: 0, enCurso: 0, meses: 10,
      aPedirUni: 500, uniMaster: 100, aPedirCajas: 5, uxc: 10, fobUni: 1, m3Master: 0.05, det: [{ id: 1, curso: 0, marca: "LK" }] }, o || {});
    const its = [mk("KKK", { det: [{ id: 2, marca: "Loke" }] }), mk("809E", { key: "809E|CH", planta: "CH", det: [{ id: 3, marca: "CH" }] }),
      mk("LLL", { det: [{ id: 4, marca: "" }] }), mk("MMM", { aPedirUni: 0, aPedirCajas: 0, stockUni: 5000, det: [{ id: 5, marca: "Loke" }] })];
    _stkPop = { kind: "pedImp", data: { items: its, meses: 10, minUsd: 25000, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: false, mcOverride: {} };
    let html = ""; window._pedImpPrintConFotos = (h) => { html = h; };
    await pedImpPdfDamian(encodeURIComponent("Zeta"));
    const d = document.createElement("div"); d.innerHTML = html.replace(/^[\s\S]*<body>/, "").replace(/<\/body>[\s\S]*$/, "");
    const filas = [...d.querySelectorAll(".hoja")].map((h) => [...h.querySelectorAll("tbody tr")].map((tr) => tr.cells[0].textContent.trim() + ":" + tr.cells[1].textContent.trim()));
    return { css: (/<style>([\s\S]*?)<\/style>/.exec(html) || [])[1] || "", filas };
  });
  if (!/@page\{size:A4 portrait/.test(r3.css) || /landscape/.test(r3.css)) fail("(E) el PDF para Damián va en A4 VERTICAL: " + (r3.css.match(/@page\{[^}]*\}/) || [""])[0]);
  const f0 = (r3.filas[0] || []).join(",");
  if (!/KKK:Loke/.test(f0) || !/809E:CH/.test(f0) || !/LLL:—/.test(f0)) fail("(E) columna Marca en el pedido (Loke / CH / — sin dato; el código sin chapa): " + f0);
  if (!/MMM:Loke/.test((r3.filas[1] || []).join(","))) fail("(E) columna Marca en «Sin pedir»: " + (r3.filas[1] || []).join(","));
  if (!/ZZ9:LK/.test((r3.filas[2] || []).join(","))) fail("(E) columna Marca en «Discontinuos»: " + (r3.filas[2] || []).join(","));
  // (F) v25.13 (Thomas) — agrupado por TIPO DE PRODUCTO (GV_Producto_Tipo): las marcas del mismo producto
  //     van juntas (LK · CH · Loke), el grupo va donde cae su artículo más urgente, raya gruesa al
  //     empezar cada grupo; y «INAL» debajo del código del que tiene certificado.
  const r4 = await p.evaluate(async () => {
    _NAC_TASAS.moq = 0;
    const mk = (cod, marca, stock) => ({ cod, prov: "Zeta", key: cod, desc: "Art " + cod, proyUni: 100, objetivoUni: 1000, stockUni: stock, enCurso: 0, meses: 10,
      aPedirUni: 500, uniMaster: 100, aPedirCajas: 5, uxc: 10, fobUni: 1, m3Master: 0.05, det: [{ id: 1, curso: 0, marca: marca, cod: cod }] });
    const its = [mk("AAA", "LK", 100), mk("BBB", "Loke", 900), mk("CCC", "CH", 500), mk("DDD", "LK", 300), mk("EEE", "LK", 200), mk("FFF", "CH", 800)];
    _impExtra = { "AAA|LK": { tipo_producto: "Colador Ø 8 cm", inal: true, inal_certificado: "CE-1" }, "BBB|LOKE": { tipo_producto: "Colador Ø 8 cm" },
      "CCC|CH": { tipo_producto: "Colador Ø 8 cm" }, "EEE|LK": { tipo_producto: "Rallador Mini" }, "FFF|CH": { tipo_producto: "Rallador Mini" } };
    _impExtraOk = true;
    _stkPop = { kind: "pedImp", data: { items: its, meses: 10, minUsd: 25000, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: false, mcOverride: {} };
    let html = ""; window._pedImpPrintConFotos = (h) => { html = h; };
    await pedImpPdfDamian(encodeURIComponent("Zeta"));
    const d = document.createElement("div"); d.innerHTML = html.replace(/^[\s\S]*<body>/, "").replace(/<\/body>[\s\S]*$/, "");
    const trs = [...d.querySelector(".hoja").querySelectorAll("tbody tr")];
    const fob = _pedImpNacionalizar(3000, 1, { modo: "consolidada", fobInal: _impFobInal(its, _pedImpUsdOf) }).detalle.filter((x) => /^Autorización/.test(x[0]))[0];
    _impExtra = {}; _impExtraOk = false;
    return { cods: trs.map((tr) => tr.cells[0].querySelector("b").firstChild.textContent.trim()), g1: trs.filter((tr) => tr.classList.contains("g1")).map((tr) => tr.cells[0].querySelector("b").firstChild.textContent.trim()),
      inal: trs.filter((tr) => /INAL/.test(tr.cells[0].textContent)).map((tr) => tr.cells[0].querySelector("b").firstChild.textContent.trim()),
      css: /tr\.g1>td\{border-top:2px/.test(html), autInal: fob ? fob[2] : "" };
  });
  if (r4.cods.join(",") !== "AAA,CCC,BBB,EEE,FFF,DDD") fail("(F) agrupado por tipo (LK·CH·Loke, el grupo donde cae el más urgente): " + r4.cods.join(","));
  if (r4.g1.join(",") !== "AAA,EEE,DDD") fail("(F) raya gruesa al empezar cada grupo: " + r4.g1.join(","));
  if (!r4.css) fail("(F) falta el estilo tr.g1 (raya gruesa de grupo)");
  if (r4.inal.join(",") !== "AAA") fail("(F) «INAL» sólo en el que tiene certificado: " + r4.inal.join(","));
  if (!/FOB con INAL 500\b/.test(r4.autInal)) fail("(F) la Autorización de Impo va sobre el FOB con INAL (500): " + r4.autInal);
  if (errs.length) fail("errores JS: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("✓ pedimp-prioridad-damian: orden por meses de stock, alerta < 4 y PDF para Damián");
})();
