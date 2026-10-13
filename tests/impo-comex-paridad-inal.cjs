/* v29.19 — IMPO COMEX: PARIDAD de los modos INAL / Vencimientos y Autorización (envases) entre el VIEJO
   (impo-comex/, build React) y el NUEVO (impocomex/ic-inal.js + ic-autorizacion.js).
   Recorre los flujos de usuario de punta a punta contra la puerta Impo_Comex_web falsa (sin red):
   INAL — vencimientos (filtros por estado y tipo, búsqueda, códigos desplegables, 🔄 con error JSON y texto),
          artículos (búsqueda por número pelado, filtros, 3 Excel), NCM (filtros, editar con Enter / Escape /
          ✓ con error), cargar certificado (subir, quitar, leer con error / cargando / ok, editar el borrador
          y su tabla de códigos tipeando, guardar con error, guardar todos, descartar, ver certificados,
          limpiar, un solo borrador con «existente»);
   AUTORIZACIÓN — empresas RNE (elegir, guardar, error), leer documentos (error, cargando, ok), editar,
          descargar el Word (las 3 confirmaciones, «Completar» lleva al primer vacío, sin certificados,
          plantilla subida, plantilla rota), Archivos vs PDF y Formulario vs PDF (ok, 403, PDF sin texto).
   En cada paso compara el texto, los valores de los campos, los botones (y si están deshabilitados), el
   diálogo abierto, los pedidos a la puerta (método + ruta + cuerpo JSON / campos del FormData) y las
   descargas (Excel byte a byte; Word por entrada, sin los id al azar de los párrafos duplicados) contra lo
   que hizo el VIEJO, guardado en tests/tools/impo-comex-paridad-inal.json.
   Regenerar ese archivo desde el viejo (mientras impo-comex/ exista):  node tests/impo-comex-paridad-inal.cjs --generar
   Sale 1 si falla. */
const fs = require('fs');
const path = require('path');
const http = require('http');
const crypto = require('crypto');
let chromium;
try { ({ chromium } = require('/opt/node22/lib/node_modules/playwright')); }
catch (_e) { try { ({ chromium } = require('playwright')); } catch (_e2) { console.error('no playwright'); process.exit(2); } }

const RAIZ = path.join(__dirname, '..');
const FIX = path.join(__dirname, 'tools', 'impo-comex-paridad-inal.json');
const GENERAR = process.argv.includes('--generar');
const RELOJ = '2026-10-09T15:00:00-03:00';
const PAGINA = `<!doctype html><html><head><meta charset="utf-8"><title>ic</title>
<script>window.APP_VERSION = "prueba";
window.sb = { auth: { getSession: async () => ({ data: { session: { access_token: "tok" } } }) }, rpc: async () => ({ data: true }) };</script>
</head><body><script src="impocomex/ic-base.js"></script></body></html>`;
const TIPOS = { '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json',
  '.wasm': 'application/wasm', '.docx': 'application/octet-stream', '.html': 'text/html' };
const md5 = (x) => crypto.createHash('md5').update(x).digest('hex');
const espera = (ms) => new Promise((r) => setTimeout(r, ms));

