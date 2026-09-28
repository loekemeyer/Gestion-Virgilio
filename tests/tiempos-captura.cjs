/* v23.71 (Luis, 28/09): «se están guardando mal los datos del tiempo de tareas».
   Corre de verdad las tres piezas de captura que fallaban (Jhonny, 22–25/09):
   A) el total de cajas del cierre de RT es de la SESIÓN, no del día (el «67» con 0 recibidas);
   B) una recepción enviada con RT cerrado registra su propio tramo RT (27 cargas sin tiempo);
   C) «Empecé Picking/Armado» sin tanda no se registra (quedaba una tarea abierta fantasma). */
const fs = require("fs"), path = require("path");
const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
const rjs = fs.readFileSync(path.join(__dirname, "..", "recepcion.js"), "utf8");
const mal = [];
function tomar(src, inicio, fin) {
  const i = src.indexOf(inicio); if (i < 0) throw new Error("no está: " + inicio);
  const j = src.indexOf(fin, i); return src.slice(i, j + fin.length);
}
(async () => {
  // A) sesión, no día
  const fA = tomar(html, "async function recepcionCajasServerTotal(legajo) {", "\n}\n");
  let pedido = null, estado = {};
  const ctxA = new Function("getLegajoState", "getTodayKey", "supaFetchAll", "SUPABASE_STOCK_ENDPOINT",
    fA + "\nreturn recepcionCajasServerTotal;")(
    () => estado, () => "2026-09-25",
    async (_e, q) => { pedido = q; return [{ delta: 35 }, { delta: 32 }]; }, "x");
  estado = { toggles: {} };
  if ((await ctxA("104")) !== null) mal.push("A: sin RT abierto tiene que devolver null (no el total del día)");
  estado = { toggles: { RT: "2026-09-25T12:39:39.000Z" } };
  await ctxA("104");
  if (!pedido || !/ts=gte\.2026-09-25T12%3A39%3A39/.test(pedido)) mal.push("A: el piso tiene que ser la apertura de RT, fue: " + pedido);

  // B) recepción con RT cerrado → tramo propio
  const fB = tomar(html, "window.autoCloseRT = function (legajo, opt) {", "\n};\n");
  const enviados = [];
  const win = {};
  new Function("window", "getLegajoState", "recepcionCajasDelDia", "toggleStartOrEnd", "desc",
    "pushHistoryForLegajo", "enqueueReport", "trySendOneReport", "removeFromQueue",
    "updatePendingIndicator", "updateCoreButtonsState", "recepcionCajasServerTotal", fB)(
    win, () => ({ toggles: {} }), () => 99, () => { mal.push("B: no hay RT abierto que cerrar"); }, { RT: "Recepción Mercadería" },
    () => {}, (p) => enviados.push(p), undefined, () => {}, () => {}, () => {}, async () => null);
  const t0 = Date.parse("2026-09-25T11:52:00Z");
  win.autoCloseRT("104", { inicioMs: t0, cajas: 32 });
  if (enviados.length !== 1) mal.push("B: la carga con RT cerrado tiene que registrar 1 tramo RT, registró " + enviados.length);
  else {
    const p = enviados[0];
    if (p.opcion !== "RT" || p.ts_inicio_iso !== new Date(t0).toISOString() || p.texto !== "32")
      mal.push("B: tramo mal armado " + JSON.stringify({ o: p.opcion, i: p.ts_inicio_iso, t: p.texto }));
  }
  win.autoCloseRT("104");   // sin RT y sin inicio: no se inventa nada
  if (enviados.length !== 1) mal.push("B: sin inicio medible no tiene que inventar un tramo");
  if (!/opState\.t0 = Date\.now\(\)/.test(rjs) || !/autoCloseRT\(RECP\.legajo, \{ inicioMs: opState\.t0/.test(rjs))
    mal.push("B: recepcion.js no le pasa el inicio de la carga a autoCloseRT");

  // C) EP/AP sin tanda
  if (!/if \(\(opcion === "EP" \|\| opcion === "AP"\) && !texto\) \{[\s\S]{0,300}return;/.test(html))
    mal.push("C: falta el freno de EP/AP sin tanda en send()");

  if (mal.length) { console.log("tiempos-captura: ✗ FAIL\n  - " + mal.join("\n  - ")); process.exit(1); }
  console.log("tiempos-captura: ✓ OK (sesión de RT, tramo de la carga suelta, EP/AP con tanda)");
})().catch((e) => { console.log("tiempos-captura: ✗ " + e.message); process.exit(1); });
