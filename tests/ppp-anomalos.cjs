/* v31.89 (Luis, 16/10/2026) — PEDIDOS ANÓMALOS en la Programación de entregas.
   Pedido: *"indicando en el día de la PPP un anuncio de «PEDIDOS ANOMALOS: X» a la izquierda de la
   fila del día donde está programado ese pedido"*. Caso testigo: LK 0364, 48 cajas de 525E (uxb 24).
   Se chequea, corriendo la Programación de verdad (estado inyectado, red cortada):
     (a) el día con 2 NP anómalas dice «PEDIDOS ANÓMALOS: 2»; el día sin anomalías no dibuja nada;
     (b) en pantalla ancha el cartel queda AFUERA de la tabla, a la izquierda y a la altura de su fila;
     (c) en el celular (sin margen) queda adentro de la fila, visible;
     (d) tocarlo abre el detalle con cada NP, artículo, motivo y si lo contacta el bot o es sólo aviso,
         y no abre el día;
     (e) la NP lleva su pastilla («⚠ anómalo · bot» si hay que contactar, «⚠ anómalo» si es sólo aviso);
     (f) si la lectura de anomalías falla, la Programación se ve igual y sin cartel;
     (g) el SQL conserva las tres reglas (las mismas que cuida GV_Reglas_Centinela).
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
const _d = (n) => { const d = new Date(); d.setHours(12, 0, 0, 0); d.setDate(d.getDate() + n);
  return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); };
const F = { hoy: _d(0), d1: _d(1), d2: _d(2) };
F.d1C = F.d1.replace(/-/g, "");

const ANOM = [
  { id: 1, empresa: "lk", np_label: "LK 0364", razon_social: "Emotiti S.A.", articulo: "525E", cajas: 48, regla: "historial",
    detalle: "Pidió 48 cj de 525E; su promedio es 2,0 cj (3 pedidos con el artículo, 9 pedidos en 12 meses). Tope ×5 = 10,0 cj",
    contactar: true, estado: "pendiente", contacto_nota: null, referencia: 2, limite: 10 },
  { id: 2, empresa: "lk", np_label: "LK 0364", razon_social: "Emotiti S.A.", articulo: "525E", cajas: 48, regla: "cajas_uxb",
    detalle: "Pidió 48 cj de 525E y la caja trae 24 u.: ¿quiso decir 2 cj (48 unidades)?", contactar: false, estado: "pendiente", contacto_nota: null, referencia: 24, limite: null },
  { id: 3, empresa: "lk", np_label: "LK 0365", razon_social: "Bazar Uxb", articulo: "501", cajas: 12, regla: "cajas_uxb",
    detalle: "Pidió 12 cj de 501 y la caja trae 12 u.: ¿quiso decir 1 cj (12 unidades)?", contactar: false, estado: "pendiente", contacto_nota: null, referencia: 12, limite: null }
];

async function correr(b, ancho, falla) {
  const p = await b.newPage({ viewport: { width: ancho, height: 1000 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "load" });
  const r = await p.evaluate(async (A) => {
    const F = A.F, out = {};
    window.__isSupervisor = true;
    window.alert = function () {}; window.confirm = function () { return true; };
    window.getTodayKey = () => F.hoy;
    window.pppSetStatus = function () {};
    window.pppLoadProgFromSupabase = async function () {};
    window.pgaNeed = function () {}; window.patrNeed = function () {};
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    window.pppPaintTabs = function () {};
    window.aprRpc = async function (fn) {
      if (fn === "gv_ppp_anomalos_lista") { if (A.falla) throw new Error("HTTP 500"); return A.ANOM; }
      return [];
    };
    _pppParsed = { prog: [{ np: "98630", tanda: "D99Z", fecha_entrega: F.d1, m3: 1.8,
                            cod: "1", razon_social: "Otra", zona: "Zona 2", programmed: true }] };
    const mk = (f, tanda, np, cli) => ({ fecha: f, tanda: tanda, np: np, np_num: 58, cod: "4288", razon_social: cli,
      localidad: "CABA", zona: "Zona 2", zona_corta: "Zona 2", empresa: "LK", origen: "web", m3: 0.5,
      estado: "pendiente", estado_orden: 1, barrio: "Villa Crespo", fecha_pedido: F.hoy });
    _pgaRows = [mk(F.d1, "F66A", "LK 0364", "Emotiti S.A."), mk(F.d1, "F66A", "LK 0365", "Bazar Uxb"),
                mk(F.d1, "F66B", "LK 0366", "Normal SRL"), mk(F.d2, "F67A", "LK 0367", "Otro Normal")];
    _pgaTs = Date.now();
    _pgaObs = new Map();
    const esperar = async function (fn, ms) {
      const t0 = Date.now();
      while (Date.now() - t0 < (ms || 15000)) { if (fn()) return true; await new Promise((res) => setTimeout(res, 40)); }
      return false;
    };
    const fila = function (sel, txt) {
      const pv = document.getElementById("pppPreview"); if (!pv) return null;
      return [...pv.querySelectorAll(sel)].find((x) => x.textContent.indexOf(txt) >= 0) || null;
    };
    _pppTab = "plan"; _pppPlanTabla = true; _pppPlanDay = null;
    document.getElementById("pppOverlay").classList.add("show");
    pppRenderProg();
    await esperar(() => !!document.querySelector("#pppPreview table.pga"));
    out.tabla = !!document.querySelector("#pppPreview table.pga");
    try { pgaAnomCargar(F.hoy); } catch (e) { out.err = String(e && e.message || e); }
    await esperar(() => !!document.querySelector("#pppPreview .pga-anom"), A.falla ? 800 : 5000);
    await new Promise((res) => setTimeout(res, 1100));   // el cartel de afuera se ubica al terminar la animación del overlay (450 ms)

    const d1 = [...document.querySelectorAll("#pppPreview tr.pga-d")][0];
    const d2 = [...document.querySelectorAll("#pppPreview tr.pga-d")][1];
    const chip = d1 && d1.querySelector(".pga-anom");
    out.chipTxt = chip ? chip.textContent.trim() : "";
    out.d2SinChip = !!d2 && !d2.querySelector(".pga-anom");
    out.tablaSigue = !!document.querySelector("#pppPreview table.pga");
    const g = document.querySelector("#pppPreview .pga-anom-g");
    out.afuera = !!g; { const bk = document.querySelector("#pppPreview .pga-blk"); out.blkLeft = bk ? Math.round(bk.getBoundingClientRect().left) : null; }
    if (g) {
      const rg = g.getBoundingClientRect(), rt = document.querySelector("#pppPreview table.pga").getBoundingClientRect(),
            rf = d1.getBoundingClientRect();
      out.aLaIzquierda = rg.right <= rt.left + 1;
      out.alturaFila = Math.abs((rg.top + rg.height / 2) - (rf.top + rf.height / 2)) < 4;
      out.gTxt = g.textContent.trim();
    }
    out.chipAdentroVisible = !!chip && getComputedStyle(chip).display !== "none" && chip.getBoundingClientRect().width > 0;
    const clic = g || chip;
    if (clic) {
      clic.click();
      await esperar(() => { const m = document.getElementById("pgaAnomModal"); return m && !m.hidden; }, 3000);
      const m = document.getElementById("pgaAnomModal"), t = (m && !m.hidden) ? m.textContent : "";
      out.modalNps = t.indexOf("LK 0364") >= 0 && t.indexOf("LK 0365") >= 0;
      out.modalMotivo = t.indexOf("Tope ×5 = 10,0 cj") >= 0;
      out.modalBot = t.indexOf("Bot: a contactar") >= 0 && t.indexOf("Sólo aviso") >= 0;
      out.diaNoAbrio = document.querySelectorAll("#pppPreview tr.pga-t").length === 0;
      pgaAnomCerrar();
    }
    pgaAbrirDia(F.d1C); pgaAbrirTanda(F.d1C + "|F66A");
    await esperar(() => !!fila("tr.pga-n", "LK 0364"));
    const n1 = fila("tr.pga-n", "LK 0364"), n2 = fila("tr.pga-n", "LK 0365");
    out.npBot = n1 && n1.querySelector(".pga-anom-np") ? n1.querySelector(".pga-anom-np").textContent.trim() : "";
    out.npAviso = n2 && n2.querySelector(".pga-anom-np") ? n2.querySelector(".pga-anom-np").textContent.trim() : "";
    _pgaItems["LK 0364"] = [{ art: "501", cajas: 3, uxb: 12 }, { art: "525E", cajas: 48, uxb: 24 }];
    pgaAbrirNp(F.d1C + "|F66A|LK 0364", "LK 0364");
    await esperar(() => !!document.querySelector("#pppPreview .pga-it"));
    const its = [...document.querySelectorAll("#pppPreview .pga-it")];
    out.itMarcado = its.filter((x) => x.classList.contains("anom")).map((x) => x.textContent.trim());
    return out;
  }, { F: F, ANOM: ANOM, falla: !!falla });
  await p.close();
  r.errs = errs;
  return r;
}

(async () => {
  const b = await chromium.launch();
  const ancho = await correr(b, 1500, false);
  const cel = await correr(b, 420, false);
  const caido = await correr(b, 1500, true);
  await b.close();

  const fallas = [];
  const ok = (c, m) => { if (!c) fallas.push(m); };
  ok(ancho.tabla, "no se dibujó la Programación");
  ok(ancho.chipTxt === "⚠ PEDIDOS ANÓMALOS: 2", "(a) el día tenía que decir «⚠ PEDIDOS ANÓMALOS: 2» y dice: " + JSON.stringify(ancho.chipTxt));
  ok(ancho.d2SinChip, "(a) el día sin anomalías dibujó el cartel");
  ok(ancho.afuera, "(b) en pantalla ancha el cartel no salió afuera de la tabla (bloque a " + ancho.blkLeft + " px del borde)");
  ok(ancho.aLaIzquierda, "(b) el cartel de afuera no está a la izquierda de la tabla");
  ok(ancho.alturaFila, "(b) el cartel de afuera no está a la altura de la fila del día");
  ok(ancho.chipAdentroVisible === false, "(b) quedaron los dos carteles: el de adentro tenía que esconderse");
  ok(ancho.modalNps, "(d) el detalle no lista las dos NP");
  ok(ancho.modalMotivo, "(d) el detalle no explica el motivo");
  ok(ancho.modalBot, "(d) el detalle no distingue «Bot: a contactar» de «Sólo aviso»");
  ok(ancho.diaNoAbrio, "(d) tocar el cartel abrió el día");
  ok(ancho.npBot === "⚠ 525E 48 cj (tope 10) · bot", "(e) la NP a contactar dice: " + JSON.stringify(ancho.npBot));
  ok(ancho.npAviso === "⚠ 501 12 cj (¿1 cj?)", "(e) la NP de sólo aviso dice: " + JSON.stringify(ancho.npAviso));
  ok((ancho.itMarcado || []).length === 1 && /525E/.test(ancho.itMarcado[0]), "(e) adentro de la NP tenía que marcarse sólo el 525E: " + JSON.stringify(ancho.itMarcado));
  ok(cel.chipTxt === "⚠ PEDIDOS ANÓMALOS: 2", "(c) en el celular el cartel no está");
  ok(!cel.afuera && cel.chipAdentroVisible, "(c) en el celular el cartel tenía que quedar adentro de la fila y visible");
  ok(caido.tablaSigue && caido.chipTxt === "", "(f) con la lectura caída la tabla tenía que verse sin cartel");
  for (const x of [ancho, cel, caido]) ok(!x.errs.length && !x.err, "error de JS: " + JSON.stringify(x.errs.concat(x.err || [])));
  const sql = fs.readFileSync(path.join(__dirname, "..", "sql", "gv_ppp_pedidos_anomalos_v3189.sql"), "utf8");
  ok(/r\.prom < par\.hprom and r\.cajas > r\.prom \* par\.hfac/.test(sql), "(g) el SQL perdió la regla de historial ×5");
  ok(/\(r\.nped < par\.hmin or r\.nart = 0\) and r\.peso >= par\.efac/.test(sql), "(g) el SQL perdió la regla de la Est. Madre (o D2: artículo nuevo de cliente con historial)");
  ok(/mod\(r\.cajas, r\.uxb\) = 0\s+and coalesce\(r\.mx, 0\) < r\.cajas/.test(sql), "(g) el SQL perdió la regla de cajas = uxb sólo sin respaldo en el historial (D1)");
  ok(/r\.prom >= par\.hprom and r\.cajas > r\.mx \* par\.hmaxf/.test(sql), "(g) el SQL perdió D3/D6: promedio ≥ 5 cj → ×2 del pedido más grande de ese artículo");
  ok(/r\.nnuevos >= par\.lmin/.test(sql) && /'linea_nueva'/.test(sql), "(g) el SQL perdió D4: incorporación de línea en un solo aviso");

  if (fallas.length) { console.error("ppp-anomalos: FALLA\n - " + fallas.join("\n - ")); process.exit(1); }
  console.log("ppp-anomalos: OK (cartel por día afuera/adentro, detalle, pastilla de NP, lectura caída, reglas en el SQL)");
})();