// ── datos falsos de la puerta (realistas) ────────────────────────────────────────────────
const LISTA = {
  certificados: [
    { id: 11, numero: 'CE-2024-00123456-APN-INAL', tipo: 'CE', organismo: 'ANMAT', fecha_emision: '2021-11-20', fecha_vencimiento: '2026-11-20',
      titular_razon_social: 'LOEKEMEYER HNOS SRL', titular_cuit: '30-12345678-9', fabricante: 'Yangjiang Kangli Co.', marcas: 'LK, Loeke',
      descripcion: 'Utensilios de acero inoxidable', codigos: ['437E', '438E', '439E'],
      productos: [{ codigo: '437E', descripcion: 'Colador Ø 8 cm' }, { codigo: '438E', descripcion: 'Colador Ø 10 cm' }] },
    { id: 12, numero: 'RNE-02-033344', tipo: 'RNE', organismo: 'INAL', fecha_emision: '2020-01-10', fecha_vencimiento: '2025-01-10',
      titular_razon_social: 'CHEF SRL', titular_cuit: '30-99999999-1', fabricante: null, marcas: null, codigos: [] },
    { id: 13, numero: 'CE-2023-777-APN-SENASA', tipo: 'CE', organismo: 'SENASA', fecha_emision: '2023-03-01', fecha_vencimiento: '2028-03-01',
      titular_razon_social: 'LOEKEMEYER HNOS SRL', fabricante: 'Fujian Hongsheng', marcas: 'Chef', codigos: ['702E', '106E'], productos: [] },
    { id: 14, numero: 'CE-SIN-FECHA', tipo: 'OTRO', organismo: null, fecha_emision: null, fecha_vencimiento: null, titular_razon_social: null, codigos: ['999E'] },
    { id: 15, numero: 'CE-HOY', tipo: 'CE', organismo: 'ANMAT', fecha_emision: '2021-10-09', fecha_vencimiento: '2026-10-09', titular_razon_social: 'X SA', codigos: [] },
  ],
  articulos: [
    { certificado_id: 11, codigo: '437E', marca: 'LK', descripcion: 'Colador Ø 8 cm', descripcion_prio: 1, descripcion_de: '437E', importador: 'LOEKEMEYER HNOS SRL',
      elaborador: 'Yangjiang Kangli Co.', numero: 'CE-2024-00123456-APN-INAL', fecha_vencimiento: '2026-11-20', dias_restantes: 42, estado: 'por_vencer' },
    { certificado_id: 11, codigo: '437EL', marca: 'Loeke', descripcion: 'Colador Ø 8 cm', descripcion_prio: 2, descripcion_de: '437E', importador: 'LOEKEMEYER HNOS SRL',
      elaborador: 'Yangjiang Kangli Co.', numero: 'CE-2024-00123456-APN-INAL', fecha_vencimiento: '2026-11-20', dias_restantes: 42, estado: 'por_vencer' },
    { certificado_id: 12, codigo: '025E', marca: null, descripcion: null, descripcion_prio: 3, descripcion_de: null, importador: 'CHEF SRL',
      elaborador: null, numero: 'RNE-02-033344', fecha_vencimiento: '2025-01-10', dias_restantes: -637, estado: 'vencido' },
    { certificado_id: 13, codigo: '702E', marca: 'Chef', descripcion: 'Rallador 4 caras', descripcion_prio: 1, descripcion_de: '702E', importador: 'LOEKEMEYER HNOS SRL',
      elaborador: 'Fujian Hongsheng', numero: 'CE-2023-777-APN-SENASA', fecha_vencimiento: '2028-03-01', dias_restantes: 509, estado: 'vigente' },
    { certificado_id: 14, codigo: '999E', marca: 'LK', descripcion: 'Sin fecha', descripcion_prio: 1, importador: null, elaborador: null,
      numero: 'CE-SIN-FECHA', fecha_vencimiento: null, dias_restantes: null, estado: 'sin_vencimiento' },
  ],
  productos: [
    { producto_id: 201, proveedor: 'KANGLI', cod_lk: '437E', cod_ch: '824', nombre_producto: 'Colador Ø 8 cm acero inoxidable con mango largo', ncm: '7323.93.00.910T',
      ncm_fuente: 'despacho', certificado_id: 11, numero: 'CE-2024-00123456-APN-INAL', tipo_match: 'exacto', estado: 'por_vencer', conflicto: false },
    { producto_id: 202, proveedor: 'FUJIAN', cod_lk: '702E', cod_ch: null, nombre_producto: 'Rallador', ncm: null, ncm_fuente: null,
      certificado_id: 13, numero: 'CE-2023-777-APN-SENASA', tipo_match: 'base', estado: 'vigente', conflicto: false },
    { producto_id: 203, proveedor: 'BECKY', cod_lk: '958E', cod_ch: '', nombre_producto: 'Batidor', ncm: '8215.99.10.000', ncm_fuente: 'manual',
      certificado_id: null, numero: null, estado: null, conflicto: true, ncms_vistos: ['8215.99.10.000', '8215.20.00.000'] },
    { producto_id: 204, proveedor: 'ZHIXIN', cod_lk: '106E', nombre_producto: 'Pelador', ncm: null, certificado_id: 12, numero: 'RNE-02-033344', tipo_match: 'exacto', estado: 'vencido' },
  ],
};
const EXTRAER = {
  borradores: [
    { numero: 'CE-2026-0001-APN-INAL', tipo: 'CE', organismo: 'ANMAT', fecha_emision: '2026-05-02', vigencia_anios: 5, fecha_vencimiento: null,
      titular_razon_social: 'LOEKEMEYER HNOS SRL', titular_cuit: '30-12345678-9', fabricante: 'Kangli', pais_origen: 'China', marcas: 'LK',
      expediente: 'EX-2026-1', anexo_if: 'IF-2026-2', deposito: 'RNE 02-0333', descripcion: 'Coladores', notas: null,
      archivo_nombre: 'ce.pdf | anexo.pdf', codigos: ['437E', '438e'], productos: [{ codigo: '437E', marca: 'LK', descripcion: 'Colador 8' }, { codigo: '999E', marca: '', descripcion: 'Extra' }] },
    { numero: 'CE-2024-00123456-APN-INAL', tipo: 'RNE', organismo: '', archivo_nombre: 'otro.pdf', codigos: ['702E'], productos: [] },
    { numero: '', tipo: 'CE', archivo_nombre: 'sin.pdf', codigos: [], productos: [] },
  ],
  existentes: { 'CE-2024-00123456-APN-INAL': { numero: 'CE-2024-00123456-APN-INAL', id: 11 } },
  errores: ['roto.pdf: no tiene texto'],
};
const EXTRAER_UNO = { borrador: { numero: 'CE-HOY', tipo: 'CE', organismo: 'ANMAT', archivo_nombre: 'ce.pdf', codigos: ['111'], productos: [] },
  existente: { numero: 'CE-HOY', id: 15 } };
