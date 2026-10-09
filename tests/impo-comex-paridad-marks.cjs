/* IMPO COMEX nuevo (impocomex/, sin build) — PARIDAD con el viejo (impo-comex/, React) en tres modos:
     📦 Analizar Shipping Marks (ic-marks.js) · 💵 Estimar Nacionalización (ic-estimar.js) · 🏦 DDJJ al Banco (ic-ddjj.js)
   Hace los flujos de punta a punta (subir archivos reales, analizar, errores de la puerta, editar, tildar, cambiar de caso,
   quitar archivos) y compara, paso a paso: el texto de la pantalla, los botones (y si están deshabilitados), los errores,
   los campos, el color de las filas, el visor de PDF, los diálogos y CADA pedido a la puerta Impo_Comex_web (método, ruta,
   cuerpo JSON completo; en FormData los campos, los valores y los archivos con nombre, tamaño y tipo).
   Lo esperado (EXPECTED, abajo) salió de correr los MISMOS pasos sobre el VIEJO.
     node tests/impo-comex-paridad-marks.cjs                  → corre el NUEVO contra lo esperado (rápido, sin red)
     PARIDAD_VIEJO=1 node tests/impo-comex-paridad-marks.cjs  → corre también el VIEJO y compara los dos en vivo
     PARIDAD_GRABAR=1 node tests/impo-comex-paridad-marks.cjs → vuelve a grabar EXPECTED desde el VIEJO (reescribe este archivo)
   La puerta es falsa (route) y el controlante de la DDJJ es FICTICIO: este repo es público. Sale 1 si falla. */
const fs = require("fs");
const os = require("os");
const path = require("path");
const http = require("http");
const zlib = require("zlib");
const crypto = require("crypto");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const RAIZ = path.join(__dirname, "..");
const VIEJO = !!process.env.PARIDAD_VIEJO || !!process.env.PARIDAD_GRABAR;
const GRABAR = !!process.env.PARIDAD_GRABAR;
const AHORA = new Date(2026, 9, 9, 12, 0, 0);      // reloj fijo: la DDJJ usa la fecha de hoy como fecha de firma
const PAGINA_NUEVO = `<!doctype html><html><head><meta charset="utf-8"><title>ic</title>
<script>window.APP_VERSION = "prueba";
window.sb = { auth: { getSession: async () => ({ data: { session: { access_token: "tok" } } }) }, rpc: async () => ({ data: true }) };</script>
</head><body><script src="impocomex/ic-base.js"></script></body></html>`;
const TIPOS = { ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css", ".json": "application/json",
  ".wasm": "application/wasm", ".html": "text/html", ".docx": "application/octet-stream" };
const b64u = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const SESION = { access_token: `${b64u({ alg: "HS256", typ: "JWT" })}.${b64u({ sub: "u1", role: "authenticated", exp: 4102444800 })}.sig`,
  refresh_token: "r", token_type: "bearer", expires_in: 3600, expires_at: 4102444800,
  user: { id: "u1", email: "sup@prueba.test", aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {} } };
const CONTROL = { denominacion: "CONTROLANTE FICTICIO SA", apellido: "FICTICIO", domicilio: "Calle Falsa 123", cuit: "20-00000000-1" };
const REPORTE = "## Verificación\n\n- **931E**: caja OK, *For* coincide\n- 932: falta el código impreso\n\n| Código | Estado |\n|---|---|\n| 931E | ✓ |\n| 932 | ⚠ |\n\n<script>alert(1)</script>";

// ── archivos de prueba (reales: Excel con xlsx, PDF con pdf-lib, PNG a mano) ──────────────────────────
async function fixtures(dir) {
  const imp = (p) => import("file://" + path.join(RAIZ, p));
  const XLSX = await imp("impocomex/vendor/xlsx.mjs");
  const { PDFDocument, StandardFonts } = await imp("impocomex/vendor/pdf-lib.js");
  const { ANCLAS } = await imp("impocomex/logica/lib/ddjjTemplate.js");
  const xl = (aoa, f) => { const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(aoa), "S1");
    fs.writeFileSync(path.join(dir, f), XLSX.write(wb, { type: "buffer", bookType: "xlsx" })); };
  xl([
    ["INNER BOX MARK", "MASTER BOX MARK"],
    ["Garlic Press (red handle) / prensa ajo"],
    ["Inner Qty: 12 PCS Product code: 931E", "For: LOEKEMEYER / PRODUCT CODE: 931E QUANTITY: 48 PCS G.W: 10KG"],
    ["Peeler Swivel"],
    ["Inner Qty: 6 Product code: 932", "For: NTL CARGO / PRODUCT CODE: 932 QUANTITY: 1,200"],
    ["Pizza Cutter"],
    ["Inner Qty: 6 Product code：933", "For: LOEKEMEYER QUANTITY: 36"],
    ["Made in China"],
    ["Can Opener Deluxe Model Extra Long Name"],
    ["Inner Qty: 10 Product code: 940", "For: LOEKEMEYER QUANTITY: 60"],
    ["Inner Qty: 10 Product code: ABC", "For: LOEKEMEYER QUANTITY: 60"],
  ], "sm.xlsx");
  xl([["Nada", "que"], ["ver", "aca"]], "sm_vacio.xlsx");
  xl([
    ["PROFORMA INVOICE"], ["BUYER:", "", "LOEKEMEYER"],
    ["Product Code", "Product Name", "Qty/Inner", "Qty / Outer", "Price"],
    ["931", "Garlic Press", 12, "48 pcs", 1.2], ["932E", "Peeler swivel", 6, 1200, 0.5], ["933", "Knife", 6, 24, 0.9],
    ["950", "Strainer", 10, 30, 2], ["xx", "basura", 1, 1, 1], ["TOTAL", "", "", "", ""], ["960", "despues del total", 1, 1, 1],
  ], "pi.xlsx");
  fs.writeFileSync(path.join(dir, "pi.csv"), "BUYER: LOEKEMEYER SA\n\nitem 931E Garlic US$ 1.20 100 48\nitem 932 Peeler US$ 0.50 50 1200\nitem 945A Grater US$2.00 10 20\n");
  async function pdf(paginas, f) {
    const d = await PDFDocument.create(); const fo = await d.embedFont(StandardFonts.Helvetica);
    const ok = (s) => [...s].map((ch) => { try { fo.encodeText(ch); return ch; } catch (_e) { return "?"; } }).join("");
    for (const lineas of paginas) {
      const p = d.addPage([600, 850]); let y = 820;
      for (const l0 of lineas) {
        const out = []; let cur = "";
        for (const w of ok(l0).split(" ")) { if ((cur + " " + w).length > 95) { out.push(cur); cur = w; } else cur = cur ? cur + " " + w : w; }
        if (cur) out.push(cur);
        for (const l of out) { if (y < 20) break; p.drawText(l, { x: 20, y, size: 9, font: fo }); y -= 12; }
      }
    }
    fs.writeFileSync(path.join(dir, f), await d.save());
  }
  await pdf([["PROFORMA INVOICE NO. PI-2026-77", "Buyer: LOEKEMEYER", "Address: Pje Falso 123 CABA", "Item 931E Garlic press US$ 1.20 100 48",
    "Item 932 Peeler US$ 0.50 50 1200", "Item 945A Grater US$ 2.00 10 20", "Total US$ 1000.00",
    "Terms: FOB Ningbo. Payment 30% deposit 70% before shipment. Packing: export carton. Shipping marks as per buyer instructions. Delivery 45 days."]], "pi.pdf");
  const porPag = {}; for (const a of ANCLAS) (porPag[a.pag] = porPag[a.pag] || []).push(a.txt);
  const pags = [];
  for (let i = 1; i <= 6; i++) {
    const l = [];
    if (i === 1) l.push("Formulario 20320-4 (13/04/2026)", "Lugar: Buenos Aires Fecha: 01/10/2026", "Solicitud de transferencia al exterior de fecha 01/10/2026 por el importe de USD 14.000,00 a favor del beneficiario.");
    if (i === 2) l.push("Posicion arancelaria 8205.51.00.300Z USD 14.000,00");
    if (i === 5) l.push(`Denominacion ${CONTROL.denominacion} Apellido ${CONTROL.apellido} Domicilio ${CONTROL.domicilio} CUIT ${CONTROL.cuit}`);
    l.push(...(porPag[i] || []).slice(0, i === 3 ? 4 : 99));   // la página 3 a medias: frases clave que no aparecen
    pags.push(l);
  }
  await pdf(pags, "ddjj.pdf");
  await pdf([["DDJJ corta"]], "ddjj_corta.pdf");
  await pdf([["COMMERCIAL INVOICE", "Invoice No.: CI-2026-77", "Date: 20/09/2026", "Consignee: CHEF SRL CUIT 30-00000000-1",
    "Item 931E Garlic press 100 pcs US$ 1.20 120.00", "TOTAL USD 14,000.00",
    "Payment terms: T/T. Port of loading Ningbo, port of discharge Buenos Aires. Country of origin China. Marks and numbers as per packing list."]], "ci.pdf");
  xl([["ITEM NO.", "DESCRIPTION", "T.QTY", "UNIT PRICE", "AMOUNT"], ["931E", "Garlic press", 1000, 2, 2000], ["932", "Peeler swivel", 500, 1.5, ""],
    ["", "Sin codigo", 10, 3, 30], ["940", "Sin cantidad", "", 3, 30], [" 950 ", "  Strainer  ", "200", "4", "800"]], "est.xlsx");
  xl([["CODE", "NAME"], ["1", "x"]], "est_vacio.xlsx");
  const png = (r, g, b) => {
    const ch = (t, d) => { const len = Buffer.alloc(4); len.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(zlib.crc32(td) >>> 0); return Buffer.concat([len, td, c]); };
    const ih = Buffer.alloc(13); ih.writeUInt32BE(2, 0); ih.writeUInt32BE(2, 4); ih[8] = 8; ih[9] = 2;
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), ch("IHDR", ih), ch("IDAT", zlib.deflateSync(Buffer.from([0, r, g, b, r, g, b, 0, r, g, b, r, g, b]))), ch("IEND", Buffer.alloc(0))]);
  };
  fs.writeFileSync(path.join(dir, "m1.png"), png(255, 0, 0)); fs.writeFileSync(path.join(dir, "m2.png"), png(0, 255, 0)); fs.writeFileSync(path.join(dir, "i1.png"), png(0, 0, 255));
}

