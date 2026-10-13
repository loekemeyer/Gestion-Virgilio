/* IMPO COMEX nuevo (impocomex/ic-cajas.js) — PARIDAD con el viejo (CajasMode.jsx, build impo-comex/).
   Corre en Chromium los flujos de punta a punta del modo «📐 Cajas vs Packing List», con la puerta
   Impo_Comex_web falsa (sin red), y compara contra lo que hizo el VIEJO (tests/tools/ic-paridad-cajas.json):
   la secuencia de pedidos a la puerta (cuerpo JSON completo; en FormData nombres de campo, archivos, tipo y
   tamaño), el texto visible, el estado de campos y botones, los diálogos, el visor de fotos y el PDF bajado.
   Flujos: importador (elegir / guardar), comercializadores (alta, cartón +/−, borrar con confirmación,
   error de la puerta), corridas guardadas (lista, cerrar, error), PL (PDF) + CI (CSV), fotos sueltas +
   .zip + .rar con repetidas, una rota, una grande (se achica), una con EAN-13 (lector local), quitar una,
   visor, verificar (lotes de 6 en paralelo, reintento 503, fotos sin asignar), solo problemas, ver la fuente
   de cada resultado, ✎ corregir, asignar código y cara, partes crudas, revisión bien/mal + motivo,
   recalcular, guardar (dos veces), PDF, abrir corridas (con cambios pendientes, solo ver), errores al
   verificar (documentos y fotos), volver al inicio.
     node tests/impo-comex-paridad-cajas.cjs            → corre el NUEVO y compara (sale 1 si difiere)
     VIEJO=1 GRABAR=1 node tests/…                       → corre el VIEJO y graba lo esperado
     AMBOS=1 node tests/…                                → corre los dos y compara entre ellos */
const fs = require("fs");
const path = require("path");
const http = require("http");
const zlib = require("zlib");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const RAIZ = path.join(__dirname, "..");
const ESPERADO = path.join(__dirname, "tools", "ic-paridad-cajas.json");
const SUPA = "https://hrxfctzncixxqmpfhskv.supabase.co";
const PAGINA = `<!doctype html><html><head><meta charset="utf-8"><title>ic</title>
<script>window.APP_VERSION = "prueba";
window.sb = { auth: { getSession: async () => ({ data: { session: { access_token: "tok" } } }) }, rpc: async () => ({ data: true }) };</script>
</head><body><script src="impocomex/ic-base.js"></script></body></html>`;
const TIPOS = { ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css", ".json": "application/json",
  ".wasm": "application/wasm", ".docx": "application/octet-stream", ".html": "text/html" };

