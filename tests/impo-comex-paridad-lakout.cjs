/* v29.19 — IMPO COMEX nuevo (impocomex/) se comporta IGUAL que el viejo (impo-comex/, React) en
   Verificar Lakout y en Historial y Comparador.
   Corre los flujos de punta a punta contra el NUEVO, con la puerta Impo_Comex_web falsa (sin red), y compara
   paso por paso con lo que hizo el VIEJO (grabado en tests/tools/ic-paridad-lakout.json):
     - los pedidos a la puerta (método, ruta, cuerpo JSON o campos del FormData con nombre y tamaño de archivo),
     - el texto visible del modo, los estados (botón deshabilitado, cargando, guardando) y los diálogos,
     - las descargas (nombre y bytes).
   Lakout: texto, error JSON y 502, preview, Corregir Relevamiento (buscar / toggle INAL / variante / sin match /
   cancelar / ✕), Guardar (con error y sin tabla rica), cabecera e ítems editables (editar, error, agregar, borrar,
   cancelar), Excel, duplicado, PDF chico (manda el archivo), escaneado por tramos (con y sin re-extract, re-extract
   caído), PDF de más de 150.000 caracteres, PDF roto, quitar archivo y reentrar.
   Historial: lista, comparador (con datos, vacío, sin histórico, error, encode), Excel y su error, lista vacía y caída.
   GRABAR=1 vuelve a grabar lo esperado desde el VIEJO (mientras impo-comex/ exista). Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
const http = require("http");
const crypto = require("crypto");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const RAIZ = path.join(__dirname, "..");
const ESPERADO = path.join(__dirname, "tools", "ic-paridad-lakout.json");
const GRABAR = process.env.GRABAR === "1";
const PAGINA = `<!doctype html><html><head><meta charset="utf-8"><title>ic</title>
<script>window.APP_VERSION = "prueba";
window.sb = { auth: { getSession: async () => ({ data: { session: { access_token: "tok" } } }) }, rpc: async () => ({ data: true }) };</script>
</head><body><script src="impocomex/ic-base.js"></script></body></html>`;
const TIPOS = { ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css", ".json": "application/json",
  ".wasm": "application/wasm", ".html": "text/html", ".docx": "application/octet-stream" };

// ── multipart (el FormData que sale a la puerta) ─────────────────────────────────────
function parseMultipart(buf, ct) {
  const m = /boundary=(.+)$/.exec(ct || ""); if (!m) return null;
  const b = Buffer.from("--" + m[1]);
  const out = []; let i = buf.indexOf(b);
  while (i >= 0) {
    const start = i + b.length;
    if (buf.slice(start, start + 2).toString() === "--") break;
    const next = buf.indexOf(b, start);
    const part = buf.slice(start + 2, next - 2);
    const hEnd = part.indexOf("\r\n\r\n");
    const head = part.slice(0, hEnd).toString();
    const body = part.slice(hEnd + 4);
    const name = (/name="([^"]*)"/.exec(head) || [])[1];
    const fn = /filename="([^"]*)"/.exec(head);
    const t = (/Content-Type: (.+)/i.exec(head) || [])[1];
    if (fn) out.push([name, { archivo: fn[1], tipo: (t || "").trim(), bytes: body.length }]);
    else out.push([name, body.toString()]);
    i = next;
  }
  return out;
}
// Strings largos (el texto del PDF) se comparan por huella.
const corto = (v) => (typeof v === "string" && v.length > 1500 ? `md5:${crypto.createHash("md5").update(v).digest("hex")}:${v.length}` : v);
function compactar(r) {
  return { m: r.m, p: r.p, q: r.q, form: r.form ? r.form.map(([k, v]) => [k, corto(v)]) : null, json: r.json, auth: r.auth };
}

// ── puerta falsa (las mismas respuestas en el viejo y en el nuevo) ─────────────────────
const XLSX_BYTES = Buffer.from("PK\u0003\u0004 excel falso de la carga 77 · ñ", "utf8");
function nuevaPuerta() {
  const st = { esc: "preview", reqs: [], demora: 0 };
  st.responder = (p, q, form, json) => {
    const J = (body, status = 200) => ({ status, body: JSON.stringify(body), ct: "application/json" });
    if (p === "/datos-ddjj") return J({ controlante: { denominacion: "X" } });
    if (p === "/editar") {
      const a = json.accion;
      if (a === "cargas_hoy") return J({ data: [] });
      if (a === "cargas_lista") {
        if (st.esc === "hist_err") return J({ error: "falla lista" }, 500);
        if (st.esc === "hist_vacio") return J({ data: [] });
        return J({ data: [
          { id: 12, nro_carga: "China 48", proveedor: "OWNLAND", modo: "lakout", fecha: "2026-10-01" },
          { id: 13, nro_carga: "China <b>49</b>", proveedor: null, modo: "multidoc", fecha: null, created_at: "2026-09-30T10:11:12Z" },
          { id: 14, nro_carga: "Kangli 7", proveedor: "KANGLI", modo: "full", fecha: null, created_at: null },
        ] });
      }
      if (a === "despacho_get") return J({ data: { id: json.id, nro_despacho: "26001IC04000123X", proveedor: "OWNLAND", flete_total: 1500, seguro_total: null, valor_fob_total: 25000.5 } });
      if (a === "despacho_update") return st.esc === "edit_err" ? J({ error: "No se pudo guardar el campo" }, 500) : J({ data: { ok: true } });
      if (a === "items_list") return J({ data: [
        { id: 501, nro_item: 1, ncm: "8205.51.00.900A", descripcion: "Colador acero", cantidad: 1200, unidad: "u", valor_fob: 1450.5, valor_cif: 1500, derecho_importacion: 270, tasa_estadistica: 45, iva: 400, nro_certificado: "INAL 123" },
        { id: 502, nro_item: 2, ncm: "3924.10.00.100K", descripcion: "Espátula", cantidad: 600, unidad: "u", valor_fob: 300, valor_cif: null, derecho_importacion: null, tasa_estadistica: null, iva: null, nro_certificado: null },
      ] });
      if (a === "item_update") return st.esc === "edit_err" ? J({ error: "Item bloqueado" }, 500) : J({ data: { ok: true } });
      if (a === "item_insert") return J({ data: { id: 999, nro_item: null, descripcion: null } });
      if (a === "item_delete") return J({ data: { ok: true } });
      if (a === "productos_buscar") return J({ data: [{ id: 31, cod_lk: "437E", cod_ch: "029", marca: "LK", nombre_producto: "Colador", inal: "SI" }] });
      if (a === "producto_insert" || a === "producto_update") return J({ data: { ok: true } });
      return J({ data: null });
    }
    if (p === "/verify-lakout") {
      const f = Object.fromEntries(form || []);
      if (st.esc === "error") return J({ error: "Proveedor no reconocido en el PDF" }, 500);
      if (st.esc === "error_txt") return { status: 502, body: "Bad gateway <html>", ct: "text/html" };
      if (f.chunk_index != null) {
        const rex = /re-extract/.test(f.chunk_pages_desc || "");
        if (rex && st.esc === "rex_err") return J({ error: "rex falló" }, 500);
        if (rex) return J({ data: { flete_total: 900, seguro_total: 45, cotiz_dolar: 0, otro: 1 }, costo_usd: 0.011 });
        const i = +f.chunk_index;
        if (i === 0 && st.esc === "cab_ok") return J({ data: { proveedor: "KANGLI", flete_total: 10, seguro_total: 2, valor_cif_total: 99, items: [] }, costo_usd: 0.02 });
        if (i === 0) return J({ data: { proveedor: "OWNLAND", nro_despacho: "26001IC0400", flete_total: 0, items: [{ codigo: "437E", ncm: "8205.51.00.900A", descripcion: "Colador", cantidad: 100, valor_fob: 50 }] }, costo_usd: 0.05 });
        return J({ data: { bl: { numero: "BL1" }, items: [{ codigo: "580", ncm: "3924.10.00.100K", descripcion: "Pinza", cantidad: 20, valor_fob: 10.25 }] }, costo_usd: 0.07 });
      }
      const base = {
        nro_carga: f.nro_carga, proveedor: "OWNLAND", nro_despacho: "26001IC04000123X", items_count: 2, costo_usd: 0.1234,
        data: { proveedor: "OWNLAND", items: [
          { nro_item: 1, subitem_nro: 2, codigo: "437E", ncm: "8205.51.00.900A", descripcion: "Colador <acero> & co", cantidad: 1200, valor_fob: 1450.5, nro_certificado: "INAL 123" },
          { nro: 7, codigo: null, ncm: null, descripcion: null, cantidad: true, valor_fob: "12" },
          { cantidad: 0 },
        ] },
        alertas: [
          { severidad: "critica", tipo: "codigo_no_relevamiento", descripcion: "Codigo 437E (LK) no está en el relevamiento" },
          { severidad: "importante", tipo: "codigo_pre_split_e", descripcion: "Item 580: pre split" },
          { severidad: "menor", tipo: "otra", descripcion: "Flete <alto>" },
          { severidad: "info", tipo: "marca_mismatch_relevamiento", descripcion: '"809E" (CHEF) marca distinta' },
        ],
        advertencias: [{ tipo: "x", descripcion: "Revisar la página 3" }],
      };
      if (f.pre_merged === "true" && f.preview !== "true") {
        return J(Object.assign({}, base, { carga_id: 77, despacho_id: 55, extraccion_incompleta: true, alertas: [], advertencias: [] }));
      }
      if (st.esc === "dup") return J(Object.assign({}, base, { duplicado: true, iguales: false, mensaje: "Ya existe la carga China 48", carga_id: 70,
        diferencias: [{ campo: "flete_total", antes: 100, ahora: null }, { campo: "proveedor", antes: null, ahora: "OWN<b>" }] }));
      if (st.esc === "dup_igual") return J(Object.assign({}, base, { duplicado: true, iguales: true, mensaje: "Sin cambios", carga_id: 70, preview: true }));
      if (st.esc === "sin_costo") return J({ nro_carga: f.nro_carga, preview: true, data: { items: [] } });
      return J(Object.assign({}, base, { preview: true }));
    }
    if (p === "/export-excel") {
      if (q.get("format") === "json" && st.esc === "rich_err") return J({ error: "sin tabla" }, 500);
      if (q.get("format") === "json") return J({ rows: [
        { "Código": "437E", "Descripción LK": "Colador acero inoxidable", "FOB USD": 1450.5, "Cant": 1200, "Obs": null, "CIF": 12, "Nota": "" },
        { "Código": "580", "Descripción LK": null, "FOB USD": "n/d", "Cant": 0, "Obs": "ok", "CIF": 3.333, "Nota": "x" },
      ] });
      if (q.get("carga_id") === "13") return J({ error: "No hay despacho para esa carga" }, 404);
      return { status: 200, body: XLSX_BYTES, ct: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" };
    }
    if (p === "/compare-historical") {
      const c = q.get("codigo");
      if (c === "ERR") return J({ error: "Falló la comparación" }, 500);
      if (c === "NADA") return J({ apariciones: 0, cargas: [] });
      if (c === "VACIO") return J({});
      if (c === "SINCARGAS") return J({ apariciones: 1, precio_promedio: 2, precio_min: null, precio_max: 3, uni_master_promedio: null });
      return J({ apariciones: 2, precio_promedio: 1.2345, precio_min: 1, precio_max: 1.469, uni_master_promedio: 48,
        cargas: [{ nro_carga: "China 48", fecha: "2026-09-01", precio: 1, cantidad: 1200, uni_master: 48, cbm_caja: 0.05 },
          { nro_carga: "China <49>", fecha: null, precio: null, cantidad: null, uni_master: null, cbm_caja: null }] });
    }
    return J({});
  };
  return st;
}

async function abrir(browser, base, cual, st) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, acceptDownloads: true });
  const page = await ctx.newPage();
  page.errs = [];
  page.on("pageerror", (e) => page.errs.push("pageerror: " + e.message));
  page.on("console", (m) => { if (m.type() === "error" && !/favicon|Failed to load resource|historial:/.test(m.text())) page.errs.push("console: " + m.text()); });
  await page.route("**/functions/v1/Impo_Comex_web/**", async (route) => {
    const r = route.request();
    const u = new URL(r.url());
    const p = u.pathname.replace(/^.*\/Impo_Comex_web/, "");
    const ct = r.headers()["content-type"] || "";
    let form = null, json = {};
    const buf = r.postDataBuffer();
    if (buf && /multipart/.test(ct)) form = parseMultipart(buf, ct);
    else if (buf) { try { json = JSON.parse(buf.toString()); } catch (_e) { json = { _raw: buf.toString() }; } }
    if (p !== "/datos-ddjj" && !(p === "/editar" && json.accion === "cargas_hoy"))
      st.reqs.push(compactar({ m: r.method(), p, q: u.search, form, json: buf && !form ? json : undefined, auth: r.headers().authorization ? "si" : "no" }));
    const res = st.responder(p, u.searchParams, form, json);
    if (st.demora && p === "/verify-lakout") await new Promise((ok) => setTimeout(ok, st.demora));
    await route.fulfill({ status: res.status, body: res.body, contentType: res.ct });
  });
  await page.route("**/rest/v1/rpc/es_supervisor_virgilio", (route) => route.fulfill({ status: 200, contentType: "application/json", body: "true" }));
  await page.route("**/auth/v1/**", (route) => route.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  if (cual === "viejo") {
    const ses = { access_token: "tok", refresh_token: "ref", expires_at: Math.floor(Date.now() / 1000) + 36000, expires_in: 36000, token_type: "bearer", user: { id: "u1", aud: "authenticated", email: "x@y.z" } };
    await page.addInitScript((s) => localStorage.setItem("sb-hrxfctzncixxqmpfhskv-auth-token", s), JSON.stringify(ses));
    await page.goto(base + "impo-comex/", { waitUntil: "load" });
  } else {
    await page.goto(base + "__ic.html", { waitUntil: "load" });
    await page.evaluate(() => window.IC.abrir());
  }
  await page.waitForSelector(".mode-card", { timeout: 20000 });
  return page;
}

