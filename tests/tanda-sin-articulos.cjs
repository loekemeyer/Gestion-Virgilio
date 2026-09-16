/* Regresión v18.49 — no se arranca una tanda que llegó SIN artículos.
   Caso D71A (14/09): la NP 97889 (Matiz SA, 9,25 m³, entrega 16/09) entró a la PPP con su
   cabecera pero sin un solo renglón — se cargó en ISIS el 23/06 y la importación del detalle
   arranca el 01/07. El operario le daba EP, recién ahí veía "no encontré artículos", y el EP
   ya había salido: la tanda quedaba en curso para siempre y trabada para todos por la
   exclusividad v5.74.
   Chequea que el EP y el AP se frenen ANTES de emitir, que el aviso diga la NP, y que una
   tanda normal no se vea afectada. Y que falle ABIERTO: si no se puede verificar, no bloquea.
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
  /* v18.72 — este test ejecuta `send()`, que reserva la tanda contra Supabase. Sin este corte
     la corrida ESCRIBE EN LA BASE REAL: el 15/09 dejó dos locks del legajo de prueba 999
     (C72F/picking y D11X/armado) que, con el lock sin TTL de la v18.65, bloqueaban esas dos
     tandas para los operarios de verdad. Antes se limpiaban solos a las 10 h y por eso nadie
     lo había notado. Abortar la red deja a `tandaReservar` fallando ABIERTO, que es su
     comportamiento sin conexión y no cambia lo que este test mide. */
  await p.route("**/*.supabase.co/**", (r) => r.abort());
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    const leg = "277";
    legajoInput.value = leg;
    let avisos = [];
    window.alert = function (m) { avisos.push(String(m || "")); };
    window.confirm = function () { return true; };
    window.maybeRegisterLateArrival = async function () {};
    window.trySendOneReport = async function () { return { ok: true }; };
    window.getActivityStatus = async function () { return null; };
    window.tandaReservar = async function () { return null; };
    window.getEmpleadosNombres = async function () { return new Map(); };
    window.showPickingList = function () {};
    window.showCompletarWizard = function () {};
    window.askPickUbicacion = async function () { return "mesa"; };
    const enq = [];
    window.enqueueReport = function (pl) { enq.push(pl && pl.opcion); };
    const limpiar = function () {
      const st = getLegajoState(leg);
      st.picking = { active:false, value:"", ts_inicio:null };
      st.armado  = { active:false, value:"", ts_inicio:null };
      setLegajoState(leg, st);
    };

    // PPP: D71A tiene la NP 97889; E03F tiene LK 0043. La base de picking sólo tiene la de E03F.
    window.fetchMonitorSheet = async function () {
      return new Map([
        ["D71A", { tanda:"D71A", pedidos:[{ np:"97889", razonSocial:"Matiz SA" }] }],
        ["E03F", { tanda:"E03F", pedidos:[{ np:"LK 0043", razonSocial:"El Gran Bazar" }] }]
      ]);
    };
    window.fetchPickingBase = async function () {
      return new Map([["LK 0043", [{ art:"505", cajas:7 }]]]);
    };

    // ---- 1) EP sobre la tanda sin artículos → NO sale el evento ----
    limpiar(); enq.length = 0; avisos = [];
    selectOption("EP"); textInput.value = "D71A";
    await send();
    out.epNoSale     = enq.indexOf("EP") < 0;
    out.epAvisa      = avisos.some(function (m) { return /NO tiene los art/i.test(m); });
    out.epDiceLaNp   = avisos.some(function (m) { return m.indexOf("97889") >= 0; });
    out.epNoAbreNada = !(getLegajoState(leg).picking || {}).active;

    // ---- 2) AP sobre la misma → tampoco (sin renglones no hay asistente, y sin asistente no hay TAP) ----
    limpiar(); enq.length = 0; avisos = [];
    selectOption("AP"); textInput.value = "D71A";
    await send();
    out.apNoSale = enq.indexOf("AP") < 0;
    out.apAvisa  = avisos.some(function (m) { return /NO tiene los art/i.test(m); });

    // ---- 3) control: la tanda que SÍ tiene artículos arranca normal ----
    limpiar(); enq.length = 0; avisos = [];
    selectOption("EP"); textInput.value = "E03F";
    await send();
    out.normalArranca = enq.indexOf("EP") >= 0;
    out.normalSinAviso = !avisos.some(function (m) { return /NO tiene los art/i.test(m); });

    // ---- 4) falla ABIERTO: si no se puede verificar, no bloquea ----
    window.fetchPickingBase = async function () { throw new Error("sin red"); };
    limpiar(); enq.length = 0;
    selectOption("EP"); textInput.value = "D71A";
    await send();
    out.sinRedNoBloquea = enq.indexOf("EP") >= 0;
    return out;
  });
  const pass = Object.keys(r).every(k => r[k]) && errs.length === 0;
  console.log("tanda-sin-articulos:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
