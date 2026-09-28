/* v23.10 (Luis, 2026-09-28) — CLIENTE NUEVO: MONTO DEL PEDIDO PARTIDO Y ALERTA DE PRECIO FALTANTE.
   (a) La fila de un pedido partido cobra la SUMA de sus partes (Speech 1 y celda Monto).
   (b) "si falta algún valor de algún producto … tiene que saltar una alerta cuando se aprieta
       contacto 1": con un código sin_precio, el Speech 1 pide confirmar y, si se cancela, no se
       marca ni se abre WhatsApp. Sin faltantes no pregunta nada. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 800 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    const mk = (o) => Object.assign({ empresa: "lk", cod: "4286", razon_social: "Capo", zona: "Zona 1",
      fecha_recep: "2026-09-25", m3: 0.3, bloques: [], cuarentena_motivos: ["cliente_nuevo"] }, o);
    _apr.pedidos = [mk({ order_id: 1555 }), mk({ order_id: 1556 }), mk({ order_id: 1559 })];
    _apr.pedidosTodos = _apr.pedidos;
    _apr.cuarPartidos = { "lk:1556": "1555" };
    _apr.cliValor = { "lk:1555": { valor: 1000, valorIva: 1210, valorImp: 0, itemsImp: 0 },
                      "lk:1556": { valor: 500, valorIva: 605, valorImp: 0, itemsImp: 0 },
                      "lk:1559": { valor: 300, valorIva: 363, valorImp: 0, itemsImp: 0 } };
    _apr.cliDtoPago = {};
    // (a) monto sumado
    out.sumaSpeech = /\$1\.815/.test(clinSpeechMsg1(_apr.pedidos[0]));
    out.sueltoSpeech = /\$363/.test(clinSpeechMsg1(_apr.pedidos[2]));
    out.celdaSuma = /1\.500/.test(clinNuevosValorFmt(_apr.pedidos[0], clinMiembros(_apr.pedidos[0])));
    // (b) alerta de precio faltante
    const eventos = []; let confirms = 0, respuesta = false;
    window.pipeEvento = async function (e, o, ev) { eventos.push(o + ":" + ev); };
    window.confirm = function () { confirms++; return respuesta; };
    window.aprRpc = async function (fn, args) {
      if (fn !== "gv_clin_composicion") return [];
      return args.p_order_id === "1556" ? [{ art: "931E", sin_precio: true }] : [{ art: "505", sin_precio: false }];
    };
    await pipeSpeech("lk", "1555", 1);
    out.preguntaYCorta = confirms === 1 && eventos.length === 0 && /931E/.test(_apr.msg || "");
    respuesta = true; await pipeSpeech("lk", "1555", 1);
    out.confirmadoSigue = confirms === 2 && eventos.length === 1;
    await pipeSpeech("lk", "1559", 1);
    out.sinFaltanteNoPregunta = confirms === 2 && eventos.length === 2;
    window.aprRpc = async function () { return []; };   // composición caída: también avisa
    respuesta = false; await pipeSpeech("lk", "1559", 1);
    out.caidaAvisa = confirms === 3 && eventos.length === 2;
    return out;
  });
  await b.close();
  const fallas = Object.keys(r).filter((k) => r[k] !== true);
  if (errs.length) console.log("pageerror:", errs.slice(0, 3));
  console.log(fallas.length ? "pipe-speech1-sin-precio: FALLA " + JSON.stringify(r) : "pipe-speech1-sin-precio: OK — " + Object.keys(r).length + " chequeos");
  process.exit(fallas.length || errs.length ? 1 : 0);
})();
