/* v26.61 (Luis, 05/10) — «Frenar la tanda», parte 1: la COPIA DEL ARMADO en el servidor.
   El avance del asistente vivía sólo en el celular hasta «Terminar». Ahora viaja además a
   GV_Armado_Avance (rpc gv_armado_avance_guardar), sin cambiar nada de lo que ve el operario.
   (A) cerrar un lío lo firma con legajo y hora, y la copia sale a los ~1,5 s con esa firma;
       la firma no cambia la letra ni el grupo del lío (_compLioSig / liosLabels).
   (B) muchos cambios seguidos (cada caja) → UNA sola copia, a los 8 s, no una por cambio.
   (C) ⏸ Pausar manda la foto YA y apaga lo programado (no sale otra después).
   (D) la foto no lleva lo que se rearma al abrir (dirByNp, sucByNp, pickUbic) y sí el resto;
       lleva dispositivo y versión.
   (E) el legajo de prueba no manda nada.
   (F) sin red: no tira error, el armado sigue y la copia sale con el próximo cambio.
   (G) terminar y soltar («No la armo yo») cierran la copia (candado sobre el código).
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  let modo = "ok"; const posts = [];
  await p.route("**/*.supabase.co/**", (r) => r.abort());   // primero: Playwright corre las rutas al revés del registro
  await p.route("**/rest/v1/rpc/gv_armado_avance_guardar**", async (route) => {
    let body = {}; try { body = JSON.parse(route.request().postData() || "{}"); } catch (_e) {}
    if (modo === "abort") return route.abort();
    posts.push(body);
    return route.fulfill({ status: 200, contentType: "application/json", body: '"ok"' });
  });
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  await p.waitForFunction(() => typeof _compAddLio === "function" && typeof _armAvProgramar === "function");
  const w = (ms) => p.waitForTimeout(ms);
  const out = {};

  const armar = (leg) => p.evaluate((leg) => {
    window.alert = function () {}; window.renderPendingSuggestion = function () {}; window.updatePendingIndicator = function () {};
    window.etlEnqueueLio = function () {};
    _comp = { legajo: leg, tanda: "F22A", fecha: "", step: 3, liosNpIdx: 0, pickUbic: "mesa 2",
      dirByNp: { "LK 0300": "Calle 1" }, sucByNp: { "LK 0300": "Suc" }, _difMovs: [],
      nps: [{ np: "LK 0300", rs: "Cliente", clase: "lio", liosArr: [], liosDone: false,
              codes: [{ cod: "501", raw: "501", sale: 6, rest: 6, cur: 0, sep: true }] }] };
  }, leg);

  // (A) lío cerrado
  await armar("104"); posts.length = 0;
  const a = await p.evaluate(() => {
    const n = _comp.nps[0];
    n.codes[0].rest -= 2;
    _compAddLio(n, { items: [{ cod: "501", qty: 2 }], cajas: 2, suelta: false });
    const l = n.liosArr[0];
    const otro = { items: [{ cod: "501", qty: 2 }], cajas: 2, suelta: false };
    return { leg: l.leg, ts: typeof l.ts === "number" && Math.abs(Date.now() - l.ts) < 5000,
             mismaFirma: _compLioSig(l) === _compLioSig(otro),
             mismaLetra: JSON.stringify(liosLabels([l, otro])) === JSON.stringify(liosLabels([otro, otro])) };
  });
  out.aFirmaLegajo = a.leg === "104" && a.ts;
  out.aNoCambiaLetraNiGrupo = a.mismaFirma && a.mismaLetra;
  await w(2200);
  out.aSaleUnaCopia = posts.length === 1 && posts[0].p_estado === "en_curso" && posts[0].p_tanda === "F22A" && posts[0].p_legajo === "104";
  const s = posts[0] && posts[0].p_snapshot;
  out.aCopiaConFirma = !!(s && s.nps && s.nps[0].liosArr[0].leg === "104");
  // (D) qué lleva la foto
  out.dSinLoQueSeRearma = !!(s && !("dirByNp" in s) && !("sucByNp" in s) && !("pickUbic" in s) && s.step === 3 && s.nps[0].codes[0].rest === 4);
  const app = await p.evaluate(() => APP_VERSION);
  out.dDispositivoYVersion = !!(posts[0] && posts[0].p_dispositivo && posts[0].p_app === app && /^\d{4}-\d\d-\d\dT/.test(posts[0].p_ts_cliente));

  // (B) muchos cambios → una copia a los 8 s
  posts.length = 0;
  await p.evaluate(() => { for (let i = 0; i < 6; i++) { _comp.nps[0].codes[0].cur = i; _compPersist(); } });
  await w(2500);
  out.bNadaAntesDe8s = posts.length === 0;
  await w(6500);
  out.bUnaSolaA8s = posts.length === 1 && posts[0].p_snapshot.nps[0].codes[0].cur === 5;

  // (C) pausar: sale ya y no queda otra programada
  posts.length = 0;
  await p.evaluate(() => { _comp.nps[0].codes[0].cur = 1; _compPersist(); compPausar(); });
  await w(800);
  out.cPausaSaleYa = posts.length === 1 && posts[0].p_estado === "en_curso" && posts[0].p_snapshot.nps[0].codes[0].cur === 1;
  await w(8500);
  out.cNoSaleOtraDespues = posts.length === 1;

  // (E) legajo de prueba
  await armar("1"); posts.length = 0;
  await p.evaluate(() => { const n = _comp.nps[0]; _compAddLio(n, { items: [{ cod: "501", qty: 1 }], cajas: 1, suelta: true }); _compPersist(); _armAvCerrar(_comp, "terminado", true); });
  await w(2200);
  out.ePruebaNoManda = posts.length === 0;

  // (F) sin red
  await armar("104"); posts.length = 0; modo = "abort";
  const f1 = await p.evaluate(() => { try { _compAddLio(_comp.nps[0], { items: [{ cod: "501", qty: 1 }], cajas: 1, suelta: true }); return _comp.nps[0].liosArr.length === 1; } catch (e) { return false; } });
  await w(2200);
  modo = "ok";
  await p.evaluate(() => { _compAddLio(_comp.nps[0], { items: [{ cod: "501", qty: 1 }], cajas: 1, suelta: true }); });
  await w(2200);
  out.fSinRedSigue = f1;
  out.fSaleConElProximo = posts.length >= 1 && posts[posts.length - 1].p_snapshot.nps[0].liosArr.length === 2;

  // (G) candados sobre el código: terminar y soltar cierran la copia
  const src = fs.readFileSync(path.join(root, "index.html"), "latin1");
  const iTerm = src.indexOf('_armAvCerrar(_comp, "terminado", true)');
  const iClear = src.indexOf("_compClearPersist(tanda);   // v4.04: completado");
  out.gTerminarCierraAntesDeBorrar = iTerm > 0 && iClear > iTerm && iClear - iTerm < 400;
  out.gSoltarAnula = src.indexOf('_armAvCerrar({ tanda: tanda, legajo: legajo }, "anulado", false)') > 0;

  let ok = true;
  for (const k of Object.keys(out)) { console.log((out[k] ? "OK   " : "FALLA") + " " + k); if (!out[k]) ok = false; }
  if (errs.length) { console.log("pageerror:", errs.slice(0, 3)); ok = false; }
  await b.close();
  console.log(ok ? "arm-avance-servidor: OK" : "arm-avance-servidor: FALLA");
  process.exit(ok ? 0 : 1);
})();