// ── abrir el viejo o el nuevo en un modo, con la puerta falsa ────────────────────────────────────────
function multipart(buf, ct) {
  const m = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(ct || ""); if (!m) return null;
  const bnd = Buffer.from("--" + (m[1] || m[2])); const partes = []; let i = buf.indexOf(bnd);
  while (i >= 0) {
    const j = buf.indexOf(bnd, i + bnd.length); if (j < 0) break;
    const parte = buf.slice(i + bnd.length + 2, j - 2); const sep = parte.indexOf("\r\n\r\n");
    const head = parte.slice(0, sep).toString("utf8");
    const name = (/name="([^"]*)"/.exec(head) || [])[1]; const fn = /filename="([^"]*)"/.exec(head);
    partes.push(fn ? { name, filename: fn[1] } : { name, value: parte.slice(sep + 4).toString("utf8") });
    i = j;
  }
  return partes;
}

async function abrir(b, kind, BASE, titulo, resp) {
  const ctx = await b.newContext({ viewport: { width: 1400, height: 900 } });
  const page = await ctx.newPage();
  await page.clock.setFixedTime(AHORA);
  const errs = [];
  page.on("pageerror", (e) => errs.push("pageerror: " + e.message));
  page.on("console", (m) => { if (m.type() === "error" && !/favicon|Failed to load resource/.test(m.text())) errs.push("console: " + m.text()); });
  // Playwright no trae el contenido de los archivos de un FormData: se miran desde la página (tamaño + huella)
  await page.addInitScript(() => {
    window.__icFd = [];
    const f0 = window.fetch;
    window.fetch = async function (url, op) {
      if (/Impo_Comex_web/.test(String(url)) && op && op.body instanceof FormData) {
        const ent = [];
        for (const [k, v] of op.body.entries()) {
          if (v instanceof Blob) {
            const h = await crypto.subtle.digest("SHA-1", await v.arrayBuffer());
            ent.push({ name: k, filename: v.name, size: v.size, type: v.type, sha: [...new Uint8Array(h)].slice(0, 6).map((x) => x.toString(16).padStart(2, "0")).join("") });
          } else ent.push({ name: k, value: String(v) });
        }
        window.__icFd.push(ent);
      }
      return f0.apply(this, arguments);
    };
  });
  const log = [];
  await page.route("**/functions/v1/Impo_Comex_web/**", async (route) => {
    const r = route.request(); const p = r.url().replace(/^.*Impo_Comex_web/, "");
    const ct = (await r.allHeaders())["content-type"] || ""; const raw = r.postDataBuffer();
    let body = null;
    if (raw) { if (/multipart/.test(ct)) body = { multipart: multipart(raw, ct) }; else { try { body = JSON.parse(raw.toString("utf8")); } catch (_e) { body = raw.toString("utf8"); } } }
    log.push({ method: r.method(), path: p, body });
    const out = await resp(p, body);
    route.fulfill({ status: out.status || 200, contentType: out.ct || "application/json", body: out.raw != null ? out.raw : JSON.stringify(out.json ?? {}) });
  });
  let ROOT;
  if (kind === "viejo") {
    await page.addInitScript((s) => { localStorage.setItem("sb-hrxfctzncixxqmpfhskv-auth-token", JSON.stringify(s)); }, SESION);
    await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(SESION.user) }));
    await page.route("**/rest/v1/rpc/es_supervisor_virgilio", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "true" }));
    await page.goto(BASE + "impo-comex/", { waitUntil: "load" });
    ROOT = "#root .app > .header + div";
  } else {
    await page.goto(BASE + "__ic.html", { waitUntil: "load" });
    await page.evaluate(() => window.IC.abrir());
    ROOT = "#icMain";
  }
  await page.waitForSelector(".mode-card", { timeout: 20000 });
  await page.waitForTimeout(300);
  const datosAntes = log.filter((x) => x.path === "/datos-ddjj").length;
  log.length = 0;
  await page.locator(".mode-card", { has: page.locator(`h3:text-is("${titulo}")`) }).first().click();
  await page.waitForFunction((R) => { const el = document.querySelector(R); return el && el.textContent.trim().length > 20 && !/Abriendo…/.test(el.textContent); }, ROOT, { timeout: 20000 });
  await page.waitForTimeout(150);
  const root = page.locator(ROOT).first();
  const norm = (s) => String(s || "").replace(/\s+/g, " ").trim();
  const A = {
    page, root, log, errs, ROOT, datosAntes, cerrar: () => ctx.close(),
    texto: async () => norm(await root.innerText()),
    async snap() {
      return page.evaluate((R) => {
        const el = document.querySelector(R); const n = (s) => String(s || "").replace(/\s+/g, " ").trim();
        return {
          text: n(el.innerText),
          btns: [...el.querySelectorAll("button")].filter((x) => x.offsetParent).map((x) => (x.disabled ? "[x]" : "") + n(x.innerText)),
          errs: [...el.querySelectorAll(".err-box")].map((e) => n(e.innerText)),
          inputs: [...el.querySelectorAll("input:not([type=file]),select")].map((i) => (i.type === "checkbox" ? (i.checked ? "☑" : "☐") : String(i.value))),
          iframes: el.querySelectorAll("iframe").length,
          trbg: [...el.querySelectorAll("tbody tr")].map((t) => getComputedStyle(t).backgroundColor).join(","),
          fd: window.__icFd.splice(0),
        };
      }, ROOT);
    },
    async archivos(zona, rutas) {
      await root.locator(".zone").nth(zona).locator("input[type=file]").first().setInputFiles(rutas);
      await page.waitForFunction(([R, z]) => { const zz = document.querySelectorAll(R + " .zone")[z]; return zz && !/Abriendo archivos/.test(zz.textContent); }, [ROOT, zona]);
      await page.waitForTimeout(120);
    },
    async quitar(zona, i) { await root.locator(".zone").nth(zona).locator(".files-list .f button").nth(i).click(); await page.waitForTimeout(80); },
    async boton(re) { await root.locator("button").filter({ hasText: re }).first().click(); },
    async esperar(fn) { await page.waitForFunction(fn, ROOT, { timeout: 20000 }); await page.waitForTimeout(120); },
    async quieto(ms = 300) {
      let prev = "", igual = 0;
      for (let k = 0; k < 150; k++) { const t = await A.texto(); if (t === prev) { if (++igual * 80 >= ms) return; } else { igual = 0; prev = t; } await page.waitForTimeout(80); }
    },
    async dialogo() { const d = page.locator("[role=dialog],[role=alertdialog]").first(); return (await d.count()) ? norm(await d.innerText()) : null; },
  };
  return A;
}

