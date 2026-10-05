/* v26.66 (Luis, 05/10, D6) — «Frenar la tanda», parte 3: CRÉDITO por operario y día.
   Una tanda FRENADA la hicieron varios: cada uno se lleva el m³ de lo que hizo, en el día en que
   lo hizo (picking por sus cajas pickeadas, armado por los líos que cerró). Lo dice
   `gv_tanda_credito`; una tanda SIN freno sigue entera al que dio el TP/TAP.
   (A) Monitor grande (fetchMonitorDayStats): 104 frenó F30A (PKF) y 277 la terminó (TP) → 104 se
       lleva 0,6 y 277 0,4 (no 1,0); la tanda sin freno F31B va entera a 277; 104 aparece aunque no
       tenga TP propio.
   (B) Sin respuesta de gv_tanda_credito → como antes (F30A entera al del TP).
   (C) TV: mismo reparto en el m³/h; la parte de un operario entra cuando ÉL cierra su tramo hoy.
   (E) El desglose por día del monitor viejo usa el mismo helper (gvM3ConCredito).
   (D) Armado: separar un código deja quién lo separó (súper / retira se acreditan por eso).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const out = {};
  const DIA = "2026-10-05";
  const iso = (hh, mm) => new Date(DIA + "T" + String(hh).padStart(2, "0") + ":" + String(mm).padStart(2, "0") + ":00-03:00").toISOString();
  const EVENTOS = [
    { opcion: "EP",  texto: "F30A", legajo: "104", ts_cliente: iso(9, 0),   ts_inicio: null },
    { opcion: "PKF", texto: "F30A", legajo: "104", ts_cliente: iso(10, 0),  ts_inicio: iso(9, 0) },
    { opcion: "EP",  texto: "F30A", legajo: "277", ts_cliente: iso(11, 0),  ts_inicio: null },
    { opcion: "TP",  texto: "F30A", legajo: "277", ts_cliente: iso(12, 0),  ts_inicio: iso(11, 0) },
    { opcion: "EP",  texto: "F31B", legajo: "277", ts_cliente: iso(13, 0),  ts_inicio: null },
    { opcion: "TP",  texto: "F31B", legajo: "277", ts_cliente: iso(14, 0),  ts_inicio: iso(13, 0) },
    { opcion: "FJ",  texto: "",     legajo: "104", ts_cliente: iso(17, 0),  ts_inicio: null },
    { opcion: "FJ",  texto: "",     legajo: "277", ts_cliente: iso(17, 0),  ts_inicio: null }
  ];
  const CRED = [{ tanda: "F30A", fase: "picking", legajo: "104", dia: DIA, cajas: 60, m3: 0.6 },
                { tanda: "F30A", fase: "picking", legajo: "277", dia: DIA, cajas: 40, m3: 0.4 }];

  // ---------------- (A)/(B) monitor grande
  for (const modo of ["ok", "caido"]) {
    const p = await b.newPage();
    const errs = []; p.on("pageerror", (e) => errs.push(e.message));
    await p.route("**/*.supabase.co/**", (r) => r.abort());
    await p.route("**/rest/v1/**", async (route) => {
      const u = route.request().url();
      let filas = [];
      if (u.indexOf("rpc/gv_tanda_credito") >= 0) { if (modo === "caido") return route.abort(); filas = CRED; }
      else if (u.indexOf("Registros_Produccion_Virgilio") >= 0 && u.indexOf("opcion=eq.FJ") < 0) filas = EVENTOS;
      else if (u.indexOf("Fichadas") >= 0) filas = [{ legajo: "104", ts_cliente: iso(8, 50) }, { legajo: "277", ts_cliente: iso(8, 50) }];
      return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(filas) });
    });
    await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
    await p.waitForFunction(() => typeof fetchMonitorDayStats === "function" && typeof gvCreditoDe === "function");
    const r = await p.evaluate(async (DIA) => {
      window.getEmpleadosNombres = async function () { return new Map([["104", "Jhonny"], ["277", "Isidro"]]); };
      window.getHistoricMap = async function () { return new Map(); };
      window.ensureFeriadosAR = async function () {};
      _monitorDayStatsCache.clear && _monitorDayStatsCache.clear();
      const d = await fetchMonitorDayStats(DIA, new Map([["F30A", { m3: 1 }], ["F31B", { m3: 0.5 }]]));
      const o = {};
      (d.perOperario || []).forEach(function (x) { o[x.legajo] = { m3Pick: Math.round(x.m3Pick * 1000) / 1000, didPick: x.didPick,
        det: (x.pickedDetail || []).map(function (dt) { return dt.tanda + ":" + (Math.round((dt.m3 || 0) * 1000) / 1000); }).join(",") }; });
      return o;
    }, DIA);
    out[modo] = r;
    if (errs.length) out[modo + "Err"] = errs.slice(0, 3);
    await p.close();
  }
  out.aCadaUnoSuParte = !!(out.ok["104"] && out.ok["104"].m3Pick === 0.6 && out.ok["277"] && out.ok["277"].m3Pick === 0.9);
  out.aElQueSoloFrenoFigura = !!(out.ok["104"] && out.ok["104"].didPick);
  out.aDetalleConSuParte = !!(out.ok["277"] && /F30A:0\.4/.test(out.ok["277"].det) && /F31B:0\.5/.test(out.ok["277"].det));
  out.bSinRespuestaComoAntes = !!(out.caido["277"] && out.caido["277"].m3Pick === 1.5);

  // ---------------- (C) TV (su código vive en una IIFE: se carga la página entera con datos simulados)
  {
    const AR = (ms) => new Date(new Date(ms).toLocaleString("en-US", { timeZone: "America/Argentina/Buenos_Aires" }));
    const key = (ms) => { const d = AR(ms); return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); };
    const T0 = Date.parse(key(Date.now()) + "T15:00:00-03:00"), HOY = key(T0), Hh = 3600 * 1000;
    const I = (ms) => new Date(ms).toISOString();
    const EV = [
      { legajo: 104, opcion: "EP",  texto: "F30A", ts_cliente: I(T0 - 6 * Hh), ts_inicio: null },
      { legajo: 104, opcion: "PKF", texto: "F30A", ts_cliente: I(T0 - 5 * Hh), ts_inicio: I(T0 - 6 * Hh) },
      { legajo: 277, opcion: "EP",  texto: "F30A", ts_cliente: I(T0 - 4 * Hh), ts_inicio: null },
      { legajo: 277, opcion: "TP",  texto: "F30A", ts_cliente: I(T0 - 3 * Hh), ts_inicio: I(T0 - 4 * Hh) },
      { legajo: 277, opcion: "EP",  texto: "F31B", ts_cliente: I(T0 - 2.5 * Hh), ts_inicio: null },
      { legajo: 277, opcion: "TP",  texto: "F31B", ts_cliente: I(T0 - 2 * Hh), ts_inicio: I(T0 - 2.5 * Hh) },
      { legajo: 44,  opcion: "EP",  texto: "F30A", ts_cliente: I(T0 - 1 * Hh), ts_inicio: null }   // retomó y sigue: todavía no cerró
    ];
    const HORAS = [
      { legajo: "104", nombre: "Cartaya Jhonny", hs_pick: 1,   hs_arm: 0, hs_total: 6, en_jornada: true },
      { legajo: "277", nombre: "Isidro Perez",   hs_pick: 1.8, hs_arm: 0, hs_total: 6, en_jornada: true },
      { legajo: "44",  nombre: "Gomez Ana",      hs_pick: 1,   hs_arm: 0, hs_total: 6, en_jornada: true }
    ];
    const CRT = CRED.map((c) => Object.assign({}, c, { dia: HOY })).concat([{ tanda: "F30A", fase: "picking", legajo: "44", dia: HOY, cajas: 30, m3: 0.3 }]);
    const PROG = [{ tanda: "F30A", np: "98901", m3: 1, fecha_entrega: HOY, razon_social: "Cliente A", zona: "Zona 1 - CABA Sur", fecha_recep: HOY },
                  { tanda: "F31B", np: "98902", m3: 0.5, fecha_entrega: HOY, razon_social: "Cliente B", zona: "Zona 1 - CABA Sur", fecha_recep: HOY }];
    for (const modo of ["ok", "caido"]) {
      const ctx = await b.newContext({ timezoneId: "America/Argentina/Buenos_Aires", viewport: { width: 1920, height: 1080 } });
      const p = await ctx.newPage();
      await p.clock.setFixedTime(T0);
      let pidio = null;
      await p.route("**/rest/v1/**", (route) => {
        const q = decodeURIComponent(route.request().url());
        if (q.includes("/rpc/gv_tanda_credito")) {
          try { pidio = JSON.parse(route.request().postData() || "null"); } catch (_e) { pidio = "mal"; }
          if (modo === "caido") return route.abort();
        }
        let f = [];
        if (q.includes("/rpc/gv_tanda_credito")) f = CRT;
        else if (q.includes("/gv_ppp_programacion_diaria")) f = PROG;
        else if (q.includes("/gv_monitor_horas_operario")) f = HORAS;
        else if (q.includes("/Registros_Produccion_Virgilio")) f = q.includes("opcion=in.(CCN,FSS)") ? [] : EV;
        route.fulfill({ status: 200, headers: { "content-type": "application/json", "content-range": "0-" + Math.max(0, f.length - 1) + "/" + f.length }, body: JSON.stringify(f) });
      });
      await p.goto("file://" + path.join(root, "monitor", "tv.html") + "?key=tv", { waitUntil: "domcontentloaded" });
      await p.waitForSelector("#splash.hide", { timeout: 15000 }).catch(() => {});
      await p.waitForFunction(() => document.querySelectorAll("#opsBox td[title]").length >= 3, null, { timeout: 15000 }).catch(() => {});
      const filas = await p.evaluate(() => [].slice.call(document.querySelectorAll("#opsBox tr")).map(function (tr) {
        const td = tr.querySelectorAll("td"); return td.length ? { nom: td[0].getAttribute("title") || "", pick: (td[1] || {}).textContent || "" } : null; }).filter(Boolean));
      const r = (n) => ((filas.find((x) => x.nom === n) || {}).pick || "").trim();
      out["tv_" + modo] = { j: r("Cartaya Jhonny"), i: r("Isidro Perez"), a: r("Gomez Ana"), pidio: pidio };
      await ctx.close();
    }
    // 104: 0,6 m³ en 1 h · 277: 0,4 + 0,5 = 0,9 en 1,8 h = 0,5 · 44: su parte NO entra (todavía no cerró su tramo)
    out.cTvCadaUnoSuParte = out.tv_ok.j === "0,6" && out.tv_ok.i === "0,5";
    out.cTvSinCierreNoSuma = out.tv_ok.a === "—";
    out.cTvPideLaTanda = !!(out.tv_ok.pidio && Array.isArray(out.tv_ok.pidio.p_tandas) && out.tv_ok.pidio.p_tandas.indexOf("F30A") >= 0);
    // sin respuesta: como antes — F30A entera al del TP (1,5 en 1,8 h = 0,8) y el que frenó, sin m³
    out.cTvSinRespuestaComoAntes = out.tv_caido.i === "0,8" && out.tv_caido.j === "—";
  }

  // (E) el desglose por día del monitor viejo usa la misma cuenta (no una copia)
  {
    const fs = require("fs");
    const src = fs.readFileSync(path.join(root, "index.html"), "latin1");
    const i0 = src.indexOf("async function showDayBreakdown("), i1 = src.indexOf("async function fetchMonitorDayStats(");
    const sdb = i0 >= 0 ? src.slice(i0, src.indexOf("\nasync function ", i0 + 10)) : "";
    const fms = i1 >= 0 ? src.slice(i1, src.indexOf("\nasync function ", i1 + 10)) : "";
    out.eDesgloseUsaElHelper = /gvM3ConCredito\(_credD, p\.pickedTandas, p\.pickFr/.test(sdb) && /PKF/.test(sdb);
    out.eMonitorUsaElHelper = /gvM3ConCredito\(_cred, p\.pickedTandas, _frP/.test(fms);
  }

  // ---------------- (D) armado: quién separó
  {
    const p = await b.newPage();
    await p.route("**/*.supabase.co/**", (r) => r.abort());
    await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
    await p.waitForFunction(() => typeof _compSepTap === "function");
    out.d = await p.evaluate(() => {
      window._compRenderSep = function () {}; window._compRecalc = function () {};
      let persistio = 0; window._compPersist = function () { persistio++; };
      _comp = { tanda: "F30A", legajo: "277", nps: [{ np: "LK 0400", clase: "etiqueta", codes: [{ cod: "501", sale: 6, sep: false }] }] };
      _compSepTap(0, 0);
      const c = _comp.nps[0].codes[0];
      return { sep: c.sep, leg: c.sepLeg, ts: typeof c.sepTs === "number", persistio: persistio };
    });
    out.dQuienSeparo = out.d.sep === true && out.d.leg === "277" && out.d.ts && out.d.persistio === 1;
    await p.close();
  }

  let ok = true;
  for (const k of Object.keys(out)) {
    if (typeof out[k] !== "boolean") continue;
    console.log((out[k] ? "OK    " : "FALLA ") + k);
    if (!out[k]) ok = false;
  }
  if (!ok) console.log(JSON.stringify(out, null, 1));
  console.log("tanda-credito: " + (ok ? "OK" : "FALLA"));
  await b.close();
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
