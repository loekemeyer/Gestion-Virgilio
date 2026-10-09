/* Paridad IMPO COMEX nuevo (impocomex/, sin build) vs viejo (impo-comex/, React): modos
   «Verificar Docs Separados» (multidoc) y «Verificación Completa» (full), con la cabecera y los ítems
   editables, el visor de PDFs, Corregir Relevamiento y los diálogos.
   Corre los flujos de punta a punta SÓLO contra el nuevo (rápido, sin red) y compara con lo que hizo el
   VIEJO con los mismos pasos y las mismas respuestas falsas de la puerta Impo_Comex_web (ESPERADO, medido
   el 09/10/2026 corriendo los dos lado a lado):
     - la secuencia de pedidos a la puerta (método, ruta y cuerpo: JSON entero; en FormData cada campo,
       su valor —el texto extraído en el navegador va como largo + md5— y los archivos por nombre);
     - una huella de lo que se ve después de cada paso (texto, botones y si están deshabilitados, valores
       de los campos, el modal de Corregir Relevamiento y los diálogos);
     - las descargas (nombre, y que el archivo bajado sea el que mandó la puerta).
   Sale 1 si algo difiere. VER=1 imprime lo que se ve en el paso que difiere. */
const fs = require("fs");
const path = require("path");
const http = require("http");
const crypto = require("crypto");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const RAIZ = path.join(__dirname, "..");
const ESPERADO = {"multidoc":{"A":{"pedidos":["A8|POST /verify-multi-doc|nro_carga= & despacho_text=(5700 car · 4db9471b9c) DESPACHO OM-1993 26001IC04000123A LI & despacho_file@despacho 123.pdf & ci_text=(939 car · d9a7481a7c) === HOJA \"Hoja1\" ===\r\nCODE,DESCRIPTIO & ci_file@invoice_A.xlsx & pl_text=(1889 car · c27d1d6b81) PACKING LIST 2 LINEA 0 ITEM 437E CAN & pl_file@otro packing.pdf & bl_file@6 BL telex.png & libre_circulacion_text=(1249 car · 49c81010ad) LIBRE CIRCULACION INAL LINEA 0 ITEM  & libre_circulacion_file@carga.zip › INAL › libre_circulacion.pdf & pesaje_file@gemez a.pdf & preview=true","A10|POST /editar|{\"accion\":\"productos_buscar\",\"codigo\":\"437E\"}","A10|POST /editar|{\"accion\":\"producto_insert\",\"producto\":{\"cod_lk\":\"437E\",\"cod_ch\":null,\"marca\":\"LK\",\"nombre_producto\":\"Codigo 437E (LK) no está en el relevamiento\",\"proveedor\":\"KANGLI\",\"inal\":null}}","A11|POST /editar|{\"accion\":\"despacho_get\",\"id\":55}","A11|POST /editar|{\"accion\":\"despacho_update\",\"id\":55,\"campo\":\"aduana\",\"valor\":\"BUENOS AIRES\"}","A11|POST /editar|{\"accion\":\"despacho_update\",\"id\":55,\"campo\":\"canal_selectivo\",\"valor\":\"ROJO\"}","A11|POST /editar|{\"accion\":\"despacho_update\",\"id\":55,\"campo\":\"total_bultos\",\"valor\":null}","A12b|POST /editar|{\"accion\":\"despacho_get\",\"id\":55}","A14a|POST /verify-multi-doc|nro_carga=China 49 & despacho_text={\"nro_despacho\":\"26001IC04000123A\",\"items\":[{\"codigo\":\"437E\" & despacho_pre_merged=true & ci_text={\"proveedor\":\"Ningbo\",\"items\":[{\"codigo\":\"437E\",\"qty\":100}]} & ci_pre_merged=true & bl_text={\"bl\":\"MSCU123\"} & bl_pre_merged=true","A14|POST /verify-multi-doc|nro_carga=China 49 & despacho_text={\"nro_despacho\":\"26001IC04000123A\",\"items\":[{\"codigo\":\"437E\" & despacho_pre_merged=true & ci_text={\"proveedor\":\"Ningbo\",\"items\":[{\"codigo\":\"437E\",\"qty\":100}]} & ci_pre_merged=true & bl_text={\"bl\":\"MSCU123\"} & bl_pre_merged=true","A15|POST /verify-multi-doc|nro_carga=China 49 & despacho_text=(5700 car · 4db9471b9c) DESPACHO OM-1993 26001IC04000123A LI & despacho_file@despacho 123.pdf & ci_text=(939 car · d9a7481a7c) === HOJA \"Hoja1\" ===\r\nCODE,DESCRIPTIO & ci_file@invoice_A.xlsx & pl_text=(1889 car · c27d1d6b81) PACKING LIST 2 LINEA 0 ITEM 437E CAN & pl_file@otro packing.pdf & bl_file@6 BL telex.png & libre_circulacion_text=(1249 car · 49c81010ad) LIBRE CIRCULACION INAL LINEA 0 ITEM  & libre_circulacion_file@carga.zip › INAL › libre_circulacion.pdf & pesaje_file@gemez a.pdf & preview=true","A16|POST /verify-multi-doc|nro_carga=China 49 & despacho_text=(5700 car · 4db9471b9c) DESPACHO OM-1993 26001IC04000123A LI & despacho_file@despacho 123.pdf & ci_text=(939 car · d9a7481a7c) === HOJA \"Hoja1\" ===\r\nCODE,DESCRIPTIO & ci_file@invoice_A.xlsx & pl_text=(1889 car · c27d1d6b81) PACKING LIST 2 LINEA 0 ITEM 437E CAN & pl_file@otro packing.pdf & bl_file@6 BL telex.png & libre_circulacion_text=(1249 car · 49c81010ad) LIBRE CIRCULACION INAL LINEA 0 ITEM  & libre_circulacion_file@carga.zip › INAL › libre_circulacion.pdf & pesaje_file@gemez a.pdf & preview=true","A17|POST /verify-multi-doc|nro_carga=China 49 & despacho_text=(5700 car · 4db9471b9c) DESPACHO OM-1993 26001IC04000123A LI & despacho_file@despacho 123.pdf & ci_text=(939 car · d9a7481a7c) === HOJA \"Hoja1\" ===\r\nCODE,DESCRIPTIO & ci_file@invoice_A.xlsx & pl_text=(1889 car · c27d1d6b81) PACKING LIST 2 LINEA 0 ITEM 437E CAN & pl_file@otro packing.pdf & bl_file@6 BL telex.png & libre_circulacion_text=(1249 car · 49c81010ad) LIBRE CIRCULACION INAL LINEA 0 ITEM  & libre_circulacion_file@carga.zip › INAL › libre_circulacion.pdf & pesaje_file@gemez a.pdf & preview=true","A18|POST /verify-multi-doc|nro_carga=China 49 & despacho_text=(5700 car · 4db9471b9c) DESPACHO OM-1993 26001IC04000123A LI & despacho_file@despacho 123.pdf & ci_text=(939 car · d9a7481a7c) === HOJA \"Hoja1\" ===\r\nCODE,DESCRIPTIO & ci_file@invoice_A.xlsx & pl_text=(1889 car · c27d1d6b81) PACKING LIST 2 LINEA 0 ITEM 437E CAN & pl_file@otro packing.pdf & bl_file@6 BL telex.png & libre_circulacion_text=(1249 car · 49c81010ad) LIBRE CIRCULACION INAL LINEA 0 ITEM  & libre_circulacion_file@carga.zip › INAL › libre_circulacion.pdf & pesaje_file@gemez a.pdf & preview=true","A19|POST /editar|{\"accion\":\"cargas_hoy\",\"desde\":\"2026-10-09T00:00:00.000Z\"}"],"snaps":{"A0 inicial":"2c7f1664a934","A1 soltar todo junto":"cc69cfd9a66b","A2 quitar PL":"d087125e6108","A3 subir PL suelto":"87b1c0bb8896","A4 pesaje con 2 archivos (single)":"fa03f3f5adea","A5 ver PDFs":"0f85c9413457","A6 pestaña 3 del visor":"bbd8b8e8cd93","A7 ocultar PDFs":"d84685ae780c","A8 durante":"8f9ebfd84dd6","A8 resultado":"9b90b629360e","A9 detalles debug":"e2e23b362578","A10 corregir relevamiento":"7727adaf0412","A10 buscado":"5a37ff36a1f4","A10 cerrado":"57f14d67c816","A10b corregir otra alerta y cerrar":"fb76084f9343","A10b cerrado":"c850d578f23e","A11 cabecera":"0cc7535839b8","A11 aduana":"280c0889abb6","A11 canal":"cb67fedef256","A11 bultos vacío":"41827da9fc63","A12 ocultar cabecera":"7638fa188fb7","A12b mostrar de nuevo":"bfd3725f7d95","A13 nro de carga":"a2da853dc808","A14a guardar con error":"c16a2479be60","A14 guardar en DB":"c66eff8f91b8","A15 error 500":"58dc3656d249","A16 error 502":"fb32e06f1325","A17 duplicado":"799f9587188c","A18 sin despacho":"b3538fc17a82","A19 volver al inicio y entrar de nuevo":"f80c34c0fd99"},"dialogos":["✓ Relevamiento actualizado.\nAceptar"],"descargas":[]},"B":{"pedidos":["B2|POST /verify-lakout|nro_carga=China 50 & chunk_index=0 & chunk_total=2 & chunk_pages_desc=paginas 1-5 & pdf_text=x1\r\n\r\nx2\r\n\r\nx3\r\n\r\nx4\r\n\r\nx5 & file@despacho scan.pdf-chunk1.pdf","B2|POST /verify-lakout|nro_carga=China 50 & chunk_index=1 & chunk_total=2 & chunk_pages_desc=paginas 6-7 & pdf_text=x6\r\n\r\nx7 & file@despacho scan.pdf-chunk2.pdf","B2|POST /verify-multi-doc|nro_carga=China 50 & despacho_file@despacho scan.pdf & ci_text=(939 car · d9a7481a7c) === HOJA \"Hoja1\" ===\r\nCODE,DESCRIPTIO & ci_file@ci.xlsx & preview=true","B3|POST /verify-lakout|nro_carga=China 50 & chunk_index=0 & chunk_total=2 & chunk_pages_desc=paginas 1-5 & pdf_text=x1\r\n\r\nx2\r\n\r\nx3\r\n\r\nx4\r\n\r\nx5 & file@despacho scan.pdf-chunk1.pdf","B3|POST /verify-lakout|nro_carga=China 50 & chunk_index=1 & chunk_total=2 & chunk_pages_desc=paginas 6-7 & pdf_text=x6\r\n\r\nx7 & file@despacho scan.pdf-chunk2.pdf","B3|POST /verify-multi-doc|nro_carga=China 50 & despacho_text={\"nro_despacho\":\"26001IC04000777C\",\"aduana\":\"BUENOS AIRES\",\" & despacho_pre_merged=true & despacho_file@despacho scan.pdf & ci_text=(939 car · d9a7481a7c) === HOJA \"Hoja1\" ===\r\nCODE,DESCRIPTIO & ci_file@ci.xlsx & preview=true"],"snaps":{"B1 despacho escaneado + CI":"ffb4e154e376","B2 verificar con un tramo que falla":"76fa960ae04a","B3 verificar con tramos ok":"9ad9a28a83aa","B4 quitar todo":"9eafd1d15a46"},"dialogos":[],"descargas":[]}},"full":{"A":{"pedidos":["A4|POST /verify-lakout|nro_carga=China 48 & file@despacho.pdf & preview=true","A4|POST /analyze-docs|files@bl.png & nro_carga=China 48 & pdf_texts=(4231 car · 949a92950a) {\"PI china 48.xlsx\":\"=== HOJA \\\"Hoja & nombres_solo_texto=[\"PI china 48.xlsx\",\"CI.pdf\",\"libre a.pdf\"] & preview=true","A6|POST /verify-lakout|nro_carga=China 48 & pdf_text={\"nro_despacho\":\"26001IC04000999B\",\"items\":[{\"codigo\":\"437E\" & filename=despacho.pdf & pre_merged=true","A6|POST /analyze-docs|nro_carga=China 48 & pre_merged=true & pre_articulos=[{\"codigo\":\"437E\",\"cantidad\":100},{\"codigo\":\"438E\",\"cantidad & pre_reporte=# Reporte de verificación\r\n\r\n**Proveedor:** Ningbo\r\n\r\n| Códi & pre_proveedor=Ningbo Hong Tai & pre_nro_carga_detectado=48 & carga_id=77","A6|GET /export-excel?carga_id=77&format=json|","A6|POST /editar|{\"accion\":\"items_list\",\"tabla\":\"articulos_carga\",\"filtro_id\":77}","A7|POST /editar|{\"accion\":\"item_update\",\"tabla\":\"articulos_carga\",\"id\":2,\"campo\":\"descripcion\",\"valor\":\"Colador grande\"}","A7|GET /export-excel?carga_id=77&format=json|","A8|POST /editar|{\"accion\":\"item_update\",\"tabla\":\"articulos_carga\",\"id\":1,\"campo\":\"cantidad\",\"valor\":null}","A8|GET /export-excel?carga_id=77&format=json|","A9|POST /editar|{\"accion\":\"item_insert\",\"tabla\":\"articulos_carga\",\"filtro_id\":77}","A9|GET /export-excel?carga_id=77&format=json|","A11|POST /editar|{\"accion\":\"item_delete\",\"tabla\":\"articulos_carga\",\"id\":2}","A11|GET /export-excel?carga_id=77&format=json|","A12|GET /export-excel?carga_id=77|","A13|GET /export-excel?carga_id=77|","A14|POST /verify-lakout|nro_carga=China 48 & file@despacho.pdf & preview=true","A14|POST /analyze-docs|files@bl.png & nro_carga=China 48 & pdf_texts=(4231 car · 949a92950a) {\"PI china 48.xlsx\":\"=== HOJA \\\"Hoja & nombres_solo_texto=[\"PI china 48.xlsx\",\"CI.pdf\",\"libre a.pdf\"] & preview=true"],"snaps":{"A0 inicial":"2479772b556d","A1 archivos":"bf6c08e13b49","A2 quitar uno":"be778cd1a7d6","A3 nro":"d958538e1c5b","A4 durante":"62c99fc3104d","A4 resultado":"acefb62d12b7","A5 reporte markdown":"399c3c8723d4","A6 guardar":"e388a636fef6","A7 editar descripción":"611fbae04d22","A8 editar número a vacío":"43ede0156c2e","A9 agregar fila":"84e564cf220e","A10 borrar fila (cancelar)":"99b4b9bd6ade","A11 borrar fila":"0bd974a091c4","A12 excel":"60408b00d555","A13 excel falla":"3048c9178295","A14 verificar con error":"45694a18bb5b"},"dialogos":["¿Eliminar este artículo?\nCancelar\nSí, borrar","¿Eliminar este artículo?\nCancelar\nSí, borrar","No se pudo descargar el Excel: No hay artículos\nAceptar"],"descargas":["verificacion_carga_77.xlsx"]},"B":{"pedidos":["B2|POST /verify-lakout|nro_carga=China 51 & pdf_text=(5700 car · 4db9471b9c) DESPACHO OM-1993 26001IC04000123A LI & filename=desp largo.pdf & preview=true","B2|POST /analyze-docs|nro_carga=China 51 & pdf_texts=(955 car · 5ecd7ecd5a) {\"pi.xlsx\":\"=== HOJA \\\"Hoja1\\\" ===\\nC & nombres_solo_texto=[\"pi.xlsx\"] & preview=true","B3|POST /verify-lakout|nro_carga=China 51 & pdf_text={\"nro_despacho\":\"26001IC04000999B\",\"items\":[{\"codigo\":\"437E\" & filename=despacho.pdf & pre_merged=true","B3|POST /analyze-docs|nro_carga=China 51 & pre_merged=true & pre_articulos=[{\"codigo\":\"437E\",\"cantidad\":100},{\"codigo\":\"438E\",\"cantidad & pre_reporte=# Reporte de verificación\r\n\r\n**Proveedor:** Ningbo\r\n\r\n| Códi & pre_proveedor=Ningbo Hong Tai & pre_nro_carga_detectado=48","B3|GET /export-excel?carga_id=88&format=json|","B3|POST /editar|{\"accion\":\"items_list\",\"tabla\":\"articulos_carga\",\"filtro_id\":88}"],"snaps":{"B1 despacho largo + PI, sin nro":"03b529c29c46","B2 nro + verificar":"0628cc7d7120","B3 guardar, sin carga del despacho y tabla que falla":"03c0f46e61b1"},"dialogos":["Error cargando items: tabla bloqueada\nAceptar"],"descargas":[]},"C":{"pedidos":["C2|POST /analyze-docs|files@pl.png & nro_carga=C1 & pdf_texts=(3855 car · 9d99577ffb) {\"ci1.pdf\":\"COMMERCIAL INVOICE LINEA & nombres_solo_texto=[\"ci1.pdf\",\"ci2.pdf\"] & preview=true","C3|POST /analyze-docs|nro_carga=C1 & pre_merged=true & pre_articulos=[{\"codigo\":\"437E\",\"cantidad\":100},{\"codigo\":\"438E\",\"cantidad & pre_reporte=# Reporte de verificación\r\n\r\n**Proveedor:** Ningbo\r\n\r\n| Códi & pre_proveedor=Ningbo Hong Tai & pre_nro_carga_detectado=48","C3|POST /editar|{\"accion\":\"items_list\",\"tabla\":\"articulos_carga\",\"filtro_id\":88}","C3|GET /export-excel?carga_id=88&format=json|"],"snaps":{"C1 un solo tipo (no habilita)":"40077cfab82c","C2 sin despacho: sólo analyze-docs":"80da335696f9","C3 guardar (carga sale de analyze-docs)":"4c64c2fce74e"},"dialogos":[],"descargas":[]}}};