const norm = (s) => String(s || "").replace(/\s+/g, " ").trim();
async function textoModo(page, cual) {
  return norm(await page.evaluate((c) => {
    if (c === "viejo") {
      const a = document.querySelector(".app"); if (!a || !a.children[1]) return "";
      // el modal de Corregir Relevamiento vive adentro del modo en React; en el nuevo cuelga de #icOv
      const fijo = [...a.children[1].querySelectorAll("div")].find((d) => d.style.position === "fixed");
      if (fijo) { fijo.style.display = "none"; const t = a.children[1].innerText; fijo.style.display = ""; return t; }
      return a.children[1].innerText;
    }
    const m = document.getElementById("icMain"); return m ? m.innerText : "";
  }, cual));
}
async function dialogo(page) {
  const d = page.locator("[role=dialog],[role=alertdialog]").first();
  if (!(await d.count())) return null;
  return norm(await d.innerText());
}
async function cerrarDialogo(page, aceptar = true) {
  const d = page.locator("[role=dialog],[role=alertdialog]").first();
  await d.waitFor({ timeout: 5000 });
  const t = norm(await d.innerText());
  const btns = d.locator("button");
  const n = await btns.count();
  await btns.nth(aceptar ? n - 1 : 0).click();
  await page.waitForTimeout(120);
  return t;
}
const btn = (page, txt) => page.locator("button", { hasText: txt }).first();
const esperar = (page, fn, arg, ms = 15000) => page.waitForFunction(fn, arg, { timeout: ms });
async function quieto(page, st) { let n = -1; for (let i = 0; i < 40; i++) { if (st.reqs.length === n) break; n = st.reqs.length; await page.waitForTimeout(150); } }
function grabador(page, st, cual) {
  const log = []; let idx = 0;
  const snap = async (paso, extra) => {
    await quieto(page, st);
    const reqs = st.reqs.slice(idx); idx = st.reqs.length;
    log.push({ paso, texto: await textoModo(page, cual), reqs, extra: extra === undefined ? null : extra, dlg: await dialogo(page) });
  };
  return { log, snap };
}

