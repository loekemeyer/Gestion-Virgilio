/* 🖨 IMPRIMIR PDF de arriba en Pedidos Importación.
   v24.76 (Luis): botón en la barra de arriba + pop-up con los proveedores + «Sólo lo que genera pedido»
   + vista previa.  v25.13 (Thomas, 30/09): *"que el de arriba tenga la misma funcionalidad de hoy (que
   te muestre todos) pero con la lógica del PDF de Damián"* → la salida son las hojas de Damián (pedido ·
   sin pedir · discontinuos) de CADA proveedor tildado, una tanda atrás de otra. */
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
  await p.waitForFunction(() => typeof pedImpRepImprimir === "function" && typeof _pedImpDamianHojas === "function", null, { timeout: 20000 });
  const r = await p.evaluate(async () => {
    const mk = (cod, prov, stk, cam, pide) => { const it = { cod, key: cod, prov, desc: "Art " + cod, proyUni: 100, objetivoUni: 1000, stockUni: stk, enCurso: cam, reingresoEst: cam ? "2026-11-01" : null, meses: 10,
      aPedirUni: pide ? 950 : 0, uniMaster: 50, uxc: 10, fobUni: 2, m3Master: 0.1, det: [{ id: cod, curso: 0, marca: "LK" }] }; it.aPedirCajas = pide ? 19 : 0; return it; };
    const items = [mk("901E", "Fujian", 800, 0, false), mk("902E", "Fujian", 50, 100, true), mk("903E", "Fujian", 300, 0, true), mk("904E", "Kangli", 10, 0, true), mk("905E", "Kangli", 900, 0, false)];
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items, meses: 10, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: true, mcOverride: {} };
    window._NAC_TASAS && (_NAC_TASAS.moq = 0);
    _pedImpRender();
    const btn = [...document.querySelectorAll("#stkPopBody .pedimp-rep-btn")];
    if (btn.length !== 1) return { err: "botón IMPRIMIR PDF: " + btn.length };
    const vista = async (soloPed, soloFujian) => {
      if (!document.getElementById("impRepOv")) btn[0].click();
      [...document.querySelectorAll("#impRepOv .imp-rep-prov")].forEach((c) => { c.checked = !soloFujian || c.value === "Fujian"; });
      document.getElementById("impRepSoloPed").checked = soloPed;
      await pedImpRepImprimir();
      const ifr = document.querySelector("#impRepOv iframe.imp-rep-prev");
      const ok = !!ifr && !!document.querySelector("#impRepOv .imp-rep-print");
      const html = ifr ? ifr.srcdoc : "";
      document.getElementById("impRepOv") && document.getElementById("impRepOv").remove();
      const d = new DOMParser().parseFromString(html, "text/html");
      const tits = [...d.querySelectorAll("th.tit, .tit3")].map((x) => x.textContent.replace(/\s+\d{2}\/\w{3}$/, "").trim());
      const ths = [...d.querySelectorAll(".hoja")].slice(0, 1).map((h) => [...h.querySelectorAll("thead tr:last-child th")].map((x) => x.childNodes[0] ? x.childNodes[0].textContent : "").join("|"))[0] || "";
      const cods = [...d.querySelectorAll(".hoja")].map((h) => [...h.querySelectorAll("tbody tr")].map((tr) => tr.cells[0].textContent.replace(/INAL$/, "")).join(","));
      return { ok, tits, ths, cods, hojas: d.querySelectorAll(".hoja").length, portrait: /size:A4 portrait/.test(html), marca: /<th>Marca<\/th>/.test(html) };
    };
    btn[0].click();
    const provs = [...document.querySelectorAll("#impRepOv .imp-rep-prov")].map((c) => c.value + ":" + c.checked);
    const todos = await vista(false, false);
    const solo = await vista(true, false);
    const uno = await vista(false, true);
    return { provs, todos, solo, uno, sinViejo: typeof _pedImpRepHtml === "undefined" };
  });
  if (r.err) { fail(r.err); await b.close(); return; }
  if (r.provs.join() !== "Fujian:true,Kangli:true") fail("el pop-up lista los proveedores tildados: " + r.provs);
  if (!r.todos.ok) fail("Imprimir tiene que mostrar la vista previa (iframe + botón Imprimir)");
  if (r.todos.tits.join("|") !== "Pedido Fujian|Sin pedir Fujian|Pedido Kangli|Sin pedir Kangli")
    fail("todos: las hojas de Damián de CADA proveedor, una tanda atrás de otra: " + r.todos.tits.join("|"));
  if (!/^Cód\|Marca\|Descripción\|Foto\|/.test(r.todos.ths)) fail("columnas del PDF de Damián: " + r.todos.ths);
  if (!r.todos.portrait || !r.todos.marca) fail("A4 vertical y columna Marca, como el de Damián");
  if (r.todos.cods[0] !== "902E,903E") fail("hoja del pedido de Fujian por urgencia: " + r.todos.cods[0]);
  if (r.solo.tits.join("|") !== "Pedido Fujian|Pedido Kangli") fail("«Sólo lo que genera pedido» deja sólo la hoja del pedido: " + r.solo.tits.join("|"));
  if (r.uno.tits.join("|") !== "Pedido Fujian|Sin pedir Fujian") fail("un proveedor tildado: sólo sus hojas: " + r.uno.tits.join("|"));
  if (!r.sinViejo) fail("el reporte de una tabla (v24.76-79) no vuelve");
  await b.close();
  if (!process.exitCode) console.log("✓ pedimp-reporte-pdf");
})();