const AUT = () => ({
  autorizacion: {
    importador: { razon_social: { valor: 'LOEKEMEYER HNOS SRL', fuente: 'factura' }, cuit: { valor: '30-12345678-9', fuente: 'factura' }, rne: { valor: 'RNE 00306900', fuente: 'rne' } },
    deposito: { provincia: { valor: 'Buenos Aires', fuente: 'factura' }, departamento: { valor: '', fuente: null }, localidad: { valor: 'Villa Martelli', fuente: 'factura' },
      domicilio: { valor: 'Virgilio 2788', fuente: 'factura' }, piso_dpto: { valor: '', fuente: null }, factura: { valor: 'HK/2026/0915', fuente: 'factura' } },
    transporte: { fecha_arribo: { valor: '', fuente: null }, bl_numero: { valor: 'COSU6345678901', fuente: 'bl' }, pais_procedencia: { valor: 'China', fuente: 'bl' } },
    productos: [
      { codigos: ['437E', '438E'], certificado: { valor: 'CE-2024-00123456-APN-INAL', fuente: 'certificado' }, pais_origen: { valor: 'China', fuente: 'certificado' },
        elaborador: { valor: 'Yangjiang Kangli Co.', fuente: 'certificado' }, denominacion: { valor: 'Coladores de acero inoxidable', fuente: 'factura' },
        marca_codigo: { valor: 'LK 437E / 438E', fuente: 'factura' }, lote: { valor: '', fuente: null }, cantidad: { valor: '4800', fuente: 'packing_list' },
        unidad: { valor: 'Unidad', fuente: 'manual' }, peso_bruto: { valor: '512.40', fuente: 'packing_list' } },
      { codigos: ['702E'], certificado: { valor: 'CE-2023-777-APN-SENASA', fuente: 'certificado' }, pais_origen: { valor: '', fuente: null },
        elaborador: { valor: 'Fujian Hongsheng', fuente: 'certificado' }, denominacion: { valor: 'Ralladores', fuente: 'factura' },
        marca_codigo: { valor: 'Chef 702E', fuente: 'factura' }, lote: { valor: 'L-77', fuente: 'factura' }, cantidad: { valor: '1200', fuente: 'packing_list' },
        unidad: { valor: '', fuente: null }, peso_bruto: { valor: '', fuente: null } },
    ],
    sin_certificado: [{ codigo: '958E', descripcion: 'Batidor', cantidad: 2400, pista: 'el CE 2023 cubre 958 sin E' }, { codigo: '590E', descripcion: null, cantidad: null, pista: null }],
    controles: [
      { control: 'Factura vs PL: cantidades', resultado: 'ok', detalle: '4 códigos coinciden' },
      { control: 'Factura vs BL: contenedor', resultado: 'critica', detalle: 'BL MSCU1234 no figura en la factura' },
      { control: 'CE vigente al arribo', resultado: 'importante', detalle: 'CE-2024 vence 20/11/2026' },
      { control: 'RNE', resultado: 'sin_datos', detalle: 'No se subió el RNE' },
    ],
    avisos: ['Peso bruto del 702E sin dato en el PL'],
  },
  errores: ['bl-roto.pdf'],
  costo_usd: 0.1834, duracion_ms: 28700,
});
const CONTRASTE = { contraste: { numero: 'PD-2026-12345678-APN-DNIYCA#SENASA', controles: [
  { control: 'RNE', resultado: 'ok', detalle: '00306900 = 00306900' },
  { control: 'Factura', resultado: 'importante', detalle: 'HK/2026/0915 vs HK-2026-0915' },
  { control: 'Cantidad 437E', resultado: 'critica', detalle: '4800 vs 480' },
  { control: 'Lote', resultado: 'sin_datos', detalle: '—' },
] } };

// ── servidor y página ───────────────────────────────────────────────────────────────────
function servidor() {
  const srv = http.createServer((req, res) => {
    const u = decodeURIComponent(req.url.split('?')[0]);
    if (u === '/__ic.html') { res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }); return res.end(PAGINA); }
    let f = path.join(RAIZ, u);
    if (f.startsWith(RAIZ) && fs.existsSync(f) && fs.statSync(f).isDirectory()) f = path.join(f, 'index.html');
    if (!f.startsWith(RAIZ) || !fs.existsSync(f)) { res.writeHead(404); return res.end('no'); }
    res.writeHead(200, { 'content-type': TIPOS[path.extname(f)] || 'application/octet-stream' });
    fs.createReadStream(f).pipe(res);
  });
  return new Promise((ok) => srv.listen(0, '127.0.0.1', () => ok(srv)));
}
function multipart(buf, ct, fixMd5) {
  const m = /boundary=(.+)$/.exec(ct || ''); if (!m) return null;
  const b = Buffer.from('--' + m[1]); const partes = []; let i = buf.indexOf(b);
  while (i >= 0) {
    const j = buf.indexOf(b, i + b.length); if (j < 0) break;
    const parte = buf.slice(i + b.length + 2, j - 2); const h = parte.indexOf('\r\n\r\n');
    const head = parte.slice(0, h).toString(); const body = parte.slice(h + 4);
    const name = (/name="([^"]*)"/.exec(head) || [])[1]; const filename = (/filename="([^"]*)"/.exec(head) || [])[1];
    if (filename !== undefined) partes.push({ name, filename, archivo: fixMd5[md5(body)] || ('?' + body.length) });
    else if (name === 'carga_ref') partes.push({ name, ok: /^\d{8}T\d{6}\d{3}Z_[0-9a-f]{8}$/.test(body.toString()) });
    else { const v = body.toString(); partes.push(v.length > 200 ? { name, largo: v.length, md5: md5(v) } : { name, value: v }); }
    i = j;
  }
  return partes;
}
const resumir = (json) => (json && typeof json === 'object' ? JSON.parse(JSON.stringify(json, (k, v) =>
  (typeof v === 'string' && v.length > 200 ? `[${v.length}:${md5(v)}]` : v))) : json);

