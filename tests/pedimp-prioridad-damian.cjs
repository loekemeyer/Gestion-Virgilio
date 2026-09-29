/* v24.42 — Pedidos Importación, corriendo la pantalla:
   (A) cada proveedor se ordena por PRIORIDAD: menos meses de stock (stock ÷ proy/mes) primero,
       sin proyección al final.
   (B) columna «Meses stock» con el número; < 4 meses va en rojo con ⚠, y el proveedor lleva el
       badge «⚠ N con < 4 meses» (también la ficha del filtro).
   (C) «📄 PDF para Damián»: columnas Código · Descripción · Foto · Stock · Máximo (meses arriba) ·
       Pedido (MC) · FOB (total arriba) · m³ (total arriba) + el resumen de cómo se compone.
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
  await p.route("**/rest/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
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
    it("BBB", "Frontier", { stockUni: 250, aPedirUni: 800 }),   // 2,5 meses → alerta
    it("CCC", "Frontier", { stockUni: 50, proyUni: 0, aPedirUni: 300 }),   // sin proyección
    it("DDD", "Frontier", { stockUni: 350, aPedirUni: 700 }),   // 3,5 meses → alerta
    it("EEE", "Kangli", { stockUni: 600, aPedirUni: 400 })      // 6 meses
  ];
  const r = await p.evaluate((its) => {
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items: its, meses: 10, minUsd: 25000, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: false, mcOverride: {} };
    _pedImpRender();
    const trs = [...document.querySelectorAll(".mva-tbl.wide tbody tr")];
    const filas = trs.map((tr) => ({ cod: tr.cells[0].textContent.trim(), meses: tr.cells[4].textContent.trim(), rojo: /b91c1c/.test(tr.cells[4].getAttribute("style") || "") }));
    const trF = trs.find((tr) => tr.cells[0].textContent.trim() === "FFF"); const camino = trF ? trF.cells[5].textContent.replace(/\s+/g, " ").trim() : "";
    const ths = [...document.querySelectorAll(".mva-tbl.wide")][0].querySelectorAll("thead th");
    const badges = [...document.querySelectorAll(".pedimp-alerta")].map((x) => x.textContent.trim());
    let html = ""; window._pedImpPrintConFotos = (h) => { html = h; };
    pedImpPdfDamian(encodeURIComponent("Frontier"));
    const d = document.createElement("div"); d.innerHTML = html.replace(/^[\s\S]*<body>/, "").replace(/<\/body>[\s\S]*$/, "");
    const pdfTh = [...d.querySelectorAll("thead th")].map((x) => x.textContent.trim());
    const pdfCods = [...d.querySelectorAll("tbody tr")].map((tr) => tr.cells[0].textContent.trim());
    return { filas, camino, th4: ths[4].textContent.trim(), badges, pdfTh, pdfCods, res: (d.querySelector(".res") || {}).textContent || "", imgs: d.querySelectorAll("tbody img").length };
  }, items);
  const cods = r.filas.map((f) => f.cod).join(",");
  if (cods !== "BBB,DDD,FFF,AAA,CCC,EEE") fail("(A) orden por prioridad (stock + en camino): esperaba BBB,DDD,FFF,AAA,CCC,EEE y dio " + cods);
  const fff = r.filas.find((x) => x.cod === "FFF");
  if (!fff || !/6,0/.test(fff.meses) || fff.rojo) fail("(A) FFF suma lo en camino: (100+500)/100 = 6,0 sin alerta: " + JSON.stringify(fff));
  if (!/500 18\/11/.test(r.camino)) fail("(A) la columna En camino muestra unidades y dd/mm: " + r.camino);
  if (!/Meses/.test(r.th4)) fail("(B) la 5.ª columna tiene que ser Meses stock: " + r.th4);
  const f = Object.fromEntries(r.filas.map((x) => [x.cod, x]));
  if (!/2,5/.test(f.BBB.meses) || !f.BBB.rojo || !/⚠/.test(f.BBB.meses)) fail("(B) BBB 2,5 meses en rojo con ⚠: " + JSON.stringify(f.BBB));
  if (!/9,0/.test(f.AAA.meses) || f.AAA.rojo) fail("(B) AAA 9,0 sin rojo: " + JSON.stringify(f.AAA));
  if (f.CCC.meses !== "—") fail("(B) sin proyección va —: " + f.CCC.meses);
  if (!r.badges.some((x) => /2 con < 4 meses/.test(x))) fail("(B) badge ⚠ 2 con < 4 meses en Frontier: " + JSON.stringify(r.badges));
  if (r.badges.some((x) => /1 con/.test(x))) fail("(B) Kangli no tiene alerta: " + JSON.stringify(r.badges));
  const exp = ["Código", "Descripción", "Foto", "Stock", "En camino", "Máximo", "Pedido", "FOB", "m³"];
  exp.forEach((h, i) => { if (!(r.pdfTh[i] || "").startsWith(h)) fail("(C) columna " + (i + 1) + " del PDF tiene que ser " + h + ": " + r.pdfTh[i]); });
  if (!/10 meses/.test(r.pdfTh[5])) fail("(C) Máximo lleva los meses arriba: " + r.pdfTh[5]);
  if (!/total u\$s 2\.300/.test(r.pdfTh[7])) fail("(C) FOB lleva el total arriba (2.300): " + r.pdfTh[7]);
  if (!/total 1,15/.test(r.pdfTh[8])) fail("(C) m³ lleva el total arriba (23 MC × 0,05 = 1,15): " + r.pdfTh[8]);
  if (r.pdfCods.join(",") !== "BBB,DDD,FFF,AAA,CCC") fail("(C) PDF por prioridad y sólo Frontier: " + r.pdfCods.join(","));
  if (r.imgs !== 5) fail("(C) una foto por artículo: " + r.imgs);
  if (!/Cómo se compone/.test(r.res) || !/master cajas/.test(r.res) || !/2 artículo\(s\) con menos de 4 meses/.test(r.res)) fail("(C) resumen incompleto: " + r.res);
  if (errs.length) fail("errores JS: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("✓ pedimp-prioridad-damian: orden por meses de stock, alerta < 4 y PDF para Damián");
})();
