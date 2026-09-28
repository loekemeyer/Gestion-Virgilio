/* v23.34 (Luis, 28/09): "fijate que no quede ninguna feature colgada así porque no estamos arrastrando".
   El pop-up de DÍA OCUPADO no puede ser sólo del arrastre. Se corren los caminos SIN arrastrar:
   (a) tildar + día + ✅ Confirmar (aprConfirmar) con el día ocupado → abre el pop-up, y el aviso
       "ya está completo" NO sale en un confirm aparte (lo muestra el pop-up); elegir 1 arma la tanda.
   (b) el mismo camino con el día VACÍO → sin pop-up, confirm de siempre (con "completo") y arma.
   (c) una tanda sin fecha soltada en un día (aprProgramarTanda) → pop-up; elegir 3 corre y DESPUÉS programa.
   (d) reprogramar una NP de ISIS (pppReprogElegir) → pop-up; elegir 1 reprograma sin preguntar de nuevo. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "load" });

  const r = await p.evaluate(async () => {
    const log = [], confirms = [];
    const F = "2026-09-30";
    const corr = [{ tanda: "E48G", fecha_actual: F, fecha_nueva: "2026-10-01", accion: "mueve", motivo: "pendiente", m3: 2.5, zona: "Zona 3 - CABA Oeste", vence: false, vencia: false }];
    let vacio = false;
    const espera = function () { return new Promise(function (res) { setTimeout(res, 60); }); };
    const abierto = function () { const o = document.getElementById("aprDoOv"); return !!(o && o.classList.contains("show")); };
    const elegir = function (i) { document.getElementById("aprDoOv").querySelectorAll(".ado-op")[i].querySelector(".ado-b").click(); };
    window.confirm = function (m) { confirms.push(m); return true; };
    window.alert = function () {};
    window.aprQuien = async function () { return "test@x"; };
    window.aprRender = function () {};
    window.pppSetStatus = function () {};
    window.pppLoadProgFromSupabase = async function () {};
    window.aprGenerarTanda = async function (f, keys, o) { log.push("generar:" + f + ":" + keys.join(",") + ":" + !!(o && o.sinConfirm)); };
    window.aprProgramar = async function (cod, f) { log.push("programarTanda:" + cod + ":" + f); };
    window.aprRpc = async function (fn, body) {
      if (fn === "gv_ppp_dia_reprogramar") { log.push("reprog:" + body.p_modo + ":" + body.p_simular); return vacio ? [] : corr; }
      if (fn === "gv_ppp_web_camion_nuevo") return [];
      if (fn === "gv_ppp_isis_programar") { log.push("isis:" + body.p_fecha); return [{ codigo: "E90A", np_programadas: 1, m3: 0.3 }]; }
      return [];
    };
    const ped = { empresa: "lk", order_id: 1504, zona: "Super", m3: 4.58, np_total: 2 };
    window.aprSelKeys = function () { return ["lk|1504"]; };
    window.aprResumenSel = function () { return { n: 1, m3: 4.58, peds: [ped] }; };
    _apr.cal = [{ dia: F, m3: 4.6, cupo: 4.3, muy_pronto: false }];
    _apr.m3Min = 0.6;

    // (a) Confirmar con el día ocupado
    _apr.diaSel = F; _apr.ocupado = false;
    await aprConfirmar(); await espera();
    const a = { popup: abierto(), confirms: confirms.slice() };
    log.length = 0; elegir(0); await espera();
    a.log = log.slice();

    // (b) Confirmar con el día vacío
    confirms.length = 0; log.length = 0; vacio = true; _apr.diaSel = F;
    await aprConfirmar(); await espera();
    const bb = { popup: abierto(), confirms: confirms.slice(), log: log.slice() };
    vacio = false;

    // (c) tanda sin fecha → día
    log.length = 0; _apr.items = { E99Z: [{ empresa: "lk", order_id: 1504, np_idx: 1 }] }; _apr.pedidosTodos = [ped];
    await aprProgramarTanda("E99Z", F); await espera();
    const c = { popup: abierto() }; log.length = 0; elegir(2); await espera(); c.log = log.slice();

    // (d) NP de ISIS
    log.length = 0; confirms.length = 0;
    _pppMov = { reprogNps: ["98617"], reprogLabel: "98617 Riondini" };
    await pppReprogElegir(F); await espera();
    const d = { popup: abierto() }; elegir(0); await espera(); d.log = log.slice(); d.confirms = confirms.slice();
    return { a: a, b: bb, c: c, d: d };
  });

  const f = [];
  if (!r.a.popup) f.push("(a) Confirmar con el día ocupado no abrió el pop-up");
  if (r.a.confirms.some(function (m) { return /completo/.test(m); })) f.push("(a) repitió 'ya está completo' en un confirm aparte");
  if (!r.a.log.some(function (x) { return /^generar:2026-09-30:lk\|1504:true$/.test(x); })) f.push("(a) elegir 1 no armó la tanda: " + r.a.log.join(" | "));
  if (r.a.log.some(function (x) { return /reprog:.*:false/.test(x); })) f.push("(a) sumar reprogramó");
  if (r.b.popup) f.push("(b) día vacío abrió el pop-up");
  if (!r.b.confirms.some(function (m) { return /completo/.test(m); })) f.push("(b) día vacío perdió el aviso de siempre");
  if (!r.b.log.some(function (x) { return /^generar:/.test(x); })) f.push("(b) día vacío no armó la tanda");
  if (!r.c.popup) f.push("(c) tanda → día no abrió el pop-up");
  const iR = r.c.log.indexOf("reprog:correr:false"), iP = r.c.log.findIndex(function (x) { return /^programarTanda:E99Z/.test(x); });
  if (iR < 0 || iP < iR) f.push("(c) no corrió y después programó: " + r.c.log.join(" | "));
  if (!r.d.popup) f.push("(d) ISIS no abrió el pop-up");
  if (!r.d.log.some(function (x) { return x === "isis:2026-09-30"; })) f.push("(d) no reprogramó la NP de ISIS: " + r.d.log.join(" | "));
  if (r.d.confirms.length) f.push("(d) preguntó de nuevo después de elegir");
  if (errs.length) f.push("pageerrors: " + errs.join(" | "));
  const ok = !f.length;
  if (!ok) console.log("  ✗ " + f.join("\n  ✗ "));
  console.log("apr-dia-ocupado-sin-arrastre: " + (ok ? "✓ OK" : "✗ FALLÓ"));
  await b.close();
  process.exit(ok ? 0 : 1);
})();