async function abrir(lado, srvUrl, fake, fixMd5) {
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: 1440, height: 900 }, acceptDownloads: true, timezoneId: 'America/Argentina/Buenos_Aires', locale: 'es-AR' });
  const p = await ctx.newPage();
  await p.clock.setFixedTime(new Date(RELOJ));
  const errs = []; const reqs = [];
  p.on('pageerror', (e) => errs.push('pageerror: ' + e.message));
  p.on('console', (m) => { if (m.type() === 'error' && !/favicon|Failed to load resource/.test(m.text())) errs.push('console: ' + m.text()); });
  await p.route('**/functions/v1/Impo_Comex_web/**', async (route) => {
    const r = route.request(); const pth = r.url().replace(/^.*Impo_Comex_web/, '');
    let json = null, parts = null; const ct = r.headers()['content-type'] || '';
    if (/multipart/.test(ct)) parts = multipart(r.postDataBuffer(), ct, fixMd5);
    else if (r.postData()) { try { json = JSON.parse(r.postData()); } catch (_) { json = r.postData(); } }
    if (pth === '/datos-ddjj') return route.fulfill({ status: 200, contentType: 'application/json', body: '{"controlante":{}}' });
    if (pth === '/editar' && json && json.accion === 'cargas_hoy') return route.fulfill({ status: 200, contentType: 'application/json', body: '{"data":[]}' });
    reqs.push({ m: r.method(), p: pth, json: resumir(json), parts });
    const out = await fake(pth, r.method(), json, parts);
    route.fulfill({ status: out.status || 200, contentType: 'application/json', body: typeof out.body === 'string' ? out.body : JSON.stringify(out.body) });
  });
  if (lado === 'viejo') {
    await p.addInitScript(() => localStorage.setItem('sb-hrxfctzncixxqmpfhskv-auth-token', JSON.stringify({ access_token: 'tok', refresh_token: 'r',
      token_type: 'bearer', expires_in: 3600, expires_at: 4102444800, user: { id: 'u1', aud: 'authenticated', role: 'authenticated', email: 'x@y.z' } })));
    await p.route('**/rest/v1/rpc/**', (route) => route.fulfill({ status: 200, contentType: 'application/json', body: 'true' }));
    await p.route('**/auth/v1/**', (route) => route.fulfill({ status: 200, contentType: 'application/json', body: '{"id":"u1","aud":"authenticated"}' }));
    await p.goto(srvUrl + 'impo-comex/', { waitUntil: 'load' });
    await p.waitForSelector('.mode-card', { timeout: 20000 });
  } else {
    await p.goto(srvUrl + '__ic.html', { waitUntil: 'load' });
    await p.evaluate(() => window.IC.abrir());
    await p.waitForSelector('#icOv .mode-card', { timeout: 20000 });
  }
  return { b, p, errs, reqs, lado, root: () => p.locator(lado === 'viejo' ? '.app > .header + div' : '#icMain') };
}
async function irModo(X, modo) {
  if (X.lado === 'viejo') {
    const titulo = { inal: 'INAL: certificados y vencimientos', vencimientos: 'INAL: certificados y vencimientos', autorizacion: 'Autorización de Importación' }[modo];
    await X.p.locator('.mode-card', { hasText: titulo }).first().click();
  } else await X.p.evaluate((m) => window.IC.ir(m), modo);
}
function foto(X) {
  return X.p.evaluate((lado) => {
    const r = lado === 'viejo' ? document.querySelector('.app > .header + div') : document.getElementById('icMain');
    if (!r) return null;
    const sin = (t) => String(t || '').replace(/\s+/g, '');
    const dlg = document.querySelector('[role=dialog],[role=alertdialog]');
    return { txt: sin(r.innerText),
      vals: [...r.querySelectorAll('input:not([type=file]),select,textarea')].map((e) => (e.type === 'checkbox' ? (e.checked ? '[x]' : '[ ]') : e.value)),
      btns: [...r.querySelectorAll('button')].map((e) => sin(e.textContent) + (e.disabled ? '(off)' : '')),
      dlg: dlg ? sin(dlg.innerText) : null };
  }, X.lado);
}

// ── corredor: en --generar anota; si no, espera a que el nuevo llegue a lo que hizo el viejo ──
function corredor(X, esperado, nombre) {
  const LOG = []; const fallas = []; let nreq = 0;
  const S = async (et, ms = 350) => {
    const i = LOG.length; const exp = esperado && esperado[i];
    if (GENERAR) {
      await espera(ms);
      const s = await foto(X); const reqs = X.reqs.slice(nreq); nreq = X.reqs.length;
      LOG.push({ et, s: md5(JSON.stringify(s)), muestra: s ? s.txt.slice(-160) : null, reqs }); return;
    }
    if (!exp) { fallas.push(`${nombre}: paso ${i} «${et}» no está en el esperado (regenerar con --generar)`); LOG.push({ et }); return; }
    const t0 = Date.now(); let s, reqs, h;
    for (;;) {
      s = await foto(X); h = md5(JSON.stringify(s)); reqs = X.reqs.slice(nreq);
      if (h === exp.s && JSON.stringify(reqs) === JSON.stringify(exp.reqs)) break;
      if (Date.now() - t0 > 7000) break;
      await espera(60);
    }
    nreq = X.reqs.length;
    if (exp.et !== et) fallas.push(`${nombre}: el paso ${i} es «${et}» y el viejo tenía «${exp.et}»`);
    if (h !== exp.s) fallas.push(`${nombre} «${et}»: la pantalla no es la del viejo.\n      viejo termina en: …${exp.muestra}\n      nuevo termina en: …${s ? s.txt.slice(-160) : null}\n      nuevo: ${JSON.stringify(s).slice(0, 900)}`);
    if (JSON.stringify(reqs) !== JSON.stringify(exp.reqs)) fallas.push(`${nombre} «${et}»: los pedidos a la puerta no son los del viejo.\n      viejo: ${JSON.stringify(exp.reqs).slice(0, 900)}\n      nuevo: ${JSON.stringify(reqs).slice(0, 900)}`);
    LOG.push({ et, s: h, reqs });
  };
  const V = (et, valor) => { // un valor suelto (foco, nombre de descarga, contenido)
    const i = LOG.length; const exp = esperado && esperado[i];
    if (!GENERAR && (!exp || JSON.stringify(exp.v) !== JSON.stringify(valor))) fallas.push(`${nombre} «${et}»: ${JSON.stringify(valor).slice(0, 400)} y el viejo: ${JSON.stringify(exp && exp.v).slice(0, 400)}`);
    LOG.push({ et, v: valor });
  };
  return { S, V, LOG, fallas };
}
const btnDe = (X) => (t, n = 0) => X.root().getByRole('button', { name: t, exact: true }).nth(n);
const dlgDe = (X) => async (t) => { const l = X.p.locator('[role=dialog] button, [role=alertdialog] button', { hasText: t }).first(); await l.waitFor({ timeout: 8000 }); await l.click(); };
const subirDe = (X) => async (id, files) => {
  await X.p.setInputFiles(`#${X.lado === 'viejo' ? 'up' : 'icup'}-${id}`, files);
  await espera(GENERAR ? 700 : 250);
};
// .docx → [[nombre, Buffer]] (zip leído con el directorio central + zlib, sin dependencias)
function unzip(buf) {
  const zlib = require('zlib');
  let e = buf.length - 22; while (e >= 0 && buf.readUInt32LE(e) !== 0x06054b50) e--;
  const n = buf.readUInt16LE(e + 10); let o = buf.readUInt32LE(e + 16); const out = [];
  for (let i = 0; i < n; i++) {
    const met = buf.readUInt16LE(o + 10), tam = buf.readUInt32LE(o + 20), ln = buf.readUInt16LE(o + 28), lx = buf.readUInt16LE(o + 30), lc = buf.readUInt16LE(o + 32);
    const nombre = buf.slice(o + 46, o + 46 + ln).toString(); const loc = buf.readUInt32LE(o + 42);
    const ini = loc + 30 + buf.readUInt16LE(loc + 26) + buf.readUInt16LE(loc + 28);
    const raw = buf.slice(ini, ini + tam);
    out.push([nombre, met === 8 ? zlib.inflateRawSync(raw) : raw]);
    o += 46 + ln + lx + lc;
  }
  return out.sort((a, b) => (a[0] < b[0] ? -1 : 1));
}
async function bajar(X, accion) {
  const pr = X.p.waitForEvent('download', { timeout: 10000 });
  await accion(); const d = await pr;
  return { nombre: d.suggestedFilename(), bytes: fs.readFileSync(await d.path()) };
}

