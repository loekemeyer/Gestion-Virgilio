#!/usr/bin/env node
// Reporte quincenal a pedir (Luis, 02/10/2026 — D6: a Thomy y Damián · D7: cada quincena).
//
// Arma el MISMO PDF que «🖨 IMPRIMIR PDF» de Pedidos Importación con todos los proveedores tildados
// (resumen + pedidos + sin pedir + discontinuos), corriendo la pantalla de verdad sin pantalla, y lo
// manda por WhatsApp con la plantilla `reporte_quincenal_a_pedir` desde el número de Meta de
// GestOpClientes (Edge Function lk_reporte-quincenal del proyecto LK, detrás del corte wa-guard).
//
// Lo corre el workflow .github/workflows/reporte-quincenal-importacion.yml (días 1 y 16). La función
// reconoce a ese workflow por su token OIDC de GitHub: no hace falta ningún secreto en el repo.
//
//   node scripts/reporte-quincenal/enviar.cjs --solo-pdf --out reporte.pdf   # sólo el PDF, no manda
//   node scripts/reporte-quincenal/enviar.cjs [--forzar] [--fecha 2026-10-16] [--out reporte.pdf]
"use strict";
const fs = require("fs");
const path = require("path");

const FN_URL = "https://kwkclwhmoygunqmlegrg.supabase.co/functions/v1/lk_reporte-quincenal";
const LK_PUBLISHABLE = "sb_publishable_mVX5MnjwM770cNjgiL6yLw_LDNl9pML";   // pública: es la de admin/admin.js
const AUDIENCIA = "lk-reporte-quincenal";
const REPO = path.join(__dirname, "..", "..");
const INTENTOS = 4;

const fmt = (n) => Math.round(Number(n || 0)).toLocaleString("es-AR");
const hoyAR = () => new Date().toLocaleDateString("en-CA", { timeZone: "America/Argentina/Buenos_Aires" });

// Las 5 variables de la plantilla, a partir de `datos` de _pedImpResumenHoja (importacion.js).
// Meta no acepta saltos de línea ni 5+ espacios seguidos en una variable.
function armarParams(datos, fechaISO) {
  const filas = (datos && datos.filas) || [];
  const t = (datos && datos.total) || {};
  const conPedido = filas.filter((f) => Number(f.usd) > 0);
  const niveles = filas.filter((f) => f.nivel >= 1 && f.nivel <= 4).map((f) => f.nivel);
  let urgentes = "—";
  if (niveles.length) {
    const min = Math.min(...niveles);
    const top = filas.filter((f) => f.nivel === min).map((f) => f.prov);
    const nom = top.length <= 3 ? top : top.slice(0, 2).concat([top.length - 2 + " más"]);
    urgentes = (nom.length > 1 ? nom.slice(0, -1).join(", ") + " y " + nom[nom.length - 1] : nom[0]) + " (prioridad " + min + ")";
  }
  const limpio = (s) => String(s).replace(/\s+/g, " ").trim();
  return [
    fechaISO.slice(8, 10) + "/" + fechaISO.slice(5, 7),
    fmt(t.usd),
    String(conPedido.length),
    fmt(t.curso),
    urgentes,
  ].map(limpio);
}

function args(argv) {
  const o = { soloPdf: false, forzar: false, fecha: null, out: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--solo-pdf") o.soloPdf = true;
    else if (a === "--forzar") o.forzar = true;
    else if (a === "--fecha") o.fecha = argv[++i];
    else if (a === "--out") o.out = argv[++i];
  }
  return o;
}

function playwright() {
  try { return require("playwright"); } catch (_e) { return require("/opt/node22/lib/node_modules/playwright"); }
}

// Corre la pantalla y devuelve { html, datos }. Valida que los números estén completos: en una carga
// lenta los m³ pueden llegar en 0 (pasó al probarlo); en ese caso se recarga.
async function armarReporte(browser, ctxOpt) {
  for (let intento = 1; intento <= INTENTOS; intento++) {
    const ctx = await browser.newContext(ctxOpt);
    const p = await ctx.newPage();
    p.on("pageerror", (e) => console.error("pageerror:", String(e).slice(0, 160)));
    try {
      await p.goto("file://" + path.join(REPO, "index.html"), { waitUntil: "domcontentloaded" });
      await p.waitForFunction(() => typeof openPedidosImportacion === "function" && typeof pedImpRepImprimir === "function"
        && typeof _pedImpResumenHoja === "function", null, { timeout: 60000 });
      const r = await p.evaluate(async () => {
        await openPedidosImportacion();
        pedImpRepAbrir();
        const provs = [...document.querySelectorAll("#impRepOv .imp-rep-prov")].map((c) => { c.checked = true; return c.value; });
        document.getElementById("impRepSoloPed").checked = false;
        await pedImpRepImprimir();
        const ifr = document.querySelector("#impRepOv iframe.imp-rep-prev");
        const res = await _pedImpResumenHoja(provs, {});
        return { provs, html: ifr ? ifr.srcdoc : "", datos: res ? res.datos : null };
      });
      const filas = (r.datos && r.datos.filas) || [];
      const m3Mal = filas.filter((f) => f.usd > 0 && !(f.m3 > 0)).map((f) => f.prov);
      console.log(`intento ${intento}: ${r.provs.length} proveedores · html ${r.html.length} · a pedir u$s ${fmt(r.datos && r.datos.total.usd)}` +
        (m3Mal.length ? ` · sin m³: ${m3Mal.join(", ")}` : ""));
      if (r.html && filas.length && !m3Mal.length) { await ctx.close(); return r; }
    } catch (e) {
      console.error(`intento ${intento} falló:`, String(e).slice(0, 200));
    }
    await ctx.close();
  }
  throw new Error(`no se pudo armar el reporte completo en ${INTENTOS} intentos`);
}

