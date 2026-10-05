/* v26.98 (Luis, 05/10) — Pedidos Importación → solapa «➕ Agregar artículo»: pide código, medidas MC e
   inner, uni × inner, uni × MC, FOB, descripción, MOQ y proveedor, y deja ajustar A MANO el primer pedido.
   Se corre la pantalla de verdad con la base mockeada:
   (a) la solapa existe y abre el formulario con todos los campos
   (b) el primer pedido sugerido = MOQ en MC enteras; tocarlo a mano recalcula unidades y FOB
   (c) «Dar de alta» llama a gv_importado_alta con lo cargado (primer pedido en UNIDADES)
   (d) gv_importado_alta va con la sesión (_PED_IMP_RPC_ESCRITURA)
   (e) 📦 Pedidos toma el primer pedido a mano mientras no haya en curso, y el MOQ propio del artículo
   Sale 1 si falla. */
const path = require("path"), fs = require("fs");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
const llamadas = [];

(async () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "importacion.js"), "utf8");
  const lista = (src.match(/const _PED_IMP_RPC_ESCRITURA = \[([\s\S]*?)\];/) || [])[1] || "";
  if (lista.indexOf('"gv_importado_alta"') < 0) fail("(d) gv_importado_alta no está en _PED_IMP_RPC_ESCRITURA");

  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", async (r) => {
    const u = r.request().url();
    let body = "[]";
    if (/gv_imp_proveedor_cfg/.test(u)) body = JSON.stringify([{ proveedor: "Fujian", moq: 1000, activo: true, orden: 1 }, { proveedor: "Becky", moq: 500, activo: true, orden: 2 }]);
    else if (/rpc\/gv_importado_alta/.test(u)) {
      const pd = JSON.parse(r.request().postData() || "{}"); llamadas.push(pd.p);
      body = JSON.stringify({ ok: true, id: 900, cod: pd.p.cod });
    }
    await r.fulfill({ status: 200, contentType: "application/json", body });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  await p.waitForFunction(() => typeof openImpAgregar === "function" && typeof _pedImpMcOf === "function", null, { timeout: 15000 });
  await p.evaluate(() => { window.facAuthWriteHeaders = async () => ({ apikey: "k", Authorization: "Bearer t", "Content-Type": "application/json" }); window.confirm = () => true; });

  // (a)
  const tab = await p.evaluate(() => /openImpAgregar\(\)/.test(_impTabsHtml("ped")));
  if (!tab) fail("(a) la solapa ➕ Agregar artículo no está en las solapas de importación");
  await p.evaluate(() => { _impAlta = null; return openImpAgregar(); });
  await p.waitForSelector("#impAltaF", { timeout: 8000 });
  const ks = await p.evaluate(() => [...document.querySelectorAll("#impAltaF [data-k]")].map(e => e.getAttribute("data-k")));
  ["cod", "marca", "proveedor", "descripcion", "mc_largo", "mc_ancho", "mc_alto", "in_largo", "in_ancho", "in_alto", "uni_inner", "uni_mc", "fob", "moq", "mc"]
    .forEach(function (k) { if (ks.indexOf(k) < 0) fail("(a) falta el campo " + k); });
  const sinTeclado = await p.evaluate(() => ["uni_inner", "uni_mc", "fob", "moq", "mc", "mc_largo"].filter(k => !document.querySelector('#impAltaF [data-k="' + k + '"]').getAttribute("inputmode")));
  if (sinTeclado.length) fail("(a) sin teclado numérico: " + sinTeclado.join(", "));

  // (b) cargar
  const set = async (k, v) => { await p.evaluate(([k, v]) => { const e = document.querySelector('#impAltaF [data-k="' + k + '"]'); e.value = v; e.dispatchEvent(new Event(e.tagName === "SELECT" ? "change" : "input")); }, [k, v]); };
  await set("cod", "999e"); await set("proveedor", "Fujian"); await set("descripcion", "Colador prueba");
  await set("mc_largo", "60"); await set("mc_ancho", "40"); await set("mc_alto", "30");
  await set("in_largo", "20"); await set("in_ancho", "10"); await set("in_alto", "10");
  await set("uni_inner", "12"); await set("uni_mc", "144"); await set("fob", "1,25");
  const sug = await p.evaluate(() => document.querySelector('#impAltaF [data-k="mc"]').value);
  if (sug !== "7") fail("(b) MC sugerido = ceil(1.000 / 144) = 7, dio " + sug);
  await set("moq", "2000");
  const sug2 = await p.evaluate(() => document.querySelector('#impAltaF [data-k="mc"]').value);
  if (sug2 !== "14") fail("(b) con MOQ propio 2.000 el sugerido = 14 MC, dio " + sug2);
  await p.evaluate(() => { _impAlta.mcTocado = true; });
  await set("mc", "10");
  const txt = await p.evaluate(() => document.getElementById("impAltaF").innerText);
  if (!/1\.440/.test(txt)) fail("(b) 10 MC × 144 = 1.440 u no aparece");
  if (!/1\.800,00/.test(txt)) fail("(b) FOB 1.440 × 1,25 = 1.800,00 no aparece");

  // (c)
  await p.evaluate(() => impAltaGuardar());
  await p.waitForFunction(() => /quedó en el maestro/.test(document.getElementById("stkPopBody").innerText), null, { timeout: 8000 });
  const c = llamadas[0] || {};
  const esp = { cod: "999E", marca: "LK", proveedor: "Fujian", fob: 1.25, uni_mc: 144, uni_inner: 12, moq: 2000, primer_pedido_u: 1440, mc_largo: 60, in_alto: 10 };
  Object.keys(esp).forEach(function (k) { if (c[k] !== esp[k]) fail("(c) " + k + " = " + JSON.stringify(c[k]) + ", esperaba " + esp[k]); });

  // (e)
  const e = await p.evaluate(() => {
    _stkPop = { kind: "pedImp" };
    const base = { cod: "999E", prov: "Fujian", uniMaster: 144, uxc: 12, aPedirCajas: 0, aPedirUni: 0, proyUni: 0, enCurso: 0, primerPedidoU: 1440 };
    const conCurso = Object.assign({}, base, { enCurso: 1440 });
    const moq = Object.assign({}, base, { primerPedidoU: 0, aPedirCajas: 1, proyUni: 500, stockUni: 0, moqArt: 2880 });
    return { mc: _pedImpMcOf(base), curso: _pedImpMcOf(conCurso), moq: _pedImpMoqCalc(moq).moq };
  });
  if (e.mc !== 10) fail("(e) con primer pedido a mano 1.440 u (144 por MC) tiene que pedir 10 MC, dio " + e.mc);
  if (e.curso !== 0) fail("(e) con pedido en curso el primer pedido a mano ya no cuenta, dio " + e.curso);
  if (e.moq !== 2880) fail("(e) el MOQ propio del artículo tiene que ganarle al del proveedor, dio " + e.moq);

  if (errs.length) fail("errores en la página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("✓ imp-agregar-articulo");
})().catch((e) => { console.error(e); process.exit(1); });