async function fixtures(browser, base) {
  const st = nuevaPuerta();
  const page = await abrir(browser, base, "nuevo", st);
  const r = await page.evaluate(async () => {
    const PL = await window.IC.lib("pdf-lib");
    const b64 = (u8) => { let s = ""; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000)); return btoa(s); };
    async function pdf(paginas, lineas, texto) {
      const doc = await PL.PDFDocument.create(); doc.setCreationDate(new Date(0)); doc.setModificationDate(new Date(0));
      const font = await doc.embedFont(PL.StandardFonts.Helvetica);
      for (let p = 0; p < paginas; p++) {
        const pg = doc.addPage([600, 850]);
        if (!lineas) { pg.drawRectangle({ x: 50, y: 50, width: 200, height: 200 }); continue; }
        for (let i = 0; i < lineas; i++) pg.drawText(texto(p, i), { x: 10, y: 830 - i * 13, size: 7, font });
      }
      return b64(await doc.save({ useObjectStreams: false }));
    }
    return {
      texto: await pdf(1, 15, (p, i) => `DESPACHO 26001IC04 ITEM ${i} CODIGO 437E NCM 8205.51.00.900A FOB 1450.50`),
      chico: await pdf(1, 5, (p, i) => `LINEA ${i} CODIGO 580 PINZA CHICA CANTIDAD 20 FOB 10.25`),
      scan: await pdf(7, 0),
      grande: await pdf(36, 62, (p, i) => `P${p} L${i} TEXTO LARGO DEL LAKOUT PARA PASAR EL MAXIMO 0123456789 ABCDEFGHIJ`),
    };
  });
  await page.context().close();
  return r;
}
const PDF = (fx, k, nombre) => ({ name: nombre, mimeType: "application/pdf", buffer: Buffer.from(fx[k], "base64") });

