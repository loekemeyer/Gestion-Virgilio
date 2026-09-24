/* v22.23 (Luis, 24/09) — switch «Web» por importado en Pedidos Importación, al lado de
   «Cartel web». OFF = el artículo se oculta de la página LK (GV_Web_Oculto → LK pone
   products.active=false). Se corre la pantalla de verdad:
   (a) cargada la lista, 599E sale OCULTO y 505E visible (0599E también es 599E);
   (b) ocultar 505E pide confirmación y manda gv_web_oculto_set {p_cod:'505E', p_visible:false}
       con el header de supervisor; si se cancela la confirmación, no manda nada;
   (c) sin sesión no manda nada;
   (d) si la RPC de la lista falla, el switch Web no se dibuja y el de Cartel web sigue.
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
  const sets = []; let listaFalla = false;
  await p.route("**/rest/v1/**", async (r) => {
    const u = r.request().url();
    if (u.includes("/rpc/gv_reingreso_excluidos")) return r.fulfill({ status: 200, contentType: "application/json", body: "[]" });
    if (u.includes("/rpc/gv_web_ocultos")) return listaFalla ? r.fulfill({ status: 500, body: "x" }) : r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify([{ cod: "599E" }]) });
    if (u.includes("/rpc/gv_web_oculto_set")) { sets.push({ body: r.request().postDataJSON(), auth: r.request().headers()["authorization"] }); return r.fulfill({ status: 200, contentType: "application/json", body: "false" }); }
    return r.fulfill({ status: 200, contentType: "application/json", body: "[]" });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const it = (cod) => ({ cod, desc: "art " + cod, prov: "X", proyUni: 10, objetivoUni: 0, stockUni: 0, enCurso: 0, aPedirUni: 100, aPedirCajas: 10, uniMaster: 10, det: [{ id: 1, curso: 0, marca: "" }] });
  await p.evaluate((items) => {
    _reingExcl = null; _reingExclCargando = true;
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items: items, meses: 10 }, soloPedir: false, mcOverride: {} };
    _reingExclCargando = false;
  }, [it("0599E"), it("505E")]);
  await p.evaluate(() => _reingExclCargar());
  const est = () => p.evaluate(() => [...document.querySelectorAll(".mva-tbl.wide tbody tr")].map((tr) => {
    const c = tr.querySelector("input[onchange*=pedImpWebVisible]");
    const cw = tr.querySelector("input[onchange*=pedImpReingresoWeb]");
    return tr.cells[0].textContent.trim().slice(0, 5).replace(/^0+/, "") + "=" + (c ? (c.checked ? "vis" : "OCU") : "-") + (cw ? "" : "!sinCartel");
  }));
  const a1 = await est();
  if (a1.join() !== "599E=OCU,505E=vis") fail("(a) esperaba 599E=OCU,505E=vis y dio " + a1.join());
  await p.evaluate(() => { facAuthWriteHeaders = async (h) => Object.assign({ apikey: "k", Authorization: "Bearer SUP" }, h || {}); window.confirm = () => false; });
  await p.evaluate(() => pedImpWebVisible(encodeURIComponent("505E"), false));
  if (sets.length) fail("(b) cancelando la confirmación igual mandó: " + JSON.stringify(sets));
  await p.evaluate(() => { window.confirm = () => true; });
  await p.evaluate(() => pedImpWebVisible(encodeURIComponent("505E"), false));
  const b1 = await est();
  if (sets.length !== 1 || sets[0].body.p_cod !== "505E" || sets[0].body.p_visible !== false) fail("(b) request: " + JSON.stringify(sets));
  else if (sets[0].auth !== "Bearer SUP") fail("(b) no fue con el header de supervisor: " + sets[0].auth);
  if (b1.join() !== "599E=OCU,505E=OCU") fail("(b) tras ocultar dio " + b1.join());
  await p.evaluate(() => { facAuthWriteHeaders = async () => null; window.alert = () => {}; });
  await p.evaluate(() => pedImpWebVisible(encodeURIComponent("599E"), true));
  if (sets.length !== 1) fail("(c) sin sesión igual mandó el cambio");
  listaFalla = true;
  await p.evaluate(() => { _reingExcl = null; return _reingExclCargar(); });
  const d1 = await est();
  if (d1.join() !== "599E=-,505E=-") fail("(d) con la lista caída esperaba sin switch Web y con Cartel web; dio " + d1.join());
  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("pedimp-web-visible: OK — " + a1.join() + " → " + b1.join());
})();
