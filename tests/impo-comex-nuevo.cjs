/* v29.18 (Elías, 09/10) — IMPO COMEX nuevo, sin build (impocomex/).
   Corre la pantalla de verdad en Chromium, servida por http (los módulos ES no cargan desde file://),
   con la sesión de Gestión y la puerta Impo_Comex_web falsas (sin red):
   A. abre, verifica la sesión y dibuja el inicio con los 10 modos;
   B. entra a CADA modo (11, vencimientos incluido) sin errores de página ni de consola y con contenido;
   C. la lógica de parseo ORIGINAL anda en el navegador desde impocomex/logica + vendor:
      PDF con texto (pdf.js + worker), Excel (xlsx), .zip (fflate), .rar (unrar.wasm), código de barras
      EAN-13 (zxing) y la plantilla del Word;
   D. la DDJJ recibe el controlante desde la puerta (no está en el código).
   Sale 1 si falla. SHOTS=<dir> guarda una captura por modo. */
const fs = require("fs");
const path = require("path");
const http = require("http");
const zlib = require("zlib");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const RAIZ = path.join(__dirname, "..");
const PAGINA = `<!doctype html><html><head><meta charset="utf-8"><title>ic</title>
<script>window.APP_VERSION = "prueba";
window.sb = { auth: { getSession: async () => ({ data: { session: { access_token: "tok" } } }) }, rpc: async () => ({ data: true }) };</script>
</head><body><script src="impocomex/ic-base.js"></script></body></html>`;
const TIPOS = { ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css", ".json": "application/json",
  ".wasm": "application/wasm", ".docx": "application/octet-stream", ".html": "text/html" };

// .rar (RAR 4, sin comprimir) armado a mano: un archivo "carp/a.pdf" adentro.
function rar4(nombre, datos) {
  const crc = (b) => zlib.crc32(b) >>> 0;
  const u16 = (n) => { const b = Buffer.alloc(2); b.writeUInt16LE(n); return b; };
  const u32 = (n) => { const b = Buffer.alloc(4); b.writeUInt32LE(n >>> 0); return b; };
  const marca = Buffer.from([0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x00]);
  const arcCuerpo = Buffer.concat([Buffer.from([0x73]), u16(0), u16(13), u16(0), u32(0)]);
  const arc = Buffer.concat([u16(crc(arcCuerpo) & 0xffff), arcCuerpo]);
  const nom = Buffer.from(nombre, "latin1");
  const fCuerpo = Buffer.concat([Buffer.from([0x74]), u16(0x8000), u16(32 + nom.length), u32(datos.length), u32(datos.length),
    Buffer.from([0]), u32(crc(datos)), u32(0x5a210000), Buffer.from([20, 0x30]), u16(nom.length), u32(0x20), nom]);
  const fh = Buffer.concat([u16(crc(fCuerpo) & 0xffff), fCuerpo]);
  const fin = Buffer.from([0xc4, 0x3d, 0x7b, 0x00, 0x40, 0x07, 0x00]);
  return Buffer.concat([marca, arc, fh, datos, fin]);
}

function respuestaFalsa(url, metodo, cuerpo) {
  const u = new URL(url); const p = u.pathname.replace(/^.*\/Impo_Comex_web/, "");
  let body = {};
  try { body = cuerpo ? JSON.parse(cuerpo) : {}; } catch (_e) { body = {}; }
  if (p === "/datos-ddjj") return { controlante: { denominacion: "CONTROLANTE PRUEBA", apellido: "X", domicilio: "Y", cuit: "20000000001" } };
  if (p === "/editar") {
    if (body.accion === "cargas_hoy" || body.accion === "cargas_lista") return { data: [] };
    return { data: [] };
  }
  if (p.startsWith("/inal-certificados")) return { certificados: [], productos: [], articulos: [] };
  if (p === "/verify-cajas") {
    if (body.accion === "cuit_entidades_listar") return { importadores: [], comercializadores: [] };
    if (body.accion === "corridas_listar") return { corridas: [] };
    return {};
  }
  if (p === "/autorizacion-envases") return { empresas: [] };
  return {};
}