// ── LAKOUT ───────────────────────────────────────────────────────────────────────────
async function flujoLakout(browser, base, cual, fx) {
  const st = nuevaPuerta();
  const page = await abrir(browser, base, cual, st);
  const { log, snap } = grabador(page, st, cual);
  const NRO = 'input[placeholder="ej. China 48"]';
  const run = btn(page, "Analizar Despacho");
  const runBtn = page.locator("button", { hasText: /Analizar Despacho|Procesando/ }).first();
  const esperarFin = async () => { await esperar(page, () => ![...document.querySelectorAll("button")].some((b) => /Procesando\.\.\./.test(b.textContent))); await page.waitForTimeout(150); };
  const subir = async (f) => {
    await page.locator("input[type=file]:not([webkitdirectory])").first().setInputFiles(f);
    await esperar(page, (n) => [...document.querySelectorAll(".files-list span")].some((s) => s.textContent === n), f.name);
  };
  const analizar = async (esc) => { st.esc = esc; await run.click(); await esperarFin(); await page.waitForTimeout(150); };
  const modal = () => page.locator("h3", { hasText: "📝 Corregir Relevamiento" }).locator("xpath=..").locator("xpath=..");
  const hayModal = () => page.locator("h3", { hasText: "📝 Corregir Relevamiento" }).count();
  const editar = async (loc, valor) => { const h = await loc.elementHandle(); await h.fill(valor); await h.evaluate((e) => e.blur()); await page.waitForTimeout(450); };

  await page.locator(".mode-card", { hasText: "Verificar Lakout" }).click();
  await page.waitForSelector(NRO);
  await snap("abrir", { dis: await run.isDisabled() });
  await page.fill(NRO, "China 48");
  await snap("nro sin archivo", { dis: await run.isDisabled() });
  await subir(PDF(fx, "texto", "lakout china 48.pdf"));
  await snap("con archivo", { dis: await run.isDisabled() });
  await page.fill(NRO, "   ");
  await snap("nro en blanco", { dis: await run.isDisabled() });
  await page.fill(NRO, "China 48");
  await btn(page, "Ver PDF").click(); await page.waitForTimeout(600);
  await snap("ver pdf", { visor: await page.locator("text=Despacho subido").count(), iframes: (await page.locator("iframe, embed, object, canvas").count()) > 0 });
  await btn(page, "Ocultar PDF").click(); await page.waitForTimeout(150);
  await snap("ocultar pdf");

  await analizar("error"); await snap("error json");
  await analizar("error_txt"); await snap("error 502 texto");

  st.esc = "preview"; st.demora = 1200; await run.click(); await page.waitForTimeout(350);
  const cargTxt = await textoModo(page, cual); st.demora = 0;
  await snap("cargando", { modo: cargTxt, txt: norm(await runBtn.textContent()), dis: await runBtn.isDisabled() });
  await esperarFin(); await snap("preview");

  // Corregir Relevamiento
  const corr = page.locator("button", { hasText: "Corregir Relevamiento" });
  await snap("nro botones corregir", { n: await corr.count() });
  await corr.nth(0).click(); await page.waitForTimeout(150);
  await snap("modal abierto", { m: norm(await modal().innerText()) });
  await modal().locator("button", { hasText: "Buscar en relevamiento" }).click(); await page.waitForTimeout(250);
  await snap("modal buscar", { m: norm(await modal().innerText()) });
  await modal().locator("select").first().selectOption("toggle_inal"); await page.waitForTimeout(120);
  await snap("modal toggle", { m: norm(await modal().innerText()) });
  await modal().locator("button", { hasText: "Guardar y volver" }).click(); await page.waitForTimeout(250);
  const av1 = await cerrarDialogo(page);
  await snap("modal guardado", { av: av1, modal: await hayModal() });
  await corr.nth(1).click(); await page.waitForTimeout(150);
  await snap("modal 2", { m: norm(await modal().innerText()), sel: await modal().locator("select").first().inputValue() });
  await modal().locator('input[placeholder^="OWNLAND"]').fill("KANGLI");
  await modal().locator("select").nth(2).selectOption("SI");
  await modal().locator("select").nth(1).selectOption("CH");
  await modal().locator("button", { hasText: "Guardar y volver" }).click(); await page.waitForTimeout(250);
  await snap("modal 2 guardado", { av: await cerrarDialogo(page) });
  await corr.nth(2).click(); await page.waitForTimeout(150);
  await modal().locator("select").first().selectOption("actualizar_marca");
  await modal().locator("button", { hasText: "Guardar y volver" }).click(); await page.waitForTimeout(250);
  await snap("modal 3 sin match", { av: await cerrarDialogo(page), sigue: await hayModal() });
  await modal().locator("button", { hasText: "Cancelar" }).click(); await page.waitForTimeout(120);
  await snap("modal 3 cancelado", { modal: await hayModal() });
  await corr.nth(0).click(); await page.waitForTimeout(120);
  await modal().locator("button", { hasText: "✕" }).first().click(); await page.waitForTimeout(120);
  await snap("modal cruz", { modal: await hayModal() });

  // Guardar en DB
  st.esc = "error"; await btn(page, "Guardar en DB").click(); await page.waitForTimeout(400);
  await snap("guardar error", { dis: await btn(page, "Guardar en DB").isDisabled() });
  st.esc = "preview"; st.demora = 1200;
  await btn(page, "Guardar en DB").click();
  const gb = page.locator("button", { hasText: /Guardando|Guardar en DB/ }).first();
  await page.waitForTimeout(300);
  const gtxt = norm(await gb.textContent()), gdis = await gb.isDisabled();
  st.demora = 0;
  await snap("guardando", { txt: gtxt, dis: gdis });
  await esperar(page, () => /Guardado — Carga/.test(document.body.innerText));
  await esperar(page, () => /Vista enriquecida/.test(document.body.innerText));
  await page.waitForTimeout(300);
  await snap("guardado");

  // cabecera
  await btn(page, "Mostrar/editar campos").click();
  await esperar(page, () => /Editá cualquier campo/.test(document.body.innerText));
  await snap("cabecera");
  await editar(page.locator("label", { hasText: /^Seguro/ }).locator("xpath=following-sibling::*[1]"), "45.5");
  await snap("cabecera editada");
  await page.waitForTimeout(1600);
  await snap("cabecera ✓ se va");
  await btn(page, "Ocultar editor").click(); await page.waitForTimeout(150);
  await btn(page, "Mostrar/editar campos").click(); await page.waitForTimeout(450);
  await snap("cabecera reabierta");
  await btn(page, "Ocultar editor").click(); await page.waitForTimeout(150);
  // errores al editar
  st.esc = "edit_err";
  await btn(page, "Mostrar/editar campos").click(); await page.waitForTimeout(450);
  await editar(page.locator("label", { hasText: /^Flete/ }).locator("xpath=following-sibling::*[1]"), "1600");
  await snap("cabecera error", { av: await cerrarDialogo(page) });
  await btn(page, "Ocultar editor").click(); await page.waitForTimeout(150);
  await editar(page.locator('input[title="Colador acero"]').first(), "Colador X");
  await snap("item error", { av: await cerrarDialogo(page) });
  st.esc = "preview";
  // ítems
  await editar(page.locator('input[title="Espátula"]').first(), "Espátula silicona");
  await snap("item editado");
  await btn(page, "+ Agregar fila").click(); await page.waitForTimeout(450);
  await snap("item agregado");
  const borrar = page.locator("button", { hasText: "🗑" });
  await borrar.nth(0).click();
  await snap("confirmar borrar", { d: await cerrarDialogo(page, false) });
  await borrar.nth(1).click();
  await snap("confirmar borrar 2", { d: await cerrarDialogo(page, true) });
  await page.waitForTimeout(350);
  await snap("item borrado");

  // Excel
  const [dl] = await Promise.all([page.waitForEvent("download"), btn(page, "Descargar Excel").click()]);
  await snap("excel", { nombre: dl.suggestedFilename(), igual: fs.readFileSync(await dl.path()).equals(XLSX_BYTES) });

  await analizar("dup"); await snap("duplicado");
  await analizar("dup_igual"); await snap("duplicado igual");
  await analizar("sin_costo"); await snap("sin costo");

  st.esc = "preview";
  await subir(PDF(fx, "chico", "chico.pdf"));
  await snap("reemplazo archivo");
  await analizar("preview"); await snap("chico");
  await subir(PDF(fx, "scan", "scan 7p.pdf"));
  await analizar("preview"); await snap("scan");
  await analizar("rex_err"); await snap("scan rex falla");
  await analizar("cab_ok"); await snap("scan sin rex");
  st.esc = "rich_err"; await btn(page, "Guardar en DB").click();
  await esperar(page, () => /Guardado — Carga/.test(document.body.innerText)); await page.waitForTimeout(450);
  await snap("guardado sin tabla rica");
  await subir(PDF(fx, "grande", "grande.pdf"));
  await analizar("preview"); await snap("grande");
  await subir({ name: "roto.pdf", mimeType: "application/pdf", buffer: Buffer.from("esto no es un pdf") });
  await analizar("preview"); await snap("roto");
  await page.locator('.files-list button[title="Quitar"]').first().click(); await page.waitForTimeout(150);
  await snap("quitado", { dis: await run.isDisabled() });
  await btn(page, "← Inicio").click(); await page.waitForTimeout(150);
  await page.locator(".mode-card", { hasText: "Verificar Lakout" }).click();
  await page.waitForSelector(NRO);
  await snap("reentrada", { nro: await page.inputValue(NRO) });

  const errs = page.errs.slice();
  await page.context().close();
  return { log, errs };
}

