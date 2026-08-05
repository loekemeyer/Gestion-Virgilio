/* Test de regresión (v7.63) — 📲 Enviar OC por WhatsApp al tallerista.
   El teléfono sale de la tabla Talleristas_Contacto (cargada en _oc.tels) vía ocTelDe:
   respeta duales y el caso "no enviar por WhatsApp" (sin tel → no se puede enviar). El
   botón 📲 WhatsApp aparece en el detalle de la OC. No dispara window.open ni el
   portapapeles (eso es interacción del navegador). Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado (ver tests/smoke.cjs)."); process.exit(2); }
}

(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = {};
    // _oc.tels = lo que carga ocLoadTels desde Talleristas_Contacto (sólo los que TIENEN tel)
    _oc = {
      rows: [{ id: 1, proveedor: "Lopez Jose", fecha: "2026-08-05", rubro: "Art Term", codigo: "107", descripcion: "X", cantidad: 5, cantidad_recibida: 0, unidad: "Cajas", estado: "pendiente" }],
      tels: [
        { keys: _ocProvKeys("Lopez Jose"), tel: "+5491123510085" },
        { keys: _ocProvKeys("Martin C"), tel: "+5491162498171" },
        { keys: _ocProvKeys("Garcia / Lucho"), tel: "+5491172228961" }   // dual
      ]
    };
    // ocTelDe encuentra el teléfono por nombre normalizado
    out.lopez = ocTelDe("Lopez Jose") === "+5491123510085";
    out.martinC = ocTelDe("Martin C") === "+5491162498171";
    out.dual = ocTelDe("Garcia") === "+5491172228961" || ocTelDe("Lucho") === "+5491172228961";  // dual matchea cualquiera
    // el que no está en la tabla (o marcado "no enviar") → sin tel
    out.sinTel = ocTelDe("Oscar") === "";
    // dígitos para wa.me (lo que hace el botón)
    out.digits = "+5491123510085".replace(/\D/g, "") === "5491123510085";
    out.fns = typeof ocWhatsappTallerista === "function" && typeof _ocPngBlob === "function";
    // el botón 📲 WhatsApp aparece en el detalle de una OC
    _oc.openKey = _ocGroupKey(_oc.rows[0]);
    _oc.view = "detail";
    out.boton = ocBodyDetail().indexOf("📲 WhatsApp") >= 0;
    return out;
  });

  await b.close();
  const fail = [];
  Object.keys(r).forEach(function (k) { if (r[k] !== true) fail.push(k + "=" + JSON.stringify(r[k])); });
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  if (fail.length) { console.error("ocg-wa: FALLÓ →", fail.join(", ")); process.exit(1); }
  console.log("ocg-wa: OK — WhatsApp al tallerista (tel desde Talleristas_Contacto vía ocTelDe + botón)");
  process.exit(0);
})();
