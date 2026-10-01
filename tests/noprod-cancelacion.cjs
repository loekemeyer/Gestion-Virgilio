/* v25.68 (Luis) — la tarea ANULADA es NO PRODUCTIVA, discriminada como «Cancelación de tarea» con su
   tiempo: el pop-up de No productivas del monitor la rotula y suma aparte. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage(); const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/*.supabase.co/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    _monitorLiveStats = { todayKey: "2026-10-01", today: { perOperario: [{ legajo: "8", nombre: "Juan", noprodMin: 40, noprodDetail: [
      { opcion: "PB", texto: "", ts_inicio: "2026-10-01T12:00:00Z", ts_cliente: "2026-10-01T12:10:00Z", durMs: 600000 },
      { opcion: "CR", texto: "ANULADO", ts_inicio: "2026-10-01T13:00:00Z", ts_cliente: "2026-10-01T13:30:00Z", durMs: 1800000 } ] }] } };
    showOperarioActivityDetail("8", "noprod");
    const t = document.querySelector("#tandaModal .tanda-modal-body").innerText;
    return { rotula: /Cancelación de tarea\s+CR · Control Remitos/.test(t), suma: /Cancelación de tarea: 30 min · 1 tarea/.test(t),
             banoNormal: /PB\s+Paré Baño/.test(t) && !/Cancelación de tarea\s+PB/.test(t) };
  });
  const pass = Object.values(r).every(Boolean) && errs.length === 0;
  console.log("noprod-cancelacion:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
