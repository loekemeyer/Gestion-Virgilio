/* v23.19 — IMPO COMEX (versión web) dentro de Gestión Virgilio.
   Candado estático:
   (a) el botón 🛃 IMPO COMEX está en las solapas de Pedidos Importación y abre impo-comex/;
   (b) la copia armada existe, lleva robots noindex y pide a la puerta Impo_Comex_web;
   (c) en la copia NO van el token del servidor ni los datos personales de la DDJJ (repo público):
       el controlante lo entrega la puerta, y el token vive sólo en el servidor. */
const fs = require("fs");
const path = require("path");
const raiz = path.join(__dirname, "..");
const fallas = [];
const ok = (c, m) => { if (!c) fallas.push(m); };

const html = (fs.readFileSync(path.join(raiz, "index.html"), "utf8") + "\n" + fs.readFileSync(path.join(raiz, "importacion.js"), "utf8"));
const i = html.indexOf("function _impTabsHtml(");
const tabs = i >= 0 ? html.slice(i, html.indexOf("\n}\n", i)) : "";
ok(/onclick="openImpoComex\(\)"[^>]*>🛃 IMPO COMEX</.test(tabs), "(a) falta el botón 🛃 IMPO COMEX en _impTabsHtml");
ok(/function openImpoComex\(\)\s*\{\s*location\.href\s*=\s*"impo-comex\/"/.test(html), "(a) openImpoComex no abre impo-comex/");

const dir = path.join(raiz, "impo-comex");
ok(fs.existsSync(path.join(dir, "index.html")), "(b) no está impo-comex/index.html");
if (fs.existsSync(path.join(dir, "index.html"))) {
  const idx = fs.readFileSync(path.join(dir, "index.html"), "utf8");
  ok(/name="robots" content="noindex,nofollow"/.test(idx), "(b) impo-comex/index.html sin robots noindex");
  const assets = path.join(dir, "assets");
  const js = fs.readdirSync(assets).filter(f => /\.m?js$/.test(f)).map(f => fs.readFileSync(path.join(assets, f), "latin1")).join("\n");
  ok(js.includes("Impo_Comex_web"), "(b) la copia no pide a la puerta Impo_Comex_web (¿es el build del portable?)");
  ok(!/16894232|Maturana/.test(js), "(c) la copia lleva los datos personales de la DDJJ");
  ok(!/eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9/.test(js), "(c) la copia lleva una clave legacy (JWT): usar la sb_publishable_");
}

// (e) v29.18 — IMPO COMEX nuevo, sin build (Elías, 09/10): impocomex/ con scripts clásicos que cuelgan de window.IC.
//     El botón «🛃 IMPO COMEX nuevo» lo abre; cada modo está en su ic-<modo>.js y la lógica de parseo es la
//     original copiada tal cual en impocomex/logica/. Tampoco lleva token ni datos personales.
ok(/onclick="openImpoComex2\(\)"[^>]*>🛃 IMPO COMEX nuevo</.test(tabs), "(e) falta el botón 🛃 IMPO COMEX nuevo en _impTabsHtml");
ok(/function openImpoComex2\(\)[\s\S]{0,400}impocomex\/ic-base\.js/.test(html), "(e) openImpoComex2 no carga impocomex/ic-base.js");
const nuevo = path.join(raiz, "impocomex");
ok(fs.existsSync(path.join(nuevo, "ic-base.js")), "(e) falta impocomex/ic-base.js");
if (fs.existsSync(path.join(nuevo, "ic-base.js"))) {
  const base = fs.readFileSync(path.join(nuevo, "ic-base.js"), "utf8");
  const m = base.match(/const ARCHIVO_MODO = \{([\s\S]*?)\};/);
  const pares = m ? [...m[1].matchAll(/(\w+):\s*'([^']+)'/g)].map(x => [x[1], x[2]]) : [];
  ok(pares.length >= 11, "(e) ARCHIVO_MODO no lista los 11 modos");
  for (const [modo, archivo] of pares) {
    const f = path.join(nuevo, archivo);
    ok(fs.existsSync(f), `(e) falta impocomex/${archivo} (modo ${modo})`);
    if (fs.existsSync(f)) ok(fs.readFileSync(f, "utf8").includes(`IC.modo('${modo}'`), `(e) impocomex/${archivo} no registra el modo ${modo}`);
  }
  const textos = [];
  const recorrer = (d) => { for (const n of fs.readdirSync(d)) { const q = path.join(d, n); if (fs.statSync(q).isDirectory()) recorrer(q); else if (/\.(m?js|css|html)$/.test(n)) textos.push([q, fs.readFileSync(q, "latin1")]); } };
  recorrer(nuevo);
  for (const [q, t] of textos) {
    const r = path.relative(raiz, q);
    ok(!/16894232|Maturana/.test(t), `(e) ${r} lleva los datos personales de la DDJJ`);
    ok(!/eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9/.test(t), `(e) ${r} lleva una clave legacy (JWT)`);
    if (/[\\/]logica[\\/]/.test(q)) ok(!/import\.meta\.env|\?url['"]/.test(t), `(e) ${r} quedó con import.meta.env o ?url (sólo anda con build)`);
  }
}

// (d) el fuente de la puerta vive acá y tampoco lleva datos personales: los lee de la base
const puerta = path.join(__dirname, "..", "supabase", "impo-comex-web", "index.ts");
ok(fs.existsSync(puerta), "(d) falta supabase/impo-comex-web/index.ts (fuente de la puerta)");
if (fs.existsSync(puerta)) {
  const ts = fs.readFileSync(puerta, "utf8");
  ok(!/16894232|Maturana/.test(ts), "(d) la puerta lleva los datos personales de la DDJJ");
  ok(ts.includes("gv_impo_comex_ddjj_controlante"), "(d) la puerta no lee el controlante de la base");
}
for (const f of fs.readdirSync(path.join(__dirname, "..", "sql")).filter(f => /impo_comex/.test(f)))
  ok(!/16894232|Maturana/.test(fs.readFileSync(path.join(__dirname, "..", "sql", f), "utf8")), `(d) sql/${f} lleva datos personales`);

if (fallas.length) { console.error("✗ impo-comex-web:\n  - " + fallas.join("\n  - ")); process.exit(1); }
console.log("✓ impo-comex-web: botón en Importación, copia armada web y la nueva sin build, sin token ni datos personales");
