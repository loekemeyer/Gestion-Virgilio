/* Regresión v21.21 — UN ARMADO ANULADO NO ES UN ARMADO.

   POR QUÉ. Para deshacer un armado NO se borra la fila de `Entregas_Virgilio`: se le pega
   `-X` a la `tanda` (E29D → E29D-X) y queda su fila en `GV_Tanda_Anulada`. Es el mismo
   criterio que los eventos (TAP→TAPX): borrar la fila libera el `client_id` y la cola
   offline del celular resucita el armado.

   `_compNpsYaArmadas` —el candado anti doble-armado POR NP— leía por NP **sin mirar la
   tanda**, así que una fila anulada trababa igual que una viva, y para siempre.

   Caso E29D (22/09, Luis): LK 0034 se DESARMÓ el 15/09 (17 cajas volvieron: 13 a góndola,
   4 a excedente) y se anuló el TAP. El 22/09 el operario, con el pallet a medio preparar,
   se comió «Ya está armado el pedido NP LK 0034, LK 0035 (en otra tanda)». Lo peor: ese
   mismo cartel le dice «avisá para darlo de baja a mano primero», que era EXACTAMENTE lo
   que ya se había hecho — el candado ignoraba su propia salida.

   `_compTandaYaArmada` (el candado por TANDA) no tiene el problema: filtra `tanda=eq.<T>`
   y `E29D-X` no matchea. Por eso el síntoma aparecía sólo en el de por NP.

   ⚠ El candado sigue frenando lo VIVO: una fila con tanda sin `-X` bloquea igual, que es
   para lo que existe (98532/98533, 98490, 98583: 57 cajas contadas por dos).
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
    const out = { urls: [] };
    function J(data) {
      return Promise.resolve({ ok: true, status: 200,
        headers: { get: function () { return null; } }, json: function () { return Promise.resolve(data); } });
    }
    function stub(rows) {
      window.fetch = function (url) { out.urls.push(String(url)); return J(rows); };
    }

    // (1) el caso real de Luis: las 19 líneas de LK 0034 / LK 0035 están en E29D-X (anuladas)
    stub([{ np: "LK 0034", tanda: "E29D-X" }, { np: "LK 0035", tanda: "E29D-X" }]);
    out.anuladas = await _compNpsYaArmadas(["LK 0034", "LK 0035"]);

    // (2) lo VIVO sigue trabando
    stub([{ np: "LK 0034", tanda: "E29D" }]);
    out.viva = await _compNpsYaArmadas(["LK 0034", "LK 0035"]);

    // (3) mezcla: una anulada y una viva → sólo traba la viva
    stub([{ np: "LK 0034", tanda: "E29D-X" }, { np: "LK 0035", tanda: "E48D" }]);
    out.mezcla = await _compNpsYaArmadas(["LK 0034", "LK 0035"]);

    // (4) tanda nula o vacía NO cuenta como anulada (se traba, que es lo conservador)
    stub([{ np: "LK 0034", tanda: null }, { np: "LK 0035", tanda: "" }]);
    out.sinTanda = await _compNpsYaArmadas(["LK 0034", "LK 0035"]);

    // (5) la convención, directa
    out.helper = {
      x:   _entregaAnulada({ tanda: "E29D-X" }),
      x2:  _entregaAnulada({ tanda: "D69H-X" }),
      xn:  _entregaAnulada({ tanda: "E29D-X2" }),   // segunda anulación
      pad: _entregaAnulada({ tanda: " E29D-X " }),
      viva: _entregaAnulada({ tanda: "E29D" }),
      nula: _entregaAnulada({ tanda: null }),
      // ⚠ no puede comerse una tanda real terminada en X sin guion
      falso: _entregaAnulada({ tanda: "E29X" })
    };
    return out;
  });

  await b.close();
  const fails = [];
  const eq = (a, b_) => JSON.stringify(a) === JSON.stringify(b_);

  if (!eq(r.anuladas, [])) fails.push("una Entrega ANULADA (E29D-X) sigue trabando el armado: " + JSON.stringify(r.anuladas));
  if (!eq(r.viva, ["LK 0034"])) fails.push("una Entrega VIVA dejó de trabar: " + JSON.stringify(r.viva));
  if (!eq(r.mezcla, ["LK 0035"])) fails.push("mezcla anulada+viva mal resuelta: " + JSON.stringify(r.mezcla));
  if (!eq(r.sinTanda, ["LK 0034", "LK 0035"])) fails.push("una Entrega sin tanda tiene que trabar (conservador): " + JSON.stringify(r.sinTanda));

  const h = r.helper || {};
  if (h.x !== true || h.x2 !== true || h.xn !== true || h.pad !== true) fails.push("_entregaAnulada no reconoce el sufijo -X: " + JSON.stringify(h));
  if (h.viva !== false || h.nula !== false || h.falso !== false) fails.push("_entregaAnulada marca de más: " + JSON.stringify(h));

  // la lectura tiene que PEDIR la tanda, o no hay con qué filtrar
  const pidioTanda = (r.urls || []).some((u) => /select=np%2Ctanda|select=np,tanda/.test(u));
  if (!pidioTanda) fails.push("la consulta no pide la columna `tanda`: " + JSON.stringify(r.urls && r.urls[0]));

  if (errs.length) fails.push("errores de página: " + errs.join(" | "));
  if (fails.length) { console.error("comp-armado-anulado: FALLA\n  - " + fails.join("\n  - ")); process.exit(1); }
  console.log("comp-armado-anulado: OK — lo anulado no traba, lo vivo sí (4 casos + la convención).");
})();