async function aPdf(browser, ctxOpt, html, out) {
  const ctx = await browser.newContext(ctxOpt);
  const q = await ctx.newPage();
  await q.setContent(html, { waitUntil: "domcontentloaded", timeout: 60000 });
  let last = -1, quieto = 0;
  for (let i = 0; i < 90; i++) {   // hasta 3 min: cada foto prueba varias URLs (LK .webp, Chef .jpg)
    await q.waitForTimeout(2000);
    const st = await q.evaluate(() => { const a = [...document.images]; return { ok: a.filter((x) => x.complete && x.naturalWidth > 0).length, pend: a.filter((x) => !x.complete).length }; });
    if (st.ok === last && st.pend === 0) { if (++quieto >= 3) break; } else quieto = 0;
    last = st.ok;
  }
  const fotos = await q.evaluate(() => { const a = [...document.images]; return a.filter((i) => i.complete && i.naturalWidth > 0).length + "/" + a.length; });
  await q.pdf({ path: out, preferCSSPageSize: true, printBackground: true });
  await ctx.close();
  console.log(`PDF ${out}: ${(fs.statSync(out).size / 1048576).toFixed(1)} MB · fotos ${fotos}`);
}

async function tokenOidc() {
  const url = process.env.ACTIONS_ID_TOKEN_REQUEST_URL, tok = process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN;
  if (!url || !tok) throw new Error("sin token OIDC: esto sólo manda desde el workflow (permissions: id-token: write)");
  const r = await fetch(url + "&audience=" + encodeURIComponent(AUDIENCIA), { headers: { Authorization: "Bearer " + tok } });
  const j = await r.json();
  if (!j.value) throw new Error("GitHub no devolvió el token OIDC");
  return j.value;
}
async function llamar(oidc, body) {
  const r = await fetch(FN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: LK_PUBLISHABLE, "x-gh-oidc": oidc },
    body: JSON.stringify(body),
  });
  const txt = await r.text();
  let j; try { j = JSON.parse(txt); } catch (_e) { j = { ok: false, error: txt.slice(0, 300) }; }
  return { status: r.status, j };
}

async function main() {
  const o = args(process.argv.slice(2));
  const fecha = o.fecha || hoyAR();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(fecha)) throw new Error("--fecha AAAA-MM-DD");
  const out = o.out || path.join(REPO, `reporte-quincenal-${fecha}.pdf`);
  const { chromium } = playwright();
  const proxy = process.env.HTTPS_PROXY;
  const browser = await chromium.launch(proxy ? { proxy: { server: proxy } } : {});
  const ctxOpt = { viewport: { width: 1600, height: 900 }, ...(proxy ? { ignoreHTTPSErrors: true } : {}) };
  let params;
  try {
    const r = await armarReporte(browser, ctxOpt);
    await aPdf(browser, ctxOpt, r.html, out);
    params = armarParams(r.datos, fecha);
  } finally { await browser.close(); }
  console.log("variables:", JSON.stringify(params));
  if (o.soloPdf) return;

  const oidc = await tokenOidc();
  const s = await llamar(oidc, { action: "subir", fecha });
  if (!s.j.ok) throw new Error(`subir: HTTP ${s.status} ${s.j.error || ""}`);
  const put = await fetch(s.j.signedUrl, {
    method: "PUT",
    headers: { "Content-Type": "application/pdf", "x-upsert": "true", apikey: LK_PUBLISHABLE },
    body: fs.readFileSync(out),
  });
  if (!put.ok) throw new Error(`subida del PDF: HTTP ${put.status} ${(await put.text()).slice(0, 200)}`);
  const e = await llamar(oidc, { action: "enviar", fecha, params, forzar: o.forzar });
  console.log("envío:", JSON.stringify(e.j));
  if (!e.j.ok) throw new Error(`enviar: HTTP ${e.status} ${e.j.error || ""}`);
}

if (require.main === module) {
  main().catch((e) => { console.error("✗", e.message || e); process.exit(1); });
} else {
  module.exports = { armarParams };
}
