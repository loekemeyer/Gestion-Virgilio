// Reporte diario de horas por operario (v25.50, pedido de Elías, 01/10/2026).
// Reemplazará al PDF de gv-reporte-diario-virgilio; mientras tanto convive: esta función NO toca
// la del PDF ni el cron 98. Por defecto manda sólo al número de PRUEBAS.
//
// Productivo = sólo picking y armado. Todo lo demás con nombre es "Hs no Prod" (una columna por
// tarea). "T Muerto" = jornada sin ninguna tarea cargada: es un error de carga, se muestra aparte
// y NO suma en Hs no Prod. Hs Total = Hs Prod + Hs no Prod. Sin bloque de "Pendientes".
// Los números salen de la RPC public.gv_horas_operario_detalle_v2(p_dia) (misma lógica que la TV).
// Por WhatsApp se manda en PDF (la plantilla de Meta está aprobada con un PDF); el Excel queda
// guardado en el bucket y su link vuelve en la respuesta.
//
//   { "fecha": "2026-09-30", "wa_token": "..." }                  -> prueba, al número de pruebas
//   { "fecha": "..", "solo_xlsx": true }                           -> arma Excel y PDF, no manda WhatsApp
//   { "fecha": "..", "test": false, "wa_token": "..." }            -> a JUAN
//   { "fecha": "..", "destinatarios": ["549..."], "wa_token": ".."} -> a esos números

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import ExcelJS from "npm:exceljs@4.4.0";
import { jsPDF } from "https://esm.sh/jspdf@2.5.2";

const SUPABASE_URL = "https://hrxfctzncixxqmpfhskv.supabase.co";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const WA_PHONE_ID = Deno.env.get("WA_PHONE_ID") || "918089688061759";
const WA_TEMPLATE = Deno.env.get("WA_TEMPLATE") || "informe_produccion_virgilio";
const WA_IDIOMA = "es_AR";
const DEST_PRUEBA = ["5491156517686"];
const DEST_PROD = ["5491126161913"]; // Juan
const BUCKET = "reportes";
const TZ = "America/Argentina/Buenos_Aires";
const MIN_H = 1 / 60; // menos de 1 minuto se deja en blanco

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const ALIAS: Record<string, string> = { "104": "Jhonny", "8": "Farias", "94": "Isidro", "277": "Jhonny C", "237": "Franco" };
const nombreCorto = (legajo: string, nombre: string) => ALIAS[legajo] || String(nombre || "").trim().split(/\s+/)[0] || `Leg ${legajo}`;

