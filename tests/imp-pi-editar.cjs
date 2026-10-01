/* v25.94 — ✏️ EDITAR PI en 🚢 En curso: corregir las cantidades de cada ítem con registro de QUIÉN,
   QUÉ DÍA y A QUÉ HORA. Pedido: "cuando toco el lápiz, me pregunte quién es la persona que va a
   corregir la PI… y un cuadradito Otro para poner el nombre".
   Se corre la pantalla de verdad con la base mockeada:
   (a) el lápiz abre el pop-up y lo PRIMERO es «¿Quién corrige?» con los editores + «Otro»
   (b) elegido, aparecen los ítems con su cantidad actual y un input por ítem
   (c) «Ver cambios» llama a gv_imp_pi_editar con p_simular=true, manda SÓLO lo que cambió y
       con el `antes` que se vio, y muestra antes → después
   (d) «Guardar» la llama con p_simular=false y el mismo editor
   (e) «Otro» manda el nombre tipeado
   (f) las tres RPC van con la sesión (están en _PED_IMP_RPC_ESCRITURA)
   Sale 1 si falla. */
const path = require("path"), fs = require("fs");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };

const REF = "PI HT26-06-600-R1";
const CURSO = [{ pedido_ref: REF, proveedor: "Fujian", n_lineas: 3, unidades: 9336, pendiente: 9336, usd: 3000, m3: 5,
  fecha_embarque: "2026-09-19", fecha_llegada: "2026-11-01" }];
const LINEAS = [
  { bache_id: 77, importado_id: 63, cod_art: "438E", marca: "CH", descripcion: "Colador 20cm", unidades: 1224, pendiente: 1224, fob_uni: 0.5, usd: 612, m3: 1 },
  { bache_id: 78, importado_id: 65, cod_art: "438EL", marca: "LK", descripcion: "Colador 20cm", unidades: 6912, pendiente: 6912, fob_uni: 0.5, usd: 3456, m3: 3 },
  { bache_id: 82, importado_id: 67, cod_art: "035E", marca: "LK", descripcion: "Tamiz", unidades: 1200, pendiente: 1200, fob_uni: 0.85, usd: 1020, m3: 1 }
];
const llamadas = [];

