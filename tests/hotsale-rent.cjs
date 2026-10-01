/* v25.91 · v25.93 · v25.98 — Hot Sale: rentabilidad ponderada del período (Thomas, 01/10/2026).
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
     (l) una lista de súpers vacía NO se dibuja como «no hay súpers»: dice que falta la sesión;
     (m) lo importado por TIERRA NATIVA o CHEF trae las columnas de LK: importador, u$s → LK por
         unidad (guardado en la base por gv_hotsale_precio_lk_guardar; para Chef el botón «usar»
         carga la última factura Chef → LK), lo que LK le factura al súper y la rent. de LK hoy /
         en HS / ponderada con ⚠ en lo que queda a pérdida; un nacional no lleva esas celdas; el
         dólar se guarda por gv_hotsale_param_guardar y al cambiarlo se recalcula; y el resumen
         suma una fila por importador con cuántos ítems quedan a pérdida.
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
  { empresa: "lk", cod: "026", cod_base: "26", descripcion: "Colador 8 cm", es_importado: true, rubro: "Coladores", tipo: "Colador Ø 8 cm", ultima_compra: "2026-09-30", cajas: 100, unidades: 1200, lineas: 10,
    importador: "Tierra Nativa", precio_usd_lk: 0.5, precio_usd_nota: null, venta_unit: 1000, venta_fecha: "2026-09-30", uxb: 12, ref_chef_usd: null, ref_chef_fecha: null },
  { empresa: "lk", cod: "501", cod_base: "501", descripcion: "Cuchillo de untar", es_importado: false, rubro: "Utensilios", tipo: null, ultima_compra: "2026-09-30", cajas: 200, unidades: 4800, lineas: 20 },
  { empresa: "chef", cod: "702EL", cod_base: "702E", descripcion: "Sacacorchos de dos tiempos", es_importado: true, rubro: "Sacacorchos", tipo: null, ultima_compra: "2026-08-12", cajas: 300, unidades: 3600, lineas: 7,
    importador: "Chef", precio_usd_lk: null, precio_usd_nota: null, venta_unit: 1200, venta_fecha: "2026-08-12", uxb: 12, ref_chef_usd: 0.9, ref_chef_fecha: "2026-01-28" },
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
    window.sb = { rpc: async (name, args) => {
      llamadas.push([name, args]);
      if (name === "gv_hotsale_supers") return { data: SUPERS };
      if (name === "gv_hotsale_items_super") return { data: args && args.p_super_key === "inc" ? ITEMS.map((i) => Object.assign({}, i)) : [] };
      if (name === "gv_hotsale_params") return { data: { dolar: { valor: 1450, actualizado_at: "2026-10-01T12:00:00Z", por: "x" } } };
      if (name === "gv_hotsale_param_guardar") return { data: { clave: args.p_clave, valor: args.p_valor } };
      if (name === "gv_hotsale_precio_lk_guardar") return { data: { cod: args.p_cod, precio_usd: args.p_precio_usd } };
      return { data: [] };
    } };
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
    /* (m) rent. de LK en lo importado por TN / Chef (A 20 · H 2 · P 12 · K 2) */
    out.lkHeads = [...document.querySelectorAll("#hsItems thead th.lkh")].map((t) => t.innerHTML.replace(/<br>/g, " ").replace(/\s+/g, " "));
    const filaIt = (k) => document.querySelector('#hsItems tr[data-k="' + k + '"]');
    const celdas = (k) => [...(filaIt(k) ? filaIt(k).children : [])].map((td) => td.textContent.trim());
    out.lk026 = celdas("lk|026");
    out.itemsAncho = document.getElementById("hsItems").getBoundingClientRect().width; out.wrapAncho = document.getElementById("hsItemsWrap").clientWidth;
    out.lk702 = celdas("chef|702EL");
    out.lk501 = filaIt("lk|501").children.length;
    out.na501 = filaIt("lk|501").lastElementChild.getAttribute("colspan");
    out.dolarVal = (document.getElementById("hsDolar") || {}).value;
    const ref = filaIt("chef|702EL") && filaIt("chef|702EL").querySelector("button.ref");
    out.refTxt = ref ? ref.textContent : null;
    if (ref) ref.click();
    await espera(120);
    out.rpcUsd = llamadas.find((l) => l[0] === "gv_hotsale_precio_lk_guardar");
    out.lk702b = celdas("chef|702EL");
    out.refSigue = !!(filaIt("chef|702EL") && filaIt("chef|702EL").querySelector("button.ref"));
    const resumen2 = [...document.querySelectorAll("#hsT tbody tr")].filter((tr) => !tr.classList.contains("grp")).map((tr) => [...tr.children].map((td) => td.textContent.trim()));
    out.resLK = resumen2.filter((f) => /^(Tierra Nativa|Chef)/.test(f[0]));
    out.grpLK = [...document.querySelectorAll("#hsT tr.grp td")].map((t) => t.textContent).find((t) => /Rent\. de LK/.test(t));
    const dol = document.getElementById("hsDolar"); if (dol) { dol.value = "2000"; dol.dispatchEvent(new Event("change")); }
    await espera(120);
    out.rpcDolar = llamadas.find((l) => l[0] === "gv_hotsale_param_guardar");
    out.lk026b = celdas("lk|026");
    out.dolarInfo = (document.getElementById("hsDolarInfo") || {}).textContent || "";
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
  const m = await pm.evaluate(async ({ SUPERS, ITEMS }) => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    for (let i = 0; i < 50 && typeof window.openHotSale !== "function"; i++) await espera(100);
    window.requireSupervisor = () => true;
    try { localStorage.removeItem("gv_hotsale_params_v2"); } catch (_e) {}
    window.openHotSale(); await espera(100);
    const t = document.getElementById("hsT").getBoundingClientRect();
    const f = document.getElementById("hsForm").getBoundingClientRect();
    const body = document.querySelector(".hs-body");
    const prom = { right: Math.max(t.right, f.right), w: innerWidth, scroll: body.scrollWidth <= body.clientWidth };
    window.sb = { rpc: async (n, a) => n === "gv_hotsale_supers" ? { data: SUPERS } : n === "gv_hotsale_items_super" ? { data: ITEMS } : n === "gv_hotsale_params" ? { data: { dolar: { valor: 1450, actualizado_at: "2026-10-01" } } } : { data: {} } };
    window.hsModo("super"); await espera(150); window.hsSuperElegir("inc"); await espera(150);
    const f2 = document.getElementById("hsForm").getBoundingClientRect(), s2 = document.getElementById("hsSel").getBoundingClientRect();
    return Object.assign(prom, { superScroll: body.scrollWidth <= body.clientWidth, superRight: Math.max(f2.right, s2.right), filas: document.querySelectorAll("#hsItems tbody tr").length });
  }, { SUPERS, ITEMS });
  const fails = [];
  if (!(m.right <= m.w && m.scroll)) fails.push("(h) a 390 px llega a " + m.right + " px de " + m.w);
  if (!(m.superScroll && m.superRight <= m.w && m.filas === 4)) fails.push("(h) a 390 px en modo súper la pantalla se va a la derecha: scroll=" + m.superScroll + " right=" + m.superRight + " filas=" + m.filas);
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
  if (r.lkHeads.join("|") !== "u$s → LK por u|Venta LK $/u|Rent. LK hoy|Rent. LK en HS|Rent. LK pond.") fails.push("(m) encabezados LK: " + r.lkHeads.join("|"));
  if (r.dolarVal !== "1450") fails.push("(m) el dólar de la base no se ve: " + r.dolarVal);
  if (!(r.lk026[4] === "Imp·TN" && /^\$ 1\.000/.test(r.lk026[8]) && r.lk026[9] === "38 %" && r.lk026[10] === "10 %" && r.lk026[11] === "30 %")) fails.push("(m) 026 por TN: " + JSON.stringify(r.lk026.slice(7)));
  if (!(r.lk702[4] === "Imp·Chef" && r.refTxt === "usar 0,9" && r.lk702[9] === "—" && r.lk702[11] === "—")) fails.push("(m) 702EL sin u$s: " + JSON.stringify(r.lk702.slice(7)) + " ref=" + r.refTxt);
  if (!(r.lk501 === 8 && r.na501 === "5")) fails.push("(m) el nacional lleva " + r.lk501 + " celdas, colspan " + r.na501);
  if (!r.rpcUsd || r.rpcUsd[1].p_cod !== "702E" || Math.abs(r.rpcUsd[1].p_precio_usd - 0.9) > 1e-9) fails.push("(m) RPC del u$s: " + JSON.stringify(r.rpcUsd));
  if (!(r.lk702b[9] === "⚠ -8 %" && r.lk702b[10] === "⚠ -26 %" && r.lk702b[11] === "⚠ -13 %" && !r.refSigue)) fails.push("(m) 702EL con la ref cargada: " + JSON.stringify(r.lk702b.slice(7)) + " refSigue=" + r.refSigue);
  const tn = r.resLK.find((f) => /^Tierra Nativa/.test(f[0])), ch = r.resLK.find((f) => /^Chef/.test(f[0]));
  if (!tn || !/ninguno a pérdida/.test(tn[0]) || tn[1] !== "1 / 1" || tn[2] !== "100" || tn[3] !== "38 %" || tn[4] !== "10 %" || tn[5] !== "30 %") fails.push("(m) resumen TN: " + JSON.stringify(tn));
  if (!ch || !/a pérdida: 1 hoy · 1 en HS · 1 pond\./.test(ch[0]) || ch[1] !== "1 / 1" || ch[2] !== "300" || ch[3] !== "-8 %" || ch[4] !== "-26 %" || ch[5] !== "-13 %") fails.push("(m) resumen Chef: " + JSON.stringify(ch));
  if (!r.grpLK || !/dólar \$ 1\.450/.test(r.grpLK)) fails.push("(m) el grupo de LK no dice el dólar: " + r.grpLK);
  if (!r.rpcDolar || r.rpcDolar[1].p_clave !== "dolar" || r.rpcDolar[1].p_valor !== 2000) fails.push("(m) RPC del dólar: " + JSON.stringify(r.rpcDolar));
  if (!(r.lk026b[9] === "0 %" && /guardado/.test(r.dolarInfo))) fails.push("(m) con dólar 2000 el 026 da " + r.lk026b[10] + " · " + r.dolarInfo);
  if (!(r.itemsAncho > 0 && r.itemsAncho <= r.wrapAncho + 1)) fails.push("(m) a 1400 px la tabla de ítems (" + r.itemsAncho + " px) no entra en su marco (" + r.wrapAncho + "): columnas cortadas");
  if (!r.lblVuelven) fails.push("(j) al volver a promedio no vuelven las rent. generales");
  if (!r.selOculto) fails.push("(j) en modo promedio sigue viéndose «¿Qué súper?»");
  if (!(r.inputAncho > 0 && r.inputAncho <= 100)) fails.push("(i) el input mide " + r.inputAncho + " px: el width:auto global le gana al del módulo");
  if (!r.cerrado) fails.push("(f) no cierra");
  if (errs.length) fails.push("errores: " + errs.join(" | "));
  await b.close();
  if (fails.length) { console.error("FALLA hotsale-rent:\n  " + fails.join("\n  ")); process.exit(1); }
  console.log("OK hotsale-rent");
})();
