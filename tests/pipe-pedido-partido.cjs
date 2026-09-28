/* v23.06 (Luis, 2026-09-28) — PEDIDO PARTIDO = UNA FILA TAMBIÉN EN CLIENTES NUEVOS.
   "si todos esos surgen de 1 pedido deberían figurar en una sola linea". Caso Capo SA (LK 4286):
   1555 + su parte diferida 1556 (Tafí Viejo), 1557 + 1558 (S.M. Tucumán) y 1559 (Alberdi).
   Son 3 pedidos a 3 sucursales: tienen que salir 3 filas, no 5 — y no 1. */
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
    _apr.cal = [{ dia: "2026-09-29", habil: true, m3: 1, tandas: 1, np: 2, cupo: 6, resta: 5, pasado: false }];
    const mk = (o) => Object.assign({ empresa: "lk", cod: "4286", razon_social: "Autoservicio Capo SA",
      zona: "Zona 1 - CABA Sur", fecha_recep: "2026-09-25", localidad: "Tucuman", direccion: "x",
      m3: 0.016, m3_parcial: false, lineas: 1, cajas: 2, np_total: 1, bloques: [],
      cuarentena_motivos: ["cliente_nuevo"], cuarentena_detalle: { nuevo_pedidos: 1 } }, o);
    _pppTab = "prog";
    document.getElementById("pppOverlay").classList.add("show");
    _apr.cuarResumen = []; _apr.cuarContacto = {}; _apr.cuarComN = {}; _apr.cuarMismo = {}; _apr.cuarRepo = {};
    _apr.pipe = {}; _apr.pipeCfg = {};
    _apr.pedidos = [
      mk({ order_id: 1555, m3: 0.782, np_total: 3, direccion: "La Rioja 555 - Tafi Viejo" }),
      mk({ order_id: 1556, direccion: "La Rioja 555 - Tafi Viejo" }),
      mk({ order_id: 1557, m3: 1.019, np_total: 4, direccion: "Lamadrid 157 -S.M Tucuman" }),
      mk({ order_id: 1558, direccion: "Lamadrid 157 -S.M Tucuman" }),
      mk({ order_id: 1559, m3: 0.710, np_total: 3, direccion: "Ruta 38 Esq Marañon - Alberdi" }),
      // otro cliente, 2 pedidos a la MISMA sucursal: no lleva badge
      mk({ order_id: 1600, cod: "77", razon_social: "Uno Solo", direccion: "Calle 1" }),
      mk({ order_id: 1601, cod: "77", razon_social: "Uno Solo", direccion: "Calle 1" }),
    ];
    _apr.pedidosTodos = _apr.pedidos;
    const filas = (h) => (h.match(/class="cuar-tr pipe-tr/g) || []).length;

    // (A) sin el mapa de partidos: 5 filas, como antes (no se rompe nada)
    _apr.cuarPartidos = {}; aprRender(); await new Promise((res) => setTimeout(res, 150));
    let html = document.getElementById("pppPreview").innerHTML;
    out.sinMapa5 = filas(html) === 7;

    // (B) con el mapa: 3 filas, contador 3, chip en 2, m³ sumado, encabeza el original
    _apr.cuarPartidos = { "lk:1556": "1555", "lk:1558": "1557" };
    aprRender(); await new Promise((res) => setTimeout(res, 150));
    html = document.getElementById("pppPreview").innerHTML;
    out.filas3 = filas(html) === 5;   // 3 de Capo + 2 de Uno Solo (no son partidos: son 2 pedidos)
    out.contador3 = /Clientes nuevos <b>\(5\)<\/b>/.test(html);
    out.chip2 = (html.match(/cuar-chip-partido/g) || []).length === 2;
    out.m3Sumado = /0,798 m³/.test(html) && /1,035 m³/.test(html);
    // v23.07: badge de sucursal sólo para el cliente con 2+ direcciones (3 filas de Capo, 0 de Uno Solo)
    out.sucBadge3 = (html.match(/class="apr-suc"/g) || []).length === 3;
    out.sucTextos = /🏬 La Rioja 555 - Tafi Viejo/.test(html) && /🏬 Lamadrid 157 -S.M Tucuman/.test(html) && /🏬 Ruta 38 Esq Marañon - Alberdi/.test(html);
    out.sinFilaHija = !/>web LK 1556</.test(html) && !/>web LK 1558</.test(html);
    return out;
  });
  await b.close();
  const fallas = Object.keys(r).filter((k) => r[k] !== true);
  if (errs.length) console.log("pageerror:", errs.slice(0, 3));
  console.log(fallas.length ? "pipe-pedido-partido: FALLA " + JSON.stringify(r) : "pipe-pedido-partido: OK — " + Object.keys(r).length + " chequeos");
  process.exit(fallas.length || errs.length ? 1 : 0);
})();
