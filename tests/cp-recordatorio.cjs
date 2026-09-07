/* Regresión v14.01 — el recordatorio "⏰ Es hora de completar los faltantes".
   Cinco arreglos, uno por caso:
     1) TOPE de hora: antes disparaba de 15:30 a 23:59.
     2) FERIADOS: antes sólo miraba lunes-a-viernes (el 07/09 le era "hábil").
     3) NO AVISA SI NO HAY NADA que completar: antes avisaba igual todos los días.
     4) El DEDUP se marca DESPUÉS de abrir el modal: si el modal falla, mañana reintenta.
     5) Sin red no avisa ni marca (no quema el aviso del día).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado (/opt/node22/lib/node_modules/playwright)."); process.exit(2); }
}

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    // ── arnés: se reemplazan las funciones (son `function`, o sea propiedades de window) ──
    let alerts = [], abiertos = [];
    window.alert = function (m) { alerts.push(String(m)); };
    window.showCPModal = function (leg) { abiertos.push(String(leg)); };
    // el destinatario: hacemos que caiga por el camino 2 (supervisor = operadora)
    window.__isSupervisor = true;
    window.__authEmail = FAC_OPERADORA_EMAIL;

    async function correr(opts) {
      alerts = []; abiertos = [];
      try { localStorage.clear(); } catch (_e) {}
      _cpRecordBusy = false;
      _pppNoHabiles = opts.feriado ? new Set([String(opts.ymd).replace(/-/g, "")]) : new Set();
      window._cpRecordNowAR = function () { return { ymd: opts.ymd, min: opts.min, habil: opts.habil }; };
      window.cpLoadFaltantes = async function () {
        if (opts.sinRed) throw new Error("sin red");
        return new Array(opts.pendientes || 0).fill({ np: "98542", cod_art: "231", cajas_falto: 1 });
      };
      if (opts.modalRompe) window.showCPModal = function () { throw new Error("modal roto"); };
      else window.showCPModal = function (leg) { abiertos.push(String(leg)); };
      await cpRecordCheck();
      let marcado = false;
      try { marcado = !!localStorage.getItem("vir_cp_record_" + String(FAC_OPERADORA_EMAIL).toLowerCase() + "_" + opts.ymd); } catch (_e) {}
      return { avisos: alerts.length, abiertos: abiertos.length, marcado: marcado, texto: alerts[0] || "" };
    }

    const base = { ymd: "2026-09-08", habil: true, pendientes: 5 };

    // 1) dentro de la ventana (16:00) y con faltantes → avisa, abre y marca
    let x = await correr(Object.assign({}, base, { min: 16 * 60 }));
    out.enVentanaAvisa   = x.avisos === 1 && x.abiertos === 1 && x.marcado === true;
    out.diceCuantos      = /5 pendientes/.test(x.texto);

    // 2) TOPE: 19:00 ya está fuera → no avisa (antes sí)
    x = await correr(Object.assign({}, base, { min: 19 * 60 }));
    out.topeCorta        = x.avisos === 0 && x.marcado === false;

    // 3) antes del piso (10:20, el caso que reportó el dueño) → no avisa
    x = await correr(Object.assign({}, base, { min: 10 * 60 + 20 }));
    out.antesDelPiso     = x.avisos === 0 && x.marcado === false;

    // 4) SIN faltantes pendientes → no molesta (antes avisaba igual)
    x = await correr(Object.assign({}, base, { min: 16 * 60, pendientes: 0 }));
    out.sinNadaNoAvisa   = x.avisos === 0 && x.abiertos === 0 && x.marcado === false;

    // 5) FERIADO de la empresa → no avisa (antes sí: sólo miraba lunes-a-viernes)
    x = await correr(Object.assign({}, base, { min: 16 * 60, feriado: true }));
    out.feriadoNoAvisa   = x.avisos === 0 && x.marcado === false;

    // 6) fin de semana → no avisa
    x = await correr(Object.assign({}, base, { min: 16 * 60, habil: false }));
    out.finDeSemanaNo    = x.avisos === 0 && x.marcado === false;

    // 7) si el modal FALLA no se marca el dedup → mañana reintenta (antes se quemaba el día)
    x = await correr(Object.assign({}, base, { min: 16 * 60, modalRompe: true }));
    out.modalRotoReintenta = x.marcado === false;

    // 8) sin red no avisa ni marca
    x = await correr(Object.assign({}, base, { min: 16 * 60, sinRed: true }));
    out.sinRedNoQuema    = x.avisos === 0 && x.marcado === false;

    // 9) el que no es destinatario no recibe nada
    window.__isSupervisor = false; window.__authEmail = "otro@ejemplo.com";
    x = await correr(Object.assign({}, base, { min: 16 * 60 }));
    out.ajenoNoRecibe    = x.avisos === 0 && x.abiertos === 0;

    return out;
  });

  await b.close();
  const fails = Object.keys(r).filter((k) => !r[k]);
  const ok = fails.length === 0 && errs.length === 0;
  console.log("cp-recordatorio:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none", ok ? "· ✓ OK" : "· ✗ FALLA: " + fails.join(", "));
  process.exit(ok ? 0 : 1);
})();