(async () => {
  // (f) estático: las tres RPC con la sesión
  const src = fs.readFileSync(path.join(__dirname, "..", "importacion.js"), "utf8");
  const lista = (src.match(/const _PED_IMP_RPC_ESCRITURA = \[([\s\S]*?)\];/) || [])[1] || "";
  ["gv_imp_pi_editar", "gv_imp_pi_editores", "gv_imp_pi_ediciones"].forEach(function (n) {
    if (lista.indexOf('"' + n + '"') < 0) fail("(f) " + n + " no está en _PED_IMP_RPC_ESCRITURA (iría con la clave pública y la base la rechaza)");
  });

  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", async (r) => {
    const u = r.request().url();
    let body = "[]";
    const pd = (() => { try { return JSON.parse(r.request().postData() || "null"); } catch (_e) { return null; } })();
    if (/rpc\/gv_importados_pedidos_curso/.test(u)) body = JSON.stringify(CURSO);
    else if (/rpc\/gv_imp_pi_editores/.test(u)) body = JSON.stringify([{ nombre: "Thomas" }, { nombre: "Tomás" }, { nombre: "Vivi" }, { nombre: "Luis" }, { nombre: "Gastón" }]);
    else if (/rpc\/gv_importado_pedido_lineas/.test(u)) body = JSON.stringify(LINEAS);
    else if (/rpc\/gv_imp_pi_ediciones/.test(u)) body = JSON.stringify([]);
    else if (/rpc\/gv_imp_pi_editar/.test(u)) {
      llamadas.push(pd);
      const filas = (pd.p_cambios || []).map(function (c) {
        const l = LINEAS.find(function (x) { return x.bache_id === c.bache_id; });
        return { bache_id: c.bache_id, cod_art: l.cod_art, marca: l.marca, antes: c.antes, despues: c.unidades, delta: c.unidades - c.antes, sale: c.unidades === 0 };
      });
      const tA = 9336, tD = tA + filas.reduce(function (s, f) { return s + f.delta; }, 0);
      body = JSON.stringify({ simulado: pd.p_simular, ts: "2026-09-30T18:00:00Z", editor: pd.p_editor,
        editor_nuevo: !/^(Thomas|Tomás|Vivi|Luis|Gastón)$/.test(pd.p_editor), pedido_ref: REF, ref_nuevo: pd.p_nuevo_ref,
        cambios: filas.length, filas: filas, total_antes: tA, total_despues: tD });
    }
    await r.fulfill({ status: 200, contentType: "application/json", body });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  await p.waitForFunction(() => typeof openImpEnCurso === "function" && typeof impPiEditar === "function", null, { timeout: 15000 });
  await p.evaluate(() => { window.facAuthWriteHeaders = async () => ({ apikey: "k", Authorization: "Bearer t", "Content-Type": "application/json" }); });

  await p.evaluate(() => openImpEnCurso());
  await p.waitForFunction(() => /Editar PI/.test((document.getElementById("stkPopBody") || {}).innerHTML || ""), null, { timeout: 10000 });
  const viejo = await p.evaluate(() => /impCursoRenombrar\(/.test(document.getElementById("stkPopBody").innerHTML));
  if (viejo) fail("(a) quedó el botón viejo que renombraba sin registrar quién");

  // (a) el lápiz → ¿quién?
  await p.evaluate(() => { [...document.querySelectorAll("#stkPopBody .imcu-b")].find(x => /Editar PI/.test(x.textContent)).click(); });
  await p.waitForFunction(() => document.querySelectorAll("#impPiEdOv .ipe-ed").length > 0, null, { timeout: 8000 });
  const q = await p.evaluate(() => ({
    txt: document.getElementById("impPiEdOv").innerText,
    eds: [...document.querySelectorAll("#impPiEdOv .ipe-ed")].map(x => x.textContent.trim()),
    otro: !!document.getElementById("impPiEdOtroIn"),
    inputs: document.querySelectorAll("#impPiEdOv .ipe-in").length }));
  if (!/Quién corrige/.test(q.txt)) fail("(a) el pop-up no arranca preguntando quién corrige");
  ["Thomas", "Tomás", "Vivi", "Luis", "Gastón"].forEach(function (n) { if (q.eds.indexOf(n) < 0) fail("(a) falta el editor " + n + ": " + q.eds.join(", ")); });
  if (!q.otro) fail("(a) falta el cuadro «Otro»");
  if (q.inputs) fail("(a) las cantidades se muestran antes de decir quién corrige");

  // (b) elige Vivi → ítems
  await p.evaluate(() => { [...document.querySelectorAll("#impPiEdOv .ipe-ed")].find(x => x.textContent.trim() === "Vivi").click(); });
  await p.waitForFunction(() => document.querySelectorAll("#impPiEdOv .ipe-in").length === 3, null, { timeout: 8000 });
  const ed = await p.evaluate(() => document.getElementById("impPiEdOv").innerText);
  if (!/Corrige:\s*Vivi/.test(ed)) fail("(b) no dice quién corrige");
  if (!/6\.912/.test(ed) || !/1\.224/.test(ed)) fail("(b) no muestra las cantidades actuales");

  // (c) cambia 438E 1224→2520, 438EL 6912→5616; 035E queda vacío (sin cambio)
  await p.fill('#impPiEdOv tr#ipeR77 input.ipe-in', "2520");
  await p.fill('#impPiEdOv tr#ipeR78 input.ipe-in', "5616");
  const tot = await p.evaluate(() => document.getElementById("ipeTotD").textContent);
  if (tot.trim() !== "—") fail("(c) el total debería quedar igual (+1.296 −1.296) y dice " + tot);
  await p.evaluate(() => { [...document.querySelectorAll("#impPiEdOv .ipe-b")].find(x => /Ver cambios/.test(x.textContent)).click(); });
  await p.waitForFunction(() => /Esto es lo que cambia/.test(document.getElementById("impPiEdOv").innerText), null, { timeout: 8000 });
  const sim = llamadas[0] || {};
  if (sim.p_simular !== true) fail("(c) «Ver cambios» no simula (p_simular=" + sim.p_simular + "): escribiría sin mostrar");
  if (sim.p_editor !== "Vivi") fail("(c) no manda el editor: " + sim.p_editor);
  const cs = (sim.p_cambios || []);
  if (cs.length !== 2) fail("(c) manda " + cs.length + " cambios (tenían que ser 2: el ítem que no se tocó no viaja)");
  const c77 = cs.find(c => c.bache_id === 77) || {};
  if (c77.unidades !== 2520 || c77.antes !== 1224) fail("(c) el 438E no viaja con la cantidad nueva y el antes visto: " + JSON.stringify(c77));
  const rv = await p.evaluate(() => document.getElementById("impPiEdOv").innerText);
  if (!/1\.224/.test(rv) || !/2\.520/.test(rv) || !/\+1\.296/.test(rv) || !/−1\.296/.test(rv)) fail("(c) el antes → después no se ve: " + rv.slice(0, 300));

  // (d) guardar
  await p.evaluate(() => { [...document.querySelectorAll("#impPiEdOv .ipe-b")].find(x => /Guardar/.test(x.textContent)).click(); });
  await p.waitForFunction(() => /Guardado/.test(document.getElementById("impPiEdOv").innerText), null, { timeout: 8000 });
  const gd = llamadas[1] || {};
  if (gd.p_simular !== false) fail("(d) «Guardar» no escribe (p_simular=" + gd.p_simular + ")");
  if (gd.p_editor !== "Vivi" || (gd.p_cambios || []).length !== 2) fail("(d) guardó otra cosa que lo revisado: " + JSON.stringify(gd));
  const ok = await p.evaluate(() => document.getElementById("impPiEdOv").innerText);
  if (!/Vivi/.test(ok) || !/\d{2}\/\d{2}\/\d{2}/.test(ok)) fail("(d) el cartel de guardado no dice quién y cuándo");
  await p.evaluate(() => impPiEdCerrar());

  // (e) «Otro»
  llamadas.length = 0;
  await p.evaluate((r) => impPiEditar(encodeURIComponent(r), "Fujian"), REF);
  await p.waitForFunction(() => !!document.getElementById("impPiEdOtroIn"), null, { timeout: 8000 });
  await p.fill("#impPiEdOtroIn", "Marianela");
  await p.evaluate(() => impPiEdOtro());
  await p.waitForFunction(() => document.querySelectorAll("#impPiEdOv .ipe-in").length === 3, null, { timeout: 8000 });
  await p.fill('#impPiEdOv tr#ipeR82 input.ipe-in', "2208");
  await p.evaluate(() => impPiEdRevisar());
  await p.waitForFunction(() => /editor nuevo/.test(document.getElementById("impPiEdOv").innerText), null, { timeout: 8000 });
  if ((llamadas[0] || {}).p_editor !== "Marianela") fail("(e) «Otro» no manda el nombre tipeado: " + JSON.stringify(llamadas[0]));

  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("✓ editar PI: quién → cantidades → antes/después simulado → guardar con editor y hora");
})().catch((e) => { console.error(e); process.exit(1); });