// ── escenarios: los MISMOS pasos en el viejo y el nuevo ─────────────────────────────────────────────
function puerta(c) {
  return async (p, body) => {
    if (p === "/datos-ddjj") return { json: { controlante: CONTROL } };
    if (p === "/editar") return { json: { data: [] } };
    if (c.pausa) { const pz = c.pausa; c.pausa = null; await pz; }
    return c.r ? c.r(p, body) : { json: {} };
  };
}
function colgar(c) { let soltar; c.pausa = new Promise((r) => { soltar = r; }); return () => soltar(); }   // ver el estado "cargando"

const ESC = {
  marks: {
    titulo: "Analizar Shipping Marks",
    async run(A, rec, c, f) {
      await rec("inicio");
      await A.archivos(0, [f("sm.xlsx")]); await rec("sm subido");
      await A.boton(/Analizar/); await A.quieto(); await rec("sin PI ni fotos");
      await A.archivos(1, [f("pi.xlsx")]); await A.boton(/Analizar/); await A.quieto(); await rec("PI excel");
      await A.quitar(1, 0); await rec("PI quitada");
      await A.archivos(1, [f("pi.pdf")]); await A.boton(/Analizar/); await A.quieto(500); await rec("PI pdf");
      await A.quitar(1, 0); await A.archivos(1, [f("pi.csv")]); await A.boton(/Analizar/); await A.quieto(); await rec("PI csv");
      await A.archivos(2, [f("m1.png"), f("m2.png")]); await A.archivos(3, [f("i1.png")]);
      await A.root.locator("select").first().selectOption("FCL"); await rec("fotos + FCL");
      c.r = (p) => (p === "/verify-marks" ? { json: { reporte: REPORTE, modelo: "gpt-prueba", costo_usd: 0.01234, duracion_ms: 4567 } } : { json: {} });
      const sol = colgar(c);
      await A.boton(/Analizar/); await A.esperar((R) => /Analizando fotos con IA/.test(document.querySelector(R).innerText)); await rec("cargando IA");
      sol(); await A.esperar((R) => /Verificación de fotos/.test(document.querySelector(R).innerText)); await A.quieto(); await rec("IA ok");
      c.r = (p) => (p === "/verify-marks" ? { status: 500, json: { error: "La IA no respondió" } } : { json: {} });
      await A.boton(/Analizar/); await A.quieto(); await rec("IA error {error}");
      c.r = () => ({ status: 502, ct: "text/plain", raw: "Bad gateway" });
      await A.boton(/Analizar/); await A.quieto(); await rec("IA error 502 texto");
      c.r = () => ({ json: {} });
      await A.boton(/Analizar/); await A.quieto(); await rec("IA sin reporte");
      await A.quitar(2, 1); await A.quitar(1, 0); await rec("quitar foto y PI");
      c.r = () => ({ json: { reporte: "solo fotos", modelo: "m2", costo_usd: "0.5", duracion_ms: 10 } });
      await A.root.locator("select").first().selectOption("LCL");
      await A.boton(/Analizar/); await A.quieto(); await rec("solo fotos sin PI");
      await A.quitar(0, 0); await rec("sin SM");
      await A.archivos(0, [f("sm_vacio.xlsx")]); await A.boton(/Analizar/); await A.quieto(); await rec("SM vacio");
    },
  },
  estimar: {
    titulo: "Estimar Nacionalización",
    async run(A, rec, c, f) {
      const NCM = [["8205.51.00.300Z", 0.95, "codigo"], ["", 0.42, "llm"], ["7323.93.00.910T", 0.81, "fuzzy"], [null, null, null]];
      c.r = (p, body) => (p === "/ncm-detect"
        ? { json: { items: (body.items || []).map((it, i) => Object.assign({}, it, { ncm: NCM[i % 4][0], ncm_confidence: NCM[i % 4][1], ncm_capa: NCM[i % 4][2] })) } }
        : { json: {} });
      await rec("inicio");
      await A.archivos(0, [f("est.xlsx")]); await rec("archivo");
      const sol = colgar(c);
      await A.boton(/Calcular/); await A.esperar((R) => /Detectando NCM/.test(document.querySelector(R).innerText)); await rec("cargando");
      sol(); await A.esperar((R) => /Resultado —/.test(document.querySelector(R).innerText)); await A.quieto(); await rec("resultado");
      const ncm = A.root.locator("table input").nth(1);
      await ncm.click(); await ncm.fill(""); await ncm.pressSequentially("7323.93.00.910T"); await A.quieto(); await rec("ncm editado");
      const cot = A.root.locator("input[type=number]").nth(0);
      await cot.fill(""); await A.quieto(); await rec("cotiz vacía");
      await cot.pressSequentially("1000"); await A.quieto(); await rec("cotiz 1000");
      await A.root.locator("select").nth(0).selectOption("N"); await A.quieto(); await rec("iibb N");
      await A.root.locator("select").nth(0).selectOption("E"); await A.quieto(); await rec("iibb E");
      await A.root.locator("select").nth(1).selectOption("AVION"); await A.quieto(); await rec("modo avion");
      const cbm = A.root.locator("input[type=number]").nth(1);
      await cbm.fill("3.5"); await A.quieto(); await rec("cbm 3.5");
      await cbm.fill(""); await cbm.pressSequentially("2.25"); await A.quieto(); await rec("cbm tipeado 2.25");
      await A.boton(/Calcular/); await A.quieto(); await rec("recalcular (pisa ncm y cbm)");
      await A.archivos(0, [f("est_vacio.xlsx")]); await A.boton(/Calcular/); await A.quieto(); await rec("excel sin items");
      await A.archivos(0, [f("est.xlsx")]);
      c.r = () => ({ status: 500, json: { error: "NCM caído" } });
      await A.boton(/Calcular/); await A.quieto(); await rec("error {error}");
      c.r = () => ({ status: 401, json: { codigo: "no_supervisor" } });
      await A.boton(/Calcular/); await A.quieto(); await rec("error no_supervisor");
      c.r = () => ({ json: {} });
      await A.boton(/Calcular/); await A.quieto(); await rec("respuesta sin items");
      await A.archivos(0, [f("pi.pdf")]); await rec("pdf ignorado por accept");
      await A.quitar(0, 0); await rec("quitado");
    },
  },
  ddjj: {
    titulo: "Declaración para presentar al Banco",
    async run(A, rec, c, f) {
      const listo = (R) => /Control visual obligatorio/.test(document.querySelector(R).innerText);
      await rec("casos");
      await A.root.locator(".mode-card").filter({ hasText: "Mercaderia en transito" }).click(); await rec("transito");
      await A.archivos(0, [f("ddjj_corta.pdf")]); await rec("ddjj corta");
      await A.boton(/Verificar declaracion/); await A.quieto(); await rec("sin monto");
      const monto = A.root.locator('input[placeholder="14000"]');
      await monto.fill("abc"); await A.boton(/Verificar declaracion/); await A.quieto(); await rec("monto abc");
      await monto.fill("14.000"); await A.boton(/Verificar declaracion/); await A.quieto(1200); await rec("pdf sin texto");
      await A.quitar(0, 0); await A.archivos(0, [f("ddjj.pdf")]); await A.archivos(1, [f("ci.pdf")]); await rec("ddjj + ci");
      await A.boton(/Verificar declaracion/); await A.esperar(listo); await A.quieto(); await rec("resultado transito");
      const chk = A.root.locator("input[type=checkbox]");
      await chk.nth(0).check(); await chk.nth(2).check(); await A.quieto(); await rec("tildes");
      await A.boton(/ver detalle/); await A.quieto(); await rec("ver detalle");
      await A.boton(/ocultar detalle/); await A.quieto(); await rec("ocultar detalle");
      const n = await chk.count(); for (let i = 0; i < n; i++) await chk.nth(i).check();
      await A.quieto(); await rec("todo tildado");
      await A.root.locator("select").first().selectOption({ index: 1 }); await A.quieto(); await rec("cambio empresa (reset)");
      await A.boton(/Verificar declaracion/); await A.esperar(listo); await A.quieto(); await rec("resultado otra empresa");
      await A.root.locator('input[placeholder="dd/mm/aaaa"]').fill("01/10/2026"); await A.quieto(); await rec("fecha (reset)");
      await A.boton(/Verificar declaracion/); await A.esperar(listo); await A.quieto(); await rec("resultado con fecha");
      await A.quitar(1, 0); await rec("ci quitada (no resetea)");
      await A.boton(/Cambiar caso/); await rec("volver a casos");
      await A.root.locator(".mode-card").filter({ hasText: "Mercaderia con despacho" }).click(); await A.quieto(); await rec("despacho (archivos siguen)");
      await A.boton(/Verificar declaracion/); await A.esperar(listo); await A.quieto(); await rec("resultado despacho");
    },
  },
};

