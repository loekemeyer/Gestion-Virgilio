/* Regresión v7.17 / idea 5572 — Stock y Compras → solapa "🧰 Insumos" (Administrar
   Insumos). Es el lado admin de la botonera del operario (idea 7917). Contrato:
     · la solapa existe, y arranca por "Pendientes de identificar"
     · pendientes = SOLO los TMP-*, con TODO editable: código (sugerido = el temporal),
       nombre, categoría, ubicación y las UNIDADES (cantidad + unidad de medida)
     · identificar manda insumo_identificar con código + nombre + categoría + ubicación
     · corregir cantidad/unidad postea ASIENTOS (el log es append-only), no edita
     · no deja identificar dejando el TMP como código
     · descartar manda el insumo a 'depurar' (no borra: puede tener stock)
     · sección CATEGORÍAS: nombre/emoji, unidades permitidas, y los insumos adentro
       (con el alta de insumo ahí mismo)
     · sección UNIDADES: el vocabulario de medidas, se agregan y se sacan
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
    const movs = [];
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
      if (url.indexOf("/Movimientos_Stock") >= 0 && opt && String(opt.method || "").toUpperCase() === "POST") {
        try { JSON.parse(opt.body).forEach(function (m) { movs.push(m); }); } catch (_e) {}
        return J({});
      }
      if (url.indexOf("/rpc/") >= 0) {
        let body = null; try { body = JSON.parse(opt.body); } catch (_e) {}
        rpc.push({ fn: url.split("/rpc/")[1].split("?")[0], body: body });
        return J(1);
      }
      if (url.indexOf("Insumos_Categorias") >= 0) {
        return J([
          { clave: "plastico", nombre: "Plásticos", emoji: "🧪", unidades: ["Bolsas"], orden: 1 },
          { clave: "fleje", nombre: "Flejes y alambres", emoji: "🧵", unidades: ["Kg"], orden: 2 },
          { clave: "importados", nombre: "Importados", emoji: "🌎", unidades: [], orden: 3 },
          { clave: "partes_plasticas", nombre: "Partes plásticas", emoji: "🧩", unidades: [], orden: 4 },
          { clave: "cajas", nombre: "Cajas", emoji: "📦", unidades: ["Paquetes", "Uni"], orden: 5 },
          { clave: "depurar", nombre: "A depurar", emoji: "🗑", unidades: [], orden: 99 }
        ]);
      }
      if (url.indexOf("Insumos_Unidades") >= 0) {
        return J(["Uni", "Kg", "Bolsas", "Paquetes", "MC", "Cajas"].map(function (n, i) { return { nombre: n, orden: i }; }));
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

    // 1) Pendientes primero y con TODO editable
    out.primeraSec = (document.querySelector("#stkBody .stk-sec") || {}).textContent || "";
    out.pendCount = document.querySelectorAll("#stkBody table")[0].querySelectorAll("tbody tr").length;
    out.pendCodSugerido = (document.getElementById("idCod_TMP-0001") || {}).value;   // "TMP-0001"
    out.pendNombre = (document.getElementById("idNom_TMP-0001") || {}).value;        // lo que escribió
    out.pendCat = (document.getElementById("idCat_TMP-0001") || {}).value;           // la que sugirió
    out.pendUbicEditable = !!document.getElementById("idUbi_TMP-0001");
    out.pendQty = (document.getElementById("idQty_TMP-0001") || {}).value;           // "7"
    out.pendUni = (document.getElementById("idUni_TMP-0001") || {}).value;           // "Bolsas"
    out.tituloUnidades = /Unidades/.test(document.querySelectorAll("#stkBody table")[0].innerHTML);
    out.sinColumnaOrden = !/>Orden</.test(document.getElementById("stkBody").innerHTML);
    out.pendMuestraLegajo = /leg 231/.test(document.getElementById("stkBody").innerHTML);

    // 2) No deja identificar dejando el temporal como código
    const antesTmp = rpc.length;
    await stkInsIdentificar("TMP-0001");
    out.rechazaTmpComoCod = rpc.length === antesTmp && /temporal/i.test(alerted);

    // 3) Identificar manda los 5 campos; corregir cantidad/unidad postea un ASIENTO
    document.getElementById("idCod_TMP-0001").value = "1234567";
    document.getElementById("idNom_TMP-0001").value = "Nylon especial";
    document.getElementById("idUbi_TMP-0001").value = "AF9";
    document.getElementById("idQty_TMP-0001").value = "12";
    document.getElementById("idUni_TMP-0001").value = "Kg";
    await stkInsIdentificar("TMP-0001");
    const ident = rpc.filter(function (x) { return x.fn === "insumo_identificar"; })[0];
    out.identCod = ident ? ident.body.p_cod : null;          // "1234567"
    out.identNom = ident ? ident.body.p_nombre : null;       // "Nylon especial"
    out.identCat = ident ? ident.body.p_categoria : null;    // "plastico"
    out.identUbi = ident ? ident.body.p_ubicacion : null;    // "AF9"
    // cambió Bolsas→Kg: saca las 7 Bolsas y pone 12 Kg, con el código TODAVÍA temporal
    out.ajusteN = movs.length;                               // 2
    out.ajusteSaca = movs.length ? (movs[0].delta === -7 && movs[0].unidad === "Bolsas") : false;
    out.ajustePone = movs.length > 1 ? (movs[1].delta === 12 && movs[1].unidad === "Kg") : false;
    out.ajusteSobreTmp = movs.length ? movs[0].cod_art === "TMP-0001" : false;

    // 4) Descartar → a 'depurar', no borra
    await stkInsDescartar("TMP-0002");
    const desc = rpc.filter(function (x) { return x.fn === "insumo_editar" && x.body.p_cod === "TMP-0002"; })[0];
    out.descartaADepurar = !!desc && desc.body.p_categoria === "depurar";

    // 5) CATEGORÍAS: una caja por categoría, con sus unidades permitidas
    const cajas = document.querySelectorAll("#stkBody .stk-catbox");
    out.nCajasCat = cajas.length;                            // 6 (las 5 + depurar)
    out.catMuestraUnis = /Unidades permitidas/.test(document.getElementById("stkBody").innerHTML);
    out.catCuentaInsumos = /3 insumos|2 insumos|1 insumo/.test(cajas[0].textContent);

    // 6) El listado de insumos y el alta viven ADENTRO de la categoría
    out.listadoOculto = !document.getElementById("stkBody").innerHTML.match(/Agregar insumo a esta categor/);
    stkInsAbrir("fleje");
    out.listadoAbre = /Agregar insumo a esta categor/.test(document.getElementById("stkBody").innerHTML);
    const tblF = document.querySelectorAll("#stkBody .stk-catlist table");
    out.listadoFleje = tblF.length ? tblF[0].querySelectorAll("tbody tr").length : 0;   // 2 (22 y 5)
    out.listadoNoTraePP = tblF.length ? !/POLIPROPILENO/.test(tblF[0].innerHTML) : false;
    _stkIns.nuevoEn = "fleje"; stkRender();
    document.getElementById("nvCod").value = "7654321";
    await stkInsAlta("fleje");
    const alta = rpc.filter(function (x) { return x.fn === "insumo_alta"; })[0];
    out.altaEnSuCat = !!alta && alta.body.p_cod === "7654321" && alta.body.p_categoria === "fleje";

    // 7) Editar la categoría: nombre + unidades permitidas
    stkInsEdit("cat:cajas");
    out.catEditAbre = !!document.getElementById("cNom_cajas");
    stkInsCatUni("cajas", "MC");                              // agrega MC a las permitidas
    document.getElementById("cNom_cajas").value = "Cajas y embalaje";
    await stkInsCatGuardar("cajas");
    const cg = rpc.filter(function (x) { return x.fn === "insumo_cat_guardar"; })[0];
    out.catGuardaNombre = cg ? cg.body.p_nombre : null;       // "Cajas y embalaje"
    out.catGuardaUnis = cg ? cg.body.p_unidades.join(",") : null;   // "Paquetes,Uni,MC"

    // 8) UNIDADES con las que trabajamos
    out.haySecUnidades = /Unidades con las que trabajamos/.test(document.getElementById("stkBody").innerHTML);
    await stkInsUniSacar("MC");
    const us = rpc.filter(function (x) { return x.fn === "insumo_unidad_guardar"; })[0];
    out.uniSacar = us ? (us.body.p_nombre === "MC" && us.body.p_activa === false) : false;

    return out;
  });

  const pass =
    r.hayTabInsumos === true && /Pendientes de identificar/.test(r.primeraSec || "") &&
    r.pendCount === 2 && r.pendCodSugerido === "TMP-0001" && r.pendNombre === "Bolsa gris sin etiqueta" &&
    r.pendCat === "plastico" && r.pendUbicEditable === true && r.pendQty === "7" && r.pendUni === "Bolsas" &&
    r.tituloUnidades === true && r.sinColumnaOrden === true && r.pendMuestraLegajo === true &&
    r.rechazaTmpComoCod === true &&
    r.identCod === "1234567" && r.identNom === "Nylon especial" && r.identCat === "plastico" && r.identUbi === "AF9" &&
    r.ajusteN === 2 && r.ajusteSaca === true && r.ajustePone === true && r.ajusteSobreTmp === true &&
    r.descartaADepurar === true &&
    r.nCajasCat === 6 && r.catMuestraUnis === true &&
    r.listadoOculto === true && r.listadoAbre === true && r.listadoFleje === 2 && r.listadoNoTraePP === true &&
    r.altaEnSuCat === true &&
    r.catEditAbre === true && r.catGuardaNombre === "Cajas y embalaje" && r.catGuardaUnis === "Paquetes,Uni,MC" &&
    r.haySecUnidades === true && r.uniSacar === true &&
    errs.length === 0;
  console.log("ins-admin:", JSON.stringify(r));
  console.log("  pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
