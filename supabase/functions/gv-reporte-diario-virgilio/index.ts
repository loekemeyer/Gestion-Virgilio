// Reporte diario de Logistica Virgilio para Juan, por WhatsApp.
//
// FORMATO NUEVO: tabla apaisada de 16 columnas por operario. Los numeros de tiempo salen
// de calculo.js (copia del engine del repo, con la regla del cierre). En modo solo_pdf la
// respuesta trae el PDF firmado (pdfUrl) Y las 16 columnas ya formateadas en `bloques`, para
// que el modulo de gestion-virgilio arme el cuadro sinoptico en HTML sin recalcular.
//
// Autenticacion: verify_jwt = true. wa_token de Meta va en el body (server_secrets.REPORTES_WA_TOKEN).
// El bucket `reportes` es privado -> se firma la URL (createSignedUrl). Ver README.md.
//   { "solo_pdf": true, "fecha": ".." }  -> arma el PDF, no manda WhatsApp; devuelve pdfUrl + bloques
//   { "wa_token": "...", "test": false } -> hoy, a JUAN (cron 18hs)
//   { "diag": true, "desde": "..", "hasta": ".." } -> auditoria de m3 por tanda

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { jsPDF } from "https://esm.sh/jspdf@2.5.2";
// @ts-ignore: copia verbatim del calculo.js del repo, sin tipos
import { procesar, CONFIG } from "./calculo.js";

const SUPABASE_URL = "https://hrxfctzncixxqmpfhskv.supabase.co";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

const WA_PHONE_ID = Deno.env.get("WA_PHONE_ID") || "918089688061759";
const WA_TEMPLATE = Deno.env.get("WA_TEMPLATE") || "informe_produccion_virgilio";
const WA_IDIOMA = "es_AR";

const DESTINATARIOS_PROD = ["5491126161913"];  // Juan
const DESTINATARIOS_TEST = ["5491156517686"];  // pruebas

const BUCKET = "reportes";
const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 5000;
const DIAS_HACIA_ATRAS = 7;   // margen para los pares que cruzan dia (findes y feriados)

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const TZ = "America/Argentina/Buenos_Aires";

function partesAR(iso: string | null): { fecha: string; hora: string } {
  if (!iso) return { fecha: "", hora: "" };
  const d = new Date(iso);
  if (isNaN(+d)) return { fecha: "", hora: "" };
  const p: Record<string, string> = {};
  new Intl.DateTimeFormat("es-AR", {
    timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false,
  }).formatToParts(d).forEach((x) => { p[x.type] = x.value; });
  return { fecha: `${p.day}/${p.month}/${p.year}`, hora: `${p.hour}:${p.minute}:${p.second}` };
}

function hoyAR(): string {
  const p: Record<string, string> = {};
  new Intl.DateTimeFormat("es-AR", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" })
    .formatToParts(new Date()).forEach((x) => { p[x.type] = x.value; });
  return `${p.year}-${p.month}-${p.day}`;
}

function horaAR(): string {
  const p: Record<string, string> = {};
  new Intl.DateTimeFormat("es-AR", { timeZone: TZ, hour: "2-digit", minute: "2-digit", hour12: false })
    .formatToParts(new Date()).forEach((x) => { p[x.type] = x.value; });
  return `${p.hour}:${p.minute}`;
}

const isoARestando = (iso: string, dias: number): string => {
  const [y, m, d] = iso.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() - dias);
  return dt.toISOString().slice(0, 10);
};

const isoADDMM = (iso: string) => { const [y, m, d] = iso.split("-"); return `${d}/${m}/${y}`; };

function celda(v: number, dec = 2): string {
  if (!v || !isFinite(v) || Math.abs(v) < 5e-3) return "-";
  return v.toFixed(dec).replace(".", ",");
}
function celdaHs(v: number): string {
  if (!v || !isFinite(v) || v <= 0) return "-";
  let h = Math.floor(v);
  let m = Math.round((v - h) * 60);
  if (m === 60) { h++; m = 0; }
  if (h === 0 && m === 0) return "-";
  return `${h}:${String(m).padStart(2, "0")}`;
}

async function paginar(sb: any, tabla: string, cols: string, filtrar?: (q: any) => any) {
  const SIZE = 1000;
  const todo: any[] = [];
  let desde = 0;
  while (true) {
    let q = sb.from(tabla).select(cols);
    if (filtrar) q = filtrar(q);
    const { data, error } = await q.range(desde, desde + SIZE - 1);
    if (error) throw new Error(`${tabla}: ${error.message}`);
    if (!data || !data.length) break;
    todo.push(...data);
    if (data.length < SIZE) break;
    desde += SIZE;
  }
  return todo;
}

