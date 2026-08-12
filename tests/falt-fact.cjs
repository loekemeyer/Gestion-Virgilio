/* Smoke de "Faltantes facturados sin completar" (v10.16).
   Abre index.html headless, stubea el fetch de `vista_faltantes_sin_completar` con filas
   conocidas y verifica que el módulo:
     (a) renderice la tabla caso-por-caso con tanda/código/cajas/NP/cliente,
     (b) sume bien el total,
     (c) agrupe por artículo al tocar el toggle (sumando cajas de varias tandas),
     (d) muestre el cartel de vacío cuando la vista no devuelve nada.
   No toca la red real ni Supabase. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}

const FILAS = [
  { tanda: "D17A", cod: "870E", cajas: 168, nps_lista: "98257", clientes: "Coto C.I.C.S.A.", fecha_entrega: "2026-08-05", ts_pkc: "2026-08-04T10:21:57-03:00" },
  { tanda: "C97A", cod: "870E", cajas: 144, nps_lista: "98091", clientes: "Coto C.I.C.S.A.", fecha_entrega: "2026-07-23", ts_pkc: "2026-07-17T08:54:00-03:00" },
  { tanda: "C74A", cod: "546",  cajas: 71,  nps_lista: "97890", clientes: "Distribuidora GM S.R.L", fecha_entrega: "2026-07-15", ts_pkc: "2026-07-14T10:01:59-03:00" }
];

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const pageerrors = [];
  page.on("pageerror", (e) => pageerrors.push(String(e && e.message || e)));

  let filas = FILAS;
  await page.route("**/*", (route) => {
    const url = route.request().url();
    if (url.includes("vista_faltantes_sin_completar")) {
      return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(filas) });
    }
    if (url.startsWith("http")) {
      return route.fulfill({ status: 200, contentType: "application/json", body: "[]" });
    }
    return route.continue();
  });

  await page.goto("file://" + path.resolve(__dirname, "..", "index.html"));
  await page.waitForFunction(() => typeof window.stkOpenFaltFact === "function");

  // (a)+(b) caso por caso
  await page.evaluate(() => window.stkOpenFaltFact());
  await page.waitForFunction(() => {
    const b = document.getElementById("stkPopBody");
    return b && !/Cargando/.test(b.textContent);
  });
  const caso = await page.evaluate(() => {
    const b = document.getElementById("stkPopBody");
    const t = b.textContent;
    return {
      filas: b.querySelectorAll("tbody tr").length,
      tieneTanda: t.includes("D17A"), tieneCod: t.includes("870E"),
      tieneNp: t.includes("98257"), tieneCliente: t.includes("Coto"),
      total: /383/.test(t)                       // 168+144+71
    };
  });

  // (c) agrupado por artículo: 870E debe sumar 168+144=312 en 2 tandas
  await page.evaluate(() => window.stkFaltFactToggleArt());
  const agrup = await page.evaluate(() => {
    const b = document.getElementById("stkPopBody");
    const rows = [...b.querySelectorAll("tbody tr")].map(tr => [...tr.children].map(td => td.textContent.trim()));
    return { filas: rows.length, primera: rows[0] || [] };
  });

  // (d) vacío
  filas = [];
  await page.evaluate(() => window.stkPopClose());
  await page.evaluate(() => window.stkOpenFaltFact());
  await page.waitForFunction(() => {
    const b = document.getElementById("stkPopBody");
    return b && !/Cargando/.test(b.textContent);
  });
  const vacio = await page.evaluate(() => /No hay faltantes/.test(document.getElementById("stkPopBody").textContent));

  await browser.close();

  const ok = caso.filas === 3 && caso.tieneTanda && caso.tieneCod && caso.tieneNp &&
             caso.tieneCliente && caso.total &&
             agrup.filas === 2 && agrup.primera[0] === "870E" && agrup.primera[2] === "312" && agrup.primera[3] === "2" &&
             vacio && pageerrors.length === 0;

  console.log("falt-fact:", JSON.stringify({ caso, agrup, vacio }),
              "· pageerrors:", pageerrors.length ? pageerrors.join(" | ") : "none",
              ok ? "· ✓ OK" : "· ✗ FALLÓ");
  process.exit(ok ? 0 : 1);
})();
