// v25.31 (Luis, 30/09) — el botón GP2 del admin de Cervantes abre la APP instalada por web+gp2:
// (pregunta una vez por compu, se acuerda en localStorage) y en el navegador si no está instalada.
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); } catch (_e) { ({ chromium } = require("playwright")); }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const out = {}, abiertos = [];
    window.open = (u) => { abiertos.push(u); return {}; };
    localStorage.removeItem("gp2_abrir");
    // 1) primera vez, dice que NO tiene la app -> navegador y se acuerda
    window.confirm = () => false; abrirAdminCervantes("gp2");
    out.web = abiertos.slice(); out.modoWeb = localStorage.getItem("gp2_abrir");
    // 2) segunda vez NO pregunta
    let pregunto = false; window.confirm = () => { pregunto = true; return true; }; abrirAdminCervantes("gp2");
    out.noRepregunta = !pregunto && abiertos.length === 2;
    // 3) «cambiar» resetea y la app va por el enlace propio
    window.alert = () => {}; gp2CambiarModo(); out.reset = localStorage.getItem("gp2_abrir") === null;
    out.link = !!document.querySelector('#cervAdmin a[onclick*="gp2CambiarModo"]');
    return out;
  });
  await b.close();
  const f = [];
  if (!(r.web.length === 1 && /vercel\.app\/GP2_MODULOS\.html/.test(r.web[0]) && r.modoWeb === "web")) f.push("sin app -> navegador: " + JSON.stringify(r));
  if (!r.noRepregunta) f.push("repregunta");
  if (!r.reset || !r.link) f.push("cambiar");
  if (!/var GP2_PROTO = "web\+gp2:modulos"/.test(require("fs").readFileSync(path.join(__dirname, "..", "index.html"), "latin1"))) f.push("protocolo");
  const src = require("fs").readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
  if (!/function _gp2App\(\)[\s\S]{0,900}setTimeout\([\s\S]{0,300}if \(fue\) return;\s*_gp2Web\(\)/.test(src)) f.push("sin fallback al navegador si la app no abre");
  if (!/modo === "app"\) \{ _gp2App\(\)/.test(src)) f.push("el modo app no pasa por _gp2App");
  if (f.length) { console.error("gp2-abrir-app: FALLA " + f.join(" · ")); process.exit(1); }
  console.log("gp2-abrir-app: OK — pregunta una vez, navegador o app por web+gp2:, y se puede cambiar");
})();
