/* Test de cpParseResumen / cpBuildResumen (idea 1752). Verifica:
   - Parse de formato "A=535X3,546X5;B=510X1(s)" devuelve estructura correcta
   - Build genera el texto canónico
   - Roundtrip build(parse(s)) es idempotente (parse -> build -> parse -> build = same)
   - Casos borde: vacío, null, un solo lío, sueltas, muchos artículos */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const out = {};

    // 1) Funciones existen
    out.fnsExist = typeof cpParseResumen === "function" && typeof cpBuildResumen === "function";

    // 2) Parse de cadena canónica
    const parsed = cpParseResumen("A=535X3,546X5;B=510X1(s)");
    out.parseLen = parsed.length === 2;
    out.parseLio1 = parsed[0].items.length === 2
      && parsed[0].items[0].cod === "535" && parsed[0].items[0].qty === 3
      && parsed[0].items[1].cod === "546" && parsed[0].items[1].qty === 5
      && parsed[0].suelta === false;
    out.parseLio2 = parsed[1].items.length === 1
      && parsed[1].items[0].cod === "510" && parsed[1].items[0].qty === 1
      && parsed[1].suelta === true;

    // 3) Parse de null y vacío → array vacío
    out.parseNull = cpParseResumen(null).length === 0;
    out.parseEmpty = cpParseResumen("").length === 0;
    out.parseUndef = cpParseResumen(undefined).length === 0;

    // 4) Parse de un solo lío sin letra
    const p1 = cpParseResumen("A=502X10");
    out.parseSingle = p1.length === 1 && p1[0].items[0].cod === "502" && p1[0].items[0].qty === 10 && !p1[0].suelta;

    // 5) Build genera texto canónico
    const lios = [
      { items: [{ cod: "535", qty: 3 }, { cod: "546", qty: 5 }], suelta: false },
      { items: [{ cod: "510", qty: 1 }], suelta: true }
    ];
    const built = cpBuildResumen(lios);
    out.buildFormat = built === "A=535X3,546X5;B=510X1(s)";

    // 6) Roundtrip: parse -> build -> parse -> build = estable
    const str1 = "A=502X3,323EX2;B=546X4(s);C=510X1";
    const rt1 = cpBuildResumen(cpParseResumen(str1));
    const rt2 = cpBuildResumen(cpParseResumen(rt1));
    out.roundtrip = rt1 === rt2;

    // 7) Roundtrip con mayúsculas (build fuerza uppercase)
    const lower = "A=502x3,323ex2";
    const rtLow = cpBuildResumen(cpParseResumen(lower));
    out.uppercase = rtLow.includes("502X3") && rtLow.includes("323EX2");

    // 8) Múltiples artículos en un lío
    const multi = cpParseResumen("A=100X1,200X2,300X3,400X4");
    out.multiItems = multi.length === 1 && multi[0].items.length === 4;
    const sumaQty = multi[0].items.reduce((s, x) => s + x.qty, 0);
    out.multiQty = sumaQty === 10;

    // 9) Build con lío vacío (items=[]) → no produce basura
    const emptyBuild = cpBuildResumen([]);
    out.buildEmpty = emptyBuild === "";

    return out;
  });

  let ok = true;
  const checks = [
    ["fnsExist", "cpParseResumen y cpBuildResumen existen"],
    ["parseLen", "parse de 2 líos → length=2"],
    ["parseLio1", "primer lío: 535X3, 546X5, no suelta"],
    ["parseLio2", "segundo lío: 510X1, suelta"],
    ["parseNull", "parse(null) → []"],
    ["parseEmpty", "parse('') → []"],
    ["parseUndef", "parse(undefined) → []"],
    ["parseSingle", "parse de un solo lío"],
    ["buildFormat", "build genera formato canónico"],
    ["roundtrip", "roundtrip parse→build es estable"],
    ["uppercase", "build fuerza uppercase"],
    ["multiItems", "parse de 4 artículos en un lío"],
    ["multiQty", "suma de quantities correcta"],
    ["buildEmpty", "build([]) → ''"],
  ];
  for (const [k, label] of checks) {
    const pass = r[k] === true;
    console.log(pass ? `  ✓ ${label}` : `  ✗ ${label} (${JSON.stringify(r[k])})`);
    if (!pass) ok = false;
  }
  if (errs.length) { console.error("Page errors:", errs); ok = false; }

  await b.close();
  console.log(ok ? "cp-resumen-roundtrip OK" : "cp-resumen-roundtrip FAIL");
  process.exit(ok ? 0 : 1);
})();
