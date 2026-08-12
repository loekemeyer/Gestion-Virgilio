/* Tolerancia de red del monitor de TV (v10.19).
   Reproduce lo que pasa en el stick del depósito: fetches que fallan de a ratos
   con el WiFi VIVO. Verifica que:
     (a) _monReintentar se recupere solo si un intento intermedio anda,
     (b) reintente hasta MON_REINTENTOS y recién ahí propague el error,
     (c) el backoff sea creciente (no martilla),
     (d) el cartel "sin actualizar" NO aparezca antes de MON_FALLOS_P_CARTEL ciclos,
     (e) las constantes del watchdog estén puestas.
   No toca la red real ni abre el monitor (no hay sesión de supervisor en el test). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const pageerrors = [];
  page.on("pageerror", (e) => pageerrors.push(String(e && e.message || e)));
  await page.route("**/*", (r) => r.request().url().startsWith("http")
    ? r.fulfill({ status: 200, contentType: "application/json", body: "[]" })
    : r.continue());
  await page.goto("file://" + path.resolve(__dirname, "..", "index.html"));
  await page.waitForFunction(() => typeof window._monReintentar === "function"
                                 && typeof MON_FALLOS_P_CARTEL !== "undefined");

  const res = await page.evaluate(async () => {
    const out = {};

    // (a) falla el 1er intento, anda el 2º → se recupera SOLO, sin error.
    let n1 = 0;
    out.recupera = await window._monReintentar(async () => {
      n1++; if (n1 === 1) throw new Error("hipo de wifi");
      return "datos";
    }, MON_REINTENTOS);
    out.intentosHastaRecuperar = n1;

    // (b)+(c) falla siempre → agota los intentos, propaga, y espacia los reintentos.
    let n2 = 0; const ts = [];
    try {
      await window._monReintentar(async () => { n2++; ts.push(Date.now()); throw new Error("caido"); },
                                  MON_REINTENTOS);
      out.propago = false;
    } catch (e) { out.propago = (e.message === "caido"); }
    out.intentosTotales = n2;
    out.backoffCreciente = ts.length >= 3 && (ts[2] - ts[1]) > (ts[1] - ts[0]);

    // (d)+(e) constantes de tolerancia y watchdog
    out.fallosParaCartel = MON_FALLOS_P_CARTEL;
    out.reloadMs = MON_RELOAD_MS;
    out.refreshMs = MONITOR_REFRESH_MS;
    // con el refresh de 30s, el cartel debe tardar >= 90s en aparecer
    out.minutosHastaCartel = (MON_FALLOS_P_CARTEL * MONITOR_REFRESH_MS) / 60000;
    return out;
  });

  await browser.close();

  const ok = res.recupera === "datos" && res.intentosHastaRecuperar === 2 &&
             res.propago === true && res.intentosTotales === 3 && res.backoffCreciente &&
             res.fallosParaCartel >= 3 && res.minutosHastaCartel >= 1.5 &&
             res.reloadMs >= 5 * 60000 &&
             pageerrors.length === 0;

  console.log("monitor-red-tolerante:", JSON.stringify(res),
              "· pageerrors:", pageerrors.length ? pageerrors.join(" | ") : "none",
              ok ? "· ✓ OK" : "· ✗ FALLÓ");
  process.exit(ok ? 0 : 1);
})();
