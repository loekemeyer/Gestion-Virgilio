/* Regresión v17.85 — el armado viaja TAMBIÉN por la cola de eventos (opcion 'ENT').

   POR QUÉ. El 14/09 el POST a Entregas_Virgilio murió con 42501 y el armado de D67M / E01J
   quedó SÓLO en el localStorage del celular del armador, que se fue a su casa: el facturador
   sin subtotal y nada que el servidor pudiera hacer. El TAP y el TAL del mismo armado SÍ
   habían llegado, porque van por la cola de eventos. Este evento pone ahí el detalle EXACTO
   de lo que va a Entregas_Virgilio, así el servidor lo puede rehacer solo
   (gv_entregas_reconstruir) sin depender de ese dispositivo.

   Se midió por qué no alcanzaba deducirlo de los eventos que ya existían: sobre 1.280 filas
   reales, el TAL + los PKC acertaban 1.159, se abstenían en 114 y ERRABAN 6 — el TAL cuenta
   LÍOS y no cajas, y el faltante que el armador carga a mano en el Paso 2 no dejaba ningún
   evento. Por eso el dato se EMITE en vez de adivinarse.

   Chequea:
   - el texto sale como  NP|TANDA|cod:ped:ent:falto,…|ENT  y respeta UN ÍTEM POR RENGLÓN
     (un código que viene en dos renglones son dos ítems, no uno sumado);
   - una NP por evento;
   - el operador de PRUEBA (legajo 0/1) NO emite nada, igual que _compSaveEntregas;
   - el evento se encola con enqueueReport (la cola de IndexedDB), no con un fetch suelto.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    let enq = [];
    window.enqueueReport = function (pl) { enq.push(pl); };
    window.trySendOneReport = undefined;
    window.updatePendingIndicator = function () {};

    // dos NP, y en la primera el MISMO código en dos renglones (3 y 2 cajas)
    const rows = [
      { np: "98690", cod_art: "501", cajas_pedidas: 3, cajas_entregadas: 3, cajas_falto: 0, tanda: "D67M" },
      { np: "98690", cod_art: "501", cajas_pedidas: 2, cajas_entregadas: 0, cajas_falto: 2, tanda: "D67M" },
      { np: "98690", cod_art: "437E LK", cajas_pedidas: 1, cajas_entregadas: 1, cajas_falto: 0, tanda: "D67M" },
      { np: "98691", cod_art: "510", cajas_pedidas: 2, cajas_entregadas: 2, cajas_falto: 0, tanda: "D67M" }
    ];

    // --- operador de PRUEBA → no emite nada ---
    window.esOperadorPrueba = function () { return true; };
    enq = []; _compSendEntregasEvento("0", "D67M", rows);
    out.prueba_noEmite = enq.length === 0;

    // --- operador REAL ---
    window.esOperadorPrueba = function () { return false; };
    enq = []; _compSendEntregasEvento("237", "D67M", rows);
    const ents = enq.filter(function (x) { return x.opcion === "ENT"; });
    out.unEventoPorNp = ents.length === 2;
    const t90 = (ents.find(function (x) { return x.texto.indexOf("98690|") === 0; }) || {}).texto || "";
    out.texto90 = t90;
    out.formato = t90 === "98690|D67M|501:3:3:0,501:2:0:2,437E LK:1:1:0|ENT";
    // el código repetido va como DOS ítems, no sumado en uno
    out.dosRenglones = (t90.split("|")[2] || "").split(",").filter(function (s) { return s.indexOf("501:") === 0; }).length === 2;
    out.enCola = ents.every(function (x) { return x.legajo === "237" && x.descripcion === "Entregas por NP (TAP)"; });
    return out;
  });
  const pass = r.prueba_noEmite === true && r.unEventoPorNp === true && r.formato === true &&
               r.dosRenglones === true && r.enCola === true && errs.length === 0;
  console.log("comp-ent-evento:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