const PAGINA = `<!doctype html><html><head><meta charset="utf-8"><title>ic</title>
<script>window.APP_VERSION = "prueba";
window.sb = { auth: { getSession: async () => ({ data: { session: { access_token: "tok" } } }) }, rpc: async () => ({ data: true }) };</script>
</head><body><script src="impocomex/ic-base.js"></script></body></html>`;
const TIPOS = { ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css", ".json": "application/json",
  ".wasm": "application/wasm", ".docx": "application/octet-stream", ".html": "text/html" };
const md5 = (b) => crypto.createHash("md5").update(b).digest("hex").slice(0, 10);
const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
const J = (o, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(o) });
const norm = (s) => String(s || "").replace(/[ \t ]+/g, " ").replace(/\s*\n\s*/g, "\n").trim();

// Multipart → lista de partes (nombre, archivo, tipo, tamaño, md5 / valor).
function partes(buf, ct) {
  const m = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(ct || "");
  if (!m) return null;
  const bnd = Buffer.from("--" + (m[1] || m[2]));
  const out = [];
  let i = buf.indexOf(bnd);
  while (i >= 0) {
    const ini = i + bnd.length;
    if (buf.slice(ini, ini + 2).toString() === "--") break;
    const fin = buf.indexOf(bnd, ini);
    if (fin < 0) break;
    const parte = buf.slice(ini + 2, fin - 2);
    const sep = parte.indexOf("\r\n\r\n");
    const cab = parte.slice(0, sep).toString("utf8");
    const cuerpo = parte.slice(sep + 4);
    const nombre = (/name="([^"]*)"/.exec(cab) || [])[1];
    const archivo = (/filename="([^"]*)"/.exec(cab) || [])[1];
    const tipo = (/content-type:\s*([^\r\n]+)/i.exec(cab) || [])[1];
    if (archivo !== undefined) out.push({ campo: nombre, archivo, tipo, ...(/-chunk\d+\.pdf$/.test(archivo) ? { bytes: Math.round(cuerpo.length / 100) * 100 + "~", md5: "(chunk pdf-lib)" } : { bytes: cuerpo.length, md5: md5(cuerpo) }) });
    else { const v = cuerpo.toString("utf8"); out.push({ campo: nombre, valor: v.length > 400 ? `(${v.length} car · ${md5(Buffer.from(v))}) ${v.slice(0, 80)}` : v }); }
    i = fin;
  }
  return out;
}


