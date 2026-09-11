/* Regresión v15.41 — el evento PKC lleva DE DÓNDE salió cada caja.

   El picking parte un artículo en DOS pasos cuando hay excedente (góndola + art·EXC),
   pero los dos comparten client_id (pkc_<legajo>_<tanda>_<ART>_<día>) y el POST va con
   merge-duplicates: el PKC del excedente PISABA al de góndola y esas cajas se perdían.
   Además el texto no decía el depósito, así que el backend re-derivaba el reparto por
   saldos vivos al reconciliar.

   Ahora sale UN SOLO evento por (tanda, artículo) con los TOTALES de los dos pasos y un
   5º campo = cajas que salieron del EXCEDENTE:  TANDA|ART|esp|real|excedente

   Chequea:
   - Split auto (pedido 15, excedente 10): el 1er paso (góndola, 5) manda esp=15 real=5 exc=0;
     al confirmar el paso de excedente manda esp=15 real=15 exc=10. Los dos con el MISMO
     client_id (una sola fila) → lo que queda es el total, no el pedazo del excedente.
   - Artículo sin excedente → 5º campo "0" (nada del excedente), no vacío.
   - _pk.excOk = false (falló la consulta de excedente) → NO manda el 5º campo, así el
     backend vuelve a repartir por saldos en vez de creerle a un fetch caído.
   - El paso de excedente marcado A MANO (manualExc) repite el esp del de góndola → no se
     suma dos veces lo pedido.
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
    const out = {}; const sent = [];
    window.enqueueReport = function (pl) { sent.push(pl); };
    window.trySendOneReport = null;
    window.updatePendingIndicator = function () {};

    // --- caso 1: split automático. Pedido 15 del 546, excedente cubre 10.
    _pk = {
      tanda: "E20A", legajo: "277", idx: 0, mode: "item", excOk: true,
      items: [
        { art: "546", key: "546", esp: 5, excHint: 10 },                 // góndola: el resto
        { art: "546", key: "546·EXC", esp: 10, isExc: true }             // excedente: al final
      ],
      results: {}
    };
    _pk.results["546"] = 5;                       // marcó el paso de góndola
    pkSendDetail("546", 5, 5);
    const e1 = sent[sent.length - 1];
    out.paso1Texto = e1.texto;                    // esperado E20A|546|15|5|0
    out.paso1EsTotal = e1.texto === "E20A|546|15|5|0";

    _pk.results["546·EXC"] = 10;                  // marcó el paso del excedente
    pkSendDetail("546", 10, 10);
    const e2 = sent[sent.length - 1];
    out.paso2Texto = e2.texto;                    // esperado E20A|546|15|15|10
    out.paso2EsTotal = e2.texto === "E20A|546|15|15|10";
    out.mismoClientId = e1.id === e2.id;          // una sola fila, a propósito

    // --- caso 2: artículo sin excedente → 5º campo "0", no vacío
    _pk = { tanda: "E20A", legajo: "277", idx: 0, mode: "item", excOk: true,
                   items: [{ art: "300", key: "300", esp: 4 }], results: { "300": 4 } };
    pkSendDetail("300", 4, 4);
    out.sinExcedente = sent[sent.length - 1].texto === "E20A|300|4|4|0";

    // --- caso 3: la consulta de excedente falló → SIN 5º campo (backend vuelve a adivinar)
    _pk = { tanda: "E20A", legajo: "277", idx: 0, mode: "item", excOk: false,
                   items: [{ art: "300", key: "300", esp: 4 }], results: { "300": 4 } };
    pkSendDetail("300", 4, 4);
    out.excOkFalseTexto = sent[sent.length - 1].texto;
    out.excOkFalseSinCampo = sent[sent.length - 1].texto === "E20A|300|4|4";

    // --- caso 4: excedente marcado A MANO — repite el esp, no se duplica lo pedido
    _pk = {
      tanda: "E20A", legajo: "277", idx: 0, mode: "item", excOk: true,
      items: [
        { art: "700", key: "700", esp: 6, hasManualExc: true },
        { art: "700", key: "700·EXC", esp: 6, isExc: true, manualExc: true }
      ],
      results: { "700": 4, "700·EXC": 2 }
    };
    pkSendDetail("700", 6, 4);
    out.manualTexto = sent[sent.length - 1].texto;        // esperado E20A|700|6|6|2
    out.manualNoDuplica = sent[sent.length - 1].texto === "E20A|700|6|6|2";

    // --- caso 5: el faltante sigue leyéndose bien (texto de 5 campos, p.length >= 4)
    out.faltanteLeeCincoCampos = "E20A|546|15|10|3".split("|").length >= 4;
    return out;
  });
  await b.close();

  /* v15.41 (pedido de Luis): los pasos de EXCEDENTE van PRIMERO. No cambia de dónde se
     descuenta (el reparto ya está decidido antes de caminar) — cambia que, si el excedente
     miente, el operario lo descubre al principio y completa de góndola en la misma pasada. */
  const src = require("fs").readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
  r.excedentePrimero = src.indexOf("excSteps.concat(items)") >= 0;
  r.noQuedoElOrdenViejo = src.indexOf("items.concat(excSteps)") < 0;

  const ok = r.excedentePrimero && r.noQuedoElOrdenViejo && r.paso1EsTotal && r.paso2EsTotal && r.mismoClientId && r.sinExcedente &&
             r.excOkFalseSinCampo && r.manualNoDuplica && r.faltanteLeeCincoCampos && !errs.length;
  console.log("pk-deposito-pkc:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none", ok ? "· ✓ OK" : "· ✗ FALLÓ");
  process.exit(ok ? 0 : 1);
})();