// ===== v21.17 - LEGAJO 600 = ENTREVISTAS, y en un mismo dia pasan VARIOS candidatos =====
// El 600 es un legajo COMPARTIDO: cada candidato entra con el y sella su nombre en
// gv_nombre_prueba (v14.62, sql/gv_nombre_prueba_entrevistas_v1462.sql). Su prueba es
// REAL: persiste eventos y descuenta stock, asi que su produccion cuenta y tiene que
// verse en el reporte. Hasta la v21.16 calculo.js lo tiraba con legajosTest.
// Medido el 22/09: ese dia el 600 lo usaron DOS personas -- javier Romero (08:31-11:47)
// y Juan Segundo Landaberry (13:09-13:48). Una sola fila "600" sumaria a los dos en un
// mismo operario, que es peor que no mostrarlo. Por eso el legajo se REESCRIBE a
// `600<SEP><nombre>` al traer los datos: todo lo que agrupa por legajo aguas abajo
// (porPersona, sreg, det, openByLeg) queda partido por candidato solo, sin tocar
// calculo.js. Sin nombre queda `600` pelado y sale como "Entrevista (s/nombre)" --
// NO se le atribuye a nadie por cercania de reloj.
const LEGAJO_ENTREVISTA = "600";
const SEP_PRUEBA = "\u00b7"; // punto medio: no aparece en un nombre tipeado

function legajoConPrueba(legajo: string, nombrePrueba: unknown): string {
  if (legajo !== LEGAJO_ENTREVISTA) return legajo;
  const n = String(nombrePrueba ?? "").trim();
  return n ? legajo + SEP_PRUEBA + n : legajo;
}

function nombreDeLegajo(legajo: unknown, empMap: Map<string, string>): string {
  const L = String(legajo ?? "").trim();
  const real = empMap.get(L);
  if (real) return real;                                   // un operario real siempre manda
  if (L === LEGAJO_ENTREVISTA) return "Entrevista (s/nombre)";
  if (L.startsWith(LEGAJO_ENTREVISTA + SEP_PRUEBA)) {
    return L.slice(LEGAJO_ENTREVISTA.length + SEP_PRUEBA.length) + " (entrevista)";
  }
  return `Legajo ${L}`;
}

// ===== v21.18 - VENTANA HORARIA: medir un lapso, no el dia entero =====
// Pedido de Luis: "medir lapsos de horas, por ejemplo desde la 1pm a 4:30 pm".
// No hace falta un filtro nuevo: calculo.js YA recorta cada par contra la jornada
// (splitParPorJornada). Alcanza con pisar esa jornada con el lapso pedido y todo lo que
// mide horas -- picking, armado, carga, no productivas y Hs S/Reg -- queda recortado solo.
// Los minutos van aparte de la hora porque 16:30 no entra en un entero.
//   { "fecha": "2026-09-22", "desde_hora": "13:00", "hasta_hora": "16:30" }
// Sin esos dos campos la jornada sigue siendo la de siempre, 08:00 a 17:00.
type Ventana = { iniH: number; iniM: number; finH: number; finM: number; etiqueta: string } | null;
const JORNADA_DEF = { iniH: 8, iniM: 0, finH: 17, finM: 0 };
const dosD = (n: number) => String(n).padStart(2, "0");

// Acepta "13:00", "13.00", "1300", "13" y "1pm"/"4:30 pm" (que es como lo dijo el pedido).
function parseHHMM(v: unknown): { h: number; m: number } | null {
  let s = String(v ?? "").trim().toLowerCase();
  if (!s) return null;
  let pm = false, am = false;
  // sin \b: en "1pm" no hay borde de palabra entre el 1 y la p, y la prueba lo cazo
  // devolviendo 08:00 en vez de 13:00.
  if (/(pm|p\.m\.)$/.test(s)) { pm = true; s = s.replace(/(pm|p\.m\.)$/, "").trim(); }
  else if (/(am|a\.m\.)$/.test(s)) { am = true; s = s.replace(/(am|a\.m\.)$/, "").trim(); }
  s = s.replace(/[.\s]/g, ":").replace(/:+/g, ":");
  const m = s.match(/^(\d{1,2})(?::(\d{1,2}))?$/) || s.match(/^(\d{2})(\d{2})$/);
  if (!m) return null;
  let h = Number(m[1]); const mi = Number(m[2] ?? 0);
  if (!isFinite(h) || !isFinite(mi) || mi < 0 || mi > 59) return null;
  if (pm && h < 12) h += 12;
  if (am && h === 12) h = 0;
  if (h < 0 || h > 24) return null;
  return { h, m: mi };
}

function parseVentana(desdeHora: unknown, hastaHora: unknown): Ventana {
  const hay = (v: unknown) => String(v ?? "").trim() !== "";
  const a = parseHHMM(desdeHora), b = parseHHMM(hastaHora);
  // Un valor cargado que no se entiende NO se reemplaza por el horario de siempre en
  // silencio: se ignora el lapso entero. Un default inventado se lee como un dato real.
  if ((hay(desdeHora) && !a) || (hay(hastaHora) && !b)) return null;
  if (!a && !b) return null;                       // sin lapso pedido: jornada de siempre
  const ini = a || { h: JORNADA_DEF.iniH, m: JORNADA_DEF.iniM };
  const fin = b || { h: JORNADA_DEF.finH, m: JORNADA_DEF.finM };
  if (fin.h * 60 + fin.m <= ini.h * 60 + ini.m) return null;   // invertida o vacia: se ignora
  return {
    iniH: ini.h, iniM: ini.m, finH: fin.h, finM: fin.m,
    etiqueta: `${dosD(ini.h)}:${dosD(ini.m)} a ${dosD(fin.h)}:${dosD(fin.m)}`,
  };
}