function fixtures(p) {
  return p.evaluate(async () => {
    const IC = window.IC;
    const PL = await IC.lib("pdf-lib");
    const X = await IC.lib("xlsx");
    const ff = await IC.lib("fflate");
    const fecha = new Date("2026-10-01T12:00:00Z");
    async function pdfTexto(lineas, paginas = 1, opt = {}) {
      const doc = await PL.PDFDocument.create();
      doc.setCreationDate(fecha); doc.setModificationDate(fecha);
      const font = await doc.embedFont(PL.StandardFonts.Helvetica);
      for (let k = 0; k < paginas; k++) {
        const pg = doc.addPage([600, 800]);
        lineas.forEach((t, i) => pg.drawText(t.replace("{p}", String(k + 1)), { x: 20, y: 780 - i * 18, size: 9, font }));
        if (opt.rect) pg.drawRectangle({ x: 50, y: 50, width: 300, height: 300, color: PL.rgb(0.8, 0.8, 0.8) });
      }
      return doc.save({ useObjectStreams: false });
    }
    const largo = (pref, n) => Array.from({ length: n }, (_, i) => `${pref} LINEA ${i} ITEM 437E CANTIDAD ${100 + i} FOB USD 12.50 NCM 7323.93.00`);
    const b64 = (u8) => { let s = ""; const a = new Uint8Array(u8); for (let i = 0; i < a.length; i += 0x8000) s += String.fromCharCode.apply(null, a.subarray(i, i + 0x8000)); return btoa(s); };
    const out = {};
    out.despachoTexto = b64(await pdfTexto(largo("DESPACHO OM-1993 26001IC04000123A", 30), 2));
    out.despachoScan = b64(await pdfTexto(["x{p}"], 7, { rect: true }));
    out.despachoCorto = b64(await pdfTexto(["DESPACHO CORTO 26001IC04000999B", "CANAL VERDE", "ADUANA BUENOS AIRES", "IMPORTADOR LOEKEMEYER", "ITEM 437E 100"], 1));
    out.packing = b64(await pdfTexto(largo("PACKING LIST", 25), 1));
    out.packing2 = b64(await pdfTexto(largo("PACKING LIST 2", 25), 1));
    out.corto = b64(await pdfTexto(["TICKET BALANZA GEMEZ", "PESO 1234 KG"], 1));
    out.random = b64(await pdfTexto(largo("OTRO DOC", 5), 1));
    out.ciPdf = b64(await pdfTexto(largo("COMMERCIAL INVOICE", 25), 1));
    out.libre = b64(await pdfTexto(largo("LIBRE CIRCULACION INAL", 15), 1));
    const wb = X.utils.book_new();
    X.utils.book_append_sheet(wb, X.utils.aoa_to_sheet([["CODE", "DESCRIPTION", "QTY", "PRICE"], ...Array.from({ length: 20 }, (_, i) => [`43${i}E`, `Producto de prueba numero ${i}`, 100 + i, 1.25 + i])]), "Hoja1");
    out.xlsx = b64(X.write(wb, { type: "array", bookType: "xlsx" }));
    const wbx = X.utils.book_new();
    X.utils.book_append_sheet(wbx, X.utils.aoa_to_sheet([["Código", "FOB USD"], ["437E", 12.5]]), "Verificacion");
    out.export = b64(X.write(wbx, { type: "array", bookType: "xlsx" }));
    const cv = document.createElement("canvas"); cv.width = 40; cv.height = 30;
    const cx = cv.getContext("2d"); cx.fillStyle = "#c00"; cx.fillRect(0, 0, 40, 30);
    out.png = b64(new Uint8Array(await (await new Promise((ok) => cv.toBlob(ok, "image/png"))).arrayBuffer()));
    out.zip = b64(ff.zipSync({ "INAL/libre_circulacion.pdf": Uint8Array.from(atob(out.libre), (c) => c.charCodeAt(0)), "INAL/nota.txt": new Uint8Array([65]) }, { mtime: fecha }));
    return out;
  });
}

