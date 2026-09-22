/* Regresión v20.92 — EL RETENIDO NO VUELVE A UNA TANDA DE OTRO CAMIÓN.

   Problema 489. `gv_ppp_web_retenido` decidía si un pedido vuelve a su tanda previa mirando
   sólo el ESTADO de esa tanda (v20.56) y el código reservado (v20.60). No miraba la zona.

   Caso LK 1448 (Silvano, 4282): sus NP son Zona 6 - GBA Norte (camión GBA Norte) y su tanda
   previa D69H es Zona 2 - CABA Centro (camión Capital). El chip decía *"esa tanda sale el
   23/09 y no se empezó: vuelve ahí"* — seguirlo parte la tanda en dos camiones y pone
   `gv_ppp_tanda_camion_mezclado` en rojo (regla de Luis, v18.87).

   Chequea, con la red simulada (sin tocar Supabase):
   - el chip DICE que la tanda es de otro camión, y nombra los dos;
   - dice que NO vuelve ahí, que va a una tanda nueva;
   - y el candado invertido: no puede volver a decir «vuelve ahí» para ese caso.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}

/* lo que devuelve gv_ppp_avisos_detalle con el arreglo puesto */
const DET = [
  { tipo: "retenido_sin_fecha", orden: 5, titulo: "Pedidos sacados a mano, esperando fecha",
    fecha: "2026-09-21", que: "LK pedido 1448",
    detalle: "3 NP · salió de la tanda D69H, E52A · ⚠ esa tanda va en el camión Capital y " +
             "este pedido en el de GBA Norte: NO vuelve ahí, va a una tanda nueva · " +
             "lo sacó loekemeyer.n8n@gmail.com, Luis (claude-remote)",
    accion: "Está en A Programar esperando día. Si su tanda ya avanzó o es de otro camión, " +
            "va a una tanda nueva y se pickea normal." },
];

(async () => {
  const root = path.join(__dirname, "..");
  const fallos = [];

  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async (det) => {
    window.fetch = async function () {
      return { ok: true, status: 200, json: async () => det };
    };
    const sup = document.getElementById("supervisorPanel");
    if (sup) sup.classList.remove("hidden");
    await pppAvisosAbrir();
    const ov = document.getElementById("pppAvisosPop");
    return { html: ov ? ov.innerHTML : "" };
  }, DET);
  await b.close();
  if (errs.length) fallos.push("errores de página: " + errs.join(" | "));

  const h = r.html || "";
  if (!/esa tanda va en el camión/.test(h))
    fallos.push("el chip no avisa que la tanda previa es de otro camión");
  if (!/Capital/.test(h) || !/GBA Norte/.test(h))
    fallos.push("no nombra los dos camiones (el de la tanda y el del pedido)");
  if (!/NO vuelve ahí/.test(h))
    fallos.push("no dice que NO vuelve a esa tanda");
  if (!/tanda nueva/.test(h))
    fallos.push("no dice a dónde va (tanda nueva)");
  // candado invertido: para este caso no puede aparecer el consejo viejo
  if (/y no se empezó: vuelve ahí/.test(h))
    fallos.push("volvió el consejo viejo «vuelve ahí» — partiría la tanda en dos camiones");

  if (fallos.length) { console.error("apr-retenido-camion FALLA:\n - " + fallos.join("\n - ")); process.exit(1); }
  console.log("apr-retenido-camion OK — el chip dice que la tanda es de otro camión y que va a una tanda nueva.");
})();
