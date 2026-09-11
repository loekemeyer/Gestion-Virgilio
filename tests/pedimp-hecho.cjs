/* v14.78 — "Cargar pedido ya hecho" (Pedidos Importación) ahora es UN pop-up: proveedor + fecha
   de entrega + renglones de dos maneras (elegir de la lista / escribir código y unidades), con
   la reconversión de unidades a cajas y master cajas en vivo. Se verifica el render, la
   conversión, el parseo del texto y lo que se manda a Supabase al guardar. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  // v15.40: sin este fallback el test muere en CI (el runner instala playwright con npm,
  // no tiene /opt/node22) y, como run.sh corta en el primero que falla, todo lo que venía
  // después NUNCA se corrió en GitHub. Mismo patrón que ya tenían los demás tests.
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1100, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const it = (cod, prov, uxc, um, id, curso) => ({ cod, desc: "art " + cod, prov, uxc, uniMaster: um, aPedirUni: 0, aPedirCajas: 0, det: [{ id, marca: "", prov, curso, uxc }] });
    _stkPop = { kind: "pedImp", data: { items: [it("505C", "Frontier", 500, 4000, 11, 100), it("026", "Frontier", 100, 1000, 12, 0), it("584E", "Kangli", 60, 600, 13, 0)], meses: 10, entregaGlobal: "" }, soloPedir: true };
    pedImpCargarPedidoHecho();
    out.abre = document.getElementById("pedHechoOv").classList.contains("show");
    out.provs = [...document.querySelectorAll("#pedHechoOv select option")].map((o) => o.value);
    out.sinProv = document.getElementById("phCuerpo").innerText.indexOf("proveedor") >= 0;

    // (1) elegir de la lista: sólo los del proveedor elegido
    pedHechoSetProv("Frontier");
    out.codsLista = [...document.querySelectorAll("#phTabla .phc-cod")].map((e) => e.textContent);
    // unidades → cajas y master cajas
    pedHechoSetUni(encodeURIComponent("505C"), "132000", 1);
    out.cj = document.getElementById("phCj1").textContent.trim();
    out.mc = document.getElementById("phMc1").textContent.trim();
    out.pie = document.getElementById("phFoot").innerText.replace(/\s+/g, " ");
    // no entra justo → ⚠
    pedHechoSetUni(encodeURIComponent("026"), "1500", 0);
    out.mcRaro = document.getElementById("phMc0").textContent.trim();
    pedHechoSetUni(encodeURIComponent("026"), "", 0);

    // (2) escribir código y unidades (incluye un código inexistente)
    pedHechoSetModo("texto");
    pedHechoSetTexto("505C 8000\n584E, 1200\n999 5");
    out.prev = [...document.querySelectorAll("#phPrev tbody tr")].map((tr) => tr.innerText.replace(/\s+/g, " ").trim());
    out.pieTxt = document.getElementById("phFoot").innerText.replace(/\s+/g, " ");

    // guardar: se interceptan RPC y PATCH
    const calls = [];
    window.confirm = () => true; window.alert = (m) => { out.alert = m; };
    window.fetch = async (u, o) => { calls.push({ u: String(u), m: (o && o.method) || "GET", b: o && o.body }); return { ok: true, status: 200, json: async () => null, text: async () => "" }; };
    _pedHecho.fecha = "2026-11-20";
    pedHechoSetRef("PI TEST-1");
    pedHechoSetEmbarque("2026-10-05");
    out.refYEmb = [_pedHecho.ref, _pedHecho.embarque];
    await pedHechoGuardar();
    out.calls = calls.map((c) => ({ u: c.u.split("/rest/v1/")[1], m: c.m, b: c.b }));
    out.cerro = !document.getElementById("pedHechoOv").classList.contains("show");
    return out;
  });

  console.log(JSON.stringify(r, null, 1));
  if (!r.abre) fail("no abre el pop-up");
  if (!r.sinProv) fail("sin proveedor no pide elegirlo");
  if (r.provs.join("|") !== "|Frontier|Kangli") fail("proveedores mal: " + r.provs);
  if (r.codsLista.join("|") !== "026|505C") fail("la lista no filtra por proveedor: " + r.codsLista);
  if (r.cj !== "264") fail("cajas mal (132000/500 = 264): " + r.cj);
  if (r.mc !== "33") fail("master cajas mal (132000/4000 = 33): " + r.mc);
  if (!/1 artículo/.test(r.pie) || !/132.000/.test(r.pie)) fail("pie mal: " + r.pie);
  if (!/⚠/.test(r.mcRaro)) fail("1500/1000 debería avisar que no entra justo: " + r.mcRaro);
  if (r.prev.length !== 3 || !/no está en importados/.test(r.prev[2])) fail("preview del texto mal: " + JSON.stringify(r.prev));
  if (!/2 artículo/.test(r.pieTxt) || !/9.200/.test(r.pieTxt)) fail("pie del modo texto mal: " + r.pieTxt);
  // v14.94: cada carga es UN BACHE nuevo (no se pisa el "en curso" con importados_set_curso), y la
  // fecha viaja en el propio bache — ya no hay PATCH a Importados.reingreso_est.
  // v15.72: además van el PI del pedido (p_ref) y la fecha de embarque (p_embarque).
  const rpc = r.calls.filter((c) => c.u.indexOf("rpc/gv_importado_bache_add") === 0);
  if (rpc.length !== 2) fail("deberían ser 2 altas de bache: " + JSON.stringify(r.calls));
  else {
    const b0 = JSON.parse(rpc[0].b), b1 = JSON.parse(rpc[1].b);
    if (b0.p_unidades !== 8000) fail("505C: el bache es de 8000 u (no acumula el en curso), vino " + rpc[0].b);
    if (b1.p_unidades !== 1200) fail("584E: el bache es de 1200 u, vino " + rpc[1].b);
    if (b0.p_fecha !== "2026-11-20") fail("la fecha de llegada no viaja en el bache: " + rpc[0].b);
    if (b0.p_ref !== "PI TEST-1") fail("el PI del pedido no viaja: " + rpc[0].b);
    if (b0.p_embarque !== "2026-10-05") fail("la fecha de embarque no viaja: " + rpc[0].b);
  }
  if (r.calls.some((c) => c.m === "PATCH")) fail("ya no debería haber PATCH a Importados: " + JSON.stringify(r.calls));
  if (!r.cerro) fail("no cerró el pop-up al guardar");
  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("✓ pedimp-hecho OK");
})();
