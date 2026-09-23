/* v21.76 — un código que NO EXISTE no se dibuja en Stocks, ni siquiera buscándolo.

   Luis, 23/09: "si busco 865 me muestra el 865 pelado (que no existe)". El 865 salía de
   dos filas de Movimientos_Stock —un ajuste del 18/08 y su reversión 25 min después—,
   porque el universo de stock se arma desde los movimientos y no desde un maestro.

   ⚠ Esto NO es la v20.95, y el test muerde por los dos lados justamente por eso:
     · código que EXISTE y está en 0  -> SE MUESTRA (el 0 es la respuesta)
     · código que NO EXISTE           -> no se muestra
   Lo segundo lo marca el backend (visible_en_stock=false, v21.76) y lo respeta
   `_stkSaldosFromView`, con su guard propio: nunca esconde algo con saldo o pedidos. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

const CERO = { terminado: 0, excedente: 0, separar_pedidos: 0, a_facturar: 0, a_guardar: 0,
               racks: 0, racks_ch: 0, para_envasar: 0, insumos_dep: 0, stock_total: 0,
               cajas_pedidas: 0, proy_cajas_mes: 0, capacidad_gondola: 0, fc_sin_salida: 0,
               es_insumo: false, familia_principal: null, es_secundario: false };

const FILAS = [
  // el fantasma: no existe, todo en cero -> el backend lo marcó invisible
  Object.assign({ cod: "865", cod_base: "865", descripcion: null, linea: null, visible_en_stock: false }, CERO),
  // el de verdad, con cajas
  Object.assign({ cod: "865E", cod_base: "865E", descripcion: "Rallador Plano A/I 3 Usos", linea: "CH",
                  visible_en_stock: true }, CERO, { terminado: 9, stock_total: 10, separar_pedidos: 1 }),
  // v20.95: EXISTE y está en CERO -> se muestra igual. Si este se esconde, el arreglo se pasó de rosca.
  Object.assign({ cod: "838E", cod_base: "838E", descripcion: "Rallador Cilindrico Mini", linea: "LK",
                  visible_en_stock: true }, CERO, { capacidad_gondola: 35, proy_cajas_mes: 34.17 }),
  // guard del front: marcado invisible PERO con cajas -> se muestra igual, nunca se esconde stock real
  Object.assign({ cod: "439E", cod_base: "439E", descripcion: "Colador Pasta", linea: "LK",
                  visible_en_stock: false }, CERO, { terminado: 15, stock_total: 15 }),
];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(({ FILAS }) => {
    const fallas = [];
    if (typeof _stkSaldosFromView !== "function") { return { fallas: ["_stkSaldosFromView no existe"], cods: [] }; }
    const m = _stkSaldosFromView(FILAS);
    const cods = Object.keys(m);

    if (cods.indexOf("865") >= 0) fallas.push('el 865 (no existe, todo en cero) se sigue dibujando');
    if (cods.indexOf("865E") < 0) fallas.push('el 865E (existe, con cajas) desapareció');
    if (cods.indexOf("838E") < 0) fallas.push('el 838E existe y está en 0: tiene que verse (v20.95)');
    if (cods.indexOf("439E") < 0) fallas.push('el 439E tiene 15 cajas: no se esconde nunca, diga lo que diga el flag');
    return { fallas, cods };
  }, { FILAS });

  const ok = r.fallas.length === 0 && errs.length === 0;
  console.log("stk-codigo-inexistente: dibuja [" + r.cods.join(",") + "]",
    (r.fallas.length ? " · FALLAS: " + r.fallas.join(" | ") : ""),
    "· pageerrors:", errs.length ? errs.join("|") : "none", "·", ok ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(ok ? 0 : 1);
})();