// ── INAL / Vencimientos ─────────────────────────────────────────────────────────────────
async function flujoInal(X, C, F, ctl) {
  const { S, V } = C; const R = X.root; const btn = btnDe(X); const dlg = dlgDe(X); const subir = subirDe(X);
  const pdfF = (n, b) => ({ name: n, mimeType: 'application/pdf', buffer: b });
  X.reqs.length = 0;
  await irModo(X, 'inal');
  await R().locator('.stat').first().waitFor({ timeout: 15000 });
  await S('venc-inicial');
  await R().locator('.stat', { hasText: 'Vencido' }).click(); await S('venc-vencido');
  await R().locator('.stat', { hasText: 'Vencido' }).click(); await S('venc-toggle');
  await R().locator('.stat', { hasText: 'Por vencer' }).click(); await S('venc-porvencer');
  await R().locator('.stat', { hasText: 'Por vencer' }).click();
  await btn('RNE').click(); await S('venc-rne');
  await btn('Todos los tipos').click();
  const bv = R().locator('input[placeholder="Buscar número, titular, marca o código"]');
  await bv.click(); await X.p.keyboard.type('loeke', { delay: 15 }); await S('venc-buscar');
  await bv.fill('702e'); await S('venc-buscar-cod');
  await bv.fill('');
  await btn('3 ▼').click(); await S('venc-abre');
  await btn('1 ▼').click(); await S('venc-abre-otro');
  await btn('1 ▲').click(); await S('venc-cierra');
  ctl.falla['/inal-certificados?'] = { status: 500, body: { error: 'Falla de prueba en la base' } };
  await btn('🔄').click(); await S('refresh-error', 700);
  await btn('🔄').click(); await S('refresh-ok', 700);
  ctl.falla['/inal-certificados?'] = { status: 502, body: 'Bad gateway' };
  await btn('🔄').click(); await S('refresh-error-texto', 700);
  await btn('🔄').click(); await S('refresh-ok-2', 500);
  // Artículos
  await btn('📦 Artículos certificados').click(); await S('art');
  const bus = R().locator('input[placeholder^="Buscar código, marca"]');
  await bus.fill('437'); await S('art-437');
  await bus.fill('25'); await S('art-25');
  await bus.fill('kangli'); await S('art-kangli');
  await bus.fill('zzz'); await S('art-nada');
  await bus.fill('');
  await btn('Vencido (1)').click(); await S('art-vencido');
  await btn('Vigente (1)').click(); await S('art-vigente');
  await btn('Todos (5)').click();
  const dls = [];
  dls.push(await bajar(X, () => btn('⬇ Descargar Excel').click()));
  await btn('Por vencer (2)').click();
  dls.push(await bajar(X, () => btn('⬇ Descargar Excel').click()));
  await btn('Todos (5)').click();
  await bus.fill('025'); dls.push(await bajar(X, () => btn('⬇ Descargar Excel').click()));
  dls.forEach((d, k) => V('excel-' + k, { nombre: d.nombre, md5: md5(d.bytes) }));
  await S('art-tras-excel');
  await btn('NCM por producto').click(); await S('ncm');
  await btn('📦 Artículos certificados').click(); await S('art-reinicia');
  // NCM
  await btn('NCM por producto').click();
  for (const f of ['Sin NCM (2)', 'Sin certificado (1)', 'Certificado de otra variante (1)', 'NCM en conflicto (1)', 'Todos (4)']) { await btn(f).click(); await S('ncm-' + f); }
  await R().locator('span[title="Click para editar"]', { hasText: '+ cargar' }).first().click(); await S('ncm-edita');
  V('ncm-foco', await X.p.evaluate(() => document.activeElement && document.activeElement.placeholder));
  await X.p.keyboard.type(' 8205.51.00 ', { delay: 10 });
  await X.p.keyboard.press('Enter'); await S('ncm-guardado', 800);
  await R().locator('span[title^="Vistos en despachos"]').click(); await S('ncm-edita-conflicto');
  await X.p.keyboard.press('Escape'); await S('ncm-escape');
  await R().locator('span[title="Click para editar"]', { hasText: '7323' }).click();
  await R().locator('input[placeholder="7323.93.00.910T"]').fill('7323.93.00.111X');
  ctl.falla['/inal-certificados'] = { status: 400, body: { error: 'NCM inválido' }, accion: 'guardar_ncm' };
  await btn('✓').click(); await S('ncm-error', 600);
  await dlg('Aceptar'); await S('ncm-error-cerrado');
  // Cargar
  await btn('+ Cargar certificado').click(); await S('cargar');
  await subir('inal-docs', [pdfF('ce.pdf', F.ce)]);
  await subir('inal-docs', [pdfF('anexo.pdf', F.anexo), { name: 'nota.txt', mimeType: 'text/plain', buffer: Buffer.from('x') }]);
  await S('cargar-subidos');
  await R().locator('.files-list button').first().click(); await S('cargar-quitado');
  await subir('inal-docs', [pdfF('ce.pdf', F.ce)]);
  ctl.falla['/inal-certificados'] = { status: 500, body: { error: 'La IA no respondió' } };
  await btn('🔍 Leer documentos').click(); await S('leer-error', 2500);
  ctl.demora = 1500;
  await btn('🔍 Leer documentos').click(); await S('leer-cargando', 900);
  await S('leer-ok', 2000);
  const caja = (i) => R().locator('div[style*="border"]').filter({ has: X.p.locator('strong', { hasText: new RegExp('^' + (i + 1) + '\\. ') }) }).last();
  const campo = (i, label) => caja(i).locator('label', { hasText: label }).first().locator('input,select');
  await campo(0, 'Número').click(); await X.p.keyboard.press('End'); await X.p.keyboard.type('-B', { delay: 15 }); await S('b0-numero');
  await campo(0, 'Tipo').selectOption('RNE');
  await campo(0, 'Organismo').selectOption('');
  await campo(0, 'Vigencia (años)').fill('3');
  await campo(0, 'Vencimiento').fill('2029-05-02');
  await campo(0, 'Notas').fill('nota de prueba');
  const tins = caja(0).locator('table input');
  await tins.nth(3).click(); await X.p.keyboard.press('End'); await X.p.keyboard.press('Backspace'); await X.p.keyboard.type('E', { delay: 15 });
  await tins.nth(4).fill('Loeke');
  await caja(0).locator('table button[title="Quitar código"]').nth(2).click();
  await caja(0).getByRole('button', { name: '+ Agregar código', exact: true }).click();
  await caja(0).locator('table input').nth(6).fill(' 500e ');
  await caja(0).locator('table input').nth(8).fill('Agregado');
  await S('b0-editado');
  await caja(0).getByRole('button', { name: '💾 Guardar certificado', exact: true }).click(); await S('b0-guardado', 900);
  ctl.falla['/inal-certificados'] = { status: 409, body: { error: 'Choque de número' }, accion: 'guardar' };
  await caja(1).getByRole('button', { name: '💾 Guardar certificado', exact: true }).click(); await S('b1-error', 800);
  await btn('💾 Guardar todos (2)').click(); await S('guardar-todos', 1000);
  await caja(2).getByRole('button', { name: 'Descartar', exact: true }).click(); await S('b2-descartado');
  await btn('Ver certificados').click(); await S('ver-certificados', 800);
  // Limpiar
  await btn('+ Cargar certificado').click();
  await subir('inal-docs', [pdfF('ce.pdf', F.ce)]);
  await btn('🔍 Leer documentos').click(); await S('leer-2', 2500);
  await btn('Limpiar').click(); await S('limpiar');
  // un solo borrador (r.borrador) con «existente»
  ctl.uno = true;
  await subir('inal-docs', [pdfF('ce.pdf', F.ce)]);
  await btn('🔍 Leer documentos').click(); await S('leer-uno', 2500);
  await caja(0).getByRole('button', { name: '💾 Guardar certificado', exact: true }).click(); await S('uno-guardado', 900);
}

