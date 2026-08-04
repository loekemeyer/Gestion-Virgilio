/* Regresión v7.14 / idea 5572 — Stock y Compras → solapa "🧰 Insumos" (Administrar
   Insumos). Es el lado admin de la botonera del operario (idea 7917). Contrato:
     · la solapa existe en la botonera de Stock y Compras
     · "Pendientes de identificar" lista SOLO los TMP-* (lo que cargó el operario)
     · identificar manda el RPC insumo_identificar con el código nuevo
     · descartar manda el insumo a 'depurar' (no borra: puede tener stock)
     · el catálogo filtra por categoría y por texto, y deja editar categoría/orden
     · el ORDEN que fija el admin manda sobre el orden automático de la app
   Sin red (fetch mockeado). */
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
    const out = {};
    const rpc = [];
    function J(data) {
      return Promise.resolve({ ok: true, status: 200, headers: { get: function () { return null; } }, json: function () { return Promise.resolve(data); } });
    }
    const CAT = [
      { cod: "22", nombre: "121 X 1,20", categoria: "fleje", ubicacion: "V2 Ad", orden: null, creado_por: "104" },
      { cod: "5", nombre: "38 X 0,55", categoria: "fleje", ubicacion: "R4At", orden: null, creado_por: "104" },
      { cod: "PP", nombre: "POLIPROPILENO", categoria: "plastico", ubicacion: "AF1", orden: null, creado_por: "104" },
      { cod: "TMP-0001", nombre: "Bolsa gris sin etiqueta", categoria: "plastico", ubicacion: null, orden: null, creado_por: "104" },
      { cod: "TMP-0002", nombre: "Alambre finito que trajo Perez", categoria: "", ubicacion: null, orden: null, creado_por: "231" }
    ];
    window.fetch = function (url, opt) {
      url = String(url);
      if (url.indexOf("/rpc/") >= 0) {
        let body = null; try { body = JSON.parse(opt.body); } catch (_e) {}
        rpc.push({ fn: url.split("/rpc/")[1].split("?")[0], body: body });
        return J(1);
      }
      if (url.indexOf("/Insumos") >= 0) return J(CAT);
      if (url.indexOf("vista_saldos_insumos_x_unidad") >= 0) {
        return J([{ cod_art: "TMP-0001", unidad: "Bolsas", saldo: 7 }, { cod_art: "22", unidad: "kg", saldo: 1483.95 }]);
      }
      return J([]);
    };
    window.confirm = function () { return true; };
    let alerted = ""; window.alert = function (m) { alerted = String(m); };

    // Esqueleto del modal (lo arma openStockAdmin; acá lo montamos a mano para no
    // depender de toda la carga de stock).
    const ov = document.createElement("div");
    ov.innerHTML = '<div class="stk-tabs" id="stkTabs"></div><div class="stk-body" id="stkBody"></div>';
    document.body.appendChild(ov);

    // La solapa existe y se puede abrir sin pasar por todo el admin de stock
    _stk = { tab: "insumos", filtro: "", arts: [], soloConteo: false, insLoaded: true };
    stkRender();
    const tabTxt = Array.prototype.map.call(document.querySelectorAll("#stkTabs .stk-tab"), function (e) { return e.textContent.trim(); });
    out.tabs = tabTxt;
    out.hayTabInsumos = tabTxt.some(function (t) { return /Insumos/.test(t); });

    await stkInsLoad();
    const body = function () { return document.getElementById("stkBody").innerHTML; };
    const filas = function (sel) { return document.querySelectorAll(sel).length; };

    // 1) Pendientes = SOLO los TMP-*
    out.pendCount = (document.querySelectorAll("#stkBody table")[0] || { querySelectorAll: function () { return []; } }).querySelectorAll("tbody tr").length;
    out.pendTraeTmp = /TMP-0001/.test(body()) && /TMP-0002/.test(body());
    out.pendMuestraDetalle = /Bolsa gris sin etiqueta/.test(body());
    out.pendMuestraSaldo = /7 Bolsas/.test(body());
    out.pendMuestraLegajo = /leg 231/.test(body());

    // 2) Identificar → RPC insumo_identificar con el código nuevo
    document.getElementById("idCod_TMP-0001").value = "1234567";
    document.getElementById("idNom_TMP-0001").value = "Nylon especial";
    await stkInsIdentificar("TMP-0001");
    const ident = rpc.filter(function (x) { return x.fn === "insumo_identificar"; })[0];
    out.identFn = !!ident;
    out.identTmp = ident ? ident.body.p_tmp : null;         // "TMP-0001"
    out.identCod = ident ? ident.body.p_cod : null;         // "1234567"
    out.identNom = ident ? ident.body.p_nombre : null;      // "Nylon especial"

    // 3) Identificar sin código no manda nada
    const antes = rpc.length;
    await stkInsIdentificar("TMP-0002");
    out.identExigeCod = rpc.length === antes && /código real/i.test(alerted);

    // 4) Descartar → a 'depurar', no borra
    await stkInsDescartar("TMP-0002");
    const desc = rpc.filter(function (x) { return x.fn === "insumo_editar" && x.body.p_cod === "TMP-0002"; })[0];
    out.descartaADepurar = !!desc && desc.body.p_categoria === "depurar";

    // 5) Catálogo: filtro por categoría y por texto
    stkInsCat("fleje");
    const tblCat = document.querySelectorAll("#stkBody table");
    out.catFleje = tblCat[tblCat.length - 1].querySelectorAll("tbody tr").length;   // 2 (22 y 5)
    out.catNoTraePP = !/POLIPROPILENO/.test(tblCat[tblCat.length - 1].innerHTML);
    _stkIns.filtro = "121"; stkRender();
    const tbl2 = document.querySelectorAll("#stkBody table");
    out.catBusca = tbl2[tbl2.length - 1].querySelectorAll("tbody tr").length;       // 1
    _stkIns.filtro = ""; stkInsCat("fleje");

    // 6) Editar: guarda categoría + orden
    stkInsEdit("22");
    out.editAbre = !!document.getElementById("edOrd_22");
    document.getElementById("edOrd_22").value = "1";
    document.getElementById("edCat_22").value = "importados";
    await stkInsGuardar("22");
    const ed = rpc.filter(function (x) { return x.fn === "insumo_editar" && x.body.p_cod === "22"; })[0];
    out.editOrden = ed ? ed.body.p_orden : null;            // 1
    out.editCat = ed ? ed.body.p_categoria : null;          // "importados"

    // 7) Alta con código real desde el admin
    _stkIns.nuevo = true; stkRender();
    document.getElementById("nvCod").value = "7654321";
    document.getElementById("nvNom").value = "Insumo del admin";
    await stkInsAlta();
    const alta = rpc.filter(function (x) { return x.fn === "insumo_alta"; })[0];
    out.altaFn = !!alta && alta.body.p_cod === "7654321";

    // 8) El ORDEN del admin manda sobre el automático de la botonera del operario
    const A = { cod: "A", nombre: "999 X 9", cat: "fleje", orden: 1, qty: 0, stock: 0 };
    const B = { cod: "B", nombre: "1 X 1", cat: "fleje", orden: null, qty: 0, stock: 0 };
    const C = { cod: "C", nombre: "2 X 2", cat: "fleje", orden: 0, qty: 0, stock: 0 };
    out.ordenManualManda = [A, B, C].slice().sort(_insSortCat("fleje")).map(function (x) { return x.cod; }).join("");  // "CAB"
    return out;
  });

  const pass =
    r.hayTabInsumos === true &&
    r.pendCount === 2 && r.pendTraeTmp === true && r.pendMuestraDetalle === true &&
    r.pendMuestraSaldo === true && r.pendMuestraLegajo === true &&
    r.identFn === true && r.identTmp === "TMP-0001" && r.identCod === "1234567" && r.identNom === "Nylon especial" &&
    r.identExigeCod === true && r.descartaADepurar === true &&
    r.catFleje === 2 && r.catNoTraePP === true && r.catBusca === 1 &&
    r.editAbre === true && r.editOrden === 1 && r.editCat === "importados" &&
    r.altaFn === true && r.ordenManualManda === "CAB" &&
    errs.length === 0;
  console.log("ins-admin:", JSON.stringify(r));
  console.log("  pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
