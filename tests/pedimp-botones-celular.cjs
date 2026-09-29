/* v24.54 (Thomas) — en el celular los botones del proveedor (Configurar / PDF pedido / PDF para
   Damián) se salían de la pantalla. Tienen que quedar todos DENTRO de la tarjeta a 390 px. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  await p.route("**/rest/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const it = { cod: "945E", prov: "Becky", key: "945E", desc: "Espátula", proyUni: 156, objetivoUni: 1560, stockUni: 168, enCurso: 0, meses: 10,
      aPedirUni: 1392, uniMaster: 72, uxc: 12, fobUni: 0.5, m3Master: 0.05, det: [{ id: 1, curso: 0, marca: "LK" }] };
    it.aPedirCajas = Math.ceil(it.aPedirUni / it.uniMaster);
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items: [it], meses: 10, minUsd: 25000, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: false, mcOverride: {} };
    _pedImpRender();
    const btns = [...document.querySelectorAll("button")].filter((x) => /PDF pedido|PDF para Dami|Configurar/.test(x.textContent));
    const card = btns[0] && btns[0].closest('div[style*="border-radius:12px"]');
    const cr = card ? card.getBoundingClientRect() : null;
    return { n: btns.length, cr: cr && { l: cr.left, r: cr.right }, bs: btns.map((x) => { const q = x.getBoundingClientRect(); return { t: x.textContent.trim(), l: q.left, r: q.right }; }) };
  });
  if (r.n !== 3) fail("tienen que estar los 3 botones: " + r.n);
  (r.bs || []).forEach((x) => { if (!r.cr || x.r > r.cr.r + 1 || x.l < r.cr.l - 1) fail("«" + x.t + "» se sale de la tarjeta: " + JSON.stringify(x) + " tarjeta " + JSON.stringify(r.cr)); });
  await b.close();
  if (!process.exitCode) console.log("✓ pedimp-botones-celular: los botones del proveedor entran a 390 px");
})();
