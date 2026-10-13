/* Regresion v30.06 (Luis, 13/10/2026) — "que no se pierda dios mio, como que se pierde?".

   La recepcion de insumos PIDE el remito (o la factura) y despues no quedaba en ninguna parte:
   `_insDocState` se usaba para GP2 y `insDocCancel` lo ponia en null al cerrar el modal, asi que
   el movimiento no lo llevaba... y a GP2 tampoco le llegaba (insEnviar lo leia de ese mismo
   objeto, que para entonces ya era null: las OC de bolsas se recibian con el remito vacio).

   Hoy el papel viaja en la columna `gv_doc` de CADA movimiento de la recepcion (es un papel) y
   el remito le llega a GP2. Mide:
     (a) el POST de los movimientos lleva gv_doc con el remito y su fecha, en TODAS las filas
     (b) una recepcion SIN papel no escribe gv_doc (no manda un jsonb de nulls)
     (c) anular la recepcion no deja el papel colgado para la siguiente
   Sin red (fetch mockeado). Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}; const movs = [];
    const J = function (data) { return Promise.resolve({ ok: true, status: 200, headers: { get: function () { return null; } }, json: function () { return Promise.resolve(data); } }); };
    const CAT = [
      { cod: "N°19", nombre: "13,6 x 0,8 · Fleje N° 19", sector: null, categoria: "fleje", ubicacion: "R6At" },
      { cod: "N°13", nombre: "84 x 1,75 · Fleje N° 13", sector: null, categoria: "fleje", ubicacion: "R1Ad" }
    ];
    window.fetch = function (url, opt) {
      url = String(url);
      if (opt && String(opt.method || "").toUpperCase() === "POST" && /\/Movimientos_Stock/.test(url)) {
        try { JSON.parse(opt.body).forEach(function (x) { movs.push(x); }); } catch (_e) {}
        return J([]);
      }
      if (url.indexOf("Insumos_Categorias") >= 0) return J([{ clave: "fleje", nombre: "Flejes y alambres", emoji: "🧵", unidades: ["Kg"], orden: 1 }]);
      if (url.indexOf("Insumos_Unidades") >= 0) return J([{ nombre: "Kg", orden: 1 }]);
      if (url.indexOf("vista_insumos") >= 0 || url.indexOf("/Insumos") >= 0) return J(CAT);
      return J([]);
    };
    // el alta de la tarea y el evento del toggle no son lo que se mide acá
    window.send = function () {}; window.gvModTareaAbrir = function () {};

    const cargarYMandar = async function (cods) {
      await showInsumoModal("RI", "104");
      insSetCat("fleje");
      cods.forEach(function (c) {
        const it = _ins.items.filter(function (x) { return x.cod === c; })[0];
        it.qty = 10; it.unidad = "Kg"; it.marca = "Mixto";
      });
      const _al = window.alert; window.alert = function () {};
      await insConfirmar();
      window.alert = _al;
    };

    // (a) con remito: el papel va en TODAS las filas
    window._insUbicacion = "Cervantes";
    insDocCancel();                      // arranca limpio
    window._insDocState = { tipoDoc: "remito", nroRemito: "", nroFactura: "", fechaRemito: "", fechaFactura: "", proveedor: "Cervantes" };
    const ov = document.createElement("div"); ov.id = "insDocModal"; document.body.appendChild(ov);
    ov.innerHTML = '<input id="insDocNroRemito" value="38880"><input id="insDocFechaRemito" value="2026-10-13">';
    window._insArrancarToggle = function () {};   // no abrir el toggle: la lista ya se maneja acá
    insDocOk("RI");
    out.guardoElPapel = !!(window._insDoc && window._insDoc.remito === "38880");
    await cargarYMandar(["N°19", "N°13"]);
    out.nMovs = movs.length;
    out.todasConRemito = movs.length === 2 && movs.every(function (m) { return m.gv_doc && m.gv_doc.remito === "38880"; });
    out.conFecha = movs.every(function (m) { return m.gv_doc && m.gv_doc.fecha_remito === "2026-10-13"; });
    out.conTipo = movs.every(function (m) { return m.gv_doc && m.gv_doc.tipo === "remito"; });
    out.limpioDespues = !window._insDoc;          // no se arrastra a la próxima

    // (b) sin papel: nada de gv_doc
    movs.length = 0;
    await cargarYMandar(["N°19"]);
    out.sinPapelSinDoc = movs.length === 1 && !movs[0].gv_doc;

    // (c) anular no deja el papel colgado
    window._insDoc = { tipo: "remito", remito: "99999" };
    await showInsumoModal("RI", "104");
    const _cf = window.confirm; window.confirm = function () { return true; };
    try { await insAnular(); } catch (_e) {}
    window.confirm = _cf;
    out.anularLimpia = !window._insDoc;
    return out;
  });

  const malas = Object.keys(r).filter((k) => r[k] !== true && k !== "nMovs");
  const pass = malas.length === 0 && r.nMovs === 2 && errs.length === 0;
  console.log(pass ? "OK ins-remito-guardado" : "FALLA ins-remito-guardado");
  if (!pass) { console.log(JSON.stringify(r, null, 2)); if (errs.length) console.log("pageerror:", errs.join(" | ")); }
  await b.close(); process.exit(pass ? 0 : 1);
})();
