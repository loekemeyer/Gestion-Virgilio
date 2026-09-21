/* Regresión v20.90 — UN ARMADO ANTERIOR AL PICKING NO TRABA EL ARMADO DE VERDAD.

   POR QUÉ. El candado anti doble-armado (v5.72) miraba SOLO si la tanda tenía filas en
   `Entregas_Virgilio`, y con eso alcanzaba para frenar a un operario con el pallet delante.

   Caso E12L / LK 0043 (El Gran Bazar): el 17/09 quedó registrado un armado SIN picking
   —7 líneas, 15 cajas, CERO movimientos de stock ese día—. El 21/09 Fabi pickeó de verdad
   y a las 15:38 Juan dio AP y se comió «La tanda ya fue armada»: cuatro días después, con
   la mercadería en la mano y sin ninguna salida.

   LA REGLA: un armado ANTERIOR al último picking de la tanda es de otro ciclo y NO traba.
   Si alguien arma dos veces en el MISMO ciclo, sus Entregas son POSTERIORES al picking y el
   candado sigue frenando igual — que es para lo que existe (NP 98114).

   Y ante cualquier duda, TRABA: el candado es lo conservador. Sin picking medible, sin
   fecha de armado, o con el endpoint de eventos caído, devuelve true.
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
    function J(data, ok) {
      return Promise.resolve({ ok: ok !== false, status: ok === false ? 500 : 200,
        headers: { get: function () { return null; } }, json: function () { return Promise.resolve(data); } });
    }
    // arm = fecha del armado (Entregas) · pk = fecha del último TP/PKC · pkOk = el endpoint responde
    function stub(arm, pk, pkOk) {
      window.fetch = function (url) {
        url = String(url);
        if (url.indexOf("Entregas_Virgilio") >= 0) return J(arm === null ? [] : [{ creado: arm }]);
        if (url.indexOf("opcion=in.(TP,PKC)") >= 0 || url.indexOf("opcion=in.%28TP%2CPKC%29") >= 0)
          return J(pk === null ? [] : [{ ts_cliente: pk }], pkOk !== false);
        return J([]);
      };
    }
    const D17 = "2026-09-17T19:07:00Z", D21 = "2026-09-21T18:30:00Z", D21b = "2026-09-21T18:38:00Z";

    // 1) el caso E12L: armado del 17 · picking del 21 → NO traba
    stub(D17, D21, true);   out.armadoViejo = await _compTandaYaArmada("E12L");        // false

    // 2) doble armado en el MISMO ciclo: picking del 21 · armado posterior → SÍ traba
    stub(D21b, D21, true);  out.dobleMismoCiclo = await _compTandaYaArmada("E12L");    // true

    // 3) sin picking medible → traba (conservador)
    stub(D17, null, true);  out.sinPicking = await _compTandaYaArmada("E12L");         // true

    // 4) el endpoint de eventos caído → traba
    stub(D17, D21, false);  out.eventosCaidos = await _compTandaYaArmada("E12L");      // true

    // 5) armado sin fecha (fila vieja) → traba
    stub(null, D21, true);  out.sinArmado = await _compTandaYaArmada("E12L");          // false: no hay armado
    window.fetch = function (url) {
      url = String(url);
      if (String(url).indexOf("Entregas_Virgilio") >= 0) return J([{ id: 1 }]);   // sin `creado`
      return J([]);
    };
    out.armadoSinFecha = await _compTandaYaArmada("E12L");                             // true

    // 6) tanda nueva (sin Entregas) → false, y vacío → false
    stub(null, null, true);
    out.nueva = await _compTandaYaArmada("ZZ99");                                      // false
    out.vacio = await _compTandaYaArmada("");                                          // false

    // 7) el helper pide la fecha, no sólo el id
    const src = _compTandaYaArmada.toString();
    out.pideCreado = /select=creado/.test(src) && /order=creado\.desc/.test(src);
    out.miraPicking = /TP,PKC/.test(src);
    return out;
  });

  const pass =
    r.armadoViejo === false && r.dobleMismoCiclo === true && r.sinPicking === true &&
    r.eventosCaidos === true && r.sinArmado === false && r.armadoSinFecha === true &&
    r.nueva === false && r.vacio === false && r.pideCreado === true && r.miraPicking === true &&
    errs.length === 0;

  console.log("comp-armado-viejo-no-traba:", JSON.stringify(r),
              "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
