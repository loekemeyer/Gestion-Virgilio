/* v24.76 (Luis 30/09) — 🖨 IMPRIMIR PDF en Pedidos Importación: botón en la barra de arriba,
   pop-up con los proveedores + «Sólo lo que genera pedido», y el reporte con Cód · Stk · E.M. ·
   Meses Stk (⚠ < 4) · m³ · u$s (sólo de lo que pide) · Pedido en curso, del más urgente al menos. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1600, height: 900 } });
  await p.route("**/rest/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const mk = (cod, prov, stk, cam, pide) => { const it = { cod, key: cod, prov, desc: "Art " + cod, proyUni: 100, objetivoUni: 1000, stockUni: stk, enCurso: cam, reingresoEst: cam ? "2026-11-01" : null, meses: 10,
      aPedirUni: pide ? 950 : 0, uniMaster: 50, uxc: 10, fobUni: 2, m3Master: 0.1, det: [{ id: cod, curso: 0, marca: "LK" }] }; it.aPedirCajas = pide ? 19 : 0; return it; };
    const items = [mk("901E", "Fujian", 800, 0, false), mk("902E", "Fujian", 50, 100, true), mk("903E", "Fujian", 300, 0, true), mk("904E", "Kangli", 10, 0, true)];
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items, meses: 10, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: true, mcOverride: {} };
    window._NAC_TASAS && (_NAC_TASAS.moq = 0);
    _pedImpRender();
    const btn = [...document.querySelectorAll("#stkPopBody .pedimp-rep-btn")];
    if (btn.length !== 1) return { err: "botón IMPRIMIR PDF: " + btn.length };
    btn[0].click();
    const provs = [...document.querySelectorAll("#impRepOv .imp-rep-prov")].map((c) => c.value + ":" + c.checked);
    const html = _pedImpRepHtml(["Fujian"], false);
    const htmlSolo = _pedImpRepHtml(["Fujian"], true);
    const d = new DOMParser().parseFromString(html, "text/html");
    const cods = [...d.querySelectorAll("tbody tr")].map((tr) => tr.cells[0].textContent);
    const f902 = [...d.querySelectorAll("tbody tr")].find((tr) => /902E/.test(tr.cells[0].textContent));
    const f901 = [...d.querySelectorAll("tbody tr")].find((tr) => /901E/.test(tr.cells[0].textContent));
    const ths = [...d.querySelectorAll("thead tr:nth-child(2) th")].map((x) => x.childNodes[0].textContent);
    return { provs, cods, ths, m902: f902.cells[3].textContent, cam902: f902.cells[6].textContent, usd901: f901.cells[5].textContent, cam901: f901.cells[6].textContent,
      solo: [...new DOMParser().parseFromString(htmlSolo, "text/html").querySelectorAll("tbody tr")].length, arial: /font-family:Arial/.test(html) && /font-size:15px/.test(html) };
  });
  if (r.err) { fail(r.err); await b.close(); return; }
  if (r.provs.join() !== "Fujian:true,Kangli:true") fail("el pop-up lista los proveedores tildados: " + r.provs);
  if (r.ths.join("|") !== "Cód.|Stk.|E.M.|Meses|m³|u$s|Pedido") fail("columnas: " + r.ths.join("|"));
  if (r.cods.join() !== "902E,903E,901E") fail("orden por urgencia (meses de stock): " + r.cods);
  if (!/^⚠ 1,5$/.test(r.m902)) fail("meses < 4 con ⚠: " + r.m902);
  if (!/100.*01\/11/.test(r.cam902)) fail("pedido en curso con unidades y fecha: " + r.cam902);
  if (r.usd901 !== "—" || r.cam901 !== "No") fail("sin pedido: u$s — y en curso No: " + r.usd901 + " " + r.cam901);
  if (r.solo !== 2) fail("«Sólo lo que genera pedido» deja 2: " + r.solo);
  if (!r.arial) fail("Arial 15");
  await b.close();
  if (!process.exitCode) console.log("✓ pedimp-reporte-pdf");
})();
