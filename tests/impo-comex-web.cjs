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
console.log("✓ impo-comex-web: botón en Importación, copia armada web, sin token ni datos personales");
