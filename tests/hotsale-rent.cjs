/* v25.91 · v25.93 — Hot Sale: rentabilidad ponderada del período (Thomas, 01/10/2026).
   Corre la pantalla de verdad (hotsale.js dentro de index.html) y mide:
     (a) el botón está en los secundarios del panel supervisor y abre el overlay con los 6 datos
         de la planilla de Thomas (HotSale %, Semanas HotSale, Rent c/AP, Rent Pta Pta, Semanas a
         Ponderar, cuánto más se vende);
     (b) la planilla de 4 semanas (100 % · 20 % · 2 HS · ×2) da 73 % y la de 16 semanas 91 %
         — porcentajes SIN decimales (Thomas, 01/10);
     (c) el ítem real (recibo 922, costo 986 → −6,49 %, 12 sem) da −12 %: la rentabilidad
         negativa se admite;
     (d) importados y nacionales salen por separado (los defaults de la planilla: 65 % y 4 %);
     (e) semanas de hot sale > semanas a ponderar → aviso y la tabla se vacía;
     (f) el botón Cerrar no hereda el button{width:100%} global (regla v23.93 / v23.98);
     (g) hsCalc es pura y el costo no entra;
     (h) a 390 px (celular) la tabla de resultados entra entera, sin cortar Nacionales;
     (i) el bloque de datos NO es ancho: a 1400 px mide menos de 640 px («está muy ancho lo de arriba»);
     (j) modo POR SÚPER: esconde las dos rent. generales, pide el súper, lista lo que compró ordenado
         por última compra (dd/mm/yy), y al cargar la rent. de cada ítem da el promedio por FAMILIA
         (imp/nac, ponderado por cajas) y por RUBRO, con su hot sale y su ponderada;
     (k) las rent. tipeadas quedan guardadas por súper (localStorage) y vuelven al reabrir;
     (l) una lista de súpers vacía NO se dibuja como «no hay súpers»: dice que falta la sesión.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

const SUPERS = [
  { super_key: "inc", nombre: "Carrefour", codigos: [{ empresa: "chef", cod: "1087" }, { empresa: "lk", cod: "1651" }], ultima_compra: "2026-09-30" },
  { super_key: "cencosud", nombre: "Jumbo", codigos: [{ empresa: "chef", cod: "2444" }], ultima_compra: "2026-09-16" }
];
const ITEMS = [
  { empresa: "lk", cod: "026", cod_base: "26", descripcion: "Colador 8 cm", es_importado: true, rubro: "Coladores", tipo: "Colador Ø 8 cm", ultima_compra: "2026-09-30", cajas: 100, unidades: 1200, lineas: 10 },
  { empresa: "lk", cod: "501", cod_base: "501", descripcion: "Cuchillo de untar", es_importado: false, rubro: "Utensilios", tipo: null, ultima_compra: "2026-09-30", cajas: 200, unidades: 4800, lineas: 20 },
  { empresa: "chef", cod: "702EL", cod_base: "702E", descripcion: "Sacacorchos de dos tiempos", es_importado: true, rubro: "Sacacorchos", tipo: null, ultima_compra: "2026-08-12", cajas: 300, unidades: 3600, lineas: 7 },
  { empresa: "lk", cod: "513", cod_base: "513", descripcion: "Pelapapas", es_importado: false, rubro: "Utensilios", tipo: null, ultima_compra: "2026-05-02", cajas: 50, unidades: 600, lineas: 2 }
];

(async () => {
  const b = await chromium.launch();
  const p = await (await b.newContext({ viewport: { width: 1400, height: 900 }, serviceWorkers: "block" })).newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async ({ SUPERS, ITEMS }) => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    for (let i = 0; i < 50 && typeof window.openHotSale !== "function"; i++) await espera(100);
    window.requireSupervisor = () => true;
    try { localStorage.removeItem("gv_hotsale_params_v2"); localStorage.removeItem("gv_hotsale_rent::inc"); } catch (_e) {}
    const out = {};
    const btn = [...document.querySelectorAll(".sup-actions.sup-secondary .sup-action-btn")].find((x) => /openHotSale/.test(x.getAttribute("onclick") || ""));
    out.boton = !!btn && /Hot Sale/.test(btn.textContent);
    window.openHotSale();
    await espera(100);
    const ov = document.getElementById("hsOv");
    out.visible = !!ov && getComputedStyle(ov).display === "flex";
    out.inputs = ov ? ov.querySelectorAll("#hsForm input").length : 0;
    out.formAncho = document.getElementById("hsForm").getBoundingClientRect().width;
    const set = (v) => { for (const k in v) { document.getElementById("hs" + k).value = v[k]; } document.getElementById("hsForm").dispatchEvent(new Event("input", { bubbles: true })); };
    const pond = () => [document.getElementById("hsPondImp"), document.getElementById("hsPondNac")].map((t) => t ? t.textContent : null);
    out.def = pond();
    set({ MI: 100, MN: 50, A: 20, H: 2, P: 4, K: 2 }); out.p4 = pond();
    set({ P: 16 }); out.p16 = pond();
    set({ MI: 100, MN: -6.49, A: 20, H: 2, P: 12, K: 2 }); out.real = pond();
    out.filasSem = document.querySelectorAll("#hsSem table tbody tr").length;
    set({ H: 5, P: 4 });
    out.errMsg = document.getElementById("hsMsg").textContent;
    out.tablaVacia = document.getElementById("hsT").innerHTML === "" && document.getElementById("hsSem").innerHTML === "";
    set({ H: 2, P: 12 });
    const cerrar = ov.querySelector(".hs-x");
    out.cerrarAncho = cerrar ? cerrar.getBoundingClientRect().width : 0;
    const c1 = window.hsCalc(1, 0.2, 4, 2, 2), c2 = window.hsCalc(-0.0649, 0.2, 12, 2, 2), c3 = window.hsCalc(0.5, 0, 10, 0, 2);
    out.calc = [c1.pond, c2.pond, c3.pond, c1.mHS];
    /* (j) modo por súper */
    const llamadas = [];
    window.sb = { rpc: async (name, args) => { llamadas.push([name, args]); if (name === "gv_hotsale_supers") return { data: SUPERS }; if (name === "gv_hotsale_items_super") return { data: args && args.p_super_key === "inc" ? ITEMS : [] }; return { data: [] }; } };
    window.hsModo("super");
    await espera(150);
    out.lblOcultas = document.getElementById("hsLblMI").hidden && document.getElementById("hsLblMN").hidden;
    const sel = document.getElementById("hsSuper");
    out.opciones = sel ? [...sel.options].map((o) => o.textContent) : [];
    window.hsSuperElegir("inc");
    await espera(150);
    out.rpcItems = llamadas.find((l) => l[0] === "gv_hotsale_items_super");
    out.fechas = [...document.querySelectorAll("#hsItems tbody tr td:first-child")].map((t) => t.textContent);
    out.cods = [...document.querySelectorAll("#hsItems tbody tr td:nth-child(2)")].map((t) => t.textContent);
    window.hsRentSet("lk|026", "80"); window.hsRentSet("chef|702EL", "60"); window.hsRentSet("lk|501", "10");
    const filas = [...document.querySelectorAll("#hsT tbody tr")].filter((tr) => !tr.classList.contains("grp")).map((tr) => [...tr.children].map((td) => td.textContent.trim()));
    out.resumen = filas;
    out.faltan = document.querySelectorAll("#hsItems tr.falta").length;
    /* (k) persiste y vuelve */
    window.hsClose(); window.openHotSale(); await espera(200);
    out.modoVuelve = _hs.modo;
    const inp = document.querySelector('#hsItems input[data-k="lk|026"]');
    out.rentVuelve = inp ? inp.value : null;
    /* (l) lista vacía */
    window.sb = { rpc: async () => ({ data: [] }) };
    _hs.supers = null; _hs.supersErr = ""; _hs.superKey = "";
    window.hsModo("super"); await espera(150);
    out.vacia = document.getElementById("hsSel").textContent;
    out.selVacia = !!document.getElementById("hsSuper");
    /* vuelve a promedio y se ven las rent. generales */
    window.hsModo("prom");
    out.lblVuelven = !document.getElementById("hsLblMI").hidden && !!document.getElementById("hsPondImp");
    out.selOculto = getComputedStyle(document.getElementById("hsSel")).display === "none";
    out.inputAncho = document.getElementById("hsA").getBoundingClientRect().width;
    window.hsClose();
    out.cerrado = getComputedStyle(ov).display === "none";
    return out;
  }, { SUPERS, ITEMS });
  /* (h) celular */
  const pm = await (await b.newContext({ viewport: { width: 390, height: 800 }, serviceWorkers: "block" })).newPage();
  await pm.route("**/rest/v1/**", (x) => x.abort());
  await pm.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const m = await pm.evaluate(async () => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    for (let i = 0; i < 50 && typeof window.openHotSale !== "function"; i++) await espera(100);
    window.requireSupervisor = () => true;
    try { localStorage.removeItem("gv_hotsale_params_v2"); } catch (_e) {}
    window.openHotSale(); await espera(100);
    const t = document.getElementById("hsT").getBoundingClientRect();
    const f = document.getElementById("hsForm").getBoundingClientRect();
    const body = document.querySelector(".hs-body");
    return { right: Math.max(t.right, f.right), w: innerWidth, scroll: body.scrollWidth <= body.clientWidth };
  });
  const fails = [];
  if (!(m.right <= m.w && m.scroll)) fails.push("(h) a 390 px llega a " + m.right + " px de " + m.w);
  if (!r.boton) fails.push("(a) falta el botón en los secundarios");
  if (!r.visible || r.inputs !== 6) fails.push("(a) overlay/inputs " + r.visible + " " + r.inputs);
  if (r.p4[0] !== "73 %") fails.push("(b) 4 semanas: " + r.p4[0]);
  if (r.p16[0] !== "91 %") fails.push("(b) 16 semanas: " + r.p16[0]);
  if (r.real[1] !== "-12 %") fails.push("(c) ítem real nacional: " + r.real[1]);
  if (r.def[0] !== "65 %" || r.def[1] !== "4 %") fails.push("(d) defaults: " + r.def);
  if (r.filasSem !== 2 * (12 + 1)) fails.push("(d) semana por semana: " + r.filasSem + " filas");
  if (!/Revisá/.test(r.errMsg) || !r.tablaVacia) fails.push("(e) error: '" + r.errMsg + "' tablaVacia=" + r.tablaVacia);
  if (!(r.cerrarAncho > 0 && r.cerrarAncho < 200)) fails.push("(f) Cerrar mide " + r.cerrarAncho + " px");
  if (Math.abs(r.calc[0] - 0.7333333) > 1e-6 || Math.abs(r.calc[1] + 0.118342) > 1e-5 || Math.abs(r.calc[2] - 0.5) > 1e-12 || Math.abs(r.calc[3] - 0.6) > 1e-12) fails.push("(g) hsCalc " + r.calc);
  if (!(r.formAncho > 0 && r.formAncho < 640)) fails.push("(i) el bloque de datos mide " + r.formAncho + " px");
  if (!r.lblOcultas) fails.push("(j) en modo súper siguen las rent. generales");
  if (r.opciones.length !== 3 || !/Carrefour · últ\. compra 30\/09\/26 · CH 1087 \+ LK 1651/.test(r.opciones[1])) fails.push("(j) opciones: " + JSON.stringify(r.opciones));
  if (!r.rpcItems || r.rpcItems[1].p_super_key !== "inc" || r.rpcItems[1].p_meses !== 12) fails.push("(j) RPC de ítems: " + JSON.stringify(r.rpcItems));
  if (r.fechas.join("|") !== "30/09/26|30/09/26|12/08/26|02/05/26") fails.push("(j) fechas: " + r.fechas.join("|"));
  if (r.cods.join("|") !== "026|501|702EL|513") fails.push("(j) orden de ítems: " + r.cods.join("|"));
  const fila = (n) => r.resumen.find((f) => f[0] === n);
  const imp = fila("Importados"), nac = fila("Nacionales"), col = fila("Coladores"), sac = fila("Sacacorchos"), ute = fila("Utensilios");
  if (!imp || imp[1] !== "2 / 2" || imp[2] !== "400" || imp[3] !== "65 %" || imp[4] !== "32 %" || imp[5] !== "56 %") fails.push("(j) Importados: " + JSON.stringify(imp));
  if (!nac || nac[1] !== "1 / 2" || nac[2] !== "250" || nac[3] !== "10 %" || nac[4] !== "-12 %" || nac[5] !== "4 %") fails.push("(j) Nacionales: " + JSON.stringify(nac));
  if (!col || col[3] !== "80 %" || !sac || sac[3] !== "60 %" || !ute || ute[3] !== "10 %" || ute[1] !== "1 / 2") fails.push("(j) rubros: " + JSON.stringify([col, sac, ute]));
  if (r.resumen[0][0] !== "Importados" || r.resumen[2][0] !== "Sacacorchos") fails.push("(j) orden del resumen (familia primero, rubro por cajas): " + r.resumen.map((f) => f[0]).join("|"));
  if (r.faltan !== 1) fails.push("(j) ítems sin cargar marcados: " + r.faltan);
  if (r.modoVuelve !== "super" || r.rentVuelve !== "80") fails.push("(k) no vuelve: modo " + r.modoVuelve + " rent " + r.rentVuelve);
  if (!/sesión de supervisor/.test(r.vacia) || r.selVacia) fails.push("(l) lista vacía: '" + r.vacia + "' select=" + r.selVacia);
  if (!r.lblVuelven) fails.push("(j) al volver a promedio no vuelven las rent. generales");
  if (!r.selOculto) fails.push("(j) en modo promedio sigue viéndose «¿Qué súper?»");
  if (!(r.inputAncho > 0 && r.inputAncho <= 100)) fails.push("(i) el input mide " + r.inputAncho + " px: el width:auto global le gana al del módulo");
  if (!r.cerrado) fails.push("(f) no cierra");
  if (errs.length) fails.push("errores: " + errs.join(" | "));
  await b.close();
  if (fails.length) { console.error("FALLA hotsale-rent:\n  " + fails.join("\n  ")); process.exit(1); }
  console.log("OK hotsale-rent");
})();