// ── HISTORIAL ────────────────────────────────────────────────────────────────────────
async function flujoHistory(browser, base, cual) {
  const st = nuevaPuerta();
  const page = await abrir(browser, base, cual, st);
  const { log, snap } = grabador(page, st, cual);
  const PROV = 'input[placeholder="OWNLAND"]', COD = 'input[placeholder="574E"]';
  const entrar = async () => { await page.locator(".mode-card", { hasText: "Historial y Comparador" }).click(); await page.waitForSelector(COD); await esperar(page, () => !/Cargando\.\.\./.test(document.body.innerText)); };
  const buscar = btn(page, "Buscar");
  const comparar = async (cod, paso) => { await page.fill(COD, cod); await buscar.click(); await page.waitForTimeout(300); await snap(paso); };
  await entrar();
  await snap("abrir", { dis: await buscar.isDisabled() });
  await page.fill(PROV, "OWNLAND");
  await snap("solo prov", { dis: await buscar.isDisabled() });
  await page.fill(COD, "574E");
  await snap("prov+cod", { dis: await buscar.isDisabled() });
  await buscar.click(); await page.waitForTimeout(300); await snap("comparar");
  await comparar("NADA", "sin historico");
  await comparar("VACIO", "respuesta vacía");
  await comparar("SINCARGAS", "sin cargas");
  await comparar("ERR", "error");
  await page.fill(PROV, "OWN LAND+"); await comparar("5 7/4&E", "encode");
  await page.fill(PROV, ""); await snap("prov vacío", { dis: await buscar.isDisabled() });
  const ex = page.locator("button", { hasText: "📥 Excel" });
  const [dl] = await Promise.all([page.waitForEvent("download"), ex.nth(0).click()]);
  await snap("excel", { nombre: dl.suggestedFilename(), igual: fs.readFileSync(await dl.path()).equals(XLSX_BYTES) });
  await ex.nth(1).click(); await page.waitForTimeout(300);
  await snap("excel error", { av: await cerrarDialogo(page) });
  await btn(page, "← Inicio").click(); st.esc = "hist_vacio"; await entrar(); await snap("vacia");
  await btn(page, "← Inicio").click(); st.esc = "hist_err"; await entrar(); await snap("lista error");
  const errs = page.errs.slice();
  await page.context().close();
  return { log, errs };
}

