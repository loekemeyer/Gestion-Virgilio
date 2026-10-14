/* v30.44 (Luis, 14/10) — ✏️ EDITAR PI: «que haya un botón que permita agregar artículos al pedido».
   Caso real: PI OL-10139 (Ownland) quedó sin el 811E.
   Se corre la pantalla de verdad con la base mockeada:
   (a) en el paso de cantidades está «➕ Agregar artículo a la PI»
   (b) el buscador ofrece primero los del proveedor de la PI y NO ofrece lo que ya está en la PI
   (c) elegido el 811E aparece como renglón «nuevo», avisa las u por master y el total suma lo que se agrega
   (d) sin cantidad no deja revisar; con cantidad, «Ver cambios» manda {agregar, importado_id, unidades}
       SIN bache_id, simulado, y el antes → después lo muestra como «nuevo»
   (e) «Guardar» manda lo mismo con p_simular=false
   (f) ✕ saca el renglón agregado antes de guardar
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };

const REF = "PI OL-10139";
const CURSO = [{ pedido_ref: REF, proveedor: "Ownland", n_lineas: 2, unidades: 7584, pendiente: 7584, usd: 4000, m3: 5,
  fecha_embarque: "2026-11-08", fecha_llegada: "2026-12-18" }];
const LINEAS = [
  { bache_id: 92, importado_id: 101, cod_art: "816E", marca: "LK", descripcion: "Pelador V", unidades: 6144, pendiente: 6144, fob_uni: 0.49, usd: 3010, m3: 2 },
  { bache_id: 91, importado_id: 102, cod_art: "817E", marca: "LK", descripcion: "Rallador", unidades: 1440, pendiente: 1440, fob_uni: 0.7, usd: 1008, m3: 1 }
];
const MAESTRO = [
  { id: 26, cod_art: "026", marca: "LK", descripcion: "Colador", proveedor: "Fujian", activo: true },
  { id: 99, cod_art: "811E", marca: "LK", descripcion: "Corta Pizza C/Mgo Ergonomico", proveedor: "Ownland", activo: true },
  { id: 101, cod_art: "816E", marca: "LK", descripcion: "Pelador V", proveedor: "Ownland", activo: true },
  { id: 102, cod_art: "817E", marca: "LK", descripcion: "Rallador", proveedor: "Ownland", activo: true },
  { id: 98, cod_art: "813E", marca: "LK", descripcion: "Afila Cuchillo", proveedor: "Ownland", activo: false }
];
const VOL = [{ cod: "811E", uni_master: 96 }, { cod: "816E", uni_master: 96 }];
const llamadas = [];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", async (r) => {
    const u = r.request().url();
    let body = "[]";
    const pd = (() => { try { return JSON.parse(r.request().postData() || "null"); } catch (_e) { return null; } })();
    if (/rpc\/gv_importados_pedidos_curso/.test(u)) body = JSON.stringify(CURSO);
    else if (/rpc\/gv_imp_pi_editores/.test(u)) body = JSON.stringify([{ nombre: "Luis" }, { nombre: "Vivi" }]);
    else if (/rpc\/gv_importado_pedido_lineas/.test(u)) body = JSON.stringify(LINEAS);
    else if (/rpc\/gv_imp_pi_ediciones/.test(u)) body = "[]";
    else if (/\/rest\/v1\/Importados_Volumen/.test(u)) body = JSON.stringify(VOL);
    else if (/\/rest\/v1\/Importados\?/.test(u)) body = JSON.stringify(MAESTRO);
    else if (/rpc\/gv_imp_pi_editar/.test(u)) {
      llamadas.push(pd);
      const filas = (pd.p_cambios || []).map(function (c) {
        if (c.agregar) { const m = MAESTRO.find(x => x.id === c.importado_id);
          return { bache_id: pd.p_simular ? null : 500, cod_art: m.cod_art, marca: m.marca, antes: 0, despues: c.unidades, delta: c.unidades, sale: false, nuevo: true }; }
        const l = LINEAS.find(x => x.bache_id === c.bache_id);
        return { bache_id: c.bache_id, cod_art: l.cod_art, marca: l.marca, antes: c.antes, despues: c.unidades, delta: c.unidades - c.antes, sale: c.unidades === 0 };
      });
      const tA = 7584, tD = tA + filas.reduce((s, f) => s + f.delta, 0);
      body = JSON.stringify({ simulado: pd.p_simular, ts: "2026-10-14T18:00:00Z", editor: pd.p_editor, editor_nuevo: false,
        pedido_ref: REF, ref_nuevo: null, cambios: filas.length, filas, total_antes: tA, total_despues: tD });
    }
    await r.fulfill({ status: 200, contentType: "application/json", body });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  await p.waitForFunction(() => typeof impPiEditar === "function", null, { timeout: 15000 });
  await p.evaluate(() => { window.facAuthWriteHeaders = async () => ({ apikey: "k", Authorization: "Bearer t", "Content-Type": "application/json" }); });

  await p.evaluate((r) => impPiEditar(encodeURIComponent(r), "Ownland"), REF);
  await p.waitForFunction(() => document.querySelectorAll("#impPiEdOv .ipe-ed").length > 0, null, { timeout: 8000 });
  await p.evaluate(() => { [...document.querySelectorAll("#impPiEdOv .ipe-ed")].find(x => x.textContent.trim() === "Luis").click(); });
  await p.waitForFunction(() => document.querySelectorAll("#impPiEdOv .ipe-in").length === 2, null, { timeout: 8000 });

  // (a)
  const btn = await p.evaluate(() => !![...document.querySelectorAll("#impPiEdOv .ipe-b")].find(x => /Agregar artículo/.test(x.textContent)));
  if (!btn) fail("(a) no está el botón «➕ Agregar artículo a la PI»");
  await p.evaluate(() => impPiEdAgrToggle());
  await p.waitForFunction(() => document.querySelectorAll("#ipeAgrDl option").length > 0, null, { timeout: 8000 });

  // (b)
  const ops = await p.evaluate(() => [...document.querySelectorAll("#ipeAgrDl option")].map(o => o.value));
  if (!/^811E/.test(ops[0] || "")) fail("(b) el primero no es del proveedor de la PI: " + ops.join(" | "));
  if (ops.some(o => /^816E|^817E/.test(o))) fail("(b) ofrece un artículo que ya está en la PI");
  if (ops.some(o => /^813E/.test(o))) fail("(b) ofrece un artículo inactivo");
  if (!ops.some(o => /^026/.test(o))) fail("(b) no ofrece los de otro proveedor (al final)");

  // (c)
  await p.evaluate((v) => impPiEdAgrElegir(v), ops[0]);
  await p.waitForFunction(() => document.querySelectorAll("#impPiEdOv tr.nuevo").length === 1, null, { timeout: 8000 });
  const t1 = await p.evaluate(() => document.getElementById("impPiEdOv").innerText);
  if (!/96 u por master/.test(t1)) fail("(c) no avisa las u por master del 811E");

  // (d) sin cantidad
  await p.evaluate(() => impPiEdRevisar());
  const t2 = await p.evaluate(() => document.getElementById("impPiEdOv").innerText);
  if (!/Poné la cantidad del 811E/.test(t2)) fail("(d) deja revisar un agregado sin cantidad");
  if (llamadas.length) fail("(d) llamó a la base con un agregado sin cantidad");
  await p.fill("#impPiEdOv tr.nuevo input.ipe-in", "2880");
  const tot = await p.evaluate(() => document.getElementById("ipeTotN").textContent.trim());
  if (tot !== "10.464") fail("(c) el total no suma lo agregado: " + tot);
  await p.evaluate(() => impPiEdRevisar());
  await p.waitForFunction(() => /Esto es lo que cambia/.test(document.getElementById("impPiEdOv").innerText), null, { timeout: 8000 });
  const sim = llamadas[0] || {};
  const ag = (sim.p_cambios || []).find(c => c.agregar) || {};
  if (sim.p_simular !== true) fail("(d) no simula");
  if (ag.importado_id !== 99 || ag.unidades !== 2880 || ag.bache_id != null) fail("(d) el agregado no viaja bien: " + JSON.stringify(sim.p_cambios));
  if ((sim.p_cambios || []).length !== 1) fail("(d) viajan renglones que no se tocaron: " + JSON.stringify(sim.p_cambios));
  const rv = await p.evaluate(() => document.getElementById("impPiEdOv").innerText);
  if (!/811E/.test(rv) || !/nuevo/.test(rv) || !/2\.880/.test(rv)) fail("(d) el antes → después no muestra el nuevo: " + rv.slice(0, 300));

  // (e)
  await p.evaluate(() => impPiEdGuardar());
  await p.waitForFunction(() => /Guardado/.test(document.getElementById("impPiEdOv").innerText), null, { timeout: 8000 });
  const gd = llamadas[1] || {};
  if (gd.p_simular !== false || !((gd.p_cambios || [])[0] || {}).agregar) fail("(e) «Guardar» no manda el agregado: " + JSON.stringify(gd));
  await p.evaluate(() => impPiEdCerrar());

  // (f) ✕ saca el renglón
  await p.evaluate((r) => impPiEditar(encodeURIComponent(r), "Ownland"), REF);
  await p.waitForFunction(() => document.querySelectorAll("#impPiEdOv .ipe-ed").length > 0, null, { timeout: 8000 });
  await p.evaluate(() => impPiEdQuien("Luis"));
  await p.waitForFunction(() => document.querySelectorAll("#impPiEdOv .ipe-in").length === 2, null, { timeout: 8000 });
  await p.evaluate(() => impPiEdAgrToggle());
  await p.waitForFunction(() => document.querySelectorAll("#ipeAgrDl option").length > 0, null, { timeout: 8000 });
  await p.evaluate(() => impPiEdAgrElegir("811E"));
  await p.waitForFunction(() => document.querySelectorAll("#impPiEdOv tr.nuevo").length === 1, null, { timeout: 8000 });
  await p.evaluate(() => document.querySelector("#impPiEdOv tr.nuevo .ipe-q-x").click());
  const quedan = await p.evaluate(() => document.querySelectorAll("#impPiEdOv tr.nuevo").length);
  if (quedan) fail("(f) el ✕ no saca el renglón agregado");

  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("✓ editar PI: ➕ agregar artículo (del proveedor primero, sin duplicar, simulado → guardado)");
})().catch((e) => { console.error(e); process.exit(1); });