(async () => {
  const srv = http.createServer((req, res) => {
    const u = decodeURIComponent(req.url.split("?")[0]);
    if (u === "/" || u === "/__ic.html") { res.writeHead(200, { "content-type": "text/html; charset=utf-8" }); return res.end(PAGINA); }
    const f = path.join(RAIZ, u);
    if (!f.startsWith(RAIZ) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end("no"); }
    res.writeHead(200, { "content-type": TIPOS[path.extname(f)] || "application/octet-stream" });
    fs.createReadStream(f).pipe(res);
  });
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const BASE = `http://127.0.0.1:${srv.address().port}/`;
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  const errs = [];
  p.on("pageerror", (e) => errs.push("pageerror: " + e.message));
  p.on("console", (m) => { if (m.type() === "error" && !/favicon/.test(m.text())) errs.push("console: " + m.text()); });
  const llamadas = [];
  await p.route("**/functions/v1/Impo_Comex_web/**", (route) => {
    const r = route.request();
    llamadas.push(r.method() + " " + r.url().replace(/^.*Impo_Comex_web/, ""));
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(respuestaFalsa(r.url(), r.method(), r.postData())) });
  });
  const fail = [];
  const ok = (c, m) => { if (!c) fail.push(m); };
  const SHOTS = process.env.SHOTS || "";
  try {
    await p.goto(BASE + "__ic.html", { waitUntil: "load" });
    await p.evaluate(() => window.IC.abrir());
    await p.waitForFunction(() => document.querySelectorAll("#icOv .mode-card").length > 0, null, { timeout: 15000 });
    const tarjetas = await p.evaluate(() => [...document.querySelectorAll("#icOv .mode-card")].map((c) => c.dataset.modo));
    ok(tarjetas.length === 10, "(A) el inicio no tiene los 10 modos: " + tarjetas.join(","));

    // D. el controlante llega por la puerta
    await p.waitForFunction(async () => { const m = await window.IC.mod("lib/ddjjTemplate"); return !!m.CONTROLANTE.denominacion; }, null, { timeout: 10000 }).catch(() => {});
    const ctl = await p.evaluate(async () => (await window.IC.mod("lib/ddjjTemplate")).CONTROLANTE.denominacion);
    ok(ctl === "CONTROLANTE PRUEBA", "(D) la DDJJ no recibió el controlante de la puerta: " + ctl);

    // B. cada modo
    const MODOS = ["lakout", "multidoc", "marks", "cajas", "inal", "vencimientos", "autorizacion", "estimar", "ddjj", "full", "history"];
    for (const m of MODOS) {
      const antes = errs.length;
      await p.evaluate((mm) => window.IC.ir(mm), m);
      await p.waitForFunction(() => { const el = document.getElementById("icMain"); return el && !/Abriendo…/.test(el.textContent) && el.textContent.trim().length > 20; }, null, { timeout: 15000 }).catch(() => {});
      await p.waitForTimeout(700);
      const est = await p.evaluate(() => { const el = document.getElementById("icMain"); return { txt: el ? el.textContent.trim() : "", err: el ? !!el.querySelector(".err-box") && /No está el modo|No se pudo cargar/.test(el.textContent) : true }; });
      ok(est.txt.length > 40 && !/Abriendo…/.test(est.txt), `(B) el modo ${m} no se dibujó: «${est.txt.slice(0, 80)}»`);
      ok(!est.err, `(B) el modo ${m} no cargó: «${est.txt.slice(0, 120)}»`);
      ok(errs.length === antes, `(B) el modo ${m} tiró errores: ${errs.slice(antes).join(" | ")}`);
      if (SHOTS) await p.screenshot({ path: path.join(SHOTS, `ic-${m}.png`), fullPage: false });
    }
    await p.evaluate(() => window.IC.ir("home"));

    // C. la lógica original en el navegador
    const rar = rar4("carp/a.pdf", Buffer.from("%PDF-1.4 prueba rar"));
    const r = await p.evaluate(async (rarB64) => {
      const IC = window.IC; const out = {};
      const pt = await IC.mod("pdfText");
      const PL = await IC.lib("pdf-lib");
      const doc = await PL.PDFDocument.create(); const pg = doc.addPage([600, 800]);
      const font = await doc.embedFont(PL.StandardFonts.Helvetica);
      for (let i = 0; i < 30; i++) pg.drawText(`LINEA ${i} CODIGO 437E CANTIDAD 1234 PRUEBA DE TEXTO LARGO`, { x: 20, y: 780 - i * 20, size: 10, font });
      const pdfBytes = await doc.save();
      const txt = await pt.extractText(new File([pdfBytes], "a.pdf", { type: "application/pdf" }));
      out.pdf = /437E/.test(txt) && /LINEA 29/.test(txt);
      const X = await IC.lib("xlsx");
      const wb = X.utils.book_new(); X.utils.book_append_sheet(wb, X.utils.aoa_to_sheet([["cod", "qty"], ["437E", 12]]), "Hoja1");
      const xb = X.write(wb, { type: "array", bookType: "xlsx" });
      out.xlsx = /437E,12/.test(await pt.extractXlsxText(new File([xb], "a.xlsx")));
      const XS = await IC.lib("xlsx-js-style"); out.xs = !!((XS.default || XS).utils && (XS.default || XS).writeFile);
      const ff = await IC.lib("fflate");
      const zip = ff.zipSync({ "carp/a.pdf": pdfBytes, "carp/b.txt": new Uint8Array([1]) });
      const ar = await IC.mod("archivos");
      const z = await ar.expandir([{ file: new File([zip], "x.zip") }], { accept: "application/pdf" });
      out.zip = z.archivos.length === 1 && z.archivos[0].name === "x.zip › carp › a.pdf" && z.ignorados.length === 1;
      const rb = Uint8Array.from(atob(rarB64), (c) => c.charCodeAt(0));
      const zr = await ar.expandir([{ file: new File([rb], "y.rar") }], { accept: "application/pdf" });
      out.rar = zr.archivos.length === 1 && zr.archivos[0].name === "y.rar › carp › a.pdf" ? true : JSON.stringify(zr.ignorados);
      // EAN-13 dibujado a mano → lector local (zxing)
      const ean = "7791234567898"; const L = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"];
      const G = L.map((s) => s.split("").reverse().map((c) => (c === "1" ? "0" : "1")).join(""));
      const R = L.map((s) => s.split("").map((c) => (c === "1" ? "0" : "1")).join(""));
      const PAR = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"];
      let bits = "101"; const par = PAR[+ean[0]];
      for (let i = 1; i <= 6; i++) bits += (par[i - 1] === "L" ? L : G)[+ean[i]];
      bits += "01010"; for (let i = 7; i <= 12; i++) bits += R[+ean[i]]; bits += "101";
      const cv = document.createElement("canvas"); const mod = 4; cv.width = (bits.length + 20) * mod; cv.height = 160;
      const cx = cv.getContext("2d"); cx.fillStyle = "#fff"; cx.fillRect(0, 0, cv.width, cv.height); cx.fillStyle = "#000";
      for (let i = 0; i < bits.length; i++) if (bits[i] === "1") cx.fillRect((i + 10) * mod, 10, mod, 140);
      const blob = await new Promise((okb) => cv.toBlob(okb, "image/png"));
      const bc = await IC.mod("barcodeLocal");
      out.ean = await bc.leerCodigoBarras(new File([blob], "c.png", { type: "image/png" }));
      const tpl = await fetch(IC.url("plantillas/autorizacion-envases.docx"));
      out.docx = tpl.ok && (await tpl.arrayBuffer()).byteLength > 5000;
      const dj = await IC.mod("lib/ddjjCheck"); out.ddjj = typeof dj.verificarDdjj === "function";
      const lt = await IC.mod("lakoutTramos"); out.tramos = typeof lt.unirTramos === "function";
      const cn = await IC.mod("lib/calculoNacionalizacion"); out.nac = typeof cn.calcularNacionalizacion === "function";
      return out;
    }, rar.toString("base64"));
    ok(r.pdf, "(C) pdf.js no extrajo el texto del PDF");
    ok(r.xlsx, "(C) no se leyó el Excel");
    ok(r.xs, "(C) xlsx-js-style no cargó");
    ok(r.zip, "(C) el .zip no se expandió como el original");
    ok(r.rar === true, "(C) el .rar no se expandió: " + r.rar);
    ok(r.ean === "7791234567898", "(C) el lector de código de barras no leyó el EAN-13: " + r.ean);
    ok(r.docx, "(C) no se bajó la plantilla del Word");
    ok(r.ddjj && r.tramos && r.nac, "(C) falta un módulo de lógica (ddjjCheck / lakoutTramos / calculoNacionalizacion)");
    ok(errs.length === 0, "errores en la página: " + errs.join(" | "));
    ok(llamadas.some((x) => /datos-ddjj/.test(x)), "(D) no se pidió el controlante a la puerta");
  } catch (e) {
    fail.push("excepción: " + (e && e.stack || e));
  }
  await b.close(); srv.close();
  if (fail.length) { console.error("✗ impo-comex-nuevo:\n  - " + fail.join("\n  - ")); process.exit(1); }
  console.log("✓ impo-comex-nuevo: los 11 modos abren sin errores y la lógica original (PDF, Excel, zip, rar, EAN-13, Word) anda en el navegador");
})();