// ── Autorización ────────────────────────────────────────────────────────────────────────
async function flujoAut(X, C, F, ctl) {
  const { S, V } = C; const R = X.root; const btn = btnDe(X); const dlg = dlgDe(X); const subir = subirDe(X);
  const pdfF = (n, b) => ({ name: n, mimeType: 'application/pdf', buffer: b });
  const campo = (label, n = 0) => R().locator(`xpath=.//label[normalize-space()="${label}"]/following-sibling::*[1]`).nth(n);
  const dlgSi = async (n) => { for (let k = 0; k < n; k++) { const d = X.p.locator('[role=dialog] button, [role=alertdialog] button', { hasText: 'Descargar igual' }); try { await d.first().waitFor({ timeout: 1500 }); } catch (_) { break; } await d.first().click(); await espera(150); } };
  const docx = async (d) => ({ nombre: d.nombre, entradas: unzip(d.bytes).map(([k, v]) => [k,
    md5(v.toString('latin1').replace(/(w14:paraId|w14:textId)="[0-9A-Fa-f]+"/g, '').replace(/<w:id w:val="-?\d+"\/>/g, ''))]) });
  X.reqs.length = 0;
  await irModo(X, 'autorizacion');
  await R().locator('h3', { hasText: 'Autorización de Importación de Envases' }).waitFor({ timeout: 15000 });
  await S('inicial', 700);
  await R().locator('select').first().selectOption('00306900'); await S('elige-empresa');
  await R().locator('input[placeholder="Razón social (para guardar)"]').fill(''); await S('razon-vacia');
  await R().locator('input[placeholder="Razón social (para guardar)"]').click();
  await X.p.keyboard.type('  Nueva SA ', { delay: 15 });
  await R().locator('input[placeholder="00306900"]').fill(' 00-123 '); await S('rne-tipeado');
  await btn('💾').click(); await S('rne-guardado', 700);
  await dlg('Aceptar'); await S('rne-guardado-cerrado');
  ctl.falla.rne_guardar = { status: 500, body: { error: 'RNE duplicado' } };
  await btn('💾').click(); await S('rne-error', 700);
  await dlg('Aceptar');
  await subir('aut-factura', [pdfF('factura.pdf', F.factura)]);
  await subir('aut-pl', [{ name: 'pl.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', buffer: F.pl }]);
  await subir('aut-bl', [pdfF('bl.pdf', F.bl)]);
  await subir('aut-certs', [pdfF('ce1.pdf', F.ce), pdfF('ce2.pdf', F.ce2)]);
  await R().locator('#aut-fecha-arribo').fill('2026-10-20');
  await S('docs-cargados');
  ctl.falla.leer = { status: 500, body: { error: 'Timeout de la IA' } };
  await btn('🔍 Leer documentos y armar formulario').click(); await S('leer-error', 3000);
  ctl.demora = 1500;
  await btn('🔍 Leer documentos y armar formulario').click(); await S('leer-cargando', 1000);
  await S('leer-ok', 2500);
  await campo('Departamento').click(); await X.p.keyboard.type('San Martín', { delay: 15 });
  await campo('Provincia').fill('');
  await campo('Unidad de medida', 1).selectOption('Kilogramo');
  await campo('Denominación').fill('Coladores de acero\ninoxidable 18/8');
  await campo('Factura n°').fill('HK/2026:0915*');
  await S('editado');
  await btn('⬇ Descargar Word completado').click(); await S('desc-dlg1', 400);
  await dlg('Volver'); await S('desc-volver');
  await btn('⬇ Descargar Word completado').click();
  await dlg('Descargar igual'); await S('desc-dlg-vacios', 400);
  await dlg('Completar'); await espera(500);
  V('foco-vacio', await X.p.evaluate(() => { const a = document.activeElement; return a ? [a.tagName, a.value, a.getAttribute('data-falta')] : null; }));
  await campo('Provincia').fill('Buenos Aires');
  V('word-1', await docx(await bajar(X, async () => { await btn('⬇ Descargar Word completado').click(); await dlgSi(2); })));
  await S('descargado', 600);
  await btn('Quitar').click(); await S('quitado-1');
  await btn('Quitar').click(); await S('quitado-2');
  await btn('⬇ Descargar Word completado').click(); await dlgSi(1); await S('desc-sin-cert', 300);
  V('word-2', await docx(await bajar(X, () => dlg('Descargar igual'))));
  await S('descargado-2', 600);
  await subir('aut-form', [{ name: 'mi-form.docx', mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', buffer: F.docx }]);
  await S('form-subido');
  V('word-3', await docx(await bajar(X, async () => { await btn('⬇ Descargar Word completado').click(); await dlgSi(3); })));
  await R().locator('.zone', { hasText: 'Formulario (.docx)' }).locator('.files-list button').click();
  await subir('aut-form', [{ name: 'roto.docx', mimeType: 'application/octet-stream', buffer: Buffer.from('no es zip') }]);
  await btn('⬇ Descargar Word completado').click(); await dlgSi(3);
  await S('docx-roto', 500);
  await btn('🗂️ Archivos Vs PDF SENASA').click(); await S('modo-archivos');
  await subir('aut-pd', [pdfF('pd.pdf', F.pd)]);
  await btn('🔍 Verificar archivos vs PDF devuelto').click(); await S('archivos-ok', 3500);
  await btn('📄 Formulario Vs PDF SENASA').click(); await S('modo-formpd');
  await subir('aut-formenv', [pdfF('enviado.pdf', F.enviado)]);
  await S('formpd-cargado');
  await btn('🔍 Comparar formulario vs PDF devuelto').click(); await S('formpd-ok', 2500);
  ctl.falla.contrastar_form_pd = { status: 403, body: { codigo: 'no_supervisor' } };
  await btn('🔍 Comparar formulario vs PDF devuelto').click(); await S('formpd-403', 2500);
  await R().locator('.zone', { hasText: 'Formulario enviado' }).locator('.files-list button').click();
  await subir('aut-formenv', [pdfF('escaneo.pdf', F.vacio)]);
  await btn('🔍 Comparar formulario vs PDF devuelto').click(); await S('formpd-sin-texto', 2500);
  await btn('📝 Crear formulario').click(); await S('vuelve-crear');
}

function fakeInal(ctl) {
  return async (p, m, json) => {
    const key = Object.keys(ctl.falla).find((k) => p.startsWith(k) && (!ctl.falla[k].accion || (json && json.accion === ctl.falla[k].accion)));
    if (key) { const r = ctl.falla[key]; delete ctl.falla[key]; return r; }
    if (p.startsWith('/inal-certificados') && m === 'GET') return { body: LISTA };
    if (json && json.accion === 'guardar_ncm') return { body: { ok: true } };
    if (json && json.accion === 'guardar') return { body: { ok: true, id: 99 } };
    if (p === '/inal-certificados') { if (ctl.demora) { await espera(ctl.demora); ctl.demora = 0; } return { body: ctl.uno ? EXTRAER_UNO : EXTRAER }; }
    return { body: {} };
  };
}
function fakeAut(ctl) {
  return async (p, m, json, parts) => {
    const acc = json ? json.accion : (parts ? (parts.find((x) => x.name === 'accion') || {}).value : null);
    if (ctl.falla[acc]) { const r = ctl.falla[acc]; delete ctl.falla[acc]; return r; }
    if (ctl.demora) { await espera(ctl.demora); ctl.demora = 0; }
    if (acc === 'rne_listar') return { body: { empresas: [{ razon_social: 'LOEKEMEYER HNOS SRL', rne: '00306900' }, { razon_social: 'CHEF SRL', rne: '02033344' }] } };
    if (acc === 'rne_guardar') return { body: { ok: true } };
    if (acc === 'leer') { const r = AUT(); if (parts.some((x) => x.name === 'pd_0')) Object.assign(r, CONTRASTE); return { body: r }; }
    if (acc === 'contrastar_form_pd') return { body: CONTRASTE };
    return { body: {} };
  };
}

// Archivos de prueba armados con las librerías del repo (pdf-lib y xlsx de impocomex/vendor).
async function fixtures(srvUrl) {
  const b = await chromium.launch(); const p = await (await b.newContext({ timezoneId: 'America/Argentina/Buenos_Aires', locale: 'es-AR' })).newPage();
  await p.clock.setFixedTime(new Date(RELOJ));
  await p.goto(srvUrl + '__ic.html', { waitUntil: 'load' });
  const out = await p.evaluate(async () => {
    const IC = window.IC; const PL = await IC.lib('pdf-lib'); const XM = await IC.lib('xlsx'); const X = XM.utils ? XM : XM.default;
    const pdf = async (lineas) => {
      const doc = await PL.PDFDocument.create(); const pg = doc.addPage([600, 800]);
      if (lineas) { const f = await doc.embedFont(PL.StandardFonts.Helvetica);
        for (let k = 0; k < 40; k++) pg.drawText(lineas[k % lineas.length] + ' LINEA ' + k + ' TEXTO DE RELLENO PARA LEER', { x: 20, y: 780 - k * 18, size: 9, font: f }); }
      return btoa(String.fromCharCode(...await doc.save()));
    };
    const wb = X.utils.book_new();
    X.utils.book_append_sheet(wb, X.utils.aoa_to_sheet([['ITEM', 'QTY', 'G.W.'], ['437E', 2400, 256.2], ['438E', 2400, 256.2]]), 'PL');
    const pl = new Uint8Array(X.write(wb, { type: 'array', bookType: 'xlsx' }));
    return { ce: await pdf(['CERTIFICADO CE-2026-0001-APN-INAL', 'TITULAR LOEKEMEYER HNOS SRL', 'CODIGOS 437E 438E']), anexo: await pdf(['ANEXO IF-2026-2', 'FABRICANTE KANGLI', 'MARCA LK']),
      factura: await pdf(['COMMERCIAL INVOICE HK/2026/0915', '437E 2400 PCS', '438E 2400 PCS']), bl: await pdf(['BILL OF LADING COSU6345678901']),
      ce1: await pdf(['CERTIFICADO CE-2024-00123456']), ce2: await pdf(['CERTIFICADO CE-2023-777']), pd: await pdf(['PD-2026-12345678-APN-DNIYCA#SENASA']),
      enviado: await pdf(['FORMULARIO ENVIADO RNE 00306900']), vacio: await pdf(null), pl: btoa(String.fromCharCode(...pl)) };
  });
  await b.close();
  const F = {}; for (const [k, v] of Object.entries(out)) F[k] = Buffer.from(v, 'base64');
  F.docx = fs.readFileSync(path.join(RAIZ, 'impocomex/plantillas/autorizacion-envases.docx'));
  const fixMd5 = {}; for (const [k, v] of Object.entries(F)) fixMd5[md5(v)] = k;
  return { F, fixMd5 };
}

(async () => {
  const t0 = Date.now();
  const srv = await servidor(); const url = `http://127.0.0.1:${srv.address().port}/`;
  const lado = GENERAR ? 'viejo' : 'nuevo';
  const esperado = GENERAR ? null : JSON.parse(fs.readFileSync(FIX, 'utf8'));
  const fallas = []; const salida = {};
  try {
    const { F, fixMd5 } = await fixtures(url);
    const FA = Object.assign({}, F, { ce: F.ce1 });
    const correr = async (nombre, flujo, fake, FF) => {
      const ctl = { falla: {}, demora: 0, uno: false };
      const X = await abrir(lado, url, fake(ctl), fixMd5);
      const C = corredor(X, esperado && esperado[nombre], nombre);
      try { await flujo(X, C, FF, ctl); } catch (e) { C.fallas.push(`${nombre}: excepción ${String(e && e.stack || e).slice(0, 600)}`); }
      if (X.errs.length) C.fallas.push(`${nombre}: errores en la página: ${X.errs.join(' | ')}`);
      if (!GENERAR && esperado[nombre] && C.LOG.length !== esperado[nombre].length) C.fallas.push(`${nombre}: ${C.LOG.length} pasos y el viejo ${esperado[nombre].length}`);
      salida[nombre] = C.LOG; fallas.push(...C.fallas);
      await X.b.close();
    };
    await Promise.all([
      correr('inal', flujoInal, fakeInal, F),
      correr('autorizacion', flujoAut, fakeAut, FA),
    ]);
    // «Vencimientos» del nuevo = INAL abierto en la solapa de vencimientos (en el viejo, InalMode tabInicial="vencimientos")
    if (!GENERAR) {
      const ctl = { falla: {}, demora: 0, uno: false };
      const X = await abrir('nuevo', url, fakeInal(ctl), fixMd5);
      await irModo(X, 'vencimientos');
      await X.root().locator('.stat').first().waitFor({ timeout: 15000 });
      const C = corredor(X, [esperado.inal[0]], 'vencimientos'); await C.S('venc-inicial');
      fallas.push(...C.fallas); await X.b.close();
    }
  } catch (e) { fallas.push('excepción: ' + (e && e.stack || e)); }
  srv.close();
  if (GENERAR) {
    if (fallas.length) { console.error('✗ no se pudo generar:\n  - ' + fallas.join('\n  - ')); process.exit(1); }
    fs.writeFileSync(FIX, JSON.stringify(salida, null, 1) + '\n');
    console.log(`✓ esperado regenerado desde el VIEJO en ${path.relative(RAIZ, FIX)} (${salida.inal.length} + ${salida.autorizacion.length} pasos)`);
    return;
  }
  const seg = ((Date.now() - t0) / 1000).toFixed(1);
  if (fallas.length) { console.error(`✗ impo-comex-paridad-inal (${seg} s):\n  - ` + fallas.slice(0, 12).join('\n  - ') + (fallas.length > 12 ? `\n  … y ${fallas.length - 12} más` : '')); process.exit(1); }
  console.log(`✓ impo-comex-paridad-inal (${seg} s): INAL/Vencimientos (${esperado.inal.length} pasos) y Autorización (${esperado.autorizacion.length} pasos) se comportan igual que el viejo: pantallas, pedidos a la puerta, Excel y Word`);
})();
