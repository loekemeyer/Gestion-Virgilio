/* v31.01 (Luis, 15/10/2026) — Terminar Día con tareas abiertas.
   Luis: «cuando terminan el día con tareas abiertas, tiene que avisar que se van a cerrar y cómo. Cuando cierran un armado o
   picking en curso, debería simplemente decirles que queda registrado lo que hicieron hasta ahí y se puede retomar por ellos
   (o por otra persona) al día siguiente».
   (A) el cuadro: picking en curso sin pregunta (sin radios) y con el aviso «queda registrado … retomar vos u otra persona»;
       CR, Bajar de racks, Mover racks y el Guardado aparecen en «Se cierran ahora».
   (B) al confirmar: el picking sigue (st.picking activo + continuar), CR se cierra (evento CR con ts_inicio), Bajar de
       racks manda RKB «sin bajar» con la hora de apertura, Mover racks manda MDT, el guardado queda cerrado; todo ANTES
       del FJ. No sale TP.
   (C) una tarea de módulo vencida (> 12 h) se limpia sin evento.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/*.supabase.co/**", (r) => r.abort());
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const w = (ms) => new Promise((res) => setTimeout(res, ms));
    window.alert = function () {}; window.confirm = function () { return true; };
    window.trySendOneReport = async function () { return { ok: false }; };   // todo queda en la cola para leerlo
    window.flushQueue = async function () {};
    window.terminarDiaDrenarCola = async function () {};
    window.bulkSendDayReplay = function () {};
    const LEG = "94", H = 3600000, now = Date.now();
    localStorage.clear(); legajoInput.value = LEG;
    goToOptions(); await w(30);
    const st = getLegajoState(LEG);
    st.picking = { active: true, value: "F21C", ts_inicio: new Date(now - 2 * H).toISOString() };
    st.toggles = Object.assign(st.toggles || {}, { CR: new Date(now - H).toISOString() });
    st.racks = { active: true, ts: now - 40 * 60000 };
    st.tmov = { active: true, ts: now - 20 * 60000 };
    st.mg = { active: true, ts: now - 10 * 60000 };
    st.tcp = { active: true, ts: now - 30 * H };   // vencida
    setLegajoState(LEG, st);

    // (A)
    terminarDia(); await w(30);
    const box = document.getElementById("terminarDiaContent");
    const txt = box.innerText;
    out.aSinRadios = !box.querySelector('input[type="radio"]');
    out.aAvisoTanda = /Queda registrado lo que pickeaste hasta acá/.test(txt) && /retomar vos u otra persona/.test(txt) && /F21C/.test(txt);
    const cierran = (document.getElementById("tdSeCierran") || {}).innerText || "";
    out.aListaCierran = ["CR", "Bajar de racks", "Mover racks", "Guardado a Góndola"].every((x) => cierran.includes(x));
    out.aVencidaNoSeLista = !cierran.includes("Completar Pedido");

    // (B)
    await confirmarTerminarDia(); await w(50);
    const q = readQueue().map((x) => x.payload || x);
    const ops = q.map((x) => x.opcion);
    const s2 = getLegajoState(LEG);
    out.bPickingSigue = !!(s2.picking && s2.picking.active) && !!(s2.continuar && s2.continuar.Picking);
    out.bSinTP = !ops.includes("TP");
    const cr = q.find((x) => x.opcion === "CR");
    out.bCR = !!cr && !!cr.ts_inicio_iso && !(s2.toggles && s2.toggles.CR);
    const rkb = q.find((x) => x.opcion === "RKB");
    out.bRKB = !!rkb && rkb.texto === "sin bajar" && Math.abs(Date.parse(rkb.ts_inicio_iso) - (now - 40 * 60000)) < 5;
    const mdt = q.find((x) => x.opcion === "MDT");
    out.bMDT = !!mdt && mdt.texto === "MOV" && !!mdt.ts_inicio_iso;
    out.bModulosCerrados = !(s2.racks && s2.racks.active) && !(s2.tmov && s2.tmov.active) && !(s2.mg && s2.mg.active);
    const iFJ = ops.indexOf("FJ");
    out.bAntesDelFJ = iFJ > -1 && ["CR", "RKB", "MDT"].every((o) => ops.indexOf(o) > -1 && ops.indexOf(o) < iFJ);
    // (C)
    out.cVencidaLimpia = !(s2.tcp && s2.tcp.active) && !q.some((x) => x.opcion === "MDT" && x.texto === "CP");
    return out;
  });

  let ok = true;
  for (const k of Object.keys(r)) if (r[k] !== true) { ok = false; console.log("  ✗ " + k); }
  if (errs.length) { ok = false; console.log("  pageerrors: " + errs.join(" | ")); }
  console.log("td-cierra-tareas: " + JSON.stringify(r) + " · pageerrors: " + (errs.length ? errs.length : "none") + " · " + (ok ? "✓ OK" : "✗ FALLA"));
  await b.close();
  process.exit(ok ? 0 : 1);
})();
