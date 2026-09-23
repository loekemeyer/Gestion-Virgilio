/* v22.09 — buscador por código en «📦 Pedidos Importación».

   Se corre la pantalla de verdad (no es un candado de texto) y se miran las cuatro cosas
   que definen la regla:
   (a) SIN buscar, "Solo Pedido" sigue escondiendo lo que no pide (no vuelve el ruido);
   (b) BUSCANDO el código aparece aunque no pida NADA y aunque esté en OTRO proveedor que
       el elegido — regla v20.95: una fila que no sale no se distingue de un código que no
       existe, así que el término gana sobre "Solo Pedido" y sobre el filtro de proveedor;
   (c) el código va por PREFIJO de la grafía que se muestra (regla v21.09): "03" trae el 035E
       y "30" NO trae el 030 ni el 035E; y nunca por pedazo ("031" no trae el 231);
   (d) el texto libre busca en la descripción.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const it = (cod, prov, desc, aPedir) => ({
    cod, prov, desc, proyUni: 10, objetivoUni: 100, stockUni: 0, enCurso: 0,
    aPedirUni: aPedir, aPedirCajas: aPedir ? 1 : 0, uniMaster: aPedir || 10,
    fobUni: 0.2, m3Master: 0.05, det: [{ id: 1, curso: 0, marca: "" }]
  });
  // 035E no pide nada (es el "838E" de esta pantalla) y vive en Fujian;
  // 231 y 307 existen para probar que el prefijo no agarra por el medio.
  const items = [
    it("035E", "Fujian", "Cernidor de Harina", 0),
    it("026", "Fujian", "Colador 8cm", 144),
    it("231", "Kangli", "Palo de Amasar", 50),
    it("307", "Kangli", "Rallador", 60),
    it("587C", "Frontier", "Cuchilla pelapapas laser", 4000)
  ];
  const cods = async (q, prov, soloPedir) => p.evaluate((a) => {
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items: a.items, meses: 10 }, soloPedir: a.soloPedir, mcOverride: {}, provFiltro: a.prov, q: a.q };
    _pedImpRender();
    return [...document.querySelectorAll(".mva-tbl.wide tbody tr")].map((tr) => tr.cells[0].textContent.trim());
  }, { items, prov: prov || "", soloPedir: soloPedir !== false, q: q || "" });

  const hayInput = await p.evaluate(() => { _stkPopShell("📦 Pedidos Importación", "stkPopBody", true); _stkPop = { kind: "pedImp", data: { items: [], meses: 10 }, soloPedir: true, mcOverride: {} }; _pedImpRender(); return !!document.querySelector("input.pedimp-q"); });
  if (!hayInput) fail("no se dibujó el buscador (input.pedimp-q)");

  const a1 = await cods("");
  if (a1.indexOf("035E") >= 0) fail("(a) sin buscar, el que no pide nada igual salió: " + a1.join());
  if (a1.indexOf("026") < 0) fail("(a) sin buscar se perdió el que sí pide: " + a1.join());

  const b1 = await cods("035E", "Kangli");          // otro proveedor elegido, y no pide nada
  if (b1.join() !== "035E") fail("(b) buscando 035E parado en Kangli dio: " + b1.join());

  const c1 = await cods("03");
  if (c1.join() !== "035E") fail("(c) «03» tenía que traer sólo el 035E y dio: " + c1.join());
  const c2 = await cods("30");
  if (c2.join() !== "307") fail("(c) «30» tenía que traer sólo el 307 (no el 030/035E) y dio: " + c2.join());
  const c3 = await cods("031");
  if (c3.length) fail("(c) «031» trajo algo por el medio: " + c3.join());
  const c4 = await cods("026 231");                  // varios términos
  if (c4.slice().sort().join() !== "026,231") fail("(c) dos términos dieron: " + c4.join());

  const d1 = await cods("cernidor");
  if (d1.join() !== "035E") fail("(d) texto libre dio: " + d1.join());
  const d2 = await cods("zzzz");
  if (d2.length) fail("(d) una búsqueda sin resultados igual dibujó filas: " + d2.join());

  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("pedimp-buscador: OK — sin buscar " + a1.join("/") + " · «03»→" + c1.join() + " · «30»→" + c2.join() + " · 035E en otro prov→" + b1.join());
})();