function hoyAR(): string {
  const p: Record<string, string> = {};
  new Intl.DateTimeFormat("es-AR", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" })
    .formatToParts(new Date()).forEach((x) => { p[x.type] = x.value; });
  return `${p.year}-${p.month}-${p.day}`;
}

// columnas de detalle = una por tarea no productiva (orden del ranking de septiembre)
const DET: { k: string; h: string }[] = [
  { k: "cr", h: "Ctrol\nRemit" }, { k: "rg", h: "Recep y\nGuard\nART" }, { k: "limp", h: "Limp" },
  { k: "rk", h: "Racks" }, { k: "pc", h: "Comida" }, { k: "cc", h: "Carg\nCami" },
  { k: "rr", h: "Recep\nRemi" }, { k: "pb", h: "Baño" }, { k: "ei", h: "Entrg\nInsum" },
  { k: "at", h: "Timbre" }, { k: "ct", h: "Cont" }, { k: "ri", h: "Recep\nInsum" }, { k: "perm", h: "Perm" },
  // v25.64-anulado: una tarea ANULADA es tiempo muerto = no productivo; sale aparte de su tarea
  { k: "anu", h: "Anulado" },
];
// tamaño de letra del encabezado (pt de Excel); el resto 16
const FS: Record<string, number> = {
  "Recep y\nGuard\nART": 12, "Comida": 12, "Timbre": 12, "Recep\nInsum": 12,
  "Arma\nx Hs": 14, "T\nMuerto": 12, "Anulado": 12, "Recep\nRemi": 14, "Entrg\nInsum": 14,
};

function calcular(filas: any[]) {
  const num = (v: unknown) => Number(v) || 0;
  const rows = filas.map((f) => {
    const d: any = { legajo: String(f.legajo), nombre: nombreCorto(f.legajo, f.nombre) };
    for (const k of ["jor", "pick", "arm", "cr", "rg", "limp", "rk", "pc", "cc", "rr", "pb", "ei", "at", "ct", "ri", "perm", "anu", "m3p", "m3a"]) d[k] = num(f[k]);
    d.prod = d.pick + d.arm;
    d.reg = DET.reduce((s, c) => s + d[c.k], 0);
    d.sin = Math.max(d.jor - d.prod - d.reg, 0); // aparte: NO suma en no productivo
    d.noprod = d.reg;
    d.total = d.prod + d.noprod;
    return d;
  }).sort((a, b) => b.noprod - a.noprod);
  const det = DET.filter((c) => rows.some((r) => r[c.k] > MIN_H)); // sin datos ese día -> se omite
  const haySin = rows.some((r) => r.sin > MIN_H);
  const head = ["Nombre", "Pking\nx Hs", "Arma\nx Hs", "Hs\nProd"]
    .concat(haySin ? ["T\nMuerto"] : [])
    .concat(det.map((c) => c.h)).concat(["Hs no\nProd", "Hs\nTotal", "Fecha"]);
  return { rows, det, haySin, head };
}
const ritmo = (m3: number, hs: number) => (hs > 0.05 && m3 > 0 ? Math.round((m3 / hs) * 100) / 100 : "—");

async function construirXlsx(filas: any[], fecha: string): Promise<Uint8Array> {
  const { rows, det, haySin, head } = calcular(filas);
  const hr = (h: number) => (h > MIN_H ? h / 24 : null);

  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet(fecha.split("-").reverse().join("-"));
  ws.addRow(head);
  const [y, m, d] = fecha.split("-").map(Number);
  for (const r of rows) {
    ws.addRow(
      [r.nombre, ritmo(r.m3p, r.pick), ritmo(r.m3a, r.arm), hr(r.prod)]
        .concat(haySin ? [hr(r.sin)] : [])
        .concat(det.map((c) => hr(r[c.k]))).concat([hr(r.noprod), hr(r.total), new Date(Date.UTC(y, m - 1, d, 12))]),
    );
  }
  const n = head.length;
  const thin = { style: "thin" as const, color: { argb: "FF000000" } };
  const med = { style: "medium" as const, color: { argb: "FF000000" } };
  const centro = { horizontal: "center" as const, vertical: "middle" as const, wrapText: true };

  ws.getRow(1).height = 80;
  head.forEach((h, i) => {
    const c = ws.getCell(1, i + 1);
    c.font = { name: "Calibri", size: FS[h] || 16, bold: true };
    c.alignment = centro; c.border = { left: thin, right: thin, top: med, bottom: med };
  });
  for (let r = 2; r <= ws.rowCount; r++) {
    ws.getRow(r).height = 24;
    for (let i = 1; i <= n; i++) {
      const c = ws.getCell(r, i);
      c.font = { name: "Calibri", size: 14 }; c.alignment = centro;
      c.border = { left: thin, right: thin, top: thin, bottom: r === ws.rowCount ? med : thin };
      if (i === 2 || i === 3) c.numFmt = "0.00";
      if (i >= 4 && i <= n - 1) c.numFmt = "[h]:mm";
      if (i === n) c.numFmt = "dd/mm";
    }
  }
  head.forEach((h, i) => {
    const hmax = Math.max(...h.split("\n").map((x) => x.length));
    const dmax = i === 0 ? Math.max(...rows.map((r) => r.nombre.length)) : 5;
    ws.getColumn(i + 1).width = Math.round((Math.max(dmax * 1.3, hmax * (FS[h] || 16) * 0.094) + 1) * 10) / 10;
  });
  ws.views = [{ state: "frozen", xSplit: 1, ySplit: 1 }];
  const buf = await wb.xlsx.writeBuffer();
  return new Uint8Array(buf as ArrayBuffer);
}

// Detalle por tanda de picking (TP) y armado (TAP) cerrados ese día. Los minutos son NETOS, con las
// pausas descontadas (B, Elías 01/10): salen de public.gv_horas_operario_tandas_v2, la misma lógica que el
// resumen, así que la suma por operario cierra con «Pking x Hs» / «Arma x Hs».
type DetT = { tanda: string; m3: number; mi: number };
type DetOp = { pick: DetT[]; arm: DetT[] };
async function traerTandas(sb: any, fecha: string): Promise<Record<string, DetOp>> {
  const { data, error } = await sb.rpc("gv_horas_operario_tandas_v2", { p_dia: fecha });
  if (error) throw new Error("gv_horas_operario_tandas_v2: " + error.message);
  const out: Record<string, DetOp> = {};
  for (const x of data || []) {
    const o = (out[String(x.legajo)] = out[String(x.legajo)] || { pick: [], arm: [] });
    o[x.tarea === "pick" ? "pick" : "arm"].push({ tanda: x.tanda, m3: Number(x.m3) || 0, mi: Number(x.min_net) || 0 });
  }
  for (const k in out) for (const s of ["pick", "arm"] as const) out[k][s].sort((a, b) => b.m3 - a.m3);
  return out;
}

// Mismo cuadro en PDF, formato cuadro sinóptico: ancho de columna según el dato, todo centrado,
// sin relleno ni color. Abajo, el detalle por tanda de picking y armado de cada operario.
function construirPdf(filas: any[], fecha: string, tandas: Record<string, DetOp>): Uint8Array {
  const { rows, det, haySin, head } = calcular(filas);
  const hm = (h: number) => {
    if (!(h > MIN_H)) return "";
    const t = Math.round(h * 60);
    return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`;
  };
  const dec = (v: unknown) => (typeof v === "number" ? v.toFixed(2).replace(".", ",") : String(v));
  const [y, m, d] = fecha.split("-");
  const doc = new jsPDF({ orientation: "landscape", unit: "pt", format: "a4" });
  const pageW = doc.internal.pageSize.getWidth(), pageH = doc.internal.pageSize.getHeight();
  const FSZ = 11, HSZ = 10, PAD = 5, rH = 18;
  doc.setLineWidth(0.7);

  // celda: texto centrado H/V; varias líneas
  const celda = (x: number, yy: number, w: number, h: number, lines: string[], bold: boolean, size: number) => {
    doc.rect(x, yy, w, h);
    doc.setFont("helvetica", bold ? "bold" : "normal"); doc.setFontSize(size);
    const lh = size + 1;
    const ty = yy + h / 2 - ((lines.length - 1) * lh) / 2 + size * 0.35;
    lines.forEach((l, j) => doc.text(l, x + w / 2, ty + j * lh, { align: "center" }));
  };
  // la letra del encabezado sigue la misma proporción que en el Excel (FS / 16): T Muerto, Comida… más chicas
  const hsz = (h: string) => Math.round(HSZ * (FS[h] || 16) / 16 * 10) / 10;
  const anchos = (hdr: string[][], body: string[][], hs: number[] = []) => hdr.map((hl, i) => {
    doc.setFont("helvetica", "bold"); doc.setFontSize(hs[i] || HSZ);
    let w = Math.max(...hl.map((l) => doc.getTextWidth(l)));
    for (const row of body) {
      doc.setFont("helvetica", "normal"); doc.setFontSize(FSZ);
      w = Math.max(w, doc.getTextWidth(row[i] || ""));
    }
    return w + PAD * 2;
  });
  const titulo = (t: string, yy: number) => {
    doc.setFont("helvetica", "bold"); doc.setFontSize(13);
    doc.text(t, pageW / 2, yy, { align: "center" });
  };

  // 1) resumen por operario
  const body1: string[][] = rows.map((r) =>
    [r.nombre, dec(ritmo(r.m3p, r.pick)), dec(ritmo(r.m3a, r.arm)), hm(r.prod)]
      .concat(haySin ? [hm(r.sin)] : [])
      .concat(det.map((c) => hm(r[c.k]))).concat([hm(r.noprod), hm(r.total), `${d}/${m}`]),
  );
  const hdr1 = head.map((h) => h.split("\n"));
  // encabezado: la letra más grande (≤ HSZ, ≥ 7) que entra en el ancho del dato; si no, la proporción del Excel
  const hs1 = head.map((h, i) => {
    doc.setFont("helvetica", "normal"); doc.setFontSize(FSZ);
    const wd = Math.max(...body1.map((r) => doc.getTextWidth(r[i] || "")));
    doc.setFont("helvetica", "bold");
    for (let z = HSZ; z >= 7; z -= 0.5) {
      doc.setFontSize(z);
      if (Math.max(...hdr1[i].map((l) => doc.getTextWidth(l))) <= wd) return z;
    }
    return Math.min(hsz(h), 7);
  });
  let w1 = anchos(hdr1, body1, hs1);
  const k = Math.min(1, (pageW - 40) / w1.reduce((a, b) => a + b, 0));
  w1 = w1.map((w) => w * k);
  let x0 = (pageW - w1.reduce((a, b) => a + b, 0)) / 2;
  titulo(`Horas por operario — ${d}/${m}/${y}`, 36);
  let yy = 48;
  const hH = 14 * Math.max(...hdr1.map((l) => l.length)) + 6;
  const fila1 = (cells: string[][], h: number, bold: boolean, size: number | number[]) => {
    let x = x0;
    cells.forEach((lines, i) => { celda(x, yy, w1[i], h, lines, bold, Array.isArray(size) ? size[i] : size); x += w1[i]; });
    yy += h;
  };
  fila1(hdr1, hH, true, hs1);
  for (const row of body1) fila1(row.map((c) => [c]), rH, false, FSZ);

  // 2) detalle por tanda (≡ pop-up m³/h del Mon. Admin): Nombre · Tarea · Tanda · m³ · Min trab · Ritmo
  type L = { nombre: string; tarea: string; tanda: string; m3: string; mi: string; rit: string; tot: boolean };
  const lin: L[] = [];
  const rit = (m3: number, mi: number) => (mi > 0.5 && m3 > 0 ? dec(Math.round((m3 / (mi / 60)) * 100) / 100) : "—");
  for (const r of rows) {
    const t = tandas[r.legajo] || { pick: [], arm: [] };
    for (const [s, lab] of [["pick", "Picking"], ["arm", "Armado"]] as const) {
      const xs = t[s];
      let sm = 0, smi = 0, nf = 0;
      for (const x of xs) {
        sm += x.m3; smi += x.mi; nf++;
        lin.push({ nombre: r.nombre, tarea: lab, tanda: x.tanda, m3: dec(x.m3), mi: x.mi > 0 ? String(Math.round(x.mi)) : "—", rit: rit(x.m3, x.mi), tot: false });
      }
      // D18 (Elías 01/10): lo que el resumen cuenta y no está en ninguna tanda cerrada (tarea abierta sin TP/TAP)
      const ab = (s === "pick" ? r.pick : r.arm) * 60 - smi;
      if (ab >= 1) {
        smi += ab; nf++;
        lin.push({ nombre: r.nombre, tarea: lab, tanda: "Abierto", m3: "—", mi: String(Math.round(ab)), rit: "—", tot: false });
      }
      if (nf > 1) lin.push({ nombre: r.nombre, tarea: lab, tanda: "Total", m3: dec(sm), mi: smi > 0 ? String(Math.round(smi)) : "—", rit: rit(sm, smi), tot: true });
    }
  }
  if (lin.length) {
    const hdr2 = [["Nombre"], ["Tarea"], ["Tanda"], ["m³"], ["Min", "trab"], ["Ritmo", "m³/h"]];
    const body2 = lin.map((l) => [l.nombre, l.tarea, l.tanda, l.m3, l.mi, l.rit]);
    const w2 = anchos(hdr2, body2);
    x0 = (pageW - w2.reduce((a, b) => a + b, 0)) / 2;
    const hH2 = 34;
    const cab = () => {
      titulo("Detalle por tanda — picking y armado", yy + 14);
      yy += 24;
      let x = x0;
      hdr2.forEach((l, i) => { celda(x, yy, w2[i], hH2, l, true, HSZ); x += w2[i]; });
      yy += hH2;
    };
    yy += 16;
    if (yy + 24 + hH2 + rH * 3 > pageH - 30) { doc.addPage(); yy = 20; }
    cab();
    // grupos para unir la celda de Nombre y la de Tarea (sin celdas vacías)
    let i = 0;
    while (i < lin.length) {
      let j = i;
      while (j < lin.length && lin[j].nombre === lin[i].nombre) j++;
      const n = j - i;
      if (yy + n * rH > pageH - 30) { doc.addPage(); yy = 20; cab(); }
      celda(x0, yy, w2[0], n * rH, [lin[i].nombre], true, FSZ);
      let a = i;
      while (a < j) {
        let b2 = a;
        while (b2 < j && lin[b2].tarea === lin[a].tarea) b2++;
        celda(x0 + w2[0], yy + (a - i) * rH, w2[1], (b2 - a) * rH, [lin[a].tarea], false, FSZ);
        a = b2;
      }
      for (let q = i; q < j; q++) {
        let x = x0 + w2[0] + w2[1];
        const l = lin[q], yq = yy + (q - i) * rH;
        [l.tanda, l.m3, l.mi, l.rit].forEach((c, z) => { celda(x, yq, w2[z + 2], rH, [c], l.tot, FSZ); x += w2[z + 2]; });
      }
      yy += n * rH;
      i = j;
    }
  }
  return new Uint8Array(doc.output("arraybuffer") as ArrayBuffer);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  const responder = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
  try {
    let body: any = {};
    try { body = await req.json(); } catch { /* sin body */ }
    const esTest = body?.test !== false;
    const fecha: string = body?.fecha || hoyAR();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(fecha)) return responder({ error: "fecha inválida (AAAA-MM-DD)" }, 400);
    if (!SERVICE_KEY) return responder({ error: "falta SUPABASE_SERVICE_ROLE_KEY" }, 500);

    const sb = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data: filas, error: errRpc } = await sb.rpc("gv_horas_operario_detalle_v2", { p_dia: fecha });
    if (errRpc) throw new Error("gv_horas_operario_detalle_v2: " + errRpc.message);
    if (!filas || !filas.length) return responder({ sin_datos: true, fecha, enviados: 0 });

    const stamp = Date.now();
    const subir = async (nombre: string, bytes: Uint8Array, tipo: string) => {
      const { error } = await sb.storage.from(BUCKET).upload(nombre, bytes, { contentType: tipo, upsert: true });
      if (error) throw new Error(`subiendo ${nombre}: ${error.message}`);
      const { data, error: e2 } = await sb.storage.from(BUCKET).createSignedUrl(nombre, 21600);
      if (e2 || !data?.signedUrl) throw new Error(`firmando ${nombre}: ${e2?.message || "sin URL"}`);
      return data.signedUrl;
    };
    const xlsxBytes = await construirXlsx(filas, fecha);
    const tandas = await traerTandas(sb, fecha);
    const pdfBytes = construirPdf(filas, fecha, tandas);
    const xlsxUrl = await subir(`horas_${fecha}_${stamp}.xlsx`, xlsxBytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
    const pdfUrl = await subir(`horas_${fecha}_${stamp}.pdf`, pdfBytes, "application/pdf");

    if (body?.solo_xlsx === true) return responder({ solo_xlsx: true, fecha, operarios: filas.length, xlsxUrl, pdfUrl, bytesXlsx: xlsxBytes.length, bytesPdf: pdfBytes.length });

    const destPedidos = Array.isArray(body?.destinatarios)
      ? body.destinatarios.map((x: any) => String(x).replace(/\D/g, "")).filter(Boolean) : [];
    const numeros = destPedidos.length ? destPedidos : (esTest ? DEST_PRUEBA : DEST_PROD);
    const waToken = Deno.env.get("WA_TOKEN") || String(body?.wa_token || "");
    if (!waToken) return responder({ error: "falta el token de Meta (body.wa_token o secret WA_TOKEN)", xlsxUrl, pdfUrl }, 500);

    const waUrl = `https://graph.facebook.com/v21.0/${WA_PHONE_ID}/messages`;
    const fechaLinda = fecha.split("-").reverse().join("/");
    const resultados: any[] = [];
    for (const numero of numeros) {
      let ultimo: any = { numero, ok: false, error: "sin intentos" };
      for (let intento = 1; intento <= 3; intento++) {
        try {
          const res = await fetch(waUrl, {
            method: "POST",
            headers: { Authorization: `Bearer ${waToken}`, "Content-Type": "application/json" },
            body: JSON.stringify({
              messaging_product: "whatsapp", to: numero, type: "template",
              template: {
                name: WA_TEMPLATE, language: { code: WA_IDIOMA },
                components: [
                  { type: "header", parameters: [{ type: "document", document: { link: pdfUrl, filename: `Virgilio_${fecha}.pdf` } }] },
                  { type: "body", parameters: [{ type: "text", text: fechaLinda }] },
                ],
              },
            }),
          });
          const data = await res.json();
          ultimo = { numero, ok: res.ok, intentos: intento, error: res.ok ? undefined : data?.error?.message, codigo: res.ok ? undefined : data?.error?.code };
          if (res.ok) break;
        } catch (err) {
          ultimo = { numero, ok: false, intentos: intento, error: String(err) };
        }
        if (intento < 3) await sleep(5000);
      }
      resultados.push(ultimo);
    }
    return responder({
      test: esTest, fecha, plantilla: WA_TEMPLATE, destinatarios: numeros, operarios: filas.length,
      enviados: resultados.filter((x) => x.ok).length, total: numeros.length, xlsxUrl, pdfUrl, resultados,
    });
  } catch (err) {
    console.error(err);
    return responder({ error: String(err) }, 500);
  }
});