// ── respuestas falsas de la puerta (las mismas que recibió el viejo) ─────────────────────
function rutasMultidoc(st) {
  return async (reg) => {
    const p = reg.path, b = reg.cuerpo || {};
    if (p === "/editar") {
      if (b.accion === "despacho_get") return J({ data: { id: b.id, nro_despacho: "26001IC04000123A", fecha_oficializacion: "2026-09-30", aduana: null, canal_selectivo: "VERDE", modo_envio: "FCL", total_bultos: 120, valor_fob_total: 15000.5, importador_nombre: "LOEKEMEYER HNOS" } });
      if (b.accion === "despacho_update") return J({ data: { ok: true } });
      if (b.accion === "productos_buscar") return J({ data: [{ id: 9, cod_lk: "437E", cod_ch: null, marca: "LK", nombre_producto: "Colador", inal: "SI" }] });
      if (b.accion === "producto_insert") return J({ data: { id: 10 } });
      return J({ data: [] });
    }
    if (p === "/verify-lakout") {
      st.lakout = (st.lakout || 0) + 1;
      const idx = (reg.cuerpo.find((x) => x.campo === "chunk_index") || {}).valor;
      if (st.fase === "chunkFalla" && idx === "1") return J({ error: "Chunk ilegible" }, 500);
      return J({ data: { nro_despacho: idx === "0" ? "26001IC04000777C" : null, aduana: idx === "1" ? "BUENOS AIRES" : null,
        items: [{ codigo: idx === "0" ? "437E" : "438E", marca: "LK", ncm: "7323.93.00.100A", cantidad: 100 + Number(idx), valor_fob: 50 }], legibilidad: idx === "0" ? "buena" : "media" } });
    }
    if (p === "/verify-multi-doc") {
      const pre = reg.cuerpo.some((x) => x.campo === "preview");
      if (st.fase === "lento") await dormir(1500);
      if (st.fase === "error500") return J({ error: "Se cayó el servidor de IA" }, 500);
      if (st.fase === "error502") return { status: 502, contentType: "text/plain", body: "Bad gateway" };
      if (st.fase === "duplicado") return J({ duplicado: true, mensaje: "La carga China 49 ya tiene el despacho 26001IC04000123A guardado.", preview: true, slots_processed: ["despacho", "ci"], nro_carga: "China 49", costo_usd: 0, duracion_ms: 120, items_count: 0 });
      if (st.fase === "sinDespacho") return J({ preview: true, slots_processed: ["ci", "pl"], nro_carga: null, costo_usd: 0.05, duracion_ms: 30000, items_count: 4, nro_despacho: null, alertas: [], advertencias: [], parsed_data: { ci: { items: [1] } } });
      if (!pre) return J({ preview: false, nro_carga: "China 49", nro_despacho: "26001IC04000123A", items_count: 12, slots_processed: ["despacho", "ci", "bl"], costo_usd: 0, duracion_ms: 900, despacho_id: 56, alertas: [], advertencias: [{ descripcion: "Guardado con advertencias" }] });
      return J({
        preview: true, nro_carga: "China 49", nro_despacho: "26001IC04000123A", items_count: 12,
        slots_processed: ["despacho", "ci", "bl", "libre_circulacion"], costo_usd: 0.123456, duracion_ms: 65432, despacho_id: 55,
        alertas: [
          { severidad: "critica", tipo: "codigo_no_relevamiento", descripcion: "Codigo 437E (LK) no está en el relevamiento" },
          { severidad: "importante", tipo: "diferencia_cantidad", descripcion: "Item 438E: CI dice 100 y PL dice 90 <b>ojo</b>" },
          { severidad: "menor", tipo: "marca_mismatch_relevamiento", descripcion: "Item 439E: marca CH en relevamiento" },
          { severidad: "info", tipo: "otro", descripcion: "Todo lo demás cuadra" },
        ],
        advertencias: [{ tipo: "texto_corto", descripcion: "El PL vino escaneado" }, { descripcion: "Sin tipo" }],
        parsed_data: { despacho: { nro_despacho: "26001IC04000123A", items: [{ codigo: "437E" }] }, ci: { proveedor: "Ningbo", items: [{ codigo: "437E", qty: 100 }] }, pl: null, bl: { bl: "MSCU123" } },
      });
    }
    return J({});
  };
}

