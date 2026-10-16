/* v31.59 (Giuliana, 2026-10-16) — en el Mapa de góndolas la zona P muestra el EXCEDENTE que hay
   HOY en cada posición, sacado de gv_excedente_posicion. La zona P NO es una asignación fija:
   cuando el saldo de un código en PX se acaba, el código deja de figurar en PX.

   Se verifica corriendo la pantalla:
   (a) P18 (libre en el mapa fijo) dibuja el 654 con sus cajas y queda marcada «con excedente»;
   (b) P22 —donde estaba el 654 antes, ya sin saldo— queda LIBRE (la vista no la trae);
   (c) una celda P con un código fijo (P39 / 396) suma el excedente abajo sin perder el suyo;
   (d) la leyenda cuenta las celdas con excedente;
   (e) buscar el código resalta su posición;
   (f) si la vista falla, se conserva lo último leído (una lectura rota no es «no hay excedente»). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

const CELDAS = [];
for (let n = 16; n <= 25; n++) CELDAS.push({ sector: "P" + n, gondola: "P", celda: n, empresa: "CH", cod: null, cajas_max: null, estado: "libre" });
CELDAS.push({ sector: "P39", gondola: "P", celda: 39, empresa: "LK", cod: "396", cajas_max: 20, max_fuente: "item", estado: "ok" });
const EXC = [
  { cod: "654", clave: "654", empresa: "LK", sector: "P18", cajas: 5 },
  { cod: "902", clave: "902", empresa: "CH", sector: "P18", cajas: 20 },
  { cod: "066", clave: "066", empresa: "LK", sector: "P21", cajas: 72 },
  { cod: "315", clave: "315", empresa: "LK", sector: "P39", cajas: 4 }
];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1300, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  let falla = false, pedidoExc = "";
  await p.route("**/rest/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.route("**/rest/v1/gv_planimetria_celda*", (r) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(CELDAS) }));
  await p.route("**/rest/v1/gv_excedente_posicion*", (r) => {
    pedidoExc = r.request().url();
    if (falla) return r.fulfill({ status: 500, contentType: "application/json", body: "{}" });
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(EXC) });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const cel = async (sec) => p.evaluate((s) => {
    const c = [...document.querySelectorAll("#pmapGrid .pmap-cell")].find((x) => (x.querySelector(".pmap-sec") || {}).textContent === s);
    return c ? { cls: c.className, txt: c.textContent, tip: c.title } : null;
  }, sec);

  await p.evaluate(async () => { window.__isSupervisor = true; await openPlanimMapa(); pmapGo("P"); });
  await p.waitForFunction(() => Object.keys(window._pmapExc || {}).length > 0 || (typeof _pmapExc !== "undefined" && Object.keys(_pmapExc).length > 0), null, { timeout: 8000 }).catch(() => {});
  await p.evaluate(() => pmapGo("P"));
  const o = {};
  const p18 = await cel("P18"), p22 = await cel("P22"), p39 = await cel("P39");
  o.a_p18_654 = !!p18 && /654/.test(p18.txt) && /5/.test(p18.txt) && /pmap-exc/.test(p18.cls) && !/pmap-libre/.test(p18.cls);
  o.a_p18_dos = !!p18 && /902/.test(p18.txt);
  o.a_tip = !!p18 && /no es fijo/.test(p18.tip);
  o.b_p22_libre = !!p22 && /pmap-libre/.test(p22.cls) && !/654/.test(p22.txt);
  o.c_p39_fijoYexc = !!p39 && /396/.test(p39.txt) && /315/.test(p39.txt);
  o.d_leyenda = await p.evaluate(() => /con excedente hoy\s*3/.test((document.getElementById("pmapLeg") || {}).textContent || ""));
  o.e_pide = pedidoExc.indexOf("sector=not.is.null") >= 0;
  await p.evaluate(() => pmapBuscar("654"));
  const h = await cel("P18");
  o.e_busca = !!h && /pmap-hit/.test(h.cls);
  await p.evaluate(() => pmapBuscar(""));
  falla = true;
  await p.evaluate(async () => { await pmapExcFetch(); pmapRender(); });
  const f18 = await cel("P18");
  o.f_lecturaRotaConserva = !!f18 && /654/.test(f18.txt);

  const pass = Object.keys(o).every((k) => o[k] === true) && !errs.length;
  console.log("pmap-excedente-p:", JSON.stringify(o), "· pageerrors:", errs.length ? errs.join(" | ") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
