/* v26.65 (Luis, 05/10) — «Frenar la tanda», parte 2b.
   (A) «▶ Seguir picking» de una tanda que se FRENÓ (por el fichaje de salida o por el botón): se
       abre al instante (offline-first) y, cuando contesta la reserva, la vuelve a tomar, se abre un tramo NUEVO (EP) y el picking se siembra con lo
       pickeado de TODOS desde el servidor.
   (B) «▶ Seguir picking» de una tanda que ya agarró OTRO: se suelta lo del celular, se dice corto
       quién la tiene y no se abre nada.
   (C) La tanda sigue siendo mía (lo normal): se abre como siempre, sin EP nuevo.
   (D) Sin señal: se abre como siempre (offline-first).
   (E) «▶ Seguir armado» de una frenada propia: AP nuevo y el asistente se abre.
   (F) Al entrar a la botonera: «Tenés la tanda X frenada. ¿La retomás?» (texto de Luis) sólo si
       la frenada es de un día anterior y el celular no la tiene abierta; una vez por día.
   (G) Supervisor: «✋ Frenar» en «Modificar tanda». Armado sin copia en el servidor → no se ofrece;
       con copia → frena con motivo 'supervisor'.
   (H) «Una por vez» dice que también se puede frenar.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  let frenadasResp = "[]"; const llamadas = [];
  await p.route("**/*.supabase.co/**", (r) => r.abort());   // primero: Playwright corre las rutas al revés
  await p.route("**/rest/v1/rpc/gv_tandas_frenadas_de**", async (route) => {
    llamadas.push("frenadas_de");
    return route.fulfill({ status: 200, contentType: "application/json", body: frenadasResp });
  });
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  await p.waitForFunction(() => typeof _frenoGuardSeguir === "function" && typeof pgaModFrenar === "function");
  const out = {};

  const base = `
    window.alert = function (m) { (window.__al = window.__al || []).push(String(m)); };
    window.__enq = []; window.enqueueReport = function (pl) { window.__enq.push(pl); };
    window.flushQueue = async function () {};
    window.__abre = null; window.showPickingList = function (t, l, o) { window.__abre = { t: t, l: l, o: o || null }; };
    window.__wiz = null; window.showCompletarWizard = function (l, t) { window.__wiz = { l: l, t: t }; };
    localStorage.clear(); legajoInput.value = "277"; window.__al = [];
  `;

  // ---------------- (A) Seguir picking de una frenada propia
  out.a = await p.evaluate(async (base) => {
    eval(base);
    const st = getLegajoState("277"); st.picking = { active: true, value: "F30A", ts_inicio: "2026-10-04T12:00:00.000Z" }; setLegajoState("277", st);
    localStorage.setItem(PK_SAVE_PREFIX + "277", JSON.stringify({ tanda: "F30A", legajo: "277", day: getTodayKey(), items: [{ art: "501", key: "501", esp: 3 }], results: { "501": 3 }, idx: 0 }));
    window.tandaReservar = async function () { return { ok: true, motivo: "propia", retomada: true, legajo: "277" }; };
    pkResume("277");                                   // abre al instante; la reserva contesta después
    await new Promise(function (r) { setTimeout(r, 60); });
    const st2 = getLegajoState("277");
    return { ep: window.__enq.map((x) => x.opcion + ":" + x.texto).join(","),
             nuevoTramo: !!(st2.picking && st2.picking.active && st2.picking.ts_inicio && st2.picking.ts_inicio > "2026-10-05"),
             abreTodos: !!(window.__abre && window.__abre.t === "F30A" && window.__abre.o && window.__abre.o.seedFromServer && window.__abre.o.todos) };
  }, base);
  out.aEmiteEP = out.a.ep === "EP:F30A";
  out.aTramoNuevo = out.a.nuevoTramo;
  out.aSiembraDeTodos = out.a.abreTodos;

  // ---------------- (B) la agarró otro
  out.b = await p.evaluate(async (base) => {
    eval(base);
    const st = getLegajoState("277"); st.picking = { active: true, value: "F30A", ts_inicio: "2026-10-04T12:00:00.000Z" }; setLegajoState("277", st);
    window.tandaReservar = async function () { return { ok: false, motivo: "tomada", legajo: "104", nombre: "Jhonny" }; };
    await pkResumeServer("F30A", "277");
    const st2 = getLegajoState("277");
    return { suelta: !(st2.picking && st2.picking.active), abre: window.__abre, al: window.__al.join("|"), enq: window.__enq.length };
  }, base);
  out.bSueltaLocal = out.b.suelta && out.b.abre === null && out.b.enq === 0;
  out.bDiceQuien = out.b.al === "La tanda F30A ya la tiene Jhonny.";

  // ---------------- (C) sigue siendo mía
  out.c = await p.evaluate(async (base) => {
    eval(base);
    const st = getLegajoState("277"); st.picking = { active: true, value: "F30A", ts_inicio: "2026-10-05T12:00:00.000Z" }; setLegajoState("277", st);
    window.tandaReservar = async function () { return { ok: true, motivo: "propia", legajo: "277" }; };
    await pkResumeServer("F30A", "277");
    return { enq: window.__enq.length, abre: window.__abre, ts: getLegajoState("277").picking.ts_inicio };
  }, base);
  out.cComoSiempre = out.c.enq === 0 && !!(out.c.abre && out.c.abre.t === "F30A" && out.c.abre.o && !out.c.abre.o.todos) && out.c.ts === "2026-10-05T12:00:00.000Z";

  // ---------------- (D) sin señal
  out.d = await p.evaluate(async (base) => {
    eval(base);
    window.tandaReservar = async function () { return null; };
    await pkResumeServer("F30A", "277");
    return { enq: window.__enq.length, abre: !!window.__abre };
  }, base);
  out.dSinSenalAbre = out.d.enq === 0 && out.d.abre;

  // ---------------- (E) Seguir armado
  out.e = await p.evaluate(async (base) => {
    eval(base);
    const st = getLegajoState("277"); st.armado = { active: true, value: "F31B", ts_inicio: "2026-10-04T12:00:00.000Z" }; setLegajoState("277", st);
    window.tandaReservar = async function (t, f) { return f === "armado" ? { ok: true, motivo: "propia", retomada: true, legajo: "277" } : { ok: true }; };
    renderPendingSuggestion();
    const btn = [].slice.call(document.querySelectorAll("button")).find((x) => /Seguir armado tanda F31B/.test(x.innerText || x.textContent || ""));
    if (!btn) return { boton: false };
    await btn.onclick();
    return { boton: true, ap: window.__enq.map((x) => x.opcion + ":" + x.texto).join(","), wiz: window.__wiz };
  }, base);
  out.eAPyAbre = out.e.boton && out.e.ap === "AP:F31B" && !!(out.e.wiz && out.e.wiz.t === "F31B");

  // ---------------- (F) aviso del día siguiente
  const ayer = new Date(Date.now() - 26 * 3600 * 1000).toISOString();
  frenadasResp = JSON.stringify([{ tanda: "F30A", fase: "picking", ts_freno: ayer, motivo: "fichaje" }]);
  out.f = await p.evaluate(async (base) => {
    eval(base);
    let conf = ""; window.confirm = function (m) { conf = m; return true; };
    const enviados = []; window.send = async function () { enviados.push(selected + ":" + textInput.value); };
    await _frenoAvisoDelDia("277");
    const r1 = { conf: conf, env: enviados.join(",") };
    conf = ""; await _frenoAvisoDelDia("277");
    return { r1: r1, segunda: conf };
  }, base);
  out.fCartelExacto = out.f.r1.conf === "Tenés la tanda F30A frenada. ¿La retomás?";
  out.fRetomaConEP = out.f.r1.env === "EP:F30A";
  out.fUnaVezPorDia = out.f.segunda === "";
  // frenada HOY o ya abierta en el celular → no pregunta
  frenadasResp = JSON.stringify([{ tanda: "F30A", fase: "picking", ts_freno: new Date().toISOString() },
                                 { tanda: "F32C", fase: "picking", ts_freno: ayer }]);
  out.f2 = await p.evaluate(async (base) => {
    eval(base);
    const st = getLegajoState("277"); st.picking = { active: true, value: "F32C", ts_inicio: "2026-10-04T12:00:00.000Z" }; setLegajoState("277", st);
    let conf = ""; window.confirm = function (m) { conf = m; return true; };
    await _frenoAvisoDelDia("277");
    return conf;
  }, base);
  out.fHoyOAbiertaNoPregunta = out.f2 === "";

  // ---------------- (G) supervisor
  out.g = await p.evaluate(async () => {
    const llam = []; let snap = null;
    window._pgaTandaDe = function () { return { tanda: "F30A" }; };
    window.aprRpc = async function (fn, body) {
      llam.push(fn + ":" + JSON.stringify(body));
      if (fn === "gv_tanda_lock_estado") return [{ fase: "armado", estado: "tomada", legajo: "104", nombre: "Jhonny", ts: new Date().toISOString() }];
      if (fn === "gv_armado_avance_leer") return snap;
      if (fn === "gv_tanda_frenar") return { ok: true, motivo: "frenada" };
      return null;
    };
    window.pppLoadProgFromSupabase = async function () {}; window.pgaRecargar = function () {};
    window.confirm = function () { return true; }; window.alert = function () {};
    _pppModKey = "k";
    await pgaModFrenar();
    const body1 = (document.getElementById("pppMovBody") || {}).innerHTML || "";
    snap = { estado: "en_curso", snapshot: { nps: [] }, ts_cliente: new Date().toISOString(), nps: 4, nps_listas: 2, lios: 7, cajas_en_lios: 45 };
    await pgaModFrenar();
    const body2 = (document.getElementById("pppMovBody") || {}).innerHTML || "";
    await pgaModFrenarConfirmar();
    return { body1: body1, body2: body2, frenar: llam.filter((x) => x.indexOf("gv_tanda_frenar:") === 0) };
  });
  out.gSinCopiaNoFrena = /No hay copia de lo armado/.test(out.g.body1) && !/pgaModFrenarConfirmar/.test(out.g.body1);
  out.gConCopiaMuestra = /2 de 4 NP listas, 7 líos \(45 cajas\)/.test(out.g.body2) && /pgaModFrenarConfirmar/.test(out.g.body2);
  out.gFrenaSupervisor = out.g.frenar.length === 1 && /"p_fase":"armado"/.test(out.g.frenar[0]) && /"p_motivo":"supervisor"/.test(out.g.frenar[0]);
  out.gEnElMenu = await p.evaluate(() => /pgaModFrenar\(\)/.test(String(pgaTandaModificarAbrir)));

  // ---------------- (H) una por vez
  out.hUnaPorVezDiceFrenar = (require("fs").readFileSync(path.join(root, "index.html"), "utf8").match(/frenala con «✋ Frenar la tanda»/g) || []).length === 2;

  let ok = true;
  for (const k of Object.keys(out)) {
    if (typeof out[k] !== "boolean") continue;
    console.log((out[k] ? "OK    " : "FALLA ") + k);
    if (!out[k]) ok = false;
  }
  if (!ok) console.log(JSON.stringify(out, null, 1));
  if (errs.length) { console.log("pageerrors:", errs.slice(0, 5)); }
  console.log("tanda-frenar-2b: " + (ok ? "OK" : "FALLA"));
  await b.close();
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