// OJO: pisa CONFIG, que es de modulo. Se llama SIN await de por medio antes de procesar()
// y de calcExtra(), que son sincronicos: asi dos pedidos con lapsos distintos no se pisan.
function aplicarVentana(v: Ventana) {
  const w = v || JORNADA_DEF;
  CONFIG.jornadaInicioHora = w.iniH; CONFIG.jornadaInicioMin = w.iniM;
  CONFIG.jornadaFinHora = w.finH;    CONFIG.jornadaFinMin = w.finM;
  CONFIG.jornadaHs = ((w.finH * 60 + w.finM) - (w.iniH * 60 + w.iniM)) / 60;
}

async function traerProduccion(sb: any, desdeIso: string, hasta: string) {
  const desde = isoARestando(desdeIso, DIAS_HACIA_ATRAS);
  const fecha = hasta;
  const filas = await paginar(
    sb, "Registros_Produccion_Virgilio",
    "legajo, opcion, descripcion, texto, ts_cliente, ts_inicio, gv_nombre_prueba",
    (q: any) => q.gte("ts_cliente", `${desde}T00:00:00-03:00`)
                 .lte("ts_cliente", `${fecha}T23:59:59-03:00`)
                 .order("ts_cliente", { ascending: true }),
  );
  return filas.map((r: any) => {
    const a = partesAR(r.ts_cliente);
    const b = partesAR(r.ts_inicio);
    return {
      fecha: a.fecha, hora: a.hora,
      fechaIni: b.fecha, horaIni: b.hora,
      legajo: legajoConPrueba(String(r.legajo || "").trim(), r.gv_nombre_prueba),
      opcion: String(r.opcion || "").trim(),
      descripcion: String(r.descripcion || "").trim(),
      codigo: String(r.texto || "").trim(),
    };
  });
}

async function traerEmpleados(sb: any) {
  const filas = await paginar(sb, "Empleados", "Legajo, Empleado");
  const m = new Map<string, string>();
  filas.forEach((r: any) => {
    const leg = String(r.Legajo || "").trim();
    if (leg) m.set(leg, String(r.Empleado || "").trim());
  });
  return m;
}

async function traerPpp(sb: any) {
  const norm = (v: any) => String(v ?? "").trim().toUpperCase();
  const seguro = async (tabla: string) => {
    try { return await paginar(sb, tabla, "tanda,m3,razon_social"); }
    catch (e) { console.error(`PPP: ${tabla} fallo -> ${e}`); return []; }
  };
  const [entregados, webProg, progDiaria] = await Promise.all([
    seguro("vista_ppp_pedidos_entregados"),
    seguro("PPP_Web_Programacion"),
    seguro("GV_PPP_Programacion_Diaria"),
  ]);
  const ppp = entregados.map((r: any) => ({
    tanda: norm(r.tanda), mt3: 0, mt3fc: Number(r.m3) || 0,
    razon: String(r.razon_social || "").trim(), origen: "facturado",
  })).filter((p: any) => p.tanda);
  const aEst = (origen: string) => (r: any) => ({
    tanda: norm(r.tanda), mt3: Number(r.m3) || 0, mt3fc: 0,
    razon: String(r.razon_social || "").trim(), origen,
  });
  const pppProgDiaria = webProg.map(aEst("web")).filter((p: any) => p.tanda);
  const yaEsta = new Set(pppProgDiaria.map((p: any) => p.tanda));
  progDiaria.map(aEst("diaria")).forEach((p: any) => {
    if (p.tanda && !yaEsta.has(p.tanda)) pppProgDiaria.push(p);
  });
  return { ppp, pppProgDiaria };
}

async function traerM3Pend(sb: any, desdeIso: string): Promise<number> {
  try {
    const filas = await paginar(sb, "gv_ppp_resumen_dias", "fecha,m3",
      (q: any) => q.gte("fecha", desdeIso));
    return filas.reduce((s: number, r: any) => s + (Number(r.m3) || 0), 0);
  } catch (e) { console.error(`M3 Pend fallo -> ${e}`); return 0; }
}

