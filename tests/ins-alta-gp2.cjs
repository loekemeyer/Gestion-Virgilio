/* v31.14 (Luis, 15/10) — Stock y Compras → Insumos:
   (a) editar un insumo deja cambiar SÓLO la descripción GV y la cantidad (sin código, ISIS, categoría, unidad, factores);
       guardar manda insumo_editar con p_nombre solamente y la cantidad como ajuste en la unidad primaria;
   (b) las tablas muestran «Descripción GV» y «Descripción GP2»;
   (c) «+ Agregar insumo» abre un pop-up: «Tomar un código de GP2» (Recomendado) o «Crear uno a mano»;
       GP2: lista gv_gp2_componentes_alta, el ya vinculado no se puede elegir, viene con código y descripción de GP2,
       la descripción GV se edita, la cantidad muestra ≈ uni con el cajón de GP2; crea con gv_insumo_desde_gp2;
       sin cajón en GP2 deja cargar el factor a mano; una lectura rota lo dice;
       a mano: código, descripción, ISIS, cantidad, unidad secundaria y factor;
       una categoría sin sector en GP2 no ofrece la opción GP2. Sin red (fetch mockeado). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 900 } });
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {}, rpc = [], movs = []; let altaRota = false;
    window.alert = function (m) { out.alerta = String(m); };
    const J = (d, ok) => Promise.resolve({ ok: ok !== false, status: ok === false ? 500 : 200, headers: { get: () => null }, json: () => Promise.resolve(d) });
    const CATS = [
      { clave: "partes_crudo", nombre: "Sector Crudo", emoji: "🔩", unidades: ["Cajones"], orden: 1 },
      { clave: "importados", nombre: "Importados", emoji: "🌎", unidades: [], orden: 2 }
    ];
    const CAT = [{ cod: "Batidor Pera p/Cromar", nombre: "Batidor Pera p/Cromar", categoria: "partes_crudo", ubicacion: "IN-J1", isis: "777" }];
    const SAL = [{ cod_art: "Batidor Pera p/Cromar", unidad: "Cajones", saldo: 15 }];
    const INFO = [{ cod: "Batidor Pera p/Cromar", cod_c: "GRJ10", desc_c: "Batidor Pera", isis: "777", kg_x_uni: 0.098, uni_x_cajon: 306, kg_x_cajon: 29.99 }];
    const COMPS = [
      { comp_id: 285, codigo: "GRJ10", descripcion: "Batidor Pera", nombre_gv: "Batidor Pera", unidad: "unidad", kg_x_uni: 0.098, uni_x_cajon: 306, kg_x_cajon: 29.99, vinculado_a: "Batidor Pera p/Cromar" },
      { comp_id: 287, codigo: "GRJ10A", descripcion: "Batidor Pera Mini", nombre_gv: "Batidor Pera Mini", unidad: "unidad", kg_x_uni: 0.08, uni_x_cajon: 375, kg_x_cajon: 30, vinculado_a: null },
      { comp_id: 300, codigo: "G99", descripcion: "Pieza sin cajón", nombre_gv: "Pieza sin cajón", unidad: "unidad", kg_x_uni: null, uni_x_cajon: null, kg_x_cajon: null, vinculado_a: null }
    ];
    window.fetch = function (url, opt) {
      url = String(url);
      const m = String((opt && opt.method) || "GET").toUpperCase();
      let body = null; try { body = JSON.parse(opt.body); } catch (_e) {}
      if (url.indexOf("/rpc/gv_insumo_gp2_info") >= 0) return J(INFO);
      if (url.indexOf("/rpc/gv_gp2_componentes_alta") >= 0) { rpc.push({ fn: "gv_gp2_componentes_alta", body: body }); return altaRota ? J({}, false) : J(COMPS); }
      if (url.indexOf("/rpc/gv_insumo_desde_gp2") >= 0) { rpc.push({ fn: "gv_insumo_desde_gp2", body: body }); return J(body.p_comp_id === 287 ? "GRJ10A" : "G99"); }
      if (url.indexOf("/rpc/") >= 0) { rpc.push({ fn: url.split("/rpc/")[1].split("?")[0], body: body }); return J(null); }
      if (url.indexOf("/Movimientos_Stock") >= 0 && m === "POST") { (body || []).forEach((x) => movs.push(x)); return J({}); }
      if (url.indexOf("Insumos_Categorias") >= 0) return J(CATS);
      if (url.indexOf("Insumos_Unidades") >= 0) return J(["Cajones", "Kg", "Uni", "MC"].map((n, i) => ({ nombre: n, orden: i })));
      if (url.indexOf("vista_saldos_insumos_x_unidad") >= 0) return J(SAL);
      if (url.indexOf("vista_insumos") >= 0) return J(CAT);
      return J([]);
    };
    const ov = document.createElement("div");
    ov.innerHTML = '<div class="stk-tabs" id="stkTabs"></div><div class="stk-body" id="stkBody"></div>';
    document.body.appendChild(ov);
    _stk = { tab: "insumos", filtro: "", arts: [], soloConteo: false, insLoaded: true };
    await stkInsLoad();
    const pop = () => document.getElementById("stkInsCatPopBody");
    const modal = () => document.getElementById("stkInsAltaModal");

    // (b) columnas
    stkInsCatPopup("partes_crudo");
    const head = pop().querySelector("thead").textContent;
    out.colsDesc = /Descripción GV/.test(head) && /Descripción GP2/.test(head);
    out.descGp2 = /Batidor Pera/.test(pop().querySelector("tbody tr").cells[3].textContent);
    // (a) edición limitada
    stkInsEdit("art:Batidor Pera p/Cromar"); stkInsCatPopup("partes_crudo");
    const ids = Array.from(pop().querySelectorAll("tbody input, tbody select")).map((e) => e.id.split("_")[0]);
    out.editIds = ids.join(",");
    out.sinFactBtn = !/＋ unidad|⚖/.test(pop().querySelector("tbody").innerHTML);
    document.getElementById("edNom_Batidor Pera p/Cromar").value = "Batidor Pera p/Cromar (rev)";
    document.getElementById("edQty_Batidor Pera p/Cromar").value = "17";
    await stkInsGuardar("Batidor Pera p/Cromar");
    const ed = rpc.filter((x) => x.fn === "insumo_editar").pop();
    out.editSoloNombre = !!ed && JSON.stringify(Object.keys(ed.body).sort()) === JSON.stringify(["p_cod", "p_nombre"]) && ed.body.p_nombre === "Batidor Pera p/Cromar (rev)";
    const aj = movs.pop();
    out.editAjuste = !!aj && aj.delta === 2 && aj.unidad === "Cajones" && aj.tipo === "ajuste";

    // (c) pop-up
    stkInsAltaAbrir("partes_crudo");
    const h0 = modal().innerHTML;
    out.popupDosOpciones = /Tomar un código de GP2/.test(h0) && /Crear uno a mano/.test(h0) && h0.indexOf("Tomar un código de GP2") < h0.indexOf("Crear uno a mano") && /Recomendado/.test(h0);
    await stkInsAltaModo("gp2");
    const items = Array.from(modal().querySelectorAll(".stk-altaitem"));
    out.listaN = items.length;
    out.vinculadoDeshabilitado = !!items[0] && items[0].disabled && /ya es Batidor Pera p\/Cromar/.test(items[0].textContent);
    out.argCat = (rpc.filter((x) => x.fn === "gv_gp2_componentes_alta").pop() || { body: {} }).body.p_categoria;
    stkInsAltaBuscar("mini");
    out.buscar = modal().querySelectorAll(".stk-altaitem").length;
    stkInsAltaElegir(1);
    const hf = modal().innerHTML;
    out.formGp2 = /GRJ10A/.test(hf) && /Batidor Pera Mini/.test(hf) && /1 cajón = <b>375<\/b> uni/.test(hf) && !document.getElementById("nvCod") && !document.getElementById("nvIsis");
    out.nomPrecargado = document.getElementById("nvNom").value;
    document.getElementById("nvNom").value = "Batidor Mini p/Cromar";
    document.getElementById("nvQty").value = "2"; stkInsAltaEquiv();
    out.equiv = document.getElementById("nvEquiv").textContent;
    await stkInsAltaGp2Crear();
    const dg = rpc.filter((x) => x.fn === "gv_insumo_desde_gp2").pop();
    out.creaDesdeGp2 = !!dg && dg.body.p_comp_id === 287;
    const ren = rpc.filter((x) => x.fn === "insumo_editar").pop();
    out.renombra = !!ren && ren.body.p_cod === "GRJ10A" && ren.body.p_nombre === "Batidor Mini p/Cromar";
    const st = movs.pop();
    out.stockInicial = !!st && st.cod_art === "GRJ10A" && st.delta === 2 && st.unidad === "Cajones";
    out.cierra = !modal();
    // sin cajón en GP2 → factor a mano
    stkInsAltaAbrir("partes_crudo"); await stkInsAltaModo("gp2"); stkInsAltaElegir(2);
    out.factorManualGp2 = !!document.getElementById("nvFactor") && !!document.getElementById("nvSecUni");
    document.getElementById("nvQty").value = "1";
    document.getElementById("nvSecUni").value = "MC"; document.getElementById("nvFactor").value = "4";
    await stkInsAltaGp2Crear();
    const fg = rpc.filter((x) => x.fn === "insumo_factores_guardar").pop();
    out.factorGuardado = !!fg && fg.body.p_cod === "G99" && fg.body.p_factores[0].unidad === "Cajones" && fg.body.p_factores[1].unidad === "MC" && fg.body.p_factores[1].factor === 4;
    // lectura rota
    altaRota = true; stkInsAltaAbrir("partes_crudo"); await stkInsAltaModo("gp2");
    out.rota = /No se pudo leer GP2/.test(modal().innerHTML) && !modal().querySelector(".stk-altaitem");
    stkInsAltaCerrar(); altaRota = false;
    // a mano
    stkInsAltaAbrir("partes_crudo"); await stkInsAltaModo("manual");
    out.formManual = ["nvCod", "nvNom", "nvIsis", "nvQty", "nvUni", "nvSecUni", "nvFactor"].every((id) => !!document.getElementById(id));
    document.getElementById("nvCod").value = "NUEVO1"; document.getElementById("nvNom").value = "Pieza nueva";
    document.getElementById("nvIsis").value = "1234"; document.getElementById("nvQty").value = "3"; document.getElementById("nvUni").value = "Cajones";
    await stkInsAlta("partes_crudo");
    const al = rpc.filter((x) => x.fn === "insumo_alta").pop();
    const ii = rpc.filter((x) => x.fn === "insumo_editar").pop();
    out.manual = !!al && al.body.p_cod === "NUEVO1" && al.body.p_categoria === "partes_crudo" && !!ii && ii.body.p_isis === "1234";
    out.manualStock = (movs.pop() || {}).cod_art === "NUEVO1";
    // categoría sin sector en GP2
    stkInsAltaAbrir("importados");
    out.impoSinGp2 = document.getElementById("stkAltaGp2").disabled === true;
    stkInsAltaCerrar();
    return out;
  });
  // (g) pase GV-UI (v31.14): a 390 px todo lo tocable del alta mide ≥ 44 y el botón principal es el verde de la casa (5:1)
  await p.setViewportSize({ width: 390, height: 800 });
  const ui = await p.evaluate(async () => {
    stkInsAltaAbrir("partes_crudo"); await stkInsAltaModo("gp2"); stkInsAltaElegir(1);
    const m = document.getElementById("stkInsAltaModal");
    const chicos = Array.from(m.querySelectorAll(".stk-btn, .stk-inp")).filter((e) => e.getBoundingClientRect().height < 44).map((e) => e.id || e.textContent.trim());
    const ok = getComputedStyle(document.getElementById("stkAltaCrear")).backgroundColor;
    const meta = getComputedStyle(document.getElementById("nvEquiv")).color;
    const horiz = document.documentElement.scrollWidth > window.innerWidth;
    stkInsAltaCerrar();
    return { chicos: chicos, ok: ok, meta: meta, horiz: horiz };
  });
  r.ui = ui;
  r.uiOk = ui.chicos.length === 0 && ui.ok === "rgb(21, 128, 61)" && ui.meta === "rgb(71, 85, 105)";
  const pass = r.uiOk && r.colsDesc && r.descGp2 && r.editIds === "edNom,edQty" && r.sinFactBtn && r.editSoloNombre && r.editAjuste &&
    r.popupDosOpciones && r.listaN === 3 && r.vinculadoDeshabilitado && r.argCat === "partes_crudo" && r.buscar === 1 &&
    r.formGp2 && r.nomPrecargado === "Batidor Pera Mini" && /≈ 750 uni/.test(r.equiv) && r.creaDesdeGp2 && r.renombra &&
    r.stockInicial && r.cierra && r.factorManualGp2 && r.factorGuardado && r.rota && r.formManual && r.manual && r.manualStock &&
    r.impoSinGp2 && errs.length === 0;
  console.log("ins-alta-gp2:", JSON.stringify(r));
  console.log("  pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