function rutasFull(st) {
  let filas = null;
  return async (reg) => {
    const p = reg.path, b = reg.cuerpo || {};
    const campo = (n) => (Array.isArray(b) ? (b.find((x) => x.campo === n) || {}).valor : undefined);
    if (p === "/editar") {
      if (b.accion === "items_list") {
        if (st.fase === "itemsFalla") return J({ error: "tabla bloqueada" }, 500);
        filas = filas || [{ id: 1, codigo: "437E", descripcion: "Colador", cantidad: 100, cajas: 10, precio: 1.5, total: 150 }, { id: 2, codigo: "438E", descripcion: null, cantidad: 50, cajas: null }];
        return J({ data: filas });
      }
      if (b.accion === "item_update") return J({ data: { ok: true } });
      if (b.accion === "item_insert") return J({ data: { id: 3, codigo: null, descripcion: null } });
      if (b.accion === "item_delete") return J({ data: { ok: true } });
      return J({ data: [] });
    }
    if (p === "/verify-lakout") {
      if (campo("pre_merged") === "true") return J({ carga_id: st.sinDesp ? null : 77, despacho_id: 9, preview: false });
      return J({ preview: true, nro_carga: "China 48", proveedor: "Ningbo Hong Tai", costo_usd: 0.05, modelo: "claude-sonnet", items_count: 10,
        alertas: [{ severidad: "critica", descripcion: "El despacho no coincide con la CI" }], advertencias: [{ tipo: "w1", descripcion: "Vapor ilegible" }],
        data: { nro_despacho: "26001IC04000999B", items: [{ codigo: "437E", cantidad: 100 }] } });
    }
    if (p === "/analyze-docs") {
      if (st.fase === "iaCaida") return J({ error: "IA caída" }, 500);
      if (campo("pre_merged") === "true") return J({ carga_id: 88, preview: false });
      if (st.fase === "lento") await dormir(1200);
      return J({ preview: true, articulos: [{ codigo: "437E", cantidad: 100 }, { codigo: "438E", cantidad: 50 }], articulos_count: 2,
        reporte: "# Reporte de verificación\n\n**Proveedor:** Ningbo\n\n| Código | Cant |\n|---|---|\n| 437E | 100 |\n\n- item uno\n- item <b>dos</b>",
        proveedor: "Ningbo Hong Tai", nro_carga_detectado: "48", costo_usd: 0.0123, modelo: "claude-haiku",
        alertas: [{ severidad: "importante", descripcion: "Precio distinto al pedido" }], advertencias: [] });
    }
    if (p.startsWith("/export-excel")) {
      if (/format=json/.test(p)) {
        st.json = (st.json || 0) + 1;
        return J({ rows: [{ "Código": "437E", "Descripción": "Colador", "FOB USD": 12.5, Cantidad: 100 + st.json, "CIF USD": 0, Obs: null, Vacio: "" }] });
      }
      if (st.fase === "excelFalla") return J({ error: "No hay artículos" }, 404);
      return { status: 200, contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", body: Buffer.from(st.FX.export, "base64") };
    }
    return J({});
  };
}


// ── el operador ──────────────────────────────────────────────────────────────────────────
function driver(S, FX) {
  const p = S.p;
  const R = () => p.locator(S.raiz);
  const out = { pasos: [], descargas: [], dialogos: [] };
  let actual = null;
  const pend = () => S.pedidos.filter((x) => !x.hecho).length;
  async function estable() {
    let prev = null;
    for (let i = 0; i < 80; i++) {
      await p.waitForTimeout(150);
      const t = await p.evaluate((s) => (document.querySelector(s) || {}).innerText || "", S.raiz).catch(() => "");
      const ocupado = /Abriendo archivos|Cargando\.\.\.|Cargando cabecera|⏳ Guardando|Procesando\.\.\.|Preparando\.\.\.|\[\d\/\d\]/.test(t) || S.ver.enVuelo > 0;
      if (!ocupado && t === prev) return;
      prev = t;
    }
  }
  const file = (nombre, clave, tipo) => ({ name: nombre, mimeType: tipo || (/\.pdf$/.test(nombre) ? "application/pdf" : /\.png$/.test(nombre) ? "image/png" : /\.zip$/.test(nombre) ? "application/zip" : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"), buffer: Buffer.from(FX[clave], "base64") });
  const D = {
    out,
    file,
    paso(n) { S.ver.paso = n; actual = { paso: n }; out.pasos.push(actual); },
    async snap(n) {
      await estable();
      const info = await p.evaluate((s) => {
        const r = document.querySelector(s);
        const dlg = [...document.querySelectorAll("[role=dialog],[role=alertdialog]")].map((d) => d.innerText);
        const fijos = r ? [...r.querySelectorAll("div")].filter((d) => getComputedStyle(d).position === "fixed") : [];
        const btns = r ? [...r.querySelectorAll("button")].filter((b) => b.offsetParent && !fijos.some((f) => f.contains(b))).map((b) => `${b.innerText.replace(/\s+/g, " ").trim()}${b.disabled ? " [disabled]" : ""}${b.title ? " {" + b.title + "}" : ""}`) : [];
        const prev = fijos.map((d) => d.style.display); fijos.forEach((d) => { d.style.display = "none"; });
        const texto = r ? r.innerText : "";
        fijos.forEach((d, i) => { d.style.display = prev[i]; });
        const h = [...document.querySelectorAll("h3")].find((x) => /Corregir Relevamiento/.test(x.textContent));
        const modal = h ? h.parentElement.parentElement.innerText : "";
        const vals = r ? [...r.querySelectorAll("input:not([type=file]),select,textarea")].filter((e) => e.offsetParent && !fijos.some((f) => f.contains(e))).map((e) => `${e.tagName[0]}:${e.value}${e.disabled ? "[dis]" : ""}`) : [];
        return { texto, btns, dlg, modal, vals };
      }, S.raiz);
      out.pasos.push({ snap: n || actual.paso, texto: norm(info.texto), btns: info.btns, dlg: info.dlg.map(norm), modal: norm(info.modal), vals: info.vals });
    },
    async subir(zona, files) {
      await p.setInputFiles(S.inputId(zona), files);
      await estable();
    },
    async soltar(zona, files) {
      await p.evaluate(({ sel, fs }) => {
        const dt = new DataTransfer();
        for (const f of fs) dt.items.add(new File([Uint8Array.from(atob(f.b64), (c) => c.charCodeAt(0))], f.name, { type: f.mimeType }));
        const drop = document.querySelector(sel).closest(".zone").querySelector(".drop");
        drop.dispatchEvent(new DragEvent("dragover", { bubbles: true, cancelable: true, dataTransfer: dt }));
        drop.dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: dt }));
      }, { sel: S.inputId(zona), fs: files.map((f) => ({ name: f.name, mimeType: f.mimeType, b64: f.buffer.toString("base64") })) });
      await estable();
    },
    async btn(texto, alcance) {
      const loc = (alcance === "pagina" ? p : R()).locator("button", { hasText: texto }).first();
      for (let i = 0; i < 20; i++) { if (await loc.count()) break; await p.waitForTimeout(150); }
      await loc.click();
      await p.waitForTimeout(80);
    },
    async dialogo(boton) {
      const d = p.locator("[role=dialog],[role=alertdialog]").first();
      await d.waitFor({ timeout: 8000 });
      out.dialogos.push({ paso: actual && actual.paso, texto: norm(await d.innerText()) });
      await d.locator("button", { hasText: boton }).first().click();
      await p.waitForTimeout(100);
    },
    async llenar(sel, v) { const l = p.locator(sel).first(); await l.click(); await l.fill(v); },
    async blur(sel) { await p.locator(sel).first().evaluate((e) => e.blur()); await p.waitForTimeout(50); },
    async elegir(sel, v) { await p.locator(sel).first().selectOption(v); },
    async esperaPedido(path, n = 1) {
      for (let i = 0; i < 200; i++) { if (S.pedidos.filter((x) => x.path.startsWith(path)).length >= n) return; await p.waitForTimeout(50); }
      throw new Error("no llegó " + path);
    },
    async descarga(boton) {
      const [dl] = await Promise.all([p.waitForEvent("download", { timeout: 10000 }), D.btn(boton)]);
      const f = await dl.path();
      const buf = fs.readFileSync(f);
      out.descargas.push({ paso: actual && actual.paso, nombre: dl.suggestedFilename(), bytes: buf.length, md5: md5(buf) });
    },
    estable,
    R,
    p,
  };
  return D;
}

// ── los flujos (idénticos a los que se corrieron en el viejo) ────────────────────────────
async function mdA(D, F, st, modo) {
  D.paso("A0 inicial"); await D.snap();
  D.paso("A1 soltar todo junto");
  await D.subir("multi-bulk", [F("carga.zip", "zip"), F("despacho 123.pdf", "despachoTexto"), F("invoice_A.xlsx", "xlsx"), F("packing list.pdf", "packing"),
    F("random.pdf", "random"), F("factura2.pdf", "ciPdf"), F("6 BL telex.png", "png")]);
  await D.snap();
  D.paso("A2 quitar PL"); await D.R().locator(".zone", { hasText: "PL (Packing List)" }).first().locator("button[title=Quitar]").click(); await D.snap();
  D.paso("A3 subir PL suelto"); await D.subir("multi-pl", [F("otro packing.pdf", "packing2")]); await D.snap();
  D.paso("A4 pesaje con 2 archivos (single)"); await D.soltar("multi-pesaje", [F("gemez a.pdf", "corto"), F("gemez b.pdf", "random")]); await D.snap();
  D.paso("A5 ver PDFs"); await D.btn("👁 Ver PDFs"); await D.snap();
  D.paso("A6 pestaña 3 del visor"); await D.R().locator("button", { hasText: "pl:" }).first().click(); await D.snap();
  D.paso("A7 ocultar PDFs"); await D.btn("▼ Ocultar PDFs"); await D.snap();
  D.paso("A8 verificar (lento)"); st.fase = "lento"; await D.btn("📁 Verificar");
  await D.esperaPedido("/verify-multi-doc"); await D.p.waitForTimeout(200);
  D.out.pasos.push({ snap: "A8 durante", texto: norm(await D.R().innerText()), btn: await D.R().locator("button.btn-primary").first().isDisabled() });
  await D.snap("A8 resultado");
  D.paso("A9 detalles debug"); await D.R().locator("summary", { hasText: "Data extraida" }).click(); await D.snap();
  D.paso("A10 corregir relevamiento"); await D.btn("📝 Corregir Relevamiento"); await D.snap();
  await D.btn("🔍 Buscar en relevamiento", "pagina"); await D.p.waitForTimeout(300);
  await D.snap("A10 buscado");
  await D.llenar('input[placeholder^="OWNLAND"]', "KANGLI");
  await D.btn("💾 Guardar y volver", "pagina"); await D.dialogo("Aceptar"); await D.snap("A10 cerrado");
  D.paso("A10b corregir otra alerta y cerrar"); await D.R().locator("button", { hasText: "📝 Corregir Relevamiento" }).nth(1).click(); await D.snap();
  await D.p.locator("h3", { hasText: "📝 Corregir Relevamiento" }).locator("xpath=following-sibling::button").click(); await D.snap("A10b cerrado");
  D.paso("A11 cabecera"); await D.btn("▶ Mostrar/editar campos"); await D.snap();
  await D.llenar("xpath=//label[starts-with(normalize-space(.),'Aduana')]/following-sibling::input", "BUENOS AIRES");
  await D.blur("xpath=//label[starts-with(normalize-space(.),'Aduana')]/following-sibling::input"); await D.snap("A11 aduana");
  await D.elegir("xpath=//label[starts-with(normalize-space(.),'Canal')]/following-sibling::select", "ROJO"); await D.snap("A11 canal");
  await D.llenar("xpath=//label[starts-with(normalize-space(.),'Bultos')]/following-sibling::input", "");
  await D.blur("xpath=//label[starts-with(normalize-space(.),'Bultos')]/following-sibling::input"); await D.snap("A11 bultos vacío");
  D.paso("A12 ocultar cabecera"); await D.btn("▼ Ocultar editor"); await D.snap();
  D.paso("A12b mostrar de nuevo"); await D.btn("▶ Mostrar/editar campos"); await D.snap(); await D.btn("▼ Ocultar editor");
  D.paso("A13 nro de carga"); await D.llenar('input[placeholder="ej. China 49"]', "  China 49 "); await D.snap();
  D.paso("A14a guardar con error"); st.fase = "error500"; await D.btn("💾 Guardar en DB"); await D.snap();
  D.paso("A14 guardar en DB"); st.fase = ""; await D.btn("💾 Guardar en DB"); await D.snap();
  D.paso("A15 error 500"); st.fase = "error500"; await D.btn("📁 Verificar"); await D.snap();
  D.paso("A16 error 502"); st.fase = "error502"; await D.btn("📁 Verificar"); await D.snap();
  D.paso("A17 duplicado"); st.fase = "duplicado"; await D.btn("📁 Verificar"); await D.snap();
  D.paso("A18 sin despacho"); st.fase = "sinDespacho"; await D.btn("📁 Verificar"); await D.snap();
  D.paso("A19 volver al inicio y entrar de nuevo");
  await D.p.locator("button", { hasText: "← Inicio" }).first().click();
  await D.p.locator(".mode-card").nth(1).click();
  await D.p.waitForTimeout(500); await D.snap();
}

async function mdB(D, F, st) {
  D.paso("B1 despacho escaneado + CI"); await D.subir("multi-despacho", [F("despacho scan.pdf", "despachoScan")]);
  await D.subir("multi-ci", [F("ci.xlsx", "xlsx")]);
  await D.llenar('input[placeholder="ej. China 49"]', "China 50"); await D.snap();
  D.paso("B2 verificar con un tramo que falla"); st.fase = "chunkFalla"; await D.btn("📁 Verificar"); await D.snap();
  D.paso("B3 verificar con tramos ok"); st.fase = ""; await D.btn("📁 Verificar"); await D.snap();
  D.paso("B4 quitar todo"); for (const s of ["Despacho (OM-1993)", "CI (Commercial Invoice)"]) await D.R().locator(".zone", { hasText: s }).first().locator("button[title=Quitar]").click();
  await D.snap();
}

async function fuA(D, F, st) {
  D.paso("A0 inicial"); await D.snap();
  D.paso("A1 archivos");
  await D.subir("PI", [F("PI china 48.xlsx", "xlsx")]);
  await D.subir("CI", [F("CI.pdf", "ciPdf")]);
  await D.subir("DESPACHO", [F("despacho.pdf", "despachoCorto")]);
  await D.subir("BL", [F("bl.png", "png")]);
  await D.subir("LIBRE_CIRC", [F("libre a.pdf", "libre"), F("libre b.pdf", "random")]);
  await D.snap();
  D.paso("A2 quitar uno"); await D.R().locator("#" + D.zonaId("LIBRE_CIRC")).locator("xpath=ancestor::div[contains(@class,'zone')][1]").locator(".files-list .f button").nth(1).click(); await D.snap();
  D.paso("A3 nro"); await D.llenar('input[placeholder="ej. China 48"]', " China 48 "); await D.snap();
  D.paso("A4 verificar (lento)"); st.fase = "lento"; await D.btn("🔍 Verificar");
  await D.esperaPedido("/analyze-docs"); await D.p.waitForTimeout(200);
  D.out.pasos.push({ snap: "A4 durante", texto: norm(await D.R().innerText()), btn: await D.R().locator("button.btn-primary").first().isDisabled() });
  await D.snap("A4 resultado"); st.fase = "";
  D.paso("A5 reporte markdown"); await D.R().locator("summary", { hasText: "Ver reporte markdown" }).click(); await D.snap();
  D.paso("A6 guardar"); await D.btn("💾 Guardar en DB"); await D.snap();
  D.paso("A7 editar descripción");
  const fila = (i) => D.R().locator(".report table tbody tr").nth(i);
  await fila(1).locator("td").nth(2).locator("input").fill("Colador grande");
  await fila(1).locator("td").nth(2).locator("input").evaluate((e) => e.blur()); await D.snap();
  D.paso("A8 editar número a vacío"); await fila(0).locator("td").nth(3).locator("input").fill("");
  await fila(0).locator("td").nth(3).locator("input").evaluate((e) => e.blur()); await D.snap();
  D.paso("A9 agregar fila"); await D.btn("+ Agregar fila"); await D.snap();
  D.paso("A10 borrar fila (cancelar)"); await fila(1).locator("button", { hasText: "🗑" }).click(); await D.dialogo("Cancelar"); await D.snap();
  D.paso("A11 borrar fila"); await fila(1).locator("button", { hasText: "🗑" }).click(); await D.dialogo("Sí, borrar"); await D.snap();
  D.paso("A12 excel"); await D.descarga("📥 Excel"); await D.snap();
  D.paso("A13 excel falla"); st.fase = "excelFalla"; await D.btn("📥 Excel"); await D.dialogo("Aceptar"); await D.snap(); st.fase = "";
  D.paso("A14 verificar con error"); st.fase = "iaCaida"; await D.btn("🔍 Verificar"); await D.snap(); st.fase = "";
}

async function fuB(D, F, st) {
  D.paso("B1 despacho largo + PI, sin nro"); await D.subir("DESPACHO", [F("desp largo.pdf", "despachoTexto")]);
  await D.subir("PI", [F("pi.xlsx", "xlsx")]); await D.snap();
  D.paso("B2 nro + verificar"); await D.llenar('input[placeholder="ej. China 48"]', "China 51"); await D.btn("🔍 Verificar"); await D.snap();
  D.paso("B3 guardar, sin carga del despacho y tabla que falla"); st.sinDesp = true; st.fase = "itemsFalla"; await D.btn("💾 Guardar en DB");
  await D.dialogo("Aceptar"); await D.snap(); st.fase = "";
}

async function fuC(D, F, st) {
  D.paso("C1 un solo tipo (no habilita)"); await D.subir("CI", [F("ci1.pdf", "ciPdf"), F("ci2.pdf", "packing")]);
  await D.llenar('input[placeholder="ej. China 48"]', "C1"); await D.snap();
  D.paso("C2 sin despacho: sólo analyze-docs"); await D.subir("PL", [F("pl.png", "png")]); await D.btn("🔍 Verificar"); await D.snap();
  D.paso("C3 guardar (carga sale de analyze-docs)"); await D.btn("💾 Guardar en DB"); await D.snap();
}


const GRUPOS = [
  { modo: "multidoc", rutas: rutasMultidoc, zona: (id) => id, esc: [["A", mdA], ["B", mdB]] },
  { modo: "full", rutas: rutasFull, zona: (id) => "full-" + id, esc: [["A", fuA], ["B", fuB], ["C", fuC]] },
];

(async () => {
  const srv = http.createServer((req, res) => {
    const u = decodeURIComponent(req.url.split("?")[0]);
    if (u === "/__ic.html") { res.writeHead(200, { "content-type": "text/html; charset=utf-8" }); return res.end(PAGINA); }
    const f = path.join(RAIZ, u);
    if (!f.startsWith(RAIZ) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end("no"); }
    res.writeHead(200, { "content-type": TIPOS[path.extname(f)] || "application/octet-stream" });
    fs.createReadStream(f).pipe(res);
  });
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const BASE = `http://127.0.0.1:${srv.address().port}/`;
  const b = await chromium.launch();
  const fail = [];
  const t0 = Date.now();
  async function abrir(modo, ver, rutas) {
    const ctx = await b.newContext({ viewport: { width: 1440, height: 1000 }, acceptDownloads: true });
    const p = await ctx.newPage();
    const errs = [];
    p.on("pageerror", (e) => errs.push("pageerror: " + e.message));
    p.on("console", (m) => { if (m.type() === "error" && !/favicon|Failed to load resource/.test(m.text())) errs.push("console: " + m.text()); });
    const pedidos = [];
    await p.route("**/functions/v1/Impo_Comex_web/**", async (route) => {
      const r = route.request();
      const url = r.url().replace(/^.*Impo_Comex_web/, "");
      if (url === "/datos-ddjj") return route.fulfill({ status: 200, contentType: "application/json", body: '{"controlante":{}}' });
      const ct = r.headers()["content-type"] || "";
      const buf = r.postDataBuffer();
      let cuerpo = null;
      if (buf) cuerpo = /multipart/.test(ct) ? partes(buf, ct) : (() => { try { return JSON.parse(buf.toString()); } catch (_) { return buf.toString(); } })();
      const reg = { metodo: r.method(), path: url, cuerpo, paso: ver.paso };
      pedidos.push(reg);
      ver.enVuelo = (ver.enVuelo || 0) + 1;
      try { await route.fulfill(await rutas(reg)); } finally { ver.enVuelo--; }
    });
    await p.goto(BASE + "__ic.html", { waitUntil: "load" });
    await p.evaluate(() => window.IC.abrir());
    await p.waitForSelector("#icOv .mode-card", { timeout: 20000 });
    if (modo) await p.evaluate((m) => window.IC.ir(m), modo);
    await p.waitForFunction(() => { const e = document.getElementById("icMain"); return e && e.innerText.length > 30 && !/Abriendo…/.test(e.innerText); }, null, { timeout: 20000 });
    return { p, ctx, ver, errs, pedidos, raiz: "#icMain" };
  }
  const compacto = (p) => {
    let c = "";
    if (Array.isArray(p.cuerpo)) c = p.cuerpo.map((y) => y.archivo !== undefined ? `${y.campo}@${y.archivo}` : `${y.campo}=${String(y.valor).slice(0, 60)}`).join(" & ");
    else if (p.cuerpo) c = JSON.stringify(p.cuerpo);
    return `${p.paso.split(" ")[0]}|${p.metodo} ${p.path}|${c}`;
  };
  // Pedidos que salen juntos (en vuelo a la vez) pueden llegar en cualquier orden: se ordenan dentro del paso.
  const ordenar = (l) => { const g = []; for (const x of l) { const k = x.split("|")[0]; const u = g[g.length - 1]; if (u && u.k === k) u.l.push(x); else g.push({ k, l: [x] }); } return g.flatMap((q) => q.l.sort()); };
  try {
    const s0 = await abrir("", { paso: "" }, async () => ({ status: 200, contentType: "application/json", body: '{"data":[]}' }));
    const FX = await fixtures(s0.p); await s0.ctx.close();
    for (const G of GRUPOS) {
      for (const [nom, fn] of G.esc) {
        const ver = { paso: "" }; const st = { FX };
        const S = await abrir(G.modo, ver, G.rutas(st));
        S.inputId = (id) => "#icup-" + G.zona(id);
        const D = driver(S, FX);
        D.zonaId = (id) => "icup-" + G.zona(id);
        const F = (n, k, t) => D.file(n, k, t);
        const tag = `${G.modo}/${nom}`;
        try { await fn(D, F, st); } catch (e) { fail.push(`${tag}: el flujo se cortó: ${e.message.split("\n")[0]}`); }
        const E = ESPERADO[G.modo][nom];
        const got = ordenar(S.pedidos.filter((x) => x.paso).map(compacto)), exp = ordenar(E.pedidos.slice());
        for (let i = 0; i < Math.max(got.length, exp.length); i++)
          if (got[i] !== exp[i]) { fail.push(`${tag}: pedido ${i} distinto\n    viejo: ${exp[i]}\n    nuevo: ${got[i]}`); break; }
        const vistos = new Set();
        for (const s of D.out.pasos) {
          if (!s.snap) continue;
          vistos.add(s.snap);
          const h = crypto.createHash("md5").update(JSON.stringify(s)).digest("hex").slice(0, 12);
          if (E.snaps[s.snap] !== h) fail.push(`${tag}: lo que se ve en «${s.snap}» no es lo del viejo` + (process.env.VER ? `\n${JSON.stringify(s, null, 1)}` : " (VER=1 lo muestra)"));
        }
        for (const k of Object.keys(E.snaps)) if (!vistos.has(k)) fail.push(`${tag}: falta el paso «${k}»`);
        const dl = D.out.dialogos.map((d) => d.texto);
        if (JSON.stringify(dl) !== JSON.stringify(E.dialogos)) fail.push(`${tag}: diálogos ${JSON.stringify(dl)} ≠ viejo ${JSON.stringify(E.dialogos)}`);
        const ds = D.out.descargas;
        if (JSON.stringify(ds.map((d) => d.nombre)) !== JSON.stringify(E.descargas)) fail.push(`${tag}: descargas ${JSON.stringify(ds.map((d) => d.nombre))} ≠ viejo ${JSON.stringify(E.descargas)}`);
        for (const d of ds) if (d.md5 !== md5(Buffer.from(FX.export, "base64"))) fail.push(`${tag}: ${d.nombre} no es el archivo que mandó la puerta`);
        if (S.errs.length) fail.push(`${tag}: errores de página: ${S.errs.join(" | ")}`);
        await S.ctx.close();
      }
    }
  } catch (e) { fail.push("excepción: " + (e.stack || e.message)); }
  finally { await b.close(); srv.close(); }
  const seg = ((Date.now() - t0) / 1000).toFixed(1);
  if (fail.length) { console.log(`✗ impo-comex-paridad-multidoc (${seg} s):\n- ` + fail.join("\n- ")); process.exit(1); }
  console.log(`✓ impo-comex-paridad-multidoc: multidoc y full se comportan como el viejo (pedidos, pantalla, diálogos y descargas) en ${seg} s`);
})();