async function traerGuardPend(sb: any): Promise<{ cajas: number; ratio: number; horas: number }> {
  try {
    const ncod = (c: any) => String(c ?? "").trim().toUpperCase().replace(/^0+(?=.)/, "");
    const ncodNoWs = (c: any) => String(c ?? "").replace(/\s+/g, "").toUpperCase().replace(/^0+(?=.)/, "");

    const [saldos, capRows, racks, cfg] = await Promise.all([
      paginar(sb, "vista_saldos_stock", "clave,cod_art,terminado,a_guardar,excedente,racks"),
      paginar(sb, "Capacidad_Sector", "cod,cajas_max"),
      paginar(sb, "Racks_Planimetria", "cod_art,master_cajas,innercajas,estado",
        (q: any) => q.eq("estado", "ocupado")),
      sb.from("Stock_Config").select("valor").eq("clave", "guardado_cajas_por_hora").maybeSingle(),
    ]);
    const ratio = Math.max(1, Number(cfg?.data?.valor) || 380);

    const capMap = new Map<string, number>();
    capRows.forEach((r: any) => {
      const k = ncod(r.cod); if (!k) return;
      capMap.set(k, (capMap.get(k) || 0) + (Number(r.cajas_max) || 0));
    });

    const rkAgg = new Map<string, { inner: number; master: number; ratios: Set<number> }>();
    racks.forEach((r: any) => {
      const inner = Number(r.innercajas) || 0, master = Number(r.master_cajas) || 0;
      if (master <= 0 || inner <= 0) return;
      const k = ncodNoWs(r.cod_art); if (!k) return;
      const a = rkAgg.get(k) || { inner: 0, master: 0, ratios: new Set<number>() };
      a.inner += inner; a.master += master; a.ratios.add(Math.round((inner / master) * 1000));
      rkAgg.set(k, a);
    });
    const cxmMap = new Map<string, number>();
    rkAgg.forEach((a, k) => {
      if (a.ratios.size === 1 && a.inner % a.master === 0) cxmMap.set(k, a.inner / a.master);
    });

    const acc = new Map<string, { gond: number; aG: number; exc: number; rk: number }>();
    saldos.forEach((r: any) => {
      const k = String(r.clave ?? r.cod_art ?? "").trim(); if (!k) return;
      const a = acc.get(k) || { gond: 0, aG: 0, exc: 0, rk: 0 };
      a.gond += Number(r.terminado) || 0;
      a.aG += Number(r.a_guardar) || 0;
      a.exc += Number(r.excedente) || 0;
      a.rk += Number(r.racks) || 0;
      acc.set(k, a);
    });

    let total = 0;
    acc.forEach((a, clave) => {
      const aGuardar = Math.round(a.aG), exc = Math.round(a.exc), racksC = Math.round(a.rk);
      if (aGuardar + exc + racksC <= 0) return;
      const cap = Math.round(capMap.get(ncod(clave)) || 0);
      const gond = Math.round(a.gond);
      const cxm = cxmMap.get(ncod(clave)) || 0;
      if (cap <= 0) return;
      let room = Math.max(0, cap - gond); if (room > cap) room = cap;
      if (room <= 0) return;
      const g = Math.min(aGuardar, room);
      const e = Math.min(exc, Math.max(0, room - g));
      const roomAv = room - g - e;
      let rk = 0;
      if (racksC > 0 && roomAv > 0) {
        rk = cxm > 0 ? Math.min(Math.floor(racksC / cxm), Math.floor(roomAv / cxm)) * cxm
                     : Math.min(racksC, roomAv);
      }
      total += g + e + rk;
    });
    const cajas = Math.round(total);
    return { cajas, ratio, horas: Math.round((cajas / ratio) * 10) / 10 };
  } catch (e) { console.error(`Guard Pend fallo -> ${e}`); return { cajas: 0, ratio: 224, horas: 0 }; }
}

type Extra = {
  sreg: Map<string, number>;
  det: Map<string, { RT: number; MG: number; Limp: number; PB: number }>;
};
const TOG = new Set(["CC", "CR", "RR", "CP", "RT", "MG"]);