// Los tramos del PDF escaneado los arma pdf-lib en el momento (con la fecha de hoy adentro): el tamaño puede
// variar en uno o dos bytes entre corridas. Se tolera ±32 bytes en los archivos; todo lo demás, exacto.
function mismosPedidos(a, b) {
  if (a.length !== b.length) return false;
  const sacar = (l) => l.map((q) => JSON.stringify(q, (k, v) => (v && typeof v === "object" && "archivo" in v ? Object.assign({}, v, { bytes: 0 }) : v)));
  const bytes = (l) => { const r = []; JSON.stringify(l, (k, v) => { if (v && typeof v === "object" && "archivo" in v) r.push(v.bytes); return v; }); return r; };
  const sa = sacar(a), sb = sacar(b);
  const ordenOk = sa.every((x, i) => x === sb[i]);
  // Los pedidos que salen juntos (sin await en el medio) pueden llegar en otro orden: se comparan como conjunto.
  if (!ordenOk && JSON.stringify([...sa].sort()) !== JSON.stringify([...sb].sort())) return false;
  const ba = bytes(a).sort((x, y) => x - y), bb = bytes(b).sort((x, y) => x - y);
  return ba.length === bb.length && ba.every((x, i) => Math.abs(x - bb[i]) <= 32);
}
function comparar(nombre, esperado, real) {
  const fail = [];
  const n = Math.max(esperado.length, real.length);
  for (let i = 0; i < n; i++) {
    const x = esperado[i], y = real[i];
    if (!x || !y) { fail.push(`${nombre} #${i}: falta el paso «${(x || y).paso}»`); continue; }
    const t = `${nombre} [${x.paso}]`;
    if (x.paso !== y.paso) { fail.push(`${t}: el paso no coincide (${y.paso})`); continue; }
    if (x.texto !== y.texto) fail.push(`${t} TEXTO\n   viejo: ${x.texto}\n   nuevo: ${y.texto}`);
    if (!mismosPedidos(x.reqs, y.reqs))
      fail.push(`${t} PEDIDOS\n   viejo: ${JSON.stringify(x.reqs)}\n   nuevo: ${JSON.stringify(y.reqs)}`);
    if (JSON.stringify(x.extra) !== JSON.stringify(y.extra)) fail.push(`${t} ESTADO\n   viejo: ${JSON.stringify(x.extra)}\n   nuevo: ${JSON.stringify(y.extra)}`);
    if (x.dlg !== y.dlg) fail.push(`${t} DIÁLOGO\n   viejo: ${x.dlg}\n   nuevo: ${y.dlg}`);
  }
  return fail;
}