// Los textos largos se comparan por huella (el resto, entero). En el diff de PARIDAD_VIEJO se ven completos.
const huella = (s) => crypto.createHash("sha1").update(String(s)).digest("hex").slice(0, 16);
function compacto(rec) {
  const o = Object.assign({}, rec);
  if (o.text != null && o.textLen == null) { o.textLen = o.text.length; o.text = huella(o.text); }
  return o;
}

async function correr(b, kind, BASE, FX) {
  const out = {};
  for (const m of Object.keys(ESC)) {
    const c = {}; const A = await abrir(b, kind, BASE, ESC[m].titulo, puerta(c));
    const recs = []; let visto = 0;
    const rec = async (label) => {
      const sn = await A.snap();
      const req = A.log.slice(visto).filter((x) => !(x.path === "/datos-ddjj" || (x.path === "/editar" && x.body && x.body.accion === "cargas_hoy")));
      visto = A.log.length;
      // a cada FormData se le pegan los archivos vistos desde la página (nombre, tamaño, tipo, huella)
      const fds = sn.fd; delete sn.fd;
      for (const r of req) if (r.body && r.body.multipart) r.body = { formData: fds.shift() || r.body.multipart };
      recs.push(Object.assign({ label }, sn, { req, dlg: await A.dialogo() }));
    };
    try { await ESC[m].run(A, rec, c, (n) => path.join(FX, n)); }
    catch (e) { recs.push({ label: "EXCEPCION", text: String((e && e.message) || e).split("\n")[0] }); }
    recs.push({ label: "errores de página", errs: A.errs, datosDdjjAlEntrar: A.datosAntes + A.log.filter((x) => x.path === "/datos-ddjj").length > 0 });
    out[m] = recs; await A.cerrar();
  }
  return out;
}

function comparar(a, b, nomA, nomB, fail, completo) {
  for (const m of Object.keys(ESC)) {
    const x = a[m] || [], y = b[m] || [];
    if (x.length !== y.length) fail.push(`${m}: ${nomA} tiene ${x.length} pasos y ${nomB} ${y.length}`);
    for (let i = 0; i < Math.min(x.length, y.length); i++) {
      const p = completo ? x[i] : compacto(x[i]), q = completo ? y[i] : compacto(y[i]);
      for (const k of new Set([...Object.keys(p), ...Object.keys(q)])) {
        const jp = JSON.stringify(p[k]), jq = JSON.stringify(q[k]);
        if (jp !== jq) fail.push(`${m} · paso ${i} «${x[i].label}» · ${k}\n      ${nomA}: ${String(jp).slice(0, 700)}\n      ${nomB}: ${String(jq).slice(0, 700)}` +
          (k === "text" && !completo ? `\n      (texto ${nomB} completo: ${y[i].text})` : ""));
      }
    }
  }
}

(async () => {
  const FX = fs.mkdtempSync(path.join(os.tmpdir(), "icpar-"));
  await fixtures(FX);
  const srv = http.createServer((req, res) => {
    const u = decodeURIComponent(req.url.split("?")[0]);
    if (u === "/__ic.html") { res.writeHead(200, { "content-type": "text/html; charset=utf-8" }); return res.end(PAGINA_NUEVO); }
    const f = path.join(RAIZ, u.endsWith("/") ? u + "index.html" : u);
    if (!f.startsWith(RAIZ) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end("no"); }
    res.writeHead(200, { "content-type": TIPOS[path.extname(f)] || "application/octet-stream" });
    fs.createReadStream(f).pipe(res);
  });
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const BASE = `http://127.0.0.1:${srv.address().port}/`;
  const b = await chromium.launch();
  const fail = [];
  try {
    if (GRABAR) {
      const viejo = await correr(b, "viejo", BASE, FX);
      const comp = {}; for (const m of Object.keys(viejo)) comp[m] = viejo[m].map(compacto);
      const yo = fs.readFileSync(__filename, "utf8");
      // Los marcadores se arman en partes: escritos enteros acá, el reemplazo se comería el código.
      const MI = "/*EXPECTED-" + "INICIO*/", MF = "/*EXPECTED-" + "FIN*/";
      const a = yo.lastIndexOf(MI), z = yo.lastIndexOf(MF);
      if (a < 0 || z < a) throw new Error("no encuentro el bloque EXPECTED");
      fs.writeFileSync(__filename, yo.slice(0, a + MI.length) + " " + JSON.stringify(comp) + " " + yo.slice(z));
      console.log("EXPECTED grabado desde el VIEJO (" + Object.keys(comp).map((m) => `${m} ${comp[m].length}`).join(", ") + " pasos)");
    } else {
      const nuevo = await correr(b, "nuevo", BASE, FX);
      comparar(EXPECTED, nuevo, "VIEJO(grabado)", "NUEVO", fail, false);
      for (const m of Object.keys(nuevo)) {
        const e = nuevo[m].find((r) => r.label === "errores de página");
        if (e && e.errs.length) fail.push(`${m}: errores de página en el NUEVO: ${e.errs.join(" | ")}`);
      }
      if (VIEJO) comparar(await correr(b, "viejo", BASE, FX), nuevo, "VIEJO(en vivo)", "NUEVO", fail, true);
    }
  } catch (e) { fail.push("excepción: " + ((e && e.stack) || e)); }
  await b.close(); srv.close();
  fs.rmSync(FX, { recursive: true, force: true });
  if (fail.length) { console.error("✗ impo-comex-paridad-marks (marks · estimar · ddjj):\n  - " + fail.join("\n  - ")); process.exit(1); }
  if (!GRABAR) console.log(`✓ impo-comex-paridad-marks: Shipping Marks, Estimar y DDJJ se comportan igual que el viejo (pantalla, pedidos a la puerta y errores, paso a paso)${VIEJO ? " — comparado también en vivo contra el viejo" : ""}`);
})();

