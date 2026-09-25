/* v22.47 (Luis, 2026-09-25) — PEDIDO PARTIDO POR IMPORTADOS = UN ITEM EN CUARENTENA.
   "los dos pedidos esos son en realidad 1 partido … en cuarentena deberían aparecer agrupados en
   un solo item que diga que hay múltiples pedidos ahí". Caso Solia: LK 1545 + su parte diferida
   1546 (pedido_origen = 1545). Corre la columna de Cuarentena de verdad con los dos retenidos y
   un tercer pedido suelto, y mira que salgan 2 filas, no 3, con el chip del partido. */
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
    _apr.listo = true; _apr.tandas = []; _apr.items = {}; _apr.salida = {};
    _apr.cal = [{ dia: "2026-09-14", habil: true, m3: 1, tandas: 1, np: 2, cupo: 6, resta: 5, pasado: false }];
    const mk = (o) => Object.assign({ empresa: "lk", cod: "151", razon_social: "Solia", zona: "Zona 5 - GBA Oeste",
      fecha_recep: "2026-09-24", localidad: "Moron", direccion: "Rivadavia 18059", m3: 0.4, m3_parcial: false,
      lineas: 5, cajas: 6, np_total: 1, bloques: [], cuarentena_motivos: ["deuda"],
      cuarentena_detalle: { deuda: 3421315.29 } }, o);
    _pppTab = "prog";
    document.getElementById("pppOverlay").classList.add("show");
    _apr.cuarResumen = []; _apr.cuarContacto = {}; _apr.cuarComN = {}; _apr.cuarMismo = {}; _apr.cuarRepo = {};
    _apr.pedidos = [
      mk({ order_id: 1546, m3: 0.021, lineas: 1, cajas: 3 }),       // la parte diferida llega primero
      mk({ order_id: 1545, m3: 0.5 }),
      mk({ order_id: 1600, cod: "900", razon_social: "Otro Cliente" }),
    ];

    // (A) sin el mapa de partidos todavia: 3 filas, como antes (no se rompe nada)
    _apr.cuarPartidos = {}; aprRender(); await new Promise((res) => setTimeout(res, 150));
    let html = document.getElementById("pppPreview").innerHTML;
    out.sinMapa3 = (html.match(/class="cuar-tr/g) || []).length === 3;

    // (B) con el mapa: 1546 es parte de 1545 -> 2 filas, contador 2, chip, m3 sumado
    _apr.cuarPartidos = { "lk:1546": "1545" };
    aprRender(); await new Promise((res) => setTimeout(res, 150));
    html = document.getElementById("pppPreview").innerHTML;
    out.filas2 = (html.match(/class="cuar-tr/g) || []).length === 2;
    out.contador2 = /🚧 Cuarentena <b>\(2\)<\/b>/.test(html);
    out.chip = /cuar-chip-partido/.test(html) && /2 pedidos \(1 partido\)/.test(html);
    out.labelsJuntos = /1545[^<]*\+[^<]*1546/.test(html);   // encabeza el ORIGINAL
    out.m3Sumado = /0,52[01] m³/.test(html) || /0\.52[01] m³/.test(html);
    out.chipSoloUno = (html.match(/cuar-chip-partido/g) || []).length === 1;

    // (C) aprobarlo es aprobar el grupo: el boton de la fila apunta al original
    out.enviarOriginal = /cuarLiberar\('lk','1545'\)/.test(html) && !/cuarLiberar\('lk','1546'\)/.test(html);
    return out;
  });
  await b.close();
  const fallas = Object.keys(r).filter((k) => r[k] !== true);
  if (errs.length) console.log("pageerror:", errs.slice(0, 3));
  console.log(fallas.length ? "apr-cuar-pedido-partido: FALLA " + JSON.stringify(r) : "apr-cuar-pedido-partido: OK — " + Object.keys(r).length + " chequeos");
  process.exit(fallas.length || errs.length ? 1 : 0);
})();