(async () => {
  const t0 = Date.now();
  const srv = http.createServer((req, res) => {
    const u = decodeURIComponent(req.url.split("?")[0]);
    if (u === "/__ic.html") { res.writeHead(200, { "content-type": "text/html; charset=utf-8" }); return res.end(PAGINA); }
    let f = path.join(RAIZ, u);
    if (f.startsWith(RAIZ) && fs.existsSync(f) && fs.statSync(f).isDirectory()) f = path.join(f, "index.html");
    if (!f.startsWith(RAIZ) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end("no"); }
    res.writeHead(200, { "content-type": TIPOS[path.extname(f)] || "application/octet-stream" });
    fs.createReadStream(f).pipe(res);
  });
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = `http://127.0.0.1:${srv.address().port}/`;
  const browser = await chromium.launch();
  const fail = [];
  try {
    const fx = await fixtures(browser, base);
    if (GRABAR) {
      const lk = await flujoLakout(browser, base, "viejo", fx);
      const hi = await flujoHistory(browser, base, "viejo");
      if (lk.errs.length || hi.errs.length) throw new Error("el viejo tiró errores: " + lk.errs.concat(hi.errs).join(" | "));
      fs.writeFileSync(ESPERADO, JSON.stringify({ grabado: "viejo impo-comex/ (React)", lakout: lk.log, history: hi.log }, null, 1) + "\n");
      console.log(`grabado ${ESPERADO}: lakout ${lk.log.length} pasos, historial ${hi.log.length}`);
    }
    const esp = JSON.parse(fs.readFileSync(ESPERADO, "utf8"));
    const [lk, hi] = [await flujoLakout(browser, base, "nuevo", fx), await flujoHistory(browser, base, "nuevo")];
    fail.push(...comparar("lakout", esp.lakout, lk.log));
    fail.push(...comparar("historial", esp.history, hi.log));
    if (lk.errs.length) fail.push("lakout: errores de página: " + lk.errs.join(" | "));
    if (hi.errs.length) fail.push("historial: errores de página: " + hi.errs.join(" | "));
  } catch (e) {
    fail.push("excepción: " + (e && e.stack || e));
  } finally {
    await browser.close();
    srv.close();
  }
  const seg = ((Date.now() - t0) / 1000).toFixed(1);
  if (fail.length) { console.log(`FALLA paridad lakout/historial (${seg} s):\n- ` + fail.join("\n- ")); process.exit(1); }
  console.log(`OK paridad lakout + historial con el viejo (${seg} s)`);
})();