// Lo que hizo el VIEJO con los mismos pasos (se regraba con PARIDAD_GRABAR=1). Los textos van por huella sha1.
/* eslint-disable */
var EXPECTED = /*EXPECTED-INICIO*/ {"marks":[{"label":"inicio","text":"9cec68c36f3c0649","btns":["📁 Elegir carpeta","📁 Elegir carpeta","[x]🔍 Analizar"],"errs":[],"inputs":["LCL"],"iframes":0,"trbg":"","req":[],"dlg":null,"textLen":729},{"label":"sm subido","text":"f5b6e84c72a6f6a4","btns":["✕","📁 Elegir carpeta","📁 Elegir carpeta","🔍 Analizar"],"errs":[],"inputs":["LCL"],"iframes":0,"trbg":"","req":[],"dlg":null,"textLen":695},{"label":"sin PI ni fotos","text":"1972ce985a26a1a9","btns":["✕","📁 Elegir carpeta","📁 Elegir carpeta","🔍 Analizar"],"errs":["Subi la Proforma Invoice (para comparar) y/o fotos (para verificar cajas)."],"inputs":["LCL"],"iframes":0,"trbg":"","req":[],"dlg":null,"textLen":770},{"label":"PI excel","text":"6b23918c98065973","btns":["✕","✕","📁 Elegir carpeta","📁 Elegir carpeta","🔍 Analizar"],"errs":[],"inputs":["LCL"],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242)","req":[],"dlg":null,"textLen":1405},{"label":"PI quitada","text":"eb70c1ba54924565","btns":["✕","📁 Elegir carpeta","📁 Elegir carpeta","🔍 Analizar"],"errs":[],"inputs":["LCL"],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242)","req":[],"dlg":null,"textLen":1439},{"label":"PI pdf","text":"1723fcbd75ad34bc","btns":["✕","✕","📁 Elegir carpeta","📁 Elegir carpeta","🔍 Analizar"],"errs":[],"inputs":["LCL"],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242)","req":[],"dlg":null,"textLen":1371},{"label":"PI csv","text":"bd6172371571f0e7","btns":["✕","✕","📁 Elegir carpeta","📁 Elegir carpeta","🔍 Analizar"],"errs":[],"inputs":["LCL"],"iframes":0,"trbg":"rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242)","req":[],"dlg":null,"textLen":1447},{"label":"fotos + FCL","text":"ba6dcbecb07c05ba","btns":["✕","✕","📁 Elegir carpeta","✕","✕","📁 Elegir carpeta","✕","🔍 Analizar"],"errs":[],"inputs":["FCL"],"iframes":0,"trbg":"rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242)","req":[],"dlg":null,"textLen":1387},{"label":"cargando IA","text":"0c6048942af6ce9c","btns":["✕","✕","📁 Elegir carpeta","✕","✕","📁 Elegir carpeta","✕","[x]Analizando fotos con IA..."],"errs":[],"inputs":["FCL"],"iframes":0,"trbg":"rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242)","req":[{"method":"POST","path":"/verify-marks","body":{"formData":[{"name":"tipo_envio","value":"FCL"},{"name":"articulos","value":"[{\"documento\":\"sm.xlsx\",\"contenido\":\"[\\n {\\n  \\\"code\\\": \\\"931E\\\",\\n  \\\"name\\\": \\\"Garlic Press (red handle)\\\",\\n  \\\"forName\\\": \\\"LOEKEMEYER\\\",\\n  \\\"quantity\\\": 48\\n },\\n {\\n  \\\"code\\\": \\\"932\\\",\\n  \\\"name\\\": \\\"Peeler Swivel\\\",\\n  \\\"forName\\\": \\\"NTL CARGO\\\",\\n  \\\"quantity\\\": 1200\\n },\\n {\\n  \\\"code\\\": \\\"933\\\",\\n  \\\"name\\\": \\\"Pizza Cutter\\\",\\n  \\\"forName\\\": \\\"LOEKEMEYER QUANTITY: 36\\\",\\n  \\\"quantity\\\": 36\\n },\\n {\\n  \\\"code\\\": \\\"940\\\",\\n  \\\"name\\\": \\\"Can Opener Deluxe Model Extra Long Name\\\",\\n  \\\"forName\\\": \\\"LOEKEMEYER QUANTITY: 60\\\",\\n  \\\"quantity\\\": 60\\n }\\n]\"},{\"documento\":\"pi.csv\",\"contenido\":\"BUYER: LOEKEMEYER SA\\n\\nitem 931E Garlic US$ 1.20 100 48\\nitem 932 Peeler US$ 0.50 50 1200\\nitem 945A Grater US$2.00 10 20\\n\"}]"},{"name":"photos_TODOS_master","filename":"m1.png","size":74,"type":"image/png","sha":"19aa1b781130"},{"name":"photos_TODOS_master","filename":"m2.png","size":72,"type":"image/png","sha":"8193600e22db"},{"name":"photos_TODOS_inner","filename":"i1.png","size":72,"type":"image/png","sha":"5c3997201702"}]}}],"dlg":null,"textLen":1402},{"label":"IA ok","text":"960937fe4eddb58f","btns":["✕","✕","📁 Elegir carpeta","✕","✕","📁 Elegir carpeta","✕","🔍 Analizar"],"errs":[],"inputs":["FCL"],"iframes":0,"trbg":"rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0)","req":[],"dlg":null,"textLen":1573},{"label":"IA error {error}","text":"70045f3040e8381b","btns":["✕","✕","📁 Elegir carpeta","✕","✕","📁 Elegir carpeta","✕","🔍 Analizar"],"errs":["La IA no respondió"],"inputs":["FCL"],"iframes":0,"trbg":"rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242)","req":[{"method":"POST","path":"/verify-marks","body":{"formData":[{"name":"tipo_envio","value":"FCL"},{"name":"articulos","value":"[{\"documento\":\"sm.xlsx\",\"contenido\":\"[\\n {\\n  \\\"code\\\": \\\"931E\\\",\\n  \\\"name\\\": \\\"Garlic Press (red handle)\\\",\\n  \\\"forName\\\": \\\"LOEKEMEYER\\\",\\n  \\\"quantity\\\": 48\\n },\\n {\\n  \\\"code\\\": \\\"932\\\",\\n  \\\"name\\\": \\\"Peeler Swivel\\\",\\n  \\\"forName\\\": \\\"NTL CARGO\\\",\\n  \\\"quantity\\\": 1200\\n },\\n {\\n  \\\"code\\\": \\\"933\\\",\\n  \\\"name\\\": \\\"Pizza Cutter\\\",\\n  \\\"forName\\\": \\\"LOEKEMEYER QUANTITY: 36\\\",\\n  \\\"quantity\\\": 36\\n },\\n {\\n  \\\"code\\\": \\\"940\\\",\\n  \\\"name\\\": \\\"Can Opener Deluxe Model Extra Long Name\\\",\\n  \\\"forName\\\": \\\"LOEKEMEYER QUANTITY: 60\\\",\\n  \\\"quantity\\\": 60\\n }\\n]\"},{\"documento\":\"pi.csv\",\"contenido\":\"BUYER: LOEKEMEYER SA\\n\\nitem 931E Garlic US$ 1.20 100 48\\nitem 932 Peeler US$ 0.50 50 1200\\nitem 945A Grater US$2.00 10 20\\n\"}]"},{"name":"photos_TODOS_master","filename":"m1.png","size":74,"type":"image/png","sha":"19aa1b781130"},{"name":"photos_TODOS_master","filename":"m2.png","size":72,"type":"image/png","sha":"8193600e22db"},{"name":"photos_TODOS_inner","filename":"i1.png","size":72,"type":"image/png","sha":"5c3997201702"}]}}],"dlg":null,"textLen":1406},{"label":"IA error 502 texto","text":"247115f1d0c66dd7","btns":["✕","✕","📁 Elegir carpeta","✕","✕","📁 Elegir carpeta","✕","🔍 Analizar"],"errs":["502 Bad gateway"],"inputs":["FCL"],"iframes":0,"trbg":"rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242)","req":[{"method":"POST","path":"/verify-marks","body":{"formData":[{"name":"tipo_envio","value":"FCL"},{"name":"articulos","value":"[{\"documento\":\"sm.xlsx\",\"contenido\":\"[\\n {\\n  \\\"code\\\": \\\"931E\\\",\\n  \\\"name\\\": \\\"Garlic Press (red handle)\\\",\\n  \\\"forName\\\": \\\"LOEKEMEYER\\\",\\n  \\\"quantity\\\": 48\\n },\\n {\\n  \\\"code\\\": \\\"932\\\",\\n  \\\"name\\\": \\\"Peeler Swivel\\\",\\n  \\\"forName\\\": \\\"NTL CARGO\\\",\\n  \\\"quantity\\\": 1200\\n },\\n {\\n  \\\"code\\\": \\\"933\\\",\\n  \\\"name\\\": \\\"Pizza Cutter\\\",\\n  \\\"forName\\\": \\\"LOEKEMEYER QUANTITY: 36\\\",\\n  \\\"quantity\\\": 36\\n },\\n {\\n  \\\"code\\\": \\\"940\\\",\\n  \\\"name\\\": \\\"Can Opener Deluxe Model Extra Long Name\\\",\\n  \\\"forName\\\": \\\"LOEKEMEYER QUANTITY: 60\\\",\\n  \\\"quantity\\\": 60\\n }\\n]\"},{\"documento\":\"pi.csv\",\"contenido\":\"BUYER: LOEKEMEYER SA\\n\\nitem 931E Garlic US$ 1.20 100 48\\nitem 932 Peeler US$ 0.50 50 1200\\nitem 945A Grater US$2.00 10 20\\n\"}]"},{"name":"photos_TODOS_master","filename":"m1.png","size":74,"type":"image/png","sha":"19aa1b781130"},{"name":"photos_TODOS_master","filename":"m2.png","size":72,"type":"image/png","sha":"8193600e22db"},{"name":"photos_TODOS_inner","filename":"i1.png","size":72,"type":"image/png","sha":"5c3997201702"}]}}],"dlg":null,"textLen":1403},{"label":"IA sin reporte","text":"5d95ac26194d784d","btns":["✕","✕","📁 Elegir carpeta","✕","✕","📁 Elegir carpeta","✕","🔍 Analizar"],"errs":[],"inputs":["FCL"],"iframes":0,"trbg":"rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242)","req":[{"method":"POST","path":"/verify-marks","body":{"formData":[{"name":"tipo_envio","value":"FCL"},{"name":"articulos","value":"[{\"documento\":\"sm.xlsx\",\"contenido\":\"[\\n {\\n  \\\"code\\\": \\\"931E\\\",\\n  \\\"name\\\": \\\"Garlic Press (red handle)\\\",\\n  \\\"forName\\\": \\\"LOEKEMEYER\\\",\\n  \\\"quantity\\\": 48\\n },\\n {\\n  \\\"code\\\": \\\"932\\\",\\n  \\\"name\\\": \\\"Peeler Swivel\\\",\\n  \\\"forName\\\": \\\"NTL CARGO\\\",\\n  \\\"quantity\\\": 1200\\n },\\n {\\n  \\\"code\\\": \\\"933\\\",\\n  \\\"name\\\": \\\"Pizza Cutter\\\",\\n  \\\"forName\\\": \\\"LOEKEMEYER QUANTITY: 36\\\",\\n  \\\"quantity\\\": 36\\n },\\n {\\n  \\\"code\\\": \\\"940\\\",\\n  \\\"name\\\": \\\"Can Opener Deluxe Model Extra Long Name\\\",\\n  \\\"forName\\\": \\\"LOEKEMEYER QUANTITY: 60\\\",\\n  \\\"quantity\\\": 60\\n }\\n]\"},{\"documento\":\"pi.csv\",\"contenido\":\"BUYER: LOEKEMEYER SA\\n\\nitem 931E Garlic US$ 1.20 100 48\\nitem 932 Peeler US$ 0.50 50 1200\\nitem 945A Grater US$2.00 10 20\\n\"}]"},{"name":"photos_TODOS_master","filename":"m1.png","size":74,"type":"image/png","sha":"19aa1b781130"},{"name":"photos_TODOS_master","filename":"m2.png","size":72,"type":"image/png","sha":"8193600e22db"},{"name":"photos_TODOS_inner","filename":"i1.png","size":72,"type":"image/png","sha":"5c3997201702"}]}}],"dlg":null,"textLen":1442},{"label":"quitar foto y PI","text":"534fbe48066a507e","btns":["✕","📁 Elegir carpeta","✕","📁 Elegir carpeta","✕","🔍 Analizar"],"errs":[],"inputs":["FCL"],"iframes":0,"trbg":"rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242)","req":[],"dlg":null,"textLen":1467},{"label":"solo fotos sin PI","text":"0ce989edb3481ace","btns":["✕","📁 Elegir carpeta","✕","📁 Elegir carpeta","✕","🔍 Analizar"],"errs":[],"inputs":["LCL"],"iframes":0,"trbg":"","req":[{"method":"POST","path":"/verify-marks","body":{"formData":[{"name":"tipo_envio","value":"LCL"},{"name":"articulos","value":"[{\"documento\":\"sm.xlsx\",\"contenido\":\"[\\n {\\n  \\\"code\\\": \\\"931E\\\",\\n  \\\"name\\\": \\\"Garlic Press (red handle)\\\",\\n  \\\"forName\\\": \\\"LOEKEMEYER\\\",\\n  \\\"quantity\\\": 48\\n },\\n {\\n  \\\"code\\\": \\\"932\\\",\\n  \\\"name\\\": \\\"Peeler Swivel\\\",\\n  \\\"forName\\\": \\\"NTL CARGO\\\",\\n  \\\"quantity\\\": 1200\\n },\\n {\\n  \\\"code\\\": \\\"933\\\",\\n  \\\"name\\\": \\\"Pizza Cutter\\\",\\n  \\\"forName\\\": \\\"LOEKEMEYER QUANTITY: 36\\\",\\n  \\\"quantity\\\": 36\\n },\\n {\\n  \\\"code\\\": \\\"940\\\",\\n  \\\"name\\\": \\\"Can Opener Deluxe Model Extra Long Name\\\",\\n  \\\"forName\\\": \\\"LOEKEMEYER QUANTITY: 60\\\",\\n  \\\"quantity\\\": 60\\n }\\n]\"}]"},{"name":"photos_TODOS_master","filename":"m1.png","size":74,"type":"image/png","sha":"19aa1b781130"},{"name":"photos_TODOS_inner","filename":"i1.png","size":72,"type":"image/png","sha":"5c3997201702"}]}}],"dlg":null,"textLen":683},{"label":"sin SM","text":"15c0462bdaac16ba","btns":["📁 Elegir carpeta","✕","📁 Elegir carpeta","✕","[x]🔍 Analizar"],"errs":[],"inputs":["LCL"],"iframes":0,"trbg":"","req":[],"dlg":null,"textLen":717},{"label":"SM vacio","text":"9660b853e36ae84d","btns":["✕","📁 Elegir carpeta","✕","📁 Elegir carpeta","✕","🔍 Analizar"],"errs":["No pude leer articulos del Shipping Mark (con \"Product code\" / \"QUANTITY\")."],"inputs":["LCL"],"iframes":0,"trbg":"","req":[],"dlg":null,"textLen":707},{"label":"errores de página","errs":[],"datosDdjjAlEntrar":true}],"estimar":[{"label":"inicio","text":"93e56bebbd47e4ea","btns":["[x]🧮 Calcular nacionalización"],"errs":[],"inputs":["1450","S","LCL","0"],"iframes":0,"trbg":"","req":[],"dlg":null,"textLen":368},{"label":"archivo","text":"16ff8c030c39e22b","btns":["✕","🧮 Calcular nacionalización"],"errs":[],"inputs":["1450","S","LCL","0"],"iframes":0,"trbg":"","req":[],"dlg":null,"textLen":335},{"label":"cargando","text":"08f3c6496b4d011b","btns":["✕","[x]Detectando NCM para 4 items..."],"errs":[],"inputs":["1450","S","LCL","0"],"iframes":0,"trbg":"","req":[{"method":"POST","path":"/ncm-detect","body":{"items":[{"codigo":"931E","descripcion":"Garlic press","cantidad":1000,"precio_unitario":2,"fob":2000},{"codigo":"932","descripcion":"Peeler swivel","cantidad":500,"precio_unitario":1.5,"fob":750},{"codigo":null,"descripcion":"Sin codigo","cantidad":10,"precio_unitario":3,"fob":30},{"codigo":"950","descripcion":"Strainer","cantidad":200,"precio_unitario":4,"fob":800}]}}],"dlg":null,"textLen":338},{"label":"resultado","text":"5adb799f584fdc97","btns":["✕","🧮 Calcular nacionalización"],"errs":[],"inputs":["1450","S","LCL","1.79","8205.51.00.300Z","","7323.93.00.910T",""],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgb(255, 251, 235)","req":[],"dlg":null,"textLen":997},{"label":"ncm editado","text":"917c495d817ce260","btns":["✕","🧮 Calcular nacionalización"],"errs":[],"inputs":["1450","S","LCL","1.79","8205.51.00.300Z","7323.93.00.910T","7323.93.00.910T",""],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgb(255, 251, 235)","req":[],"dlg":null,"textLen":998},{"label":"cotiz vacía","text":"98401bf9776579ce","btns":["✕","🧮 Calcular nacionalización"],"errs":[],"inputs":["0","S","LCL","1.79","8205.51.00.300Z","7323.93.00.910T","7323.93.00.910T",""],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgb(255, 251, 235)","req":[],"dlg":null,"textLen":989},{"label":"cotiz 1000","text":"98494fc4a260f347","btns":["✕","🧮 Calcular nacionalización"],"errs":[],"inputs":["01000","S","LCL","1.79","8205.51.00.300Z","7323.93.00.910T","7323.93.00.910T",""],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgb(255, 251, 235)","req":[],"dlg":null,"textLen":997},{"label":"iibb N","text":"4af5d6df9e3d2002","btns":["✕","🧮 Calcular nacionalización"],"errs":[],"inputs":["01000","N","LCL","1.79","8205.51.00.300Z","7323.93.00.910T","7323.93.00.910T",""],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgb(255, 251, 235)","req":[],"dlg":null,"textLen":997},{"label":"iibb E","text":"4af5d6df9e3d2002","btns":["✕","🧮 Calcular nacionalización"],"errs":[],"inputs":["01000","E","LCL","1.79","8205.51.00.300Z","7323.93.00.910T","7323.93.00.910T",""],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgb(255, 251, 235)","req":[],"dlg":null,"textLen":997},{"label":"modo avion","text":"4af5d6df9e3d2002","btns":["✕","🧮 Calcular nacionalización"],"errs":[],"inputs":["01000","E","AVION","1.79","8205.51.00.300Z","7323.93.00.910T","7323.93.00.910T",""],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgb(255, 251, 235)","req":[],"dlg":null,"textLen":997},{"label":"cbm 3.5","text":"ec71ac2896cb0e40","btns":["✕","🧮 Calcular nacionalización"],"errs":[],"inputs":["01000","E","AVION","3.5","8205.51.00.300Z","7323.93.00.910T","7323.93.00.910T",""],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgb(255, 251, 235)","req":[],"dlg":null,"textLen":997},{"label":"cbm tipeado 2.25","text":"5fd40516f012d0e5","btns":["✕","🧮 Calcular nacionalización"],"errs":[],"inputs":["01000","E","AVION","02.25","8205.51.00.300Z","7323.93.00.910T","7323.93.00.910T",""],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgb(255, 251, 235)","req":[],"dlg":null,"textLen":997},{"label":"recalcular (pisa ncm y cbm)","text":"7f783145750ef529","btns":["✕","🧮 Calcular nacionalización"],"errs":[],"inputs":["01000","E","AVION","1.79","8205.51.00.300Z","","7323.93.00.910T",""],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgb(255, 251, 235)","req":[{"method":"POST","path":"/ncm-detect","body":{"items":[{"codigo":"931E","descripcion":"Garlic press","cantidad":1000,"precio_unitario":2,"fob":2000},{"codigo":"932","descripcion":"Peeler swivel","cantidad":500,"precio_unitario":1.5,"fob":750},{"codigo":null,"descripcion":"Sin codigo","cantidad":10,"precio_unitario":3,"fob":30},{"codigo":"950","descripcion":"Strainer","cantidad":200,"precio_unitario":4,"fob":800}]}}],"dlg":null,"textLen":996},{"label":"excel sin items","text":"d0e302ed7b47e993","btns":["✕","🧮 Calcular nacionalización"],"errs":["No se detectaron items en el archivo. Verifica que tenga columnas ITEM NO / DESCRIPTION / T.QTY / UNIT PRICE / AMOUNT"],"inputs":["01000","E","AVION","1.79","8205.51.00.300Z","","7323.93.00.910T",""],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgb(255, 251, 235)","req":[],"dlg":null,"textLen":1120},{"label":"error {error}","text":"9dc689184f2b641b","btns":["✕","🧮 Calcular nacionalización"],"errs":["NCM caído"],"inputs":["01000","E","AVION","1.79","8205.51.00.300Z","","7323.93.00.910T",""],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgb(255, 251, 235)","req":[{"method":"POST","path":"/ncm-detect","body":{"items":[{"codigo":"931E","descripcion":"Garlic press","cantidad":1000,"precio_unitario":2,"fob":2000},{"codigo":"932","descripcion":"Peeler swivel","cantidad":500,"precio_unitario":1.5,"fob":750},{"codigo":null,"descripcion":"Sin codigo","cantidad":10,"precio_unitario":3,"fob":30},{"codigo":"950","descripcion":"Strainer","cantidad":200,"precio_unitario":4,"fob":800}]}}],"dlg":null,"textLen":1006},{"label":"error no_supervisor","text":"f8d91c8332c7c871","btns":["✕","🧮 Calcular nacionalización"],"errs":["Sólo los supervisores de Gestión Virgilio pueden usar IMPO COMEX."],"inputs":["01000","E","AVION","1.79","8205.51.00.300Z","","7323.93.00.910T",""],"iframes":0,"trbg":"rgba(0, 0, 0, 0),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgb(255, 251, 235)","req":[{"method":"POST","path":"/ncm-detect","body":{"items":[{"codigo":"931E","descripcion":"Garlic press","cantidad":1000,"precio_unitario":2,"fob":2000},{"codigo":"932","descripcion":"Peeler swivel","cantidad":500,"precio_unitario":1.5,"fob":750},{"codigo":null,"descripcion":"Sin codigo","cantidad":10,"precio_unitario":3,"fob":30},{"codigo":"950","descripcion":"Strainer","cantidad":200,"precio_unitario":4,"fob":800}]}}],"dlg":null,"textLen":1062},{"label":"respuesta sin items","text":"16ff8c030c39e22b","btns":["✕","🧮 Calcular nacionalización"],"errs":[],"inputs":["01000","E","AVION","1"],"iframes":0,"trbg":"","req":[{"method":"POST","path":"/ncm-detect","body":{"items":[{"codigo":"931E","descripcion":"Garlic press","cantidad":1000,"precio_unitario":2,"fob":2000},{"codigo":"932","descripcion":"Peeler swivel","cantidad":500,"precio_unitario":1.5,"fob":750},{"codigo":null,"descripcion":"Sin codigo","cantidad":10,"precio_unitario":3,"fob":30},{"codigo":"950","descripcion":"Strainer","cantidad":200,"precio_unitario":4,"fob":800}]}}],"dlg":null,"textLen":335},{"label":"pdf ignorado por accept","text":"5d64cf624c6437b9","btns":["✕","🧮 Calcular nacionalización"],"errs":[],"inputs":["01000","E","AVION","1"],"iframes":0,"trbg":"","req":[],"dlg":null,"textLen":391},{"label":"quitado","text":"d4aca2e57f26674e","btns":["[x]🧮 Calcular nacionalización"],"errs":[],"inputs":["01000","E","AVION","1"],"iframes":0,"trbg":"","req":[],"dlg":null,"textLen":424},{"label":"errores de página","errs":[],"datosDdjjAlEntrar":true}],"ddjj":[{"label":"casos","text":"6c70da15c0d50577","btns":[],"errs":[],"inputs":[],"iframes":0,"trbg":"","req":[],"dlg":null,"textLen":492},{"label":"transito","text":"71fc2d817b11edd0","btns":["← Cambiar caso","[x]🔍 Verificar declaracion"],"errs":[],"inputs":["","CHEF","09/10/2026"],"iframes":0,"trbg":"","req":[],"dlg":null,"textLen":665},{"label":"ddjj corta","text":"a65309738ffda09d","btns":["← Cambiar caso","✕","🔍 Verificar declaracion"],"errs":[],"inputs":["","CHEF","09/10/2026"],"iframes":1,"trbg":"","req":[],"dlg":null,"textLen":721},{"label":"sin monto","text":"efa3b673a568d2ff","btns":["← Cambiar caso","✕","🔍 Verificar declaracion"],"errs":["Ingresa el monto a transferir en USD."],"inputs":["","CHEF","09/10/2026"],"iframes":1,"trbg":"","req":[],"dlg":null,"textLen":759},{"label":"monto abc","text":"efa3b673a568d2ff","btns":["← Cambiar caso","✕","🔍 Verificar declaracion"],"errs":["Ingresa el monto a transferir en USD."],"inputs":["abc","CHEF","09/10/2026"],"iframes":1,"trbg":"","req":[],"dlg":null,"textLen":759},{"label":"pdf sin texto","text":"4629b9363995b33e","btns":["← Cambiar caso","✕","🔍 Verificar declaracion"],"errs":["El PDF de la DDJJ no tiene capa de texto legible (escaneo sin OCR). Pasalo por OCR o verificalo a mano."],"inputs":["14.000","CHEF","09/10/2026"],"iframes":1,"trbg":"","req":[],"dlg":null,"textLen":825},{"label":"ddjj + ci","text":"0c1d8c18b59cc52d","btns":["← Cambiar caso","✕","✕","🔍 Verificar declaracion","DDJJ 20320","CI"],"errs":[],"inputs":["14.000","CHEF","09/10/2026"],"iframes":1,"trbg":"","req":[],"dlg":null,"textLen":689},{"label":"resultado transito","text":"d60f2635a480edfd","btns":["← Cambiar caso","✕","✕","🔍 Verificar declaracion","ver detalle","DDJJ 20320","CI"],"errs":[],"inputs":["14.000","CHEF","09/10/2026","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐"],"iframes":1,"trbg":"rgba(0, 0, 0, 0),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgb(254, 242, 242),rgb(254, 242, 242),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0)","req":[],"dlg":null,"textLen":5088},{"label":"tildes","text":"671befe17d2682c7","btns":["← Cambiar caso","✕","✕","🔍 Verificar declaracion","ver detalle","DDJJ 20320","CI"],"errs":[],"inputs":["14.000","CHEF","09/10/2026","☑","☐","☑","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐"],"iframes":1,"trbg":"rgba(0, 0, 0, 0),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgb(254, 242, 242),rgb(254, 242, 242),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0)","req":[],"dlg":null,"textLen":5088},{"label":"ver detalle","text":"98a276363f15201d","btns":["← Cambiar caso","✕","✕","🔍 Verificar declaracion","ocultar detalle","DDJJ 20320","CI"],"errs":[],"inputs":["14.000","CHEF","09/10/2026","☑","☐","☑","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐"],"iframes":1,"trbg":"rgba(0, 0, 0, 0),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgb(254, 242, 242),rgb(254, 242, 242),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgb(254, 242, 242),rgb(255, 251, 235),rgb(255, 251, 235),rgb(254, 242, 242),rgb(254, 242, 242),rgb(255, 251, 235),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242),rgb(254, 242, 242),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0)","req":[],"dlg":null,"textLen":12600},{"label":"ocultar detalle","text":"671befe17d2682c7","btns":["← Cambiar caso","✕","✕","🔍 Verificar declaracion","ver detalle","DDJJ 20320","CI"],"errs":[],"inputs":["14.000","CHEF","09/10/2026","☑","☐","☑","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐"],"iframes":1,"trbg":"rgba(0, 0, 0, 0),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgb(254, 242, 242),rgb(254, 242, 242),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0)","req":[],"dlg":null,"textLen":5088},{"label":"todo tildado","text":"0eca527a782c2b59","btns":["← Cambiar caso","✕","✕","🔍 Verificar declaracion","ver detalle","DDJJ 20320","CI"],"errs":[],"inputs":["14.000","CHEF","09/10/2026","☑","☑","☑","☑","☑","☑","☑","☑","☑","☑","☑","☑","☑","☑","☑","☑","☑","☑"],"iframes":1,"trbg":"rgba(0, 0, 0, 0),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgb(254, 242, 242),rgb(254, 242, 242),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0)","req":[],"dlg":null,"textLen":5089},{"label":"cambio empresa (reset)","text":"7d8bfc300f581311","btns":["← Cambiar caso","✕","✕","🔍 Verificar declaracion","DDJJ 20320","CI"],"errs":[],"inputs":["14.000","TN","09/10/2026"],"iframes":1,"trbg":"","req":[],"dlg":null,"textLen":686},{"label":"resultado otra empresa","text":"0b45b4bd6349649c","btns":["← Cambiar caso","✕","✕","🔍 Verificar declaracion","ver detalle","DDJJ 20320","CI"],"errs":[],"inputs":["14.000","TN","09/10/2026","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐"],"iframes":1,"trbg":"rgba(0, 0, 0, 0),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgb(254, 242, 242),rgb(254, 242, 242),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0)","req":[],"dlg":null,"textLen":5052},{"label":"fecha (reset)","text":"7d8bfc300f581311","btns":["← Cambiar caso","✕","✕","🔍 Verificar declaracion","DDJJ 20320","CI"],"errs":[],"inputs":["14.000","TN","01/10/2026"],"iframes":1,"trbg":"","req":[],"dlg":null,"textLen":686},{"label":"resultado con fecha","text":"1a278cf1773ed2ab","btns":["← Cambiar caso","✕","✕","🔍 Verificar declaracion","ver detalle","DDJJ 20320","CI"],"errs":[],"inputs":["14.000","TN","01/10/2026","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐"],"iframes":1,"trbg":"rgba(0, 0, 0, 0),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgb(254, 242, 242),rgb(254, 242, 242),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0)","req":[],"dlg":null,"textLen":5003},{"label":"ci quitada (no resetea)","text":"3beb02037b89e816","btns":["← Cambiar caso","✕","🔍 Verificar declaracion","ver detalle"],"errs":[],"inputs":["14.000","TN","01/10/2026","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐"],"iframes":1,"trbg":"rgba(0, 0, 0, 0),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgb(254, 242, 242),rgb(254, 242, 242),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0)","req":[],"dlg":null,"textLen":5023},{"label":"volver a casos","text":"6c70da15c0d50577","btns":[],"errs":[],"inputs":[],"iframes":0,"trbg":"","req":[],"dlg":null,"textLen":492},{"label":"despacho (archivos siguen)","text":"9e55bd9d4f8753f1","btns":["← Cambiar caso","✕","🔍 Verificar declaracion"],"errs":[],"inputs":["14.000","TN","01/10/2026"],"iframes":1,"trbg":"","req":[],"dlg":null,"textLen":502},{"label":"resultado despacho","text":"27d42da05efbc643","btns":["← Cambiar caso","✕","🔍 Verificar declaracion","ver detalle"],"errs":[],"inputs":["14.000","TN","01/10/2026","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐","☐"],"iframes":1,"trbg":"rgba(0, 0, 0, 0),rgb(254, 242, 242),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgb(255, 251, 235),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0),rgba(0, 0, 0, 0)","req":[],"dlg":null,"textLen":4491},{"label":"errores de página","errs":[],"datosDdjjAlEntrar":true}]} /*EXPECTED-FIN*/;
