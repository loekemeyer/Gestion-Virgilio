/* v21.62 (Luis, 2026-09-23) — los pedidos de CLIENTES DE PRUEBA (GV_Clientes_Prueba, tanda PRUEBAn)
   van a la PPP pero el OPERARIO no los ve.
   Chequea: (1) estático, que las pantallas del operario pasen por gvSinPrueba / gvEsTandaPrueba y que
            el Excel ISIS los saque; y que la tele (monitor/tv.html) filtre lo mismo;
            (2) en vivo, gvSinPrueba con un mapa armado a mano: saca la tanda PRUEBA1, saca el pedido
            de prueba de una tanda mezclada (y le baja los m³), deja intactas las tandas reales, y NO
            toca el mapa original (lo cachean pantallas de supervisor). */
const path = require("path"), fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
const tv  = fs.readFileSync(path.join(__dirname, "..", "monitor", "tv.html"), "utf8");
const fallas = [];
const exige = (re, msg) => { if (!re.test(src)) fallas.push(msg); };
exige(/async function gvSinPrueba\(/, "falta gvSinPrueba");
exige(/const sheetMap = await gvSinPrueba\(await fetchMonitorSheet\(\)\);/, "getPppTandasForOperator no filtra la prueba");
exige(/fetchMonitorSheet\(\)\.then\(gvSinPrueba\), fetchPickingBase\(\), fetchCorrecciones\(\)/, "showPickingList no filtra la prueba");
exige(/sheetMap = await gvSinPrueba\(sheetMap\);/, "el monitor no filtra la prueba");
exige(/const repR = \(_par\[0\] \|\| \[\]\)\.filter\(function \(r\) \{ return !gvEsTandaPrueba\(r\.tanda\); \}\), ccnR/, "Carga Camión no filtra PRUEBA");
exige(/const repR = \(_par\[0\] \|\| \[\]\)\.filter\(function \(r\) \{ return !gvEsTandaPrueba\(r\.tanda\); \}\), ccrR/, "Control Remitos no filtra PRUEBA");
exige(/_prNps\.has\(String\(ent\[i\]\.np/, "el Excel ISIS no saca los pedidos de prueba");
exige(/pgaPruebaEliminar\(/, "falta el botón Eliminar de la tanda PRUEBA");
if (!/esTandaPrueba\(tanda\)\) continue;/.test(tv) || !/GV_Clientes_Prueba/.test(tv)) fallas.push("monitor/tv.html no filtra la prueba");
if (fallas.length) { console.log("prueba-oculta-operario: ✗ FAIL\n  - " + fallas.join("\n  - ")); process.exit(1); }

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.log("prueba-oculta-operario: estático ✓ OK"); process.exit(0); } }
(async () => {
  const b = await chromium.launch();
  const p = await (await b.newContext()).newPage();
  // Playwright prueba las rutas de la ÚLTIMA registrada a la primera: la específica va después.
  await p.route("**/rest/v1/**", (r) => r.fulfill({ status: 200, headers: { "content-type": "application/json" }, body: "[]" }));
  await p.route("**/rest/v1/GV_Clientes_Prueba**", (r) => r.fulfill({ status: 200,
    headers: { "content-type": "application/json" }, body: JSON.stringify([{ empresa: "lk", cod: "99862" }]) }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const m = new Map();
    m.set("PRUEBA1", { tanda: "PRUEBA1", m3: 0.1, pedidos: [{ np: "LK 0500", cod: "99862", m3: 0.1 }] });
    m.set("E80A", { tanda: "E80A", m3: 0.5, pedidos: [{ np: "LK 0501", cod: "99862", m3: 0.2 }, { np: "LK 0502", cod: "862", m3: 0.3 }] });
    m.set("E80B", { tanda: "E80B", m3: 0.4, pedidos: [{ np: "98700", cod: "99862", m3: 0.4 }] });   // ISIS LK con cod 99862 → prueba
    m.set("E80C", { tanda: "E80C", m3: 0.7, pedidos: [{ np: "CH 0100", cod: "99862", m3: 0.7 }] });  // Chef 99862 NO es de prueba
    const o = await gvSinPrueba(m);
    return { keys: Array.from(o.keys()), e80a: o.get("E80A") && o.get("E80A").pedidos.map(x => x.np),
             e80aM3: o.get("E80A") && Math.round(o.get("E80A").m3 * 1000) / 1000,
             origIntacto: m.size === 4 && m.get("E80A").pedidos.length === 2,
             tandaPrueba: [gvEsTandaPrueba("PRUEBA12"), gvEsTandaPrueba("prueba3"), gvEsTandaPrueba("E12A"), gvEsTandaPrueba("PRUEBA")] };
  });
  await b.close();
  const mal = [];
  if (JSON.stringify(r.keys) !== JSON.stringify(["E80A", "E80C"])) mal.push("tandas que quedan: " + r.keys.join(","));
  if (JSON.stringify(r.e80a) !== JSON.stringify(["LK 0502"])) mal.push("E80A mezclada: " + JSON.stringify(r.e80a));
  if (r.e80aM3 !== 0.3) mal.push("m³ de E80A: " + r.e80aM3);
  if (!r.origIntacto) mal.push("gvSinPrueba modificó el mapa original");
  if (JSON.stringify(r.tandaPrueba) !== "[true,true,false,false]") mal.push("gvEsTandaPrueba: " + JSON.stringify(r.tandaPrueba));
  if (mal.length) { console.log("prueba-oculta-operario: ✗ FAIL\n  - " + mal.join("\n  - ")); process.exit(1); }
  console.log("prueba-oculta-operario: ✓ OK (estático + gvSinPrueba en vivo)");
})().catch((e) => { console.log("prueba-oculta-operario: ✗ FAIL " + e.message); process.exit(1); });