function calcExtra(r: any, produccion: any[], reportIso: string): Extra {
  const [Y, M, D] = reportIso.split("-").map(Number);
  const ddmm = isoADDMM(reportIso);
  const J0 = new Date(Y, M - 1, D, CONFIG.jornadaInicioHora, CONFIG.jornadaInicioMin || 0, 0).getTime();
  const J1 = new Date(Y, M - 1, D, CONFIG.jornadaFinHora, CONFIG.jornadaFinMin || 0, 0).getTime();

  const ev = produccion.filter((e) => e.fecha === ddmm)
    .slice().sort((a, b) => (a.hora || "").localeCompare(b.hora || ""));
  const oP = new Map<string, string>(), oA = new Map<string, string>();
  const togCnt = new Map<string, number>(), togLast = new Map<string, string>();
  ev.forEach((e) => {
    const L = e.legajo, o = e.opcion, t = (e.codigo || "").trim(), h = (e.hora || "").slice(0, 5);
    if (o === "EP") oP.set(L + "|" + t, h);
    else if (o === "TP") oP.delete(L + "|" + t);
    else if (o === "AP") oA.set(L + "|" + t, h);
    else if (o === "TAP") oA.delete(L + "|" + t);
    else if (TOG.has(o)) { const k = L + "|" + o; togCnt.set(k, (togCnt.get(k) || 0) + 1); togLast.set(k, L + "|" + h); }
  });
  const openByLeg = new Map<string, number>();
  const addOpen = (L: string, h: string) => {
    const [hh, mi] = h.split(":").map(Number);
    const t = new Date(Y, M - 1, D, hh, mi, 0).getTime();
    if (!openByLeg.has(L) || t < (openByLeg.get(L) as number)) openByLeg.set(L, t);
  };
  oP.forEach((h, k) => addOpen(k.split("|")[0], h));
  oA.forEach((h, k) => addOpen(k.split("|")[0], h));
  togCnt.forEach((c, k) => { if (c % 2 === 1) { const v = togLast.get(k) as string; addOpen(v.split("|")[0], v.split("|")[1]); } });

  const segByLeg = new Map<string, { ini: number; fin: number }[]>();
  (r.paresOriginales || []).forEach((p: any) => (p.segmentos || []).forEach((sg: any) => {
    const d = sg.dtIni;
    if (!(d instanceof Date)) return;
    if (d.getFullYear() !== Y || d.getMonth() !== M - 1 || d.getDate() !== D) return;
    const arr = segByLeg.get(p.legajo) || []; arr.push({ ini: +sg.dtIni, fin: +sg.dtFin }); segByLeg.set(p.legajo, arr);
  }));

  const sreg = new Map<string, number>();
  (r.porPersona || []).forEach((p: any) => {
    const segs = (segByLeg.get(p.legajo) || []).slice().sort((a, b) => a.ini - b.ini);
    const mg: { ini: number; fin: number }[] = [];
    segs.forEach((s) => {
      const b0 = Math.max(s.ini, J0), b1 = Math.min(s.fin, J1); if (b1 <= b0) return;
      if (mg.length && b0 <= mg[mg.length - 1].fin) mg[mg.length - 1].fin = Math.max(mg[mg.length - 1].fin, b1);
      else mg.push({ ini: b0, fin: b1 });
    });
    const gaps: [number, number][] = []; let cur = J0;
    mg.forEach((m) => { if (m.ini > cur) gaps.push([cur, m.ini]); cur = Math.max(cur, m.fin); });
    if (J1 > cur) gaps.push([cur, J1]);
    const O = openByLeg.has(p.legajo) ? (openByLeg.get(p.legajo) as number) : Infinity;
    let s = 0;
    gaps.forEach(([a, b]) => { const sA = a, sB = Math.min(b, O); if (sB > sA) s += sB - sA; });
    sreg.set(p.legajo, s / 36e5);
  });

  const det = new Map<string, { RT: number; MG: number; Limp: number; PB: number }>();
  (r.reportes || []).filter((rep: any) => rep.fecha === ddmm).forEach((rep: any) => {
    const g = det.get(rep.legajo) || { RT: 0, MG: 0, Limp: 0, PB: 0 };
    g.RT += (rep.opTogPorCode && rep.opTogPorCode.RT) || 0;
    g.MG += (rep.opTogPorCode && rep.opTogPorCode.MG) || 0;
    g.Limp += (rep.muertoPorTipo && rep.muertoPorTipo.Limp && rep.muertoPorTipo.Limp.hs) || 0;
    g.PB += (rep.muertoPorTipo && rep.muertoPorTipo.PB && rep.muertoPorTipo.PB.hs) || 0;
    det.set(rep.legajo, g);
  });

  return { sreg, det };
}

type Fila = {
  nombre: string;
  pkH: number; pkD: number; arH: number; arD: number;
  totDia: number; hsProd: number; pick: number; arm: number; cc: number;
  noProd: number; rt: number; mg: number; limp: number; pb: number; sinReg: number;
};
type Pendientes = { m3pend: number; dias: number; guardCajas: number; guardRatio: number; guardHoras: number } | null;

function aFila(p: any, dias: number, empMap: Map<string, string>, ex: Extra): Fila {
  const hsProd = p.pickHs + p.armHs + p.ccHs;
  const noProd = Math.max(0, p.totHs - hsProd);
  const g = ex.det.get(p.legajo) || { RT: 0, MG: 0, Limp: 0, PB: 0 };
  return {
    nombre: nombreDeLegajo(p.legajo, empMap),
    pkH: p.pickHs > 0 ? p.pickMt3 / p.pickHs : 0, pkD: p.pickMt3 / dias,
    arH: p.armHs > 0 ? p.armMt3 / p.armHs : 0, arD: p.armMt3 / dias,
    totDia: hsProd + noProd, hsProd, pick: p.pickHs, arm: p.armHs, cc: p.ccHs,
    noProd, rt: g.RT, mg: g.MG, limp: g.Limp, pb: g.PB,
    sinReg: ex.sreg.get(p.legajo) || 0,
  };
}

const COLS: { h: string[]; w: number; get: (f: Fila) => string; left?: boolean; name?: boolean }[] = [
  { h: ["Operario"], w: 42, get: (f) => f.nombre, left: true, name: true },
  { h: ["Prom.", "Picking", "M3 x Hs"], w: 16, get: (f) => celda(f.pkH) },
  { h: ["Prom.", "Picking", "M3 x Dia"], w: 16, get: (f) => celda(f.pkD) },
  { h: ["Prom.", "Arm", "M3 x Hs"], w: 16, get: (f) => celda(f.arH) },
  { h: ["Prom.", "Arm", "M3 x Dia"], w: 16, get: (f) => celda(f.arD) },
  { h: ["Total", "Hs Dia"], w: 15, get: (f) => celdaHs(f.totDia) },
  { h: ["Hs", "Prod"], w: 14, get: (f) => celdaHs(f.hsProd) },
  { h: ["Picking"], w: 14, get: (f) => celdaHs(f.pick) },
  { h: ["Armado"], w: 14, get: (f) => celdaHs(f.arm) },
  { h: ["Carga de", "Camion"], w: 16, get: (f) => celdaHs(f.cc) },
  { h: ["Hs No", "Productivas"], w: 18, get: (f) => celdaHs(f.noProd) },
  { h: ["Recp de", "Merc"], w: 15, get: (f) => celdaHs(f.rt) },
  { h: ["Guardado", "de Merc"], w: 16, get: (f) => celdaHs(f.mg) },
  { h: ["Limpieza"], w: 14, get: (f) => celdaHs(f.limp) },
  { h: ["Baño"], w: 12, get: (f) => celdaHs(f.pb) },
  { h: ["Hs", "S/Reg"], w: 16, get: (f) => celdaHs(f.sinReg) },
];