// ── fixtures ─────────────────────────────────────────────────────────────────────────────
function png(w, h, pix) {   // pix(x, y) → 0..255 (gris)
  const crc = (b) => zlib.crc32(b) >>> 0;
  const chunk = (t, d) => { const len = Buffer.alloc(4); len.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([len, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 0;
  const raw = Buffer.alloc((w + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w + 1)] = 0; for (let x = 0; x < w; x++) raw[y * (w + 1) + 1 + x] = pix(x, y); }
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}
const liso = (w, h, g) => png(w, h, (x, y) => (x * 7 + y * 3 + g) % 256);
function ean13Png(ean) {
  const L = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"];
  const G = L.map((s) => s.split("").reverse().map((c) => (c === "1" ? "0" : "1")).join(""));
  const R = L.map((s) => s.split("").map((c) => (c === "1" ? "0" : "1")).join(""));
  const PAR = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"];
  let bits = "101"; const par = PAR[+ean[0]];
  for (let i = 1; i <= 6; i++) bits += (par[i - 1] === "L" ? L : G)[+ean[i]];
  bits += "01010"; for (let i = 7; i <= 12; i++) bits += R[+ean[i]]; bits += "101";
  const mod = 4, W = (bits.length + 20) * mod, H = 160;
  return png(W, H, (x, y) => { const i = Math.floor(x / mod) - 10; return (y >= 10 && y < 150 && i >= 0 && i < bits.length && bits[i] === "1") ? 0 : 255; });
}
function pdfTexto(lineas) {   // PDF mínimo con Helvetica (pdf.js lo lee como texto)
  const cont = "BT /F1 9 Tf 20 800 Td 11 TL " + lineas.map((l) => `(${l.replace(/[()\\]/g, "")}) Tj T*`).join(" ") + " ET";
  const objs = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", `<< /Length ${cont.length} >>\nstream\n${cont}\nendstream`];
  let out = "%PDF-1.4\n"; const off = [];
  objs.forEach((o, i) => { off.push(out.length); out += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  const x = out.length;
  out += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n` + off.map((o) => String(o).padStart(10, "0") + " 00000 n \n").join("");
  out += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${x}\n%%EOF\n`;
  return Buffer.from(out, "latin1");
}
function zipStore(entradas) {   // .zip sin comprimir
  const crc = (b) => zlib.crc32(b) >>> 0; const partes = [], central = []; let off = 0;
  for (const [nombre, datos] of entradas) {
    const n = Buffer.from(nombre); const h = Buffer.alloc(30);
    h.writeUInt32LE(0x04034b50, 0); h.writeUInt16LE(20, 4); h.writeUInt32LE(crc(datos), 14); h.writeUInt32LE(datos.length, 18); h.writeUInt32LE(datos.length, 22); h.writeUInt16LE(n.length, 26);
    partes.push(h, n, datos);
    const c = Buffer.alloc(46); c.writeUInt32LE(0x02014b50, 0); c.writeUInt16LE(20, 4); c.writeUInt16LE(20, 6); c.writeUInt32LE(crc(datos), 16); c.writeUInt32LE(datos.length, 20); c.writeUInt32LE(datos.length, 24); c.writeUInt16LE(n.length, 28); c.writeUInt32LE(off, 42);
    central.push(c, n); off += 30 + n.length + datos.length;
  }
  const cd = Buffer.concat(central); const e = Buffer.alloc(22);
  e.writeUInt32LE(0x06054b50, 0); e.writeUInt16LE(entradas.length, 8); e.writeUInt16LE(entradas.length, 10); e.writeUInt32LE(cd.length, 12); e.writeUInt32LE(off, 16);
  return Buffer.concat([...partes, cd, e]);
}
function rar4(nombre, datos) {   // .rar (RAR 4, sin comprimir), igual que tests/impo-comex-nuevo.cjs
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
  return Buffer.concat([marca, arc, fh, datos, Buffer.from([0xc4, 0x3d, 0x7b, 0x00, 0x40, 0x07, 0x00])]);
}
const PL_PDF = pdfTexto(Array.from({ length: 14 }, (_, i) => `PACKING LIST INV 77/A ITEM ${i} CODE 437E CTNS 463 QTY 66672 GW 7176,5 NW 6482 MEAS 35x34,5x32,5`));
const CI_CSV = Buffer.from("item,qty,buyer\n437E,66672,TIERRA NATIVA SA\n838E,100,TIERRA NATIVA SA\n" + "x,1,relleno de la commercial invoice para pasar los 200 caracteres del texto\n".repeat(3));
const F = (name, buf, mimeType) => ({ name, mimeType, buffer: buf });
const FOTOS_1 = [F("437E (1).png", liso(120, 90, 10), "image/png"), F("437E (1).png", liso(110, 80, 20), "image/png"),
  F("838E dorso.png", ean13Png("7791234567898"), "image/png"), F("lateral.png", liso(100, 100, 30), "image/png"),
  F("grande 838E.png", liso(2000, 1500, 40), "image/png"), F("roto.jpg", Buffer.from("esto no es una foto"), "image/jpeg"),
  F("borrar.png", liso(60, 60, 50), "image/png")];
const FOTOS_ZIP = F("caja 505C.zip", zipStore([["fotos/505C master.png", liso(80, 80, 60)], ["fotos/leeme.txt", Buffer.from("x")]]), "application/zip");
const FOTOS_RAR = F("inner.rar", rar4("x/838E inner.png", liso(70, 70, 70)), "application/x-rar-compressed");

// ── la puerta falsa ──────────────────────────────────────────────────────────────────────
const PASOS = 56;   // pasos con foto (snap) del flujo
const PL_ITEMS = [{ cod: "437E", ctns: 463, qty: 66672, gw: 7176.5 }, { cod: "838E", ctns: 10, qty: 100 }, { cod: "505c ", ctns: 2, qty: 20 }];
const LECTURAS = {
  "437E": [{ foto: "437E (1).png", tipo: "master", caras: ["master_frente"], regiones: { codigo: [0.1, 0.1, 0.3, 0.2], numeracion: [10, 20, 30, 10] } },
    { foto: "437E (1).png (2)", tipo: "master", caras: ["master_lateral", "master_frente"], regiones: { gw_kg: [0.5, 0.5, 0.2, 0.1] } }],
  "838E": [{ foto: "838E dorso.png", tipo: "articulo_carton", caras: ["carton_dorso"], regiones: {} },
    { foto: "grande 838E.png", tipo: "articulo_carton", caras: ["carton_frente"] }],
  "505C": [{ foto: "no-subida.png", tipo: "master", caras: ["master_frente"] }],
};
const FILAS_1 = [
  { codigo: "437E", tipo_caja: "master", cara: "master_frente", campo: "codigo", resultado: "ok", valor_foto: "437E", valor_pl: "437E", foto_nombre: "437E (1).png" },
  { codigo: "437E", tipo_caja: "master", cara: "master_frente", campo: "total_cajas", resultado: "diferencia", valor_foto: "460", valor_pl: "463", detalle: "El PL dice 463 cajas", foto_nombre: "437E (1).png", grave: true },
  { codigo: "437E", tipo_caja: "master", cara: "master_lateral", campo: "peso_bruto_kg", resultado: "diferencia", valor_foto: "15", valor_pl: "15,5", dif_pct: -3.2258, calculo: "PL 7.176,5 kg / 463 = 15,5 | foto 15", foto_nombre: "437E (1).png (2)" },
  { codigo: "437E", tipo_caja: "master", cara: "master_lateral", campo: "peso_neto_kg", resultado: "ilegible", valor_foto: null, valor_pl: "14", foto_nombre: "437E (1).png (2)" },
  { codigo: "437E", tipo_caja: "inner", cara: "inner", campo: "unidades_por_inner", resultado: "falta_foto", valor_pl: "12", detalle: "No hay foto del inner" },
  { codigo: "838E", tipo_caja: "articulo_carton", cara: "carton_frente", campo: "comercializador", resultado: "sin_dato_pl", valor_foto: "LOKE", valor_pl: null, detalle: "El PL no trae comercializador", foto_nombre: "grande 838E.png" },
  { codigo: "838E", tipo_caja: "documentos", campo: "cantidad_ci", resultado: "diferencia", valor_foto: "100", valor_pl: "120", detalle: "CI 100 vs PL 120" },
  { codigo: "838E", tipo_caja: "articulo_carton", cara: "carton_dorso", campo: "codigo_barras", resultado: "ok", valor_pl: "7791234567898" },
  { codigo: "838E", tipo_caja: "master", campo: "marca", resultado: "raro" },
  { codigo: "505C", tipo_caja: "master", cara: "master_frente", campo: "codigo", resultado: "diferencia", valor_foto: "505", valor_pl: "505C", foto_nombre: "no-subida.png", detalle: "Dice 505" },
];
const SIN_ASIGNAR_1 = [
  { foto: "lateral.png", caras: [], gw_kg: 15.5, nw_kg: 14, medidas_cm: { l: 35, w: 34.5, h: 32.5 }, codigo_barras_lector: "7791234567898", nombre_articulo: "Rallador" },
  { foto: "perdida.png", caras: ["master_lateral"], numeracion_actual: 288, numeracion_total: 463, cantidad_master: 144, comercializador_nombre: "Loke" },
];
const LECTURA_1 = { pct_leidos: 80, leidos: 8, campos: 10, ilegibles: 1, pct_coinciden: 60, coinciden: 3, comparados: 5, difieren: 2 };

function nuevaPuerta() {
  const st = { imp: [{ id: "i1", cuit: "30712345678", razon_social: "TIERRA NATIVA SA" }, { id: "i2", cuit: "3071", razon_social: "CORTO SA" }],
    com: [{ id: "c1", cuit: "30598765432", razon_social: "LOEKEMEYER SRL", cartones: [{ id: "t1", carton: "LOKE" }] },
      { id: "c2", cuit: "20111111112", razon_social: "OTRA SA", cartones: [] }],
    n: 0, listar: 0, recomp: 0, revis: 0, fase: "ok", fallo503: false };
  function responder(accion, body, campos) {
    if (accion === "cuit_entidades_listar") return { importadores: st.imp, comercializadores: st.com };
    if (accion === "cuit_entidad_guardar") {
      if (body.razon_social === "FALLA SRL") return [500, { error: "CUIT duplicado" }];
      if (body.tipo === "importador") { if (!st.imp.some((x) => x.cuit === body.cuit)) st.imp.push({ id: "i" + (++st.n + 10), cuit: body.cuit, razon_social: body.razon_social }); }
      else {
        let c = st.com.find((x) => x.cuit === body.cuit);
        if (!c) { c = { id: "c" + (++st.n + 10), cuit: body.cuit, razon_social: body.razon_social, cartones: [{ id: "t" + (++st.n + 10), carton: body.razon_social.replace(/ (SRL|SA)$/, "") }] }; st.com.push(c); }
        if (body.carton) c.cartones.push({ id: "t" + (++st.n + 10), carton: body.carton });
      }
      return { ok: true };
    }
    if (accion === "cuit_carton_borrar") { st.com.forEach((c) => { c.cartones = c.cartones.filter((t) => t.id !== body.id); }); return { ok: true }; }
    if (accion === "cuit_comercializador_borrar") { st.com = st.com.filter((c) => c.id !== body.id); return { ok: true }; }
    if (accion === "corridas_listar") {
      st.listar++;
      if (st.listar === 3) return [500, "boom"];
      return { corridas: [
        { corrida_id: "1a2b3c4d5e6f", created_at: "2026-10-08T15:04:05Z", pl_ref: "INV 77/A", nro_carga: "China 52/B", razon_importador: "TIERRA NATIVA SA", ok: 2, diferencia: 4, ilegible: 1, falta_foto: 1, graves: 1, revisadas: 1, recalculable: true },
        { corrida_id: "99zz", created_at: "2026-09-01T10:00:00Z", pl_ref: null, nro_carga: null, razon_importador: null, ok: 5, diferencia: 0, ilegible: 0, falta_foto: 0, graves: 0, revisadas: 0, recalculable: false }] };
    }
    if (accion === "leer_documentos") {
      if (st.fase === "doc_error") return [400, { error: "El PL no tiene ítems" }];
      return { pl_items: PL_ITEMS, ci: { buyer: "TIERRA NATIVA SA", items: [{ cod: "437E", qty: 66672 }] }, pl_ref: "cajas/x/pl.pdf", ci_ref: "cajas/x/ci.csv",
        ctns_total: 475, avisos: ["La CI trae 2 ítems y el PL 3"], costo: 0.01 };
    }
    if (accion === "leer_fotos") {
      const nombres = campos.filter((c) => /^foto_\d+_nombre$/.test(c.name)).map((c) => c.value);
      if (st.fase === "fotos_error") return [400, { error: "foto inválida en " + nombres[0] }, nombres.includes("lateral.png") ? 0 : 1200];
      if (nombres.includes("lateral.png") && !st.fallo503) { st.fallo503 = true; return [503, "servicio no disponible"]; }
      const pista = (i) => (campos.find((c) => c.name === `foto_${i}_pista_codigo`) || {}).value || null;
      return { lecturas: nombres.map((n, i) => ({ foto: n, codigo: pista(i), caras: [] })), costo_usd: 0.002 * nombres.length,
        errores_ocr: nombres.includes("838E dorso.png") ? ["838E dorso.png: no se leyó el CUIT"] : [] };
    }
    if (accion === "comparar") {
      if (st.fase === "comparar_error") return [400, { error: "No se pudo comparar" }];
      return { corrida_id: "1a2b3c4d5e6f", guardado: true, resumen: { ok: 2, diferencia: 4, ilegible: 1, sin_dato_pl: 1, falta_foto: 1 },
        lectura: LECTURA_1, resultados: FILAS_1, lecturas: LECTURAS, sin_asignar: SIN_ASIGNAR_1, crudos: { si: [], no: [] }, crudos_auto: ["505C"],
        pl_items: PL_ITEMS, ci: body.ci, tipo_envio: body.tipo_envio, cuit_importador: body.cuit_importador, razon_importador: body.razon_importador,
        ctns_total: body.ctns_total, pl: { invoice_ref: "INV 77/A", items: 3 }, ci_resumen: { invoice_nro: "CI-9", buyer: "TIERRA NATIVA SA", items: 2 },
        costo_usd: body.costo_usd, duracion_ms: 4321, errores_ocr: body.errores_ocr, avisos: body.avisos };
    }
    if (accion === "recomparar") {
      st.recomp++;
      const filas = FILAS_1.map((f) => (f.campo === "peso_bruto_kg" ? Object.assign({}, f, { resultado: "ok", valor_foto: "15,5", dif_pct: null, calculo: null }) : f));
      return { resumen: { ok: 3, diferencia: 3, ilegible: 1, sin_dato_pl: 1, falta_foto: 1 }, lectura: Object.assign({}, LECTURA_1, { pct_coinciden: 75, difieren: 1 }),
        resultados: filas, lecturas: LECTURAS, sin_asignar: st.recomp === 1 ? SIN_ASIGNAR_1.slice(1) : [], crudos: body.crudos, crudos_auto: ["505C"],
        guardado: st.recomp !== 2, error_guardar: st.recomp === 2 ? "timeout de la base" : null };
    }
    if (accion === "revision_guardar") { st.revis++; return { guardadas: body.revisiones.length, no_encontradas: st.revis === 1 ? ["838E|master|marca"] : [] }; }
    if (accion === "corrida_abrir") {
      if (body.corrida_id === "99zz") {
        return { corrida_id: "99zz", abierta: true, pl_items: [], resumen: { ok: 1, diferencia: 1 }, tipo_envio: "LCL", pl: {},
          resultados: [{ codigo: "437E", tipo_caja: "master", cara: "master_frente", campo: "codigo", resultado: "ok", valor_foto: "437E", valor_pl: "437E", revision: "ok", motivo: "visto" },
            { codigo: "437E", tipo_caja: "master", cara: "master_frente", campo: "total_cajas", resultado: "diferencia", valor_foto: "460", valor_pl: "463", foto_nombre: "otra.png" }],
          lecturas: { "437E": [{ foto: "otra.png", tipo: "master", caras: ["master_frente"] }] }, sin_asignar: [], correcciones: [] };
      }
      return { corrida_id: "1a2b3c4d5e6f", abierta: true, resumen: { ok: 2, diferencia: 4, ilegible: 1, sin_dato_pl: 1, falta_foto: 1 }, lectura: LECTURA_1,
        resultados: FILAS_1.map((f, i) => (i === 1 ? Object.assign({}, f, { revision: "mal", motivo: "etiqueta corrida" }) : f)), lecturas: LECTURAS,
        sin_asignar: SIN_ASIGNAR_1.slice(1), crudos: { si: ["437E"], no: [] }, crudos_auto: ["505C"], pl_items: PL_ITEMS, ci: {}, tipo_envio: "FCL",
        cuit_importador: "30712345678", razon_importador: "TIERRA NATIVA SA", ctns_total: 475, pl: { invoice_ref: "INV 77/A", items: 3 },
        correcciones: [{ codigo: "437E", tipo: "master", campo: "peso_bruto_kg", cara: "master_lateral", valor: "15,5" }] };
    }
    return [400, { error: "acción desconocida " + accion }];
  }
  return { st, responder };
}

// multipart → [{ name, filename?, type?, size?, value? }]
function partirMultipart(buf, ctype) {
  const m = /boundary=([^;]+)/.exec(ctype || ""); if (!m) return [];
  const sep = Buffer.from("--" + m[1]); const out = []; let i = buf.indexOf(sep);
  while (i >= 0) {
    const j = buf.indexOf(sep, i + sep.length); if (j < 0) break;
    const parte = buf.slice(i + sep.length + 2, j - 2); const h = parte.indexOf("\r\n\r\n");
    const cab = parte.slice(0, h).toString("utf8"); const datos = parte.slice(h + 4);
    const name = (/name="([^"]*)"/.exec(cab) || [])[1]; const fn = /filename="([^"]*)"/.exec(cab);
    if (fn) out.push({ name, filename: fn[1], type: (/Content-Type: (.*)/i.exec(cab) || [])[1], size: datos.length });
    else out.push({ name, value: datos.toString("utf8") });
    i = j;
  }
  return out;
}

// ── una corrida (viejo o nuevo) ──────────────────────────────────────────────────────────
async function correr(modo, chromiumBrowser, BASE) {
  const viejo = modo === "viejo";
  const ctx = await chromiumBrowser.newContext({ viewport: { width: 1440, height: 900 }, timezoneId: "America/Argentina/Buenos_Aires", locale: "es-AR", acceptDownloads: true });
  const p = await ctx.newPage();
  await p.clock.setFixedTime(new Date("2026-10-09T13:00:00Z"));
  const errs = []; const log = []; let reqs = [];
  p.on("pageerror", (e) => errs.push("pageerror: " + e.message));
  p.on("console", (m) => { if (m.type() === "error" && !/favicon|Failed to load resource/.test(m.text())) errs.push("console: " + m.text()); });
  const puerta = nuevaPuerta();
  await p.route(SUPA + "/**", async (route) => {
    const r = route.request(); const u = new URL(r.url());
    if (/\/rest\/v1\/rpc\/es_supervisor_virgilio/.test(u.pathname)) return route.fulfill({ status: 200, contentType: "application/json", body: "true" });
    if (/\/auth\/v1\//.test(u.pathname)) return route.fulfill({ status: 200, contentType: "application/json", body: "{}" });
    if (!/\/functions\/v1\/Impo_Comex_web/.test(u.pathname)) return route.fulfill({ status: 404, body: "no" });
    const ruta = u.pathname.replace(/^.*\/Impo_Comex_web/, "");
    if (ruta === "/datos-ddjj") return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ controlante: {} }) });
    const ct = r.headers()["content-type"] || ""; let body = {}, campos = null, accion = "";
    if (/multipart/.test(ct)) { campos = partirMultipart(r.postDataBuffer(), ct); accion = (campos.find((c) => c.name === "accion") || {}).value; }
    else { try { body = JSON.parse(r.postData() || "{}"); } catch (_e) { body = {}; } accion = body.accion; }
    const norm = campos ? { form: campos.map((c) => (c.name === "carga_ref" ? Object.assign({}, c, { value: "<ref>" }) : c)) }
      : { json: JSON.parse(JSON.stringify(body, (k, v) => (k === "carga_ref" ? "<ref>" : k === "duracion_ms" ? "<ms>" : v))) };
    reqs.push(Object.assign({ m: r.method(), ruta, accion }, norm));
    let resp = puerta.responder(accion, body, campos || []);
    let status = 200;
    if (Array.isArray(resp)) { if (resp[2]) await new Promise((ok) => setTimeout(ok, resp[2])); status = resp[0]; resp = resp[1]; }
    return route.fulfill({ status, contentType: typeof resp === "string" ? "text/plain" : "application/json", body: typeof resp === "string" ? resp : JSON.stringify(resp) });
  });

  // ── navegación ──
  if (viejo) {
    await p.addInitScript((k) => {
      localStorage.setItem(k, JSON.stringify({ access_token: "tok", token_type: "bearer", expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
        refresh_token: "r", user: { id: "u1", aud: "authenticated", role: "authenticated", email: "sup@x.com" } }));
    }, "sb-hrxfctzncixxqmpfhskv-auth-token");
    await p.goto(BASE + "impo-comex/", { waitUntil: "load" });
  } else {
    await p.goto(BASE + "__ic.html", { waitUntil: "load" });
    await p.evaluate(() => window.IC.abrir());
  }
  const entrar = async () => {
    await p.locator(".mode-card", { hasText: "Cajas vs Packing List" }).first().click({ timeout: 20000 });
    await p.locator("h3", { hasText: "📐 Cajas vs Packing List" }).waitFor({ timeout: 20000 });
    await espera(() => reqs.some((r) => r.accion === "cuit_entidades_listar"));
    await p.waitForTimeout(150);
  };

  // ── helpers ──
  async function espera(fn, ms = 20000) { const t = Date.now(); while (!fn()) { if (Date.now() - t > ms) throw new Error("timeout esperando"); await p.waitForTimeout(40); } }
  const DLG = '[role="dialog"]:has(.btn-primary), [role="alertdialog"]:has(.btn-primary)';
  async function dialogo() { const d = p.locator(DLG); if (!(await d.count())) return null; return (await d.first().locator("div").first().innerText()).trim(); }
  async function esperaDialogo() { await p.locator(DLG).first().waitFor({ timeout: 20000 }); await p.waitForTimeout(60); return dialogo(); }
  async function cerrarDialogo(boton = "Aceptar") { await p.locator(DLG).first().locator("button", { hasText: boton }).click(); await p.waitForTimeout(120); }
  async function lightbox() {
    const fc = p.locator("figcaption"); if (!(await fc.count())) return null;
    const src = await p.locator("figure img").first().getAttribute("src");
    return { cap: (await fc.first().innerText()).trim(), region: await p.locator("[data-region]").count(), src: /^blob:/.test(src || "") ? "blob" : src };
  }
  const vista = () => p.evaluate(() => {
    const zona = (n) => n && !n.closest('[role="dialog"],[role="alertdialog"],figure');
    const cards = [...document.querySelectorAll(".card")].filter(zona);
    const txt = cards.map((c) => c.innerText).join("\n").replace(/[ \t\r\n]+/g, " ").trim();
    const campos = cards.flatMap((c) => [...c.querySelectorAll("input:not([type=file]),select,textarea")].map((e) => {
      if (e.type === "checkbox") return `[x]${e.checked ? 1 : 0}${e.disabled ? "d" : ""}`;
      if (e.tagName === "SELECT") return `[s]${e.value}|${[...e.options].map((o) => o.value + "=" + o.text).join(";")}${e.disabled ? "d" : ""}`;
      return `[i]${e.placeholder}=${e.value}${e.disabled ? "d" : ""}|${e.style.borderColor || e.style.border || ""}`;
    }));
    const botones = cards.flatMap((c) => [...c.querySelectorAll("button")].map((b) => `${b.innerText.replace(/\s+/g, " ").trim() || b.title}${b.disabled ? "(d)" : ""}`));
    const imgs = cards.flatMap((c) => [...c.querySelectorAll("img")].map((i) => i.alt + "|" + i.title + "|" + (i.src.startsWith("blob:") ? "blob" : i.src)));
    return { txt, campos, botones, imgs };
  });
  async function snap(paso, extra = {}, conPedidos = true) {
    const v = await vista();
    // pedidos de fotos en paralelo: se ordenan por la primera foto (el orden de llegada no es del flujo)
    const rq = conPedidos ? reqs.slice() : []; if (conPedidos) reqs = [];
    for (let a = 0; a < rq.length; a++) {
      if (rq[a].accion !== "leer_fotos") continue;
      let b = a; while (b < rq.length && rq[b].accion === "leer_fotos") b++;
      const tramo = rq.slice(a, b).sort((x, y) => JSON.stringify(x).localeCompare(JSON.stringify(y)));
      rq.splice(a, b - a, ...tramo); a = b;
    }
    log.push(Object.assign({ paso, reqs: rq, vista: v, dialogo: await dialogo(), lightbox: await lightbox() }, extra));
  }
  const btn = (txt) => p.locator(".card button", { hasText: txt });
  // fila del resultado por su orden (FILAS_1: 0 código · 1 total cajas · 2 peso bruto · 3 peso neto · 4 inner ·
  // 5 comercializador · 6 cantidad CI · 7 barras · 8 marca · 9 505C código)
  const filaPorIndice = (i) => p.locator(".report tbody tr").nth(i);
  const filaRes = (i) => filaPorIndice(i);
  const selImp = () => p.locator(".card select").filter({ has: p.locator("option", { hasText: "— elegir / nuevo —" }) });
  const cuitInputs = () => p.locator('.card input[placeholder="ej. 30-12345678-9"]');
  const subir = async (sufijo, files) => { await p.locator(`input[type=file][id$="up-${sufijo}"]`).setInputFiles(files); };
  const tecleo = async (loc, txt) => { await loc.click(); await loc.fill(""); await loc.pressSequentially(txt, { delay: 5 }); };

  try {
    await entrar();
    await snap("01 abre el modo");

    // ── importador ──
    await tecleo(cuitInputs().nth(0), "3071");
    await p.locator('.card input[placeholder="TIERRA NATIVA SA"]').fill("ALGO");
    await snap("02 cuit incompleto");
    await selImp().selectOption("i2"); await p.waitForTimeout(100);
    await snap("03 elige importador con cuit corto");
    await selImp().selectOption("i1"); await p.waitForTimeout(100);
    await snap("04 elige importador i1");
    await selImp().selectOption(""); await p.waitForTimeout(100);
    await tecleo(cuitInputs().nth(0), "30712345679");
    await p.locator('.card input[placeholder="TIERRA NATIVA SA"]').click();   // blur → formatea
    await p.waitForTimeout(80);
    await tecleo(p.locator('.card input[placeholder="TIERRA NATIVA SA"]'), "  IMPORTADORA NUEVA SA ");
    await snap("05 cuit nuevo tipeado y formateado al salir");
    await p.locator('.card button[title="Guardar el importador en la lista"]').click();
    await espera(() => reqs.filter((r) => r.accion === "cuit_entidades_listar").length >= 1); await p.waitForTimeout(150);
    await snap("06 guarda importador");

    // ── comercializadores ──
    await tecleo(cuitInputs().nth(1), "30500000001");
    await p.locator('.card input[placeholder="LOEKEMEYER SRL"]').click(); await p.waitForTimeout(60);
    await tecleo(p.locator('.card input[placeholder="LOEKEMEYER SRL"]'), "NUEVA SRL");
    await snap("07 alta comercializador tipeada");
    await p.locator('.card button[title="Agregar comercializador"]').click();
    await espera(() => reqs.filter((r) => r.accion === "cuit_entidades_listar").length >= 1); await p.waitForTimeout(150);
    await snap("08 comercializador guardado");
    await tecleo(cuitInputs().nth(1), "30500000002");
    await tecleo(p.locator('.card input[placeholder="LOEKEMEYER SRL"]'), "FALLA SRL");
    await p.locator('.card button[title="Agregar comercializador"]').click();
    await esperaDialogo();
    await snap("09 error de la puerta al guardar");
    await cerrarDialogo();
    const carton = p.locator('.card input[placeholder="+ cartón (Enter)"]').first();
    await carton.fill("LOEKE"); await carton.press("Enter");
    await espera(() => reqs.filter((r) => r.accion === "cuit_entidades_listar").length >= 1); await p.waitForTimeout(150);
    await snap("10 agrega cartón");
    await p.locator('.card input[placeholder="+ cartón (Enter)"]').nth(1).press("Enter");   // vacío: no pide nada
    await p.waitForTimeout(150);
    await p.locator('.card button[title="Quitar cartón"]').first().click();
    await espera(() => reqs.filter((r) => r.accion === "cuit_entidades_listar").length >= 1); await p.waitForTimeout(150);
    await snap("11 quita cartón");
    await p.locator('.card button[title="Borrar comercializador"]').nth(1).click();
    await esperaDialogo();
    await snap("12 pregunta borrar comercializador");
    await cerrarDialogo("Cancelar");
    await p.locator('.card button[title="Borrar comercializador"]').nth(1).click();
    await esperaDialogo(); await cerrarDialogo("Aceptar");
    await espera(() => reqs.filter((r) => r.accion === "cuit_entidades_listar").length >= 1); await p.waitForTimeout(150);
    await snap("13 comercializador borrado");

    // ── corridas guardadas ──
    await btn("📂 Corridas guardadas").click();
    await espera(() => reqs.some((r) => r.accion === "corridas_listar")); await p.waitForTimeout(150);
    await snap("14 lista de corridas");
    await btn("Cerrar").click(); await p.waitForTimeout(100);
    await snap("15 cierra la lista");

    // ── archivos ──
    await subir("cajas-pl", [F("packing.pdf", PL_PDF, "application/pdf")]);
    await subir("cajas-ci", [F("ci.zip", zipStore([["invoice.csv", CI_CSV], ["otra.csv", CI_CSV]]), "application/zip")]);
    await p.waitForTimeout(400);
    await subir("cajas-fotos", FOTOS_1);
    await p.waitForTimeout(400);
    await subir("cajas-fotos", [FOTOS_ZIP, FOTOS_RAR]);
    await p.locator(".card img[alt$='838E inner.png']").first().waitFor({ timeout: 20000 });
    await p.waitForTimeout(300);
    await snap("16 PL, CI, fotos sueltas + zip + rar");
    const zonaCi = () => p.locator(".zone", { hasText: "Commercial Invoice (opcional)" });
    await zonaCi().locator('.files-list button[title="Quitar"]').click(); await p.waitForTimeout(100);
    await snap("16b quita la CI");
    await subir("cajas-ci", [F("ci.zip", zipStore([["invoice.csv", CI_CSV], ["otra.csv", CI_CSV]]), "application/zip")]);
    await zonaCi().locator(".files-list").waitFor(); await p.waitForTimeout(200);
    await p.locator(".card img[alt='borrar.png']").locator("xpath=..").locator("button").click(); await p.waitForTimeout(100);
    await snap("17 quita una foto");
    await p.locator(".card img[alt='437E (1).png (2)']").click(); await p.waitForTimeout(150);
    await snap("18 visor de una foto");
    await p.keyboard.press("Escape"); await p.waitForTimeout(100);
    await p.locator(".card select").filter({ has: p.locator("option", { hasText: "LCL (consolidado)" }) }).selectOption("FCL");
    await p.locator('.card input[placeholder="China 52"]').fill("China 52/B");
    await snap("19 FCL y n° de carga");

    // ── verificar ──
    await p.locator(".card .toolbar .btn-primary").first().click();
    // el lote de "lateral.png" espera el reintento (503): mientras tanto el botón muestra el avance
    await p.locator(".card .toolbar .btn-primary", { hasText: "Leyendo fotos con IA: 2/8..." }).waitFor({ timeout: 20000 });
    await snap("19b verificando (avance)", {}, false);   // los pedidos van con el paso siguiente
    await esperaDialogo();
    await snap("20 verificado (aviso de fotos sin asignar)");
    await cerrarDialogo(); await p.waitForTimeout(200);
    await snap("21 resultado");
    await p.locator(".card button", { hasText: "sin asignar" }).first().click(); await p.waitForTimeout(100);
    await p.locator(".card label", { hasText: "Solo problemas" }).locator("input").check(); await p.waitForTimeout(100);
    await snap("22 solo problemas");
    await p.locator(".card label", { hasText: "Solo problemas" }).locator("input").uncheck(); await p.waitForTimeout(100);

    // ver la fuente de cada resultado
    await filaRes(1).locator("td").nth(5).click(); await p.waitForTimeout(150);
    await snap("23 fuente: diferencia con foto (visor con zona)");
    await p.keyboard.press("ArrowRight"); await p.waitForTimeout(80);
    await snap("24 visor: siguiente");
    await p.keyboard.press("Escape"); await p.waitForTimeout(80);
    await filaRes(2).locator("td").nth(6).locator("img").click(); await p.waitForTimeout(150);
    await snap("25 fuente desde la miniatura");
    await p.keyboard.press("Escape"); await p.waitForTimeout(80);
    await filaRes(4).locator("td").nth(5).click(); await esperaDialogo();
    await snap("26 fuente: falta foto"); await cerrarDialogo();
    await filaRes(6).locator("td").nth(5).click(); await esperaDialogo();
    await snap("27 fuente: documentos"); await cerrarDialogo();
    await filaRes(9).locator("td").nth(5).click(); await esperaDialogo();
    await snap("28 fuente: sin foto cargada"); await cerrarDialogo();
    await filaRes(0).locator("td").nth(5).click(); await p.waitForTimeout(150);
    await snap("29 fuente: ok sin detalle no hace nada");
    await filaRes(5).locator("td").nth(5).click(); await p.waitForTimeout(150);
    await snap("30 fuente: sin dato PL con foto");
    await p.keyboard.press("Escape"); await p.waitForTimeout(80);

    // ✎ corregir, asignar, crudos, revisión
    await filaRes(2).locator('button[title="Corregir a mano (valor mal leído)"]').click(); await p.waitForTimeout(80);
    await tecleo(filaRes(2).locator("td").nth(3).locator("input"), "15,5");
    await tecleo(filaRes(3).locator("td").nth(3).locator("input"), "14");
    await snap("31 corrige dos valores");
    const panel = p.locator(".card div", { hasText: "⚠ Fotos sin asignar (2)" }).last();
    const tarj = (foto) => p.locator(".card div[style*='width']").filter({ has: p.locator(`div[title="${foto}"]`) }).last();
    await tarj("lateral.png").locator("select").nth(0).selectOption("437E"); await p.waitForTimeout(80);
    await btn("↻ Recalcular").click(); await esperaDialogo();
    await snap("32 recalcular sin cara pide la cara"); await cerrarDialogo();
    await tarj("lateral.png").locator("select").nth(1).selectOption("master_lateral"); await p.waitForTimeout(80);
    await p.locator(".card label", { hasText: "505C" }).locator("input").click(); await p.waitForTimeout(60);
    await p.locator(".card label", { hasText: "437E" }).filter({ has: p.locator("input[type=checkbox]") }).locator("input").click(); await p.waitForTimeout(60);
    await filaRes(8).locator("td").nth(7).locator("select").selectOption("mal");
    await tecleo(filaRes(8).locator("td").nth(8).locator("input"), "no es la marca");
    await filaRes(1).locator("td").nth(7).locator("select").selectOption("ok");
    await p.waitForTimeout(100);
    await snap("33 asigna, crudos y revisión", { panel: !!(await panel.count()) });
    await btn("↻ Recalcular").click();
    await espera(() => reqs.some((r) => r.accion === "recomparar")); await p.waitForTimeout(250);
    await snap("34 recalculado");
    await btn("💾 Guardar").click(); await esperaDialogo();
    await snap("35 guardar (revisión)"); await cerrarDialogo();
    await filaRes(3).locator("td").nth(3).locator("input").fill("13,9"); await p.waitForTimeout(80);
    await btn("💾 Guardar").click(); await esperaDialogo();
    await snap("36 guardar con cambios (no se guardó en la base)"); await cerrarDialogo();
    await btn("💾 Guardar").click(); await esperaDialogo();
    await snap("37 guardar otra vez"); await cerrarDialogo();
    const [dl] = await Promise.all([p.waitForEvent("download", { timeout: 20000 }), btn("⬇ Descargar PDF").click()]);
    const pdfBytes = fs.readFileSync(await dl.path());
    await snap("38 descarga el PDF", { descarga: { nombre: dl.suggestedFilename(), bytes: pdfBytes.length, md5: require("crypto").createHash("md5").update(pdfBytes).digest("hex") } });

    // ── abrir corridas ──
    await filaRes(3).locator("td").nth(3).locator("input").fill("13"); await p.waitForTimeout(60);
    await btn("📂 Corridas guardadas").click(); await espera(() => reqs.some((r) => r.accion === "corridas_listar")); await p.waitForTimeout(150);
    await p.locator(".card tr", { hasText: "INV 77/A" }).locator("button", { hasText: "Abrir" }).click(); await esperaDialogo();
    await snap("39 abrir con cambios pendientes pregunta"); await cerrarDialogo("Cancelar");
    await snap("40 cancela: sigue igual");
    await p.locator(".card tr", { hasText: "INV 77/A" }).locator("button", { hasText: "Abrir" }).click(); await esperaDialogo(); await cerrarDialogo("Aceptar");
    await esperaDialogo();
    await snap("41 abierta (aviso sin asignar)"); await cerrarDialogo(); await p.waitForTimeout(150);
    await snap("42 corrida abierta");
    await filaRes(9).locator("td").nth(5).click(); await esperaDialogo();
    await snap("43 fuente en corrida abierta sin foto"); await cerrarDialogo();
    await btn("📂 Corridas guardadas").click(); await esperaDialogo();
    await snap("44 lista de corridas con error"); await cerrarDialogo();
    await btn("📂 Corridas guardadas").click(); await espera(() => reqs.some((r) => r.accion === "corridas_listar")); await p.waitForTimeout(150);
    await p.locator(".card tr", { hasText: "(solo ver)" }).locator("button", { hasText: "Abrir" }).click();
    await espera(() => reqs.some((r) => r.accion === "corrida_abrir")); await p.waitForTimeout(200);
    await snap("45 corrida vieja (solo ver)");
    await filaRes(1).locator("td").nth(5).click(); await esperaDialogo();
    await snap("46 fuente: corrida abierta, foto no cargada"); await cerrarDialogo();
    await btn("💾 Guardar").click(); await esperaDialogo();
    await snap("47 guardar sin cambios"); await cerrarDialogo();
    await filaPorIndice(0).locator("td").nth(7).locator("select").selectOption("");
    await btn("💾 Guardar").click(); await esperaDialogo();
    await snap("48 guardar revisión vuelta a auto"); await cerrarDialogo();
    const [dl2] = await Promise.all([p.waitForEvent("download", { timeout: 20000 }), btn("⬇ Descargar PDF").click()]);
    const pdf2 = fs.readFileSync(await dl2.path());
    await snap("49 PDF de corrida sin referencia", { descarga: { nombre: dl2.suggestedFilename(), bytes: pdf2.length, md5: require("crypto").createHash("md5").update(pdf2).digest("hex") } });

    // ── errores al verificar (sin CI) ──
    await zonaCi().locator('.files-list button[title="Quitar"]').click(); await p.waitForTimeout(100);
    puerta.st.fase = "doc_error";
    await p.locator(".card .toolbar .btn-primary").first().click();
    await p.locator(".card .err-box", { hasText: "El PL no tiene ítems" }).waitFor({ timeout: 20000 }); await p.waitForTimeout(100);
    await snap("50 error en el packing list");
    puerta.st.fase = "fotos_error";
    await p.locator(".card .toolbar .btn-primary").first().click();
    await p.locator(".card .err-box", { hasText: "No se pudo leer ninguna foto" }).waitFor({ timeout: 20000 }); await p.waitForTimeout(100);
    await snap("51 ninguna foto leída");
    puerta.st.fase = "comparar_error";
    await p.locator(".card .toolbar .btn-primary").first().click();
    await p.locator(".card .err-box", { hasText: "No se pudo comparar" }).waitFor({ timeout: 20000 }); await p.waitForTimeout(100);
    await snap("52 error al comparar");
    await btn("Quitar todas").click(); await p.waitForTimeout(100);
    await snap("53 quita todas las fotos");

    // ── volver al inicio y entrar de nuevo: todo arranca de cero ──
    await p.locator("button", { hasText: "← Inicio" }).click();
    await p.locator(".mode-card").first().waitFor();
    await entrar();
    await snap("54 vuelve a entrar");
  } catch (e) {
    errs.push("excepción: " + ((e && e.stack) || e));
    try { await p.screenshot({ path: path.join(process.env.SHOTS || "/tmp", `paridad-cajas-${modo}.png`) }); } catch (_e) { /* nada */ }
  }
  await ctx.close();
  return { log, errs };
}

// ── comparación ─────────────────────────────────────────────────────────────────────────
const sinEsp = (s) => String(s == null ? "" : s).replace(/\s+/g, "");
function comparar(a, b) {   // a = esperado (viejo), b = obtenido
  const dif = [];
  const n = Math.max(a.log.length, b.log.length);
  for (let i = 0; i < n; i++) {
    const x = a.log[i], y = b.log[i];
    if (!x || !y) { dif.push(`paso ${i}: falta en ${!x ? "esperado" : "obtenido"} (${(x || y).paso})`); continue; }
    const P = x.paso;
    if (x.paso !== y.paso) dif.push(`paso ${i}: nombre ${x.paso} ≠ ${y.paso}`);
    if (JSON.stringify(x.reqs) !== JSON.stringify(y.reqs)) dif.push(`[${P}] pedidos distintos:\n   esp ${JSON.stringify(x.reqs).slice(0, 1500)}\n   obt ${JSON.stringify(y.reqs).slice(0, 1500)}`);
    if (sinEsp(x.vista.txt) !== sinEsp(y.vista.txt)) {
      const s1 = sinEsp(x.vista.txt), s2 = sinEsp(y.vista.txt); let k = 0; while (k < s1.length && s1[k] === s2[k]) k++;
      dif.push(`[${P}] texto distinto en «…${s1.slice(Math.max(0, k - 60), k)}»: esp «${s1.slice(k, k + 120)}» obt «${s2.slice(k, k + 120)}»`);
    }
    for (const c of ["campos", "botones", "imgs"]) {
      const e = JSON.stringify(x.vista[c].map(sinEsp)), o = JSON.stringify(y.vista[c].map(sinEsp));
      if (e !== o) dif.push(`[${P}] ${c} distintos:\n   esp ${e.slice(0, 1200)}\n   obt ${o.slice(0, 1200)}`);
    }
    if (sinEsp(x.dialogo) !== sinEsp(y.dialogo)) dif.push(`[${P}] diálogo: esp «${x.dialogo}» obt «${y.dialogo}»`);
    if (JSON.stringify(x.lightbox) !== JSON.stringify(y.lightbox)) dif.push(`[${P}] visor: esp ${JSON.stringify(x.lightbox)} obt ${JSON.stringify(y.lightbox)}`);
    if (x.descarga || y.descarga) {
      const xd = x.descarga || {}, yd = y.descarga || {};
      if (xd.nombre !== yd.nombre || xd.md5 !== yd.md5) dif.push(`[${P}] descarga: esp ${JSON.stringify(xd)} obt ${JSON.stringify(yd)}`);
    }
    if ("panel" in x && x.panel !== y.panel) dif.push(`[${P}] panel sin asignar: esp ${x.panel} obt ${y.panel}`);
  }
  return dif;
}

(async () => {
  const t0 = Date.now();
  const srv = http.createServer((req, res) => {
    const u = decodeURIComponent(req.url.split("?")[0]);
    if (u === "/__ic.html") { res.writeHead(200, { "content-type": "text/html; charset=utf-8" }); return res.end(PAGINA); }
    let f = path.join(RAIZ, u); if (u.endsWith("/")) f = path.join(f, "index.html");
    if (!f.startsWith(RAIZ) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end("no"); }
    res.writeHead(200, { "content-type": TIPOS[path.extname(f)] || "application/octet-stream" });
    fs.createReadStream(f).pipe(res);
  });
  await new Promise((ok) => srv.listen(Number(process.env.PUERTO || 0), "127.0.0.1", ok));
  const BASE = `http://127.0.0.1:${srv.address().port}/`;
  const b = await chromium.launch();
  let fallas = [];
  try {
    if (process.env.AMBOS) {
      const [v, n] = await Promise.all([correr("viejo", b, BASE), correr("nuevo", b, BASE)]);
      if (process.env.DUMP) fs.writeFileSync(process.env.DUMP, JSON.stringify({ viejo: v, nuevo: n }, null, 1));
      fallas = [...v.errs.map((e) => "viejo: " + e), ...n.errs.map((e) => "nuevo: " + e), ...comparar(v, n)];
      if (v.log.length < PASOS) fallas.push(`el viejo hizo sólo ${v.log.length} pasos`);
    } else if (process.env.VIEJO) {
      const v = await correr("viejo", b, BASE);
      fallas = v.errs.map((e) => "viejo: " + e);
      if (v.log.length < PASOS) fallas.push(`el viejo hizo sólo ${v.log.length} pasos`);
      if (process.env.GRABAR && !fallas.length) { fs.writeFileSync(ESPERADO, JSON.stringify({ log: v.log }, null, 1) + "\n"); console.log("grabado " + ESPERADO); }
    } else {
      const esp = JSON.parse(fs.readFileSync(ESPERADO, "utf8"));
      const n = await correr("nuevo", b, BASE);
      fallas = [...n.errs.map((e) => "nuevo: " + e), ...comparar(esp, n)];
    }
  } catch (e) { fallas.push("excepción: " + ((e && e.stack) || e)); }
  await b.close(); srv.close();
  if (fallas.length) { console.error("✗ impo-comex-paridad-cajas:\n  - " + fallas.join("\n  - ")); process.exit(1); }
  console.log(`✓ impo-comex-paridad-cajas: ${PASOS} pasos del modo Cajas iguales al viejo (pedidos, pantalla, diálogos, visor y PDF) · ${Math.round((Date.now() - t0) / 1000)} s`);
})();
