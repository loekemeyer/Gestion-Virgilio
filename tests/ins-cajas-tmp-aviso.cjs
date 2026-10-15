/* v30.92 (Luis, 15/10, D8: "que aparezca mientras haya") — aviso de cajas con código temporal sin cruzar:
   (a) con cajas TMP / CJ: contador naranja en «Stock y Compras» y cartel con las dos listas;
   (b) si la lectura FALLA no se muestra 0: queda lo último leído;
   (c) sin ninguna: el contador se apaga y el cartel no se dibuja. Sin red. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); } catch (_e) { ({ chromium } = require("playwright")); }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage(); const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**://**", (r) => (/^file:/.test(r.request().url()) ? r.continue() : r.abort()));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    let resp = [{ lado: "virgilio", cod: "TMP-0050", nombre: "Caja N° 31", motivo: "" },
                { lado: "cervantes", cod: "CJ8", nombre: "Caja N°8", motivo: "" }];
    let cae = false;
    window.fetch = async function (u) {
      if (/gv_cajas_codigo_temporal/.test(String(u))) {
        if (cae) return { ok: false, status: 500, json: async () => null };
        return { ok: true, json: async () => resp };
      }
      return { ok: false, status: 500, json: async () => null, text: async () => "" };
    };
    const bd = () => document.getElementById("stkCjBadge");
    await cajasTmpFetch(true);
    const h1 = _cajasTmpHtml();
    const a = bd().style.display === "block" && bd().textContent === "2" && /TMP-0050/.test(h1) && /CJ8/.test(h1) && /Naza/.test(h1) &&
      /Escritas a mano/.test(h1) && /Cervantes provisorio/.test(h1);
    cae = true; await cajasTmpFetch(true);
    const b2 = bd().textContent === "2" && /TMP-0050/.test(_cajasTmpHtml());
    cae = false; resp = []; await cajasTmpFetch(true);
    const c = bd().style.display === "none" && _cajasTmpHtml() === "";
    return { a: a, b: b2, c: c };
  });
  await b.close();
  const ok = r.a && r.b && r.c && !errs.length;
  console.log("ins-cajas-tmp-aviso:", JSON.stringify(r), errs.length ? "· errores: " + errs.join(" | ") : "· pageerrors: none", ok ? "· ✓ OK" : "· ✗ FALLA");
  process.exit(ok ? 0 : 1);
})();
