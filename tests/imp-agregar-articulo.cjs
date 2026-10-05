/* v26.98 (Luis, 05/10) — Pedidos Importación → solapa «➕ Agregar artículo»: pide código, medidas MC e
   inner, uni × inner, uni × MC, FOB, descripción, MOQ y proveedor, y deja ajustar A MANO el primer pedido.
   Se corre la pantalla de verdad con la base mockeada:
   (a) la solapa existe y abre el formulario con todos los campos
   (b) el primer pedido sugerido = MOQ en MC enteras; tocarlo a mano recalcula unidades y FOB
   (c) «Dar de alta» llama a gv_importado_alta con lo cargado (primer pedido en UNIDADES)
   (d) gv_importado_alta va con la sesión (_PED_IMP_RPC_ESCRITURA)
   (e) 📦 Pedidos toma el primer pedido a mano mientras no haya en curso, y el MOQ propio del artículo
   v26.99 — «Agregar o modificar producto»:
   (f) el alta manda también tipo, familia, INAL, góndola y secundario (gv_importado_guardar)
   (g) MODIFICAR: se elige un importado, se cargan sus datos de la ficha, el código y la empresa no se
       editan, y guardar manda su id; sacarle el INAL o el secundario lo dice antes de guardar
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
  ["gv_importado_alta", "gv_importado_guardar", "gv_importado_ficha"].forEach(function (n) { if (lista.indexOf('"' + n + '"') < 0) fail("(d) " + n + " no está en _PED_IMP_RPC_ESCRITURA"); });

  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", async (r) => {
    const u = r.request().url();
    let body = "[]";
    if (/gv_imp_proveedor_cfg/.test(u)) body = JSON.stringify([{ proveedor: "Fujian", moq: 1000, activo: true, orden: 1 }, { proveedor: "Becky", moq: 500, activo: true, orden: 2 }]);
    else if (/rpc\/gv_importado_guardar/.test(u)) {
      const pd = JSON.parse(r.request().postData() || "{}"); llamadas.push(pd.p);
      body = JSON.stringify({ ok: true, alta: !pd.p.id, id: pd.p.id || 900, cod: pd.p.cod, hechos: ["maestro", "volumen", "uxb", "oc", "tipo", "gondola", "stock"] });
    }
    else if (/rpc\/gv_importado_ficha/.test(u)) {
      const pd = JSON.parse(r.request().postData() || "{}");
      body = JSON.stringify(pd.p_id ? { art: { id: 63, cod: "438E", marca: "CH", proveedor: "Fujian", descripcion: "Colador 20cm", fob: 0.5, moq: null, primer_pedido_u: null,
        uni_mc: 24, uni_inner: 6, mc_largo: 50, mc_ancho: 30, mc_alto: 40, tipo: "Colador Ø 20 cm", familia: "Coladores", inal: true, inal_propio: true,
        inal_certificado: "RNPA-9", inal_vence: "2027-01-01", secundario_de: "026", gondolas: [{ sector: "M14", cap: 30 }], en_curso: 1224 } }
        : { tipos: ["Colador Ø 8 cm", "Colador Ø 20 cm"], familias: ["Coladores"] });
    }
    else if (/\/rest\/v1\/Importados\?/.test(u) && /select=id,cod_art/.test(u)) body = JSON.stringify([{ id: 63, cod_art: "438E", marca: "CH", descripcion: "Colador 20cm", proveedor: "Fujian", activo: true }]);
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
  await set("tipo", "Colador prueba"); await set("familia", "Coladores"); await set("gondola_sector", "A60"); await set("gondola_cap", "20");
  await p.evaluate(() => { const e = document.querySelector('#impAltaF [data-k="inal"]'); e.checked = true; e.dispatchEvent(new Event("change")); });
  await set("inal_certificado", "RNPA-1");
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
  await p.waitForFunction(() => /quedó dado de alta|No se guardó/.test(document.getElementById("stkPopBody").innerText), null, { timeout: 8000 });
  { const t = await p.evaluate(() => document.getElementById("stkPopBody").innerText); if (/No se guardó/.test(t)) fail("(c) " + t.slice(t.indexOf("No se guardó"), t.indexOf("No se guardó") + 200)); }
  const c = llamadas[0] || {};
  const esp = { id: null, cod: "999E", marca: "LK", proveedor: "Fujian", fob: 1.25, uni_mc: 144, uni_inner: 12, moq: 2000, primer_pedido_u: 1440, mc_largo: 60, in_alto: 10,
    tipo: "Colador prueba", familia: "Coladores", inal: true, inal_certificado: "RNPA-1", gondola_sector: "A60", gondola_cap: 20 };
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

  // (g) modificar
  await p.evaluate(() => impAltaModo("mod"));
  await p.waitForSelector("#impAltaBusq", { timeout: 5000 });
  await p.evaluate(() => impAltaElegir("438E · CH · Colador 20cm"));
  await p.waitForFunction(() => { const e = document.querySelector('#impAltaF [data-k="fob"]'); return e && e.value === "0,5"; }, null, { timeout: 8000 });
  const g = await p.evaluate(() => ({ cod: !!document.querySelector('#impAltaF [data-k="cod"]'), marca: !!document.querySelector('#impAltaF [data-k="marca"]'),
    tipo: document.querySelector('#impAltaF [data-k="tipo"]').value, txt: document.getElementById("impAltaF").innerText, sec: document.querySelector('#impAltaF [data-k="secundario_de"]').value }));
  if (g.cod || g.marca) fail("(g) al modificar el código y la empresa no se editan");
  if (g.tipo !== "Colador Ø 20 cm" || g.sec !== "026") fail("(g) no cargó tipo/secundario de la ficha: " + g.tipo + " / " + g.sec);
  if (!/M14/.test(g.txt)) fail("(g) no muestra la góndola actual");
  if (!/1\.224 u en curso/.test(g.txt)) fail("(g) no avisa que ya tiene pedido en curso");
  let dialogo = "";
  await p.evaluate(() => { window.confirm = (m) => { window.__dlg = m; return true; }; });
  await set("fob", "0,6"); await set("secundario_de", "");
  await p.evaluate(() => { const e = document.querySelector('#impAltaF [data-k="inal"]'); e.checked = false; e.dispatchEvent(new Event("change")); });
  await p.evaluate(() => impAltaGuardar());
  await p.waitForFunction(() => /quedó modificado/.test(document.getElementById("stkPopBody").innerText), null, { timeout: 8000 });
  dialogo = await p.evaluate(() => window.__dlg || "");
  const m = llamadas[1] || {};
  if (m.id !== 63 || m.fob !== 0.6 || m.inal !== false || m.secundario_de_quitar !== true) fail("(g) el guardado no mandó id/fob/inal/secundario: " + JSON.stringify(m));
  if (!/se borra su certificado/.test(dialogo) || !/Deja de ser secundario de 026/.test(dialogo)) fail("(g) no avisa que se saca el INAL y el secundario: " + dialogo);

  if (errs.length) fail("errores en la página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("✓ imp-agregar-articulo");
})().catch((e) => { console.error(e); process.exit(1); });
