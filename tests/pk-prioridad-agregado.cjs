/* Regresión (idea 4990 / v12.85): la lista de tandas del operario respeta la
   PRIORIDAD que le pone `ppp_web_resync` a un agregado.

   El agujero que tapa: `PPP_Web_Programacion.prioridad` se llenaba desde v12.79 y
   el cartel rojo se veía, pero la lista del celular seguía ordenada por fecha de
   entrega y después alfabético. Una tanda con un agregado urgente para el jueves
   quedaba debajo de todas las del martes y el miércoles — o sea, invisible en la
   práctica, que es justo lo contrario de "ARMENLO YA".

   Verifica que:
   (a) la prioridad de la TANDA sea la más alta de sus NP (una sola NP con 100
       alcanza para subir la tanda entera),
   (b) la tanda urgente aparezca ARRIBA DE TODO, antes del primer grupo de fecha,
       aunque su entrega sea la más lejana,
   (c) no aparezca DOS veces (sale del agrupado por fecha),
   (d) las tandas de ISIS —que no tienen la columna— queden en prioridad 0 y en el
       mismo orden de siempre: esto es aditivo, si falla no se rompe el picking,
   (e) el bloque urgente diga a qué pedido se agregó,
   (f) sin ninguna prioridad la lista quede EXACTAMENTE como antes (sin bloque rojo). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const json = (o) => ({ ok: true, status: 200, json: async () => o,
                           text: async () => JSON.stringify(o),
                           headers: { get: () => "0-1/1" } });

    // Dos NP en la MISMA tanda web: una normal y una que es el agregado urgente.
    // La tanda urgente entrega el 11/09 — la MÁS LEJANA de las tres.
    const PROG = [
      { empresa: "lk", np: 1, tanda: "GV-02A", zona: "Zona 1", fecha_entrega: "2026-09-11",
        cod_cliente: "4109", razon_social: "Di Leo", direccion: "Bragado 5742",
        barrio: "Mataderos", m3: 0.336, es_agregado: false, agregado_a_np: null, prioridad: 0 },
      { empresa: "lk", np: 2, tanda: "GV-02A", zona: "Zona 1", fecha_entrega: "2026-09-11",
        cod_cliente: "4109", razon_social: "Di Leo", direccion: "Bragado 5742",
        barrio: "Mataderos", m3: 0.020, es_agregado: true, agregado_a_np: 1, prioridad: 100 }
    ];
    let progRows = PROG;

    window.fetch = async (url) => {
      const u = String(url);
      if (u.includes("PPP_Web_Programacion")) return json(progRows);
      return json([]);
    };
    // Dos tandas de ISIS, las dos con entrega ANTES que la urgente.
    window.fetchMonitorFromSupabase = async () => new Map([
      ["C03B", { tanda: "C03B", _key: "C03B", m3: 0.5, fechaEntrega: "09/09", fechaEntregaRaw: "2026-09-09",
                 opIsSi: false, pedidos: [{ np: "98574", m3: 0.5 }] }],
      ["C04A", { tanda: "C04A", _key: "C04A", m3: 0.7, fechaEntrega: "10/09", fechaEntregaRaw: "2026-09-10",
                 opIsSi: false, pedidos: [{ np: "98999", m3: 0.7 }] }]
    ]);
    // Ninguna tanda arrancada: el filtro "notStarted" (el de EP) las deja pasar a todas.
    window.getActivityStatus = async () => ({
      pickingStarted: new Set(), pickingDone: new Set(), pickingDoneStrict: new Set(),
      armadoStarted: new Set(), armadoDone: new Set(), armadoDoneStrict: new Set(),
      pickingEnCursoBy: new Map(), armadoEnCursoBy: new Map()
    });

    const out = {};

    // (a) la prioridad sube a la tanda
    const acc = await fetchMonitorSheet();
    const gv = acc.get("GV-02A");
    out.prioridadTanda = gv ? gv.prioridad : null;
    out.prioridadIsis  = acc.get("C03B").prioridad || 0;
    out.agregadosLen   = gv ? (gv.agregados || []).length : -1;

    const render = async () => {
      document.getElementById("tandasList").innerHTML = "";
      await populateTandasList("notStarted");
      return document.getElementById("tandasList").innerHTML;
    };

    // Primera corrida: por el camino REAL (fetchMonitorSheet → getPppTandasForOperator).
    let html = await render();
    out.hayBloqueUrgente = html.indexOf("ARMENLO YA") >= 0;
    // (b) arriba de todo: el bloque urgente antes del primer grupo de fecha
    out.urgentePrimero = html.indexOf("tandas-day-group urgente") >= 0 &&
                         html.indexOf("tandas-day-group urgente") < html.indexOf("tandas-day-header\">");
    // (c) una sola vez
    out.vecesGv = (html.match(/data-code="GV-02A"/g) || []).length;
    // (d) las de ISIS siguen ahí, en su día
    out.isisSiguen = html.indexOf('data-code="C03B"') >= 0 && html.indexOf('data-code="C04A"') >= 0;
    out.c03bAntesQueC04a = html.indexOf('data-code="C03B"') < html.indexOf('data-code="C04A"');
    // y la urgente va antes que las dos, aunque entregue después
    out.gvAntesQueIsis = html.indexOf('data-code="GV-02A"') < html.indexOf('data-code="C03B"');
    // (e) dice a qué pedido se agregó
    out.diceAQuePedido = html.indexOf("es un agregado al pedido") >= 0 &&
                         html.indexOf("LK 0002") >= 0 && html.indexOf("LK 0001") >= 0;

    // (f) sin prioridad → lista de siempre, sin bloque rojo.
    // `_pppOperatorCache` es un `let` de módulo (no vive en window) y tiene TTL, así
    // que no se puede invalidar desde afuera: para esta segunda pasada se stubea la
    // fuente de la lista. Lo que se está probando acá es el RENDER, no el merge —
    // el merge ya quedó cubierto por (a)-(e) con el camino real.
    window.getPppTandasForOperator = async () => ([
      { tanda: "GV-02A", opIsSi: false, fechaRaw: "2026-09-11", fechaDisplay: "11/09", prioridad: 0, agregados: [] },
      { tanda: "C03B",   opIsSi: false, fechaRaw: "2026-09-09", fechaDisplay: "09/09", prioridad: 0, agregados: [] },
      { tanda: "C04A",   opIsSi: false, fechaRaw: "2026-09-10", fechaDisplay: "10/09", prioridad: 0, agregados: [] }
    ]);
    html = await render();
    out.sinPrioridadSinBloque = html.indexOf("ARMENLO YA") < 0 &&
                                html.indexOf("tandas-day-group urgente") < 0;
    out.sinPrioridadGvSigue   = html.indexOf('data-code="GV-02A"') >= 0;
    // y ahí sí queda ordenada por fecha: la web (11/09) DESPUÉS de las de ISIS
    out.sinPrioridadGvUltima  = html.indexOf('data-code="GV-02A"') > html.indexOf('data-code="C04A"');

    return out;
  });

  const checks = [
    ["prioridad de la tanda = la más alta de sus NP (100)", r.prioridadTanda === 100],
    ["una tanda de ISIS queda en prioridad 0",              r.prioridadIsis === 0],
    ["el agregado se registró en la tanda",                 r.agregadosLen === 1],
    ["aparece el bloque ARMENLO YA",                        r.hayBloqueUrgente === true],
    ["el bloque urgente va antes del primer grupo de fecha", r.urgentePrimero === true],
    ["la tanda urgente aparece UNA sola vez",               r.vecesGv === 1],
    ["las tandas de ISIS siguen en la lista",               r.isisSiguen === true],
    ["las de ISIS conservan su orden por fecha",            r.c03bAntesQueC04a === true],
    ["la urgente va antes que las de ISIS pese a entregar después", r.gvAntesQueIsis === true],
    ["el bloque dice a qué pedido se agregó",               r.diceAQuePedido === true],
    ["sin prioridad NO se dibuja el bloque rojo",           r.sinPrioridadSinBloque === true],
    ["sin prioridad la tanda web sigue en la lista",        r.sinPrioridadGvSigue === true],
    ["sin prioridad vuelve al orden por fecha",             r.sinPrioridadGvUltima === true],
    ["sin errores de página",                              errs.length === 0]
  ];

  let bad = 0;
  for (const [name, ok] of checks) { console.log((ok ? "  ok   " : "  FALLA") + " · " + name); if (!ok) bad++; }
  if (errs.length) console.log("  pageerror: " + errs.join(" | "));
  console.log(bad ? "pk-prioridad-agregado: " + bad + " FALLA(S)" : "pk-prioridad-agregado: OK (" + checks.length + " chequeos)");
  await b.close();
  process.exit(bad ? 1 : 0);
})();
