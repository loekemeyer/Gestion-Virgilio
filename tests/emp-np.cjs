/* Test de regresión (v6.84, idea 9020): el picking tiene que partir por EMPRESA los
   códigos cuyo stock está separado ("438E LK" / "438E CH"), usando el número de NP
   para decidir (>90000 = Loekemeyer, si no Chef). Es lo que hace que el descuento de
   stock caiga en el saldo correcto y que el operario vea el sector de SU empresa.

   Lo que cubre:
   1. empresaDeNp: 98049→LK, 44519→CH, basura→"" (sin empresa NO se toca nada).
   2. pkCodEmpresa: sólo agrega el sufijo si la planimetría TIENE ese código; si no,
      devuelve el código pelado (así un código no partido sigue funcionando igual).
   3. codBase: saca el sufijo — lo usa todo lo que se cruza contra el PEDIDO
      (faltantes, Entregas_Virgilio), que siempre habla en código pelado.
   4. _compMatchArt: un faltante de "438E LK" tiene que matchear la línea "438E" del
      pedido. Si esto se rompe, el faltante no se le asigna a ninguna NP (silencioso).
   5. _pkItemCodes: la lectora de código de barras (idea 8243) escanea la etiqueta del
      slot, que dice "438E" pelado → el ítem partido acepta pelado Y con sufijo.
   Sale 1 si falla. */
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
    // Planimetría de prueba: 438E partido por empresa, 546 NO partido.
    window.GONDOLA = Object.assign({}, window.GONDOLA, {
      "438E": ["F13", 104], "438E LK": ["F13", 104], "438E CH": ["L05", 174], "546": ["F45", 92]
    });
    return {
      empLK:   empresaDeNp("98049"),
      empCH:   empresaDeNp("44519"),
      empNada: empresaDeNp("sin numero"),
      empVacio: empresaDeNp(""),
      // partido → sufijo por NP
      codLK: pkCodEmpresa("438E", "98049"),
      codCH: pkCodEmpresa("438E", "44519"),
      // NO partido → queda pelado aunque la NP tenga empresa
      codNoPart: pkCodEmpresa("546", "98049"),
      // sin empresa → pelado
      codSinEmp: pkCodEmpresa("438E", "xx"),
      base1: codBase("438E LK"),
      base2: codBase("809E CH"),
      base3: codBase("438E"),
      base4: codBase("546"),
      matchFaltante: _compMatchArt("438E", "438E LK"),
      matchDistinto: _compMatchArt("437E", "438E LK"),
      // 5. la lectora (idea 8243) escanea la etiqueta del slot, que dice "438E" pelado:
      //    el ítem partido tiene que aceptar los DOS códigos.
      scanCodes: _pkItemCodes({ art: "438E LK" }),
      scanNum3: _pkNum3("438E LK")
    };
  });
  await b.close();
  const fail = [];
  const eq = (k, got, want) => { if (got !== want) fail.push(k + ": esperaba " + JSON.stringify(want) + " y dio " + JSON.stringify(got)); };
  eq("empresaDeNp(98049)", r.empLK, "LK");
  eq("empresaDeNp(44519)", r.empCH, "CH");
  eq("empresaDeNp(basura)", r.empNada, "");
  eq("empresaDeNp('')", r.empVacio, "");
  eq("pkCodEmpresa(438E, NP de Loeke)", r.codLK, "438E LK");
  eq("pkCodEmpresa(438E, NP de Chef)", r.codCH, "438E CH");
  eq("pkCodEmpresa(546 = no partido)", r.codNoPart, "546");
  eq("pkCodEmpresa(438E, NP sin número)", r.codSinEmp, "438E");
  eq("codBase(438E LK)", r.base1, "438E");
  eq("codBase(809E CH)", r.base2, "809E");
  eq("codBase(438E)", r.base3, "438E");
  eq("codBase(546)", r.base4, "546");
  eq("_compMatchArt(pedido 438E, faltante 438E LK)", r.matchFaltante, true);
  eq("_compMatchArt(437E vs 438E LK)", r.matchDistinto, false);
  if (!(r.scanCodes || []).includes("438E LK")) fail.push("_pkItemCodes: falta el código con sufijo");
  if (!(r.scanCodes || []).includes("438E")) fail.push("_pkItemCodes: falta el código PELADO (la lectora no encontraría el ítem)");
  eq("_pkNum3(438E LK)", r.scanNum3, "438");
  if (errs.length) fail.push("errores de página: " + errs.join(" | "));
  if (fail.length) { console.error("emp-np: FALLÓ\n  - " + fail.join("\n  - ")); process.exit(1); }
  console.log("emp-np: OK — empresa por NP, sufijo sólo si está partido, código pelado para el pedido.");
})();
