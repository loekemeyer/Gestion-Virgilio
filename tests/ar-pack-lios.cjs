/* Test de arPackLios (idea 4535). Verifica que arPackLios(items, lioSize)
   distribuya cajas en líos sin sueltas, con suma total preservada y tamaños
   balanceados (diferencia máxima de 1 caja entre líos). */
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

    // 1) Función existe
    out.fnExists = typeof arPackLios === "function";

    // 2) items vacíos → 0 líos
    const r0 = arPackLios([], 5);
    out.emptyItems = r0.lios.length === 0;

    // 3) total=0 → 0 líos
    const r0b = arPackLios([{ art: "502", cajas: 0 }], 5);
    out.zeroCajas = r0b.lios.length === 0;

    // 4) Caso simple: 10 cajas de 1 art, lioSize=5 → 2 líos de 5
    const r1 = arPackLios([{ art: "502", cajas: 10 }], 5);
    out.simple2lios = r1.lios.length === 2;
    out.simple2sizes = r1.lios.every(l => l.reduce((s, x) => s + x.cajas, 0) === 5);

    // 5) Suma total siempre se preserva (varios escenarios)
    const scenarios = [
      { items: [{ art: "A", cajas: 7 }], lio: 3 },
      { items: [{ art: "A", cajas: 1 }], lio: 5 },
      { items: [{ art: "A", cajas: 13 }, { art: "B", cajas: 4 }], lio: 5 },
      { items: [{ art: "X", cajas: 20 }], lio: 4 },
      { items: [{ art: "A", cajas: 3 }, { art: "B", cajas: 3 }, { art: "C", cajas: 3 }], lio: 5 },
      { items: [{ art: "A", cajas: 100 }], lio: 5 },
    ];
    out.sumaPreservada = scenarios.every(sc => {
      const total = sc.items.reduce((s, x) => s + x.cajas, 0);
      const res = arPackLios(sc.items, sc.lio);
      const sumaLios = res.lios.reduce((s, l) => s + l.reduce((ss, x) => ss + x.cajas, 0), 0);
      return sumaLios === total;
    });

    // 6) Balanceo: diferencia máxima de 1 caja entre líos
    out.balanceo = scenarios.every(sc => {
      const res = arPackLios(sc.items, sc.lio);
      if (res.lios.length <= 1) return true;
      const sizes = res.lios.map(l => l.reduce((s, x) => s + x.cajas, 0));
      return Math.max(...sizes) - Math.min(...sizes) <= 1;
    });

    // 7) No hay líos vacíos
    out.sinVacios = scenarios.every(sc => {
      const res = arPackLios(sc.items, sc.lio);
      return res.lios.every(l => l.length > 0 && l.reduce((s, x) => s + x.cajas, 0) > 0);
    });

    // 8) 1 caja total → exactamente 1 lío
    const r8 = arPackLios([{ art: "Z", cajas: 1 }], 5);
    out.unaCAja1Lio = r8.lios.length === 1 && r8.lios[0][0].cajas === 1;

    // 9) Artículos adyacentes iguales se fusionan dentro del lío
    const r9 = arPackLios([{ art: "A", cajas: 10 }], 5);
    out.fusionArts = r9.lios.every(l => l.length === 1 && l[0].art === "A");

    // 10) Múltiples artículos se distribuyen correctamente
    const r10 = arPackLios([{ art: "A", cajas: 3 }, { art: "B", cajas: 7 }], 5);
    const totalR10 = r10.lios.reduce((s, l) => s + l.reduce((ss, x) => ss + x.cajas, 0), 0);
    out.multiArt = totalR10 === 10 && r10.lios.length === 2;

    return out;
  });

  let ok = true;
  const checks = [
    ["fnExists", "arPackLios existe"],
    ["emptyItems", "items vacíos → 0 líos"],
    ["zeroCajas", "total=0 → 0 líos"],
    ["simple2lios", "10 cajas / lioSize=5 → 2 líos"],
    ["simple2sizes", "cada lío tiene 5 cajas"],
    ["sumaPreservada", "suma total se preserva en todos los escenarios"],
    ["balanceo", "balanceo ≤1 caja de diferencia entre líos"],
    ["sinVacios", "no hay líos vacíos"],
    ["unaCAja1Lio", "1 caja → 1 lío"],
    ["fusionArts", "artículos adyacentes iguales se fusionan"],
    ["multiArt", "múltiples artículos se distribuyen correctamente"],
  ];
  for (const [k, label] of checks) {
    const pass = r[k] === true;
    console.log(pass ? `  ✓ ${label}` : `  ✗ ${label} (${JSON.stringify(r[k])})`);
    if (!pass) ok = false;
  }
  if (errs.length) { console.error("Page errors:", errs); ok = false; }

  await b.close();
  console.log(ok ? "ar-pack-lios OK" : "ar-pack-lios FAIL");
  process.exit(ok ? 0 : 1);
})();
