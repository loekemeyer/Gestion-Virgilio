/* Capturas de la BOTONERA del operario (index.html). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { ({ chromium } = require("playwright")); }
const OUT = __dirname;
const sleep = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  const b = await chromium.launch({ args: ["--lang=es-AR"] });
  const p = await b.newPage({ viewport: { width: 420, height: 700 }, deviceScaleFactor: 2.5, locale: "es-AR", timezoneId: "America/Argentina/Buenos_Aires" });
  p.on("pageerror", e => console.error("PAGEERROR:", e.message));
  await p.route("**/*.supabase.co/**", r => r.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.goto("file://" + path.join("/home/user/Gestion-Virgilio", "index.html"), { waitUntil: "domcontentloaded" });
  await sleep(1500);
  await p.screenshot({ path: OUT + "/00-login.png" });
  console.log("  ✓ 00-login");

  await p.evaluate(async () => {
    window.alert = function () {}; window.confirm = function () { return true; };
    const sl = ms => new Promise(r => setTimeout(r, ms));
    legajoInput.value = "237"; goToOptions(); await sl(500);
    const rt = document.querySelector('#optionsScreen [data-code="RT"]');
    if (rt) rt.click();
    await sl(300);
  });
  await sleep(600);
  await p.screenshot({ path: OUT + "/00b-botonera-rt.png" });
  console.log("  ✓ 00b-botonera-rt");
  await b.close();
})();