type Bloque = { subtitulo: string; filas: Fila[] };

function construirPdf(titulo: string, bloques: Bloque[], pend: Pendientes) {
  const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });
  const mL = 12, top = 15, hF = 7, hEnc = 13;
  const totW = COLS.reduce((a, c) => a + c.w, 0);
  const x0 = [mL]; COLS.forEach((c) => x0.push(x0[x0.length - 1] + c.w));
  const mid = (i: number) => (x0[i] + x0[i + 1]) / 2;
  const CC = (t: string, xa: number, xb: number, yt: number, h: number) =>
    doc.text(String(t), (xa + xb) / 2, yt + h / 2, { align: "center", baseline: "middle" } as any);

  doc.setTextColor(0, 0, 0); doc.setFont("helvetica", "bold"); doc.setFontSize(16);
  doc.text(titulo, mL, top);
  let y = top + 6;

  const hay = bloques.some((b) => b.filas.length);
  if (!hay) {
    doc.setFontSize(14); doc.setFont("helvetica", "normal");
    doc.text("Sin registros de produccion para la fecha.", mL, y + 6);
    return doc;
  }

  bloques.forEach((b, bi) => {
    if (!b.filas.length) return;
    if (bi > 0) y += 6;
    if (b.subtitulo) {
      doc.setFont("helvetica", "bold"); doc.setFontSize(14);
      doc.text(b.subtitulo, mL, y + 4); y += 6;
    }
    doc.setFontSize(9); doc.setFont("helvetica", "bold");
    COLS.forEach((c, i) => {
      const startY = y + (hEnc - c.h.length * 3.6) / 2 + 3.2;
      c.h.forEach((ln, k) => doc.text(ln, mid(i), startY + k * 3.6, { align: "center" }));
    });
    doc.setLineWidth(0.7); doc.rect(mL, y, totW, hEnc);
    doc.setLineWidth(0.15); for (let i = 1; i < COLS.length; i++) doc.line(x0[i], y, x0[i], y + hEnc);
    y += hEnc;
    const yC = y;
    doc.setFont("helvetica", "normal"); doc.setFontSize(14);
    b.filas.forEach((f) => {
      COLS.forEach((c, i) => {
        const v = c.get(f), tx = c.left ? x0[i] + 2 : mid(i);
        if (c.name) doc.setFontSize(12);
        doc.text(String(v), tx, y + hF / 2, { align: c.left ? "left" : "center", baseline: "middle" } as any);
        if (c.name) doc.setFontSize(14);
      });
      y += hF;
    });
    doc.setLineWidth(0.15);
    for (let i = 1; i < b.filas.length; i++) doc.line(mL, yC + i * hF, mL + totW, yC + i * hF);
    for (let i = 1; i < COLS.length; i++) doc.line(x0[i], yC, x0[i], y);
    doc.setLineWidth(0.7); doc.rect(mL, yC, totW, y - yC);
  });

  if (pend) {
    const PAD = 8, ROWH = 7.5, yB = y + 18;
    doc.setFont("helvetica", "bold"); doc.setFontSize(16);
    doc.text("Pendientes (al cierre del dia)", mL, yB);
    const gDisp = pend.guardHoras < 1
      ? `${Math.round((pend.guardCajas / pend.guardRatio) * 60)} min`
      : `${(Math.round(pend.guardHoras * 10) / 10).toString().replace(".", ",")} h`;
    const rows = [
      ["M3 Pend", `${pend.m3pend.toFixed(2).replace(".", ",")} m3  (${pend.dias.toFixed(1).replace(".", ",")} dias)`],
      ["Hs Guard Pend", `${gDisp}  (${pend.guardCajas} cajas)`],
    ];
    doc.setFontSize(14); doc.setFont("helvetica", "normal");
    const pL = Math.max(...rows.map((r) => doc.getTextWidth(r[0]))) + PAD;
    const pR = Math.max(...rows.map((r) => doc.getTextWidth(r[1]))) + PAD;
    const pW = pL + pR, pY = yB + 5;
    let py = pY;
    rows.forEach((r) => {
      doc.setFont("helvetica", "normal"); CC(r[0], mL, mL + pL, py, ROWH);
      doc.setFont("helvetica", "bold"); CC(r[1], mL + pL, mL + pW, py, ROWH); py += ROWH;
    });
    doc.setLineWidth(0.15);
    for (let i = 1; i < rows.length; i++) doc.line(mL, pY + i * ROWH, mL + pW, pY + i * ROWH);
    doc.line(mL + pL, pY, mL + pL, py);
    doc.setLineWidth(0.7); doc.rect(mL, pY, pW, py - pY);
  }
  return doc;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

  const responder = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

  try {
    let body: any = {};
    try { body = await req.json(); } catch { /* sin body */ }
    const esTest = body?.test !== false;
    const soloPdf = body?.solo_pdf === true;
    const soloDiag = body?.diag === true;
    const fecha = body?.fecha || hoyAR();
    const desde = body?.desde || fecha;
    const hasta = body?.hasta || (body?.desde ? hoyAR() : fecha);
    const variosDias = desde !== hasta;
    const ventana = parseVentana(body?.desde_hora, body?.hasta_hora);

    if (!SUPABASE_SERVICE_KEY) return responder({ error: "falta SUPABASE_SERVICE_ROLE_KEY" }, 500);

    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    const [produccion, empMap, pppRes] = await Promise.all([
      traerProduccion(sb, desde, hasta), traerEmpleados(sb), traerPpp(sb),
    ]);

    aplicarVentana(ventana);

    const r = procesar(
      { produccion, ppp: pppRes.ppp, pppProgDiaria: pppRes.pppProgDiaria },
      desde, hasta,
    );

    if (soloDiag) {
      const porTanda = new Map<string, any>();
      (r.reportes || []).forEach((rep: any) => {
        ([["pick", rep.pickPairs], ["arm", rep.armPairs], ["cc", rep.ccPairs]] as any[])
          .forEach(([tipo, pares]) => (pares || []).forEach((par: any) => {
            if (!par.tanda) return;
            const t = porTanda.get(par.tanda) ||
              { tanda: par.tanda, hs: 0, tipos: new Set<string>(), dias: new Set<string>(), legajos: new Set<string>() };
            t.hs += par.hs; t.tipos.add(tipo); t.dias.add(rep.fecha); t.legajos.add(rep.legajo);
            porTanda.set(par.tanda, t);
          }));
      });
      const fuentes = [...pppRes.ppp, ...pppRes.pppProgDiaria];
      const detalle = [...porTanda.values()].map((t: any) => {
        const hits = fuentes.filter((p: any) => p.tanda === t.tanda);
        const m3 = hits.reduce((x: number, p: any) => x + (p.mt3fc || p.mt3 || 0), 0);
        return {
          tanda: t.tanda, hs: +t.hs.toFixed(3), tipos: [...t.tipos].join("+"),
          dias: [...t.dias].join(" "), legajos: [...t.legajos].join(","),
          m3: +m3.toFixed(3),
          origen: [...new Set(hits.map((p: any) => p.origen))].join("+") || "-",
          razon: hits.length ? hits[0].razon : "",
        };
      }).sort((a, b) => (a.m3 === 0 ? 0 : 1) - (b.m3 === 0 ? 0 : 1) || b.hs - a.hs);
      const perdidas = detalle.filter((d) => d.m3 === 0);
      return responder({
        diag: true, desde, hasta, tandas: detalle.length,
        conM3: detalle.length - perdidas.length, sinM3: perdidas.length,
        hsTotal: +detalle.reduce((x, d) => x + d.hs, 0).toFixed(2),
        hsSinM3: +perdidas.reduce((x, d) => x + d.hs, 0).toFixed(2),
        m3Total: +detalle.reduce((x, d) => x + d.m3, 0).toFixed(3),
        detalle,
      });
    }

    const ordenar = (f: Fila[]) => f.sort((a, b) => b.hsProd - a.hsProd);
    const bloques: Bloque[] = [];

    if (variosDias) {
      const porDia = new Map<string, any[]>();
      (r.reportes || []).forEach((rep: any) => {
        const arr = porDia.get(rep.fecha) || []; arr.push(rep); porDia.set(rep.fecha, arr);
      });
      const aIso = (f: string) => f.slice(6, 10) + f.slice(3, 5) + f.slice(0, 2);
      [...porDia.keys()].sort((a, b) => aIso(a).localeCompare(aIso(b))).forEach((diaDDMM) => {
        const iso = `${diaDDMM.slice(6, 10)}-${diaDDMM.slice(3, 5)}-${diaDDMM.slice(0, 2)}`;
        const ex = calcExtra(r, produccion, iso);
        bloques.push({
          subtitulo: diaDDMM,
          filas: ordenar((porDia.get(diaDDMM) || []).map((rep: any) => aFila(rep, 1, empMap, ex))),
        });
      });
    } else {
      const ex = calcExtra(r, produccion, hasta);
      bloques.push({
        subtitulo: "",
        filas: ordenar((r.porPersona || []).map((p: any) => aFila(p, p.dias || 1, empMap, ex))),
      });
    }

    const [m3pend, guard] = await Promise.all([traerM3Pend(sb, hasta), traerGuardPend(sb)]);
    const hastaDDMM = isoADDMM(hasta);
    const armHoy = (r.reportes || []).filter((rep: any) => rep.fecha === hastaDDMM)
      .reduce((s: number, rep: any) => s + (rep.armMt3 || 0), 0);
    const pend: Pendientes = {
      m3pend, dias: armHoy > 0 ? m3pend / armHoy : 0,
      guardCajas: guard.cajas, guardRatio: guard.ratio, guardHoras: guard.horas,
    };

    const corto = (iso: string) => iso.slice(8, 10) + "/" + iso.slice(5, 7);
    const fechaLinda = hasta.split("-").reverse().join("/");
    const sufijoV = ventana ? ` (${ventana.etiqueta})` : "";
    const titulo = (variosDias
      ? `Logistica Virgilio - ${corto(desde)} al ${corto(hasta)}/${hasta.slice(0, 4)}`
      : `Logistica Virgilio - ${fechaLinda}`) + sufijoV;
    const doc = construirPdf(titulo, bloques, pend);

    const archivo = `virgilio_${variosDias ? desde + "_a_" + hasta : fecha}_${Date.now()}.pdf`;
    const bytes = new Uint8Array(doc.output("arraybuffer"));
    const { error: errUp } = await sb.storage.from(BUCKET)
      .upload(archivo, bytes, { contentType: "application/pdf", upsert: true });
    if (errUp) throw new Error("subiendo el PDF: " + errUp.message);
    const { data: firmada, error: errFirma } = await sb.storage.from(BUCKET)
      .createSignedUrl(archivo, 21600);
    if (errFirma || !firmada?.signedUrl) throw new Error("firmando el PDF: " + (errFirma?.message || "sin URL"));
    const pdfUrl = firmada.signedUrl;

    const totalFilas = bloques.reduce((s, b) => s + b.filas.length, 0);

    if (soloPdf) {
      let bin = "";
      for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
      return responder({
        solo_pdf: true, fecha, desde, hasta, operarios: totalFilas, pdfUrl,
        titulo, pendientes: pend, legajosExcluidos: CONFIG.legajosTest,
        ventana: ventana ? ventana.etiqueta : null,
        pdf_bytes: bytes.length, pdf_base64: btoa(bin),
        columnas: COLS.map((c) => ({ h: c.h, left: !!c.left, key: c.h.join(" ") })),
        bloques: bloques.map((b) => ({
          subtitulo: b.subtitulo || "(unico)",
          filas: b.filas.map((f) => ({
            nombre: f.nombre,
            pkH: celda(f.pkH), pkD: celda(f.pkD), arH: celda(f.arH), arD: celda(f.arD),
            totDia: celdaHs(f.totDia), hsProd: celdaHs(f.hsProd),
            pick: celdaHs(f.pick), arm: celdaHs(f.arm), cc: celdaHs(f.cc),
            noProd: celdaHs(f.noProd), rt: celdaHs(f.rt), mg: celdaHs(f.mg),
            limp: celdaHs(f.limp), pb: celdaHs(f.pb), sinReg: celdaHs(f.sinReg),
          })),
        })),
      });
    }

    const numeros = esTest ? DESTINATARIOS_TEST : DESTINATARIOS_PROD;
    const waToken = Deno.env.get("WA_TOKEN") || String(body?.wa_token || "");
    if (!waToken) {
      return responder({ error: "falta el token de Meta (body.wa_token o secret WA_TOKEN)", pdfUrl }, 500);
    }

    const waUrl = `https://graph.facebook.com/v21.0/${WA_PHONE_ID}/messages`;
    const param1 = fechaLinda;
    const resultados: any[] = [];
    for (const numero of numeros) {
      let ultimo: any = { numero, ok: false, error: "sin intentos" };
      for (let intento = 1; intento <= MAX_RETRIES; intento++) {
        try {
          const res = await fetch(waUrl, {
            method: "POST",
            headers: { Authorization: `Bearer ${waToken}`, "Content-Type": "application/json" },
            body: JSON.stringify({
              messaging_product: "whatsapp", to: numero, type: "template",
              template: {
                name: WA_TEMPLATE, language: { code: WA_IDIOMA },
                components: [
                  { type: "header", parameters: [{ type: "document",
                      document: { link: pdfUrl, filename: `Virgilio_${fecha}.pdf` } }] },
                  { type: "body", parameters: [{ type: "text", text: param1 }] },
                ],
              },
            }),
          });
          const data = await res.json();
          ultimo = { numero, ok: res.ok, intentos: intento, error: res.ok ? undefined : data?.error?.message };
          if (res.ok) break;
        } catch (err) {
          ultimo = { numero, ok: false, intentos: intento, error: String(err) };
        }
        if (intento < MAX_RETRIES) await sleep(RETRY_DELAY_MS);
      }
      resultados.push(ultimo);
    }

    return responder({
      test: esTest, fecha, hora: horaAR(), plantilla: WA_TEMPLATE,
      operarios: totalFilas, eventos: produccion.length,
      enviados: resultados.filter((x) => x.ok).length, total: numeros.length,
      pdfUrl, pendientes: pend, resultados,
    });
  } catch (err) {
    console.error(err);
    return responder({ error: String(err) }, 500);
  }
});
