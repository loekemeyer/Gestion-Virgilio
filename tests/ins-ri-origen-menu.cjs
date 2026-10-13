/* v29.82 (Luis, 13/10) — Recepción de insumos, menú reducido por categoría y UN SOLO «Enviar»:
   (a) el origen es una lista CERRADA (la de gv_insumo_origenes de esa categoría) y el texto libre
       queda escondido atrás de «✏ Otro origen»;
   (b) «✏ Otro origen» lo muestra (nunca se queda sin poder cargar lo que llegó);
   (c) si la base NO contesta, queda el texto libre de siempre (una lectura rota no es «no hay de
       dónde recibir»);
   (d) SC y SP no preguntan NADA: origen = Cervantes y la documentación arranca en el N° de remito,
       sin el paso de Remito / Factura / los dos;
   (e) terminada la documentación la recepción arranca SOLA: send({sinAviso}) y nunca se pasa por
       la pantalla de «seleccionado» a pedir un 2.º Enviar;
   (f) flejes de un PROVEEDOR = sólo los suyos, con los que GP2 no tiene asignados contados atrás
       de un botón (no se esconden); Cervantes = todos;
   (g) las bolsas sólo se envían a los inyectores que la base habilita (el excluido no se ofrece).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    window.alert = function () {}; window.confirm = function () { return true; };
    const CATS = [["plastico","🧪 Plásticos"],["fleje","🧵 Flejes"],["importados","🌎 Importados"],["partes_plasticas","🧩 Partes plásticas"],["cajas","📦 Cajas"],["parte_procesado","⚙ Procesado"],["partes_crudo","🔩 Crudo"]];
    window.insLoadMeta = async function () { INS_CATS = CATS.map(function (c) { return { k: c[0], lbl: c[1], unis: [], desc: "" }; }); };
    // el puente a GP2 no se stubea con _insGp2Opciones (es una declaración global: no se puede
    // deshacer con delete, y después (h) necesita la de verdad): se stubea su RPC.
    window.insGp2Rpc = async function () { return null; };
    window.insFetchCatalogo = async function () { return [
      { cod: "N°13", nombre: "84 x 1,75", categoria: "fleje", ubicacion: "K04" },      // Basconia
      { cod: "N°41", nombre: "90 x 1,20", categoria: "fleje", ubicacion: "K05" },      // Aperam
      { cod: "N°56", nombre: "100 x 1,00", categoria: "fleje", ubicacion: "K06" },     // sin proveedor
      { cod: "N° 43", nombre: "110 x 1,00", categoria: "fleje", ubicacion: "K07" },    // sin proveedor
      { cod: "G11", nombre: "crudo", categoria: "partes_crudo", ubicacion: "A1" }
    ]; };
    window.stockFetchSaldos = async function () { return {}; };
    window.insFetchSaldosXUni = async function () { return {}; };
    window.insFetchGp2Ri = async function () { return []; };
    // la base: sólo las dos RPC nuevas (lo demás ya está stubeado arriba)
    let origCalls = [], rpcCae = false;
    window.fetch = async function (url, opt) {
      const u = String(url || ""), body = (opt && opt.body) ? String(opt.body) : "";
      if (rpcCae) return { ok: false, status: 500, json: async function () { return null; }, text: async function () { return ""; } };
      if (/gv_insumo_origenes/.test(u)) {
        const cat = (JSON.parse(body || "{}") || {}).p_cat; origCalls.push(cat);
        const M = {
          plastico: [{ nombre: "Indarnyl", fuente: "proveedor", orden: 2 }, { nombre: "Beta Plásticos", fuente: "proveedor", orden: 2 }, { nombre: "Santa Rosa Plásticos", fuente: "proveedor", orden: 2 }],
          cajas: [{ nombre: "Corrugadora del Plata", fuente: "proveedor", orden: 2 }, { nombre: "Recicor", fuente: "proveedor", orden: 2 }],
          partes_plasticas: [{ nombre: "Cervantes", fuente: "cervantes", orden: 1 }, { nombre: "Kollplast", fuente: "inyector", orden: 2 }, { nombre: "Pat Bet Plast", fuente: "inyector", orden: 2 }, { nombre: "Pettofrezza Rafael", fuente: "inyector", orden: 2 }],
          // los 9 de verdad al 13/10: es la lista más larga y la que no entra en un celular
          fleje: ["Altrak","Aperam","Basconia","Brawin","Hermac","JL Metales","Resortes Charcas","Szapiro"].map(function (n) { return { nombre: n, fuente: "proveedor", orden: 2 }; }).concat([{ nombre: "Cervantes", fuente: "cervantes", orden: 1 }]),
          inyector: [{ nombre: "Kollplast", fuente: "inyector", orden: 2 }, { nombre: "Pat Bet Plast", fuente: "inyector", orden: 2 }, { nombre: "Pettofrezza Rafael", fuente: "inyector", orden: 2 }]
        };
        return { ok: true, status: 200, json: async function () { return M[cat] || []; } };
      }
      if (/gv_insumo_fleje_proveedor/.test(u)) {
        return { ok: true, status: 200, json: async function () { return [
          { cod: "N°13", comp_id: 1, proveedor: "Basconia" },
          { cod: "N°41", comp_id: 2, proveedor: "Aperam" },
          { cod: null, comp_id: 3, proveedor: "Brawin" }
        ]; } };
      }
      return { ok: true, status: 200, json: async function () { return []; }, text: async function () { return "[]"; } };
    };
    const hasta = async function (fn) { for (let i = 0; i < 200; i++) { if (fn()) return true; await new Promise(function (r) { setTimeout(r, 20); }); } return !!fn(); };
    const bots = function () { return Array.from(document.querySelectorAll("#insUbicProv button")).map(function (x) { return x.textContent.trim(); }); };
    const out = {};

    // ---- (a) cajas: la lista cerrada, con el texto libre escondido
    insRecibirCatGo("cajas");
    await hasta(function () { return bots().length > 1; });
    let bs = bots();
    out.a = bs.length === 3 && /Corrugadora del Plata/.test(bs[0]) && /Recicor/.test(bs[1]) && /Otro origen/.test(bs[2]) &&
      document.getElementById("insUbicLibre").style.display === "none" &&
      document.getElementById("insUbicContinuar").style.display === "none";
    // ---- (b) «Otro origen» devuelve el texto libre
    _insOrigenOtro();
    out.b = document.getElementById("insUbicLibre").style.display === "" && document.getElementById("insUbicContinuar").style.display === "";
    insUbicCancel();

    // ---- (a2) partes plásticas: los inyectores + Cervantes, y el apodo a la vista
    insRecibirCatGo("partes_plasticas");
    await hasta(function () { return bots().length > 1; });
    bs = bots();
    out.a2 = bs.length === 5 && /Cervantes/.test(bs[0]) && /Kollplast/.test(bs[1]) && /Pat Bet Plast/.test(bs[2]) && /Manolo/.test(bs[2]) && /Pettofrezza/.test(bs[3]);
    insUbicCancel();

    // ---- (c) la base no contesta → texto libre de siempre
    rpcCae = true;
    insRecibirCatGo("cajas");
    await hasta(function () { return document.getElementById("insUbicProv") && document.getElementById("insUbicProv").innerHTML === ""; });
    out.c = bots().length === 0 && document.getElementById("insUbicLibre").style.display !== "none" &&
      document.getElementById("insUbicContinuar").style.display !== "none";
    insUbicCancel(); rpcCae = false;

    // ---- (d) SC / SP: ni origen ni tipo de documento — directo al N° de remito
    let envios = [];
    window.send = async function (o) { envios.push({ sel: selected, opt: o }); };
    legajoInput.value = "104";
    insRecibirCatGo("partes_crudo");
    await hasta(function () { return !!document.getElementById("insDocNroRemito"); });
    const dh = document.getElementById("insDocBody").innerHTML;
    out.d = document.getElementById("insUbicModal") === null || document.getElementById("insUbicModal").style.display !== "flex";
    out.d = out.d && window._insUbicacion === "Cervantes" && window._insDocState.tipoDoc === "remito" &&
      !/Remito y Factura/.test(dh) && !!document.getElementById("insDocFechaRemito") && !document.getElementById("insDocNroFactura") &&
      /insRecibirCat\(\)/.test(dh);   // el «‹ Atrás» vuelve a las categorías, no a un paso que no existe

    // ---- (e) un solo «Enviar»: terminada la documentación arranca solo
    document.getElementById("insDocNroRemito").value = "12345";
    insDocOk("RI");
    out.e = envios.length === 1 && envios[0].sel === "RI" && !!(envios[0].opt && envios[0].opt.sinAviso) &&
      document.getElementById("selectedArea").classList.contains("hidden") &&
      window._insRiCat === "partes_crudo";   // la lista abre en SU categoría, no en todas

    // ---- (f) flejes por proveedor
    insRecibirCatGo("fleje");
    await hasta(function () { return bots().length > 1; });
    /* la lista más larga (9 orígenes + «Otro») NO entra en un celular: el cuadro tiene que
       SCROLLEAR con el borde de arriba alcanzable (un overlay centrado con overflow deja el
       título inalcanzable) y cada botón tiene que seguir siendo tocable (≥ 44 px). */
    const ovU = document.getElementById("insUbicModal"), card = ovU.querySelector("div");
    const chicos = Array.from(ovU.querySelectorAll("button")).filter(function (x) {
      const r = x.getBoundingClientRect(); return r.height > 0 && r.height < 44;
    }).map(function (x) { return x.textContent.trim(); });
    out.ui = ovU.scrollHeight > ovU.clientHeight && card.getBoundingClientRect().top >= 0 &&
      ovU.scrollTop === 0 && chicos.length === 0;
    out.chicos = chicos;
    const ib = bots().findIndex(function (t) { return /Basconia/.test(t); });
    insUbicOrigen(ib, "RI", "fleje");
    out.f0 = window._insProvFleje === "Basconia";
    window._insRiCat = "fleje";
    await showInsumoModal("RI", "104");
    let vis = function () { return Array.from(document.querySelectorAll("#insBody .ins-itbtn .ins-itcod")).map(function (x) { return x.textContent.trim(); }).sort(); };
    const h1 = document.getElementById("insBody").innerHTML;
    out.f = _ins.provFleje === "Basconia" && JSON.stringify(vis()) === JSON.stringify(["N°13"]) &&
      /Flejes y alambres de <b>Basconia<\/b>/.test(h1) && />Otros \(2\)</.test(h1);
    /* v29.87: «Otros» muestra SÓLO los que todavía no están vinculados (no los mezcla con los
       del proveedor) y se vuelve con «‹ Volver a los de Basconia». */
    insProvOtros();
    const h2 = document.getElementById("insBody").innerHTML;
    out.f2 = JSON.stringify(vis()) === JSON.stringify(["N° 43", "N°56"].sort()) &&
      /todavía no están asignados/.test(h2) && /‹ Volver a los de Basconia/.test(h2) && !/N°13/.test(h2);
    insProvOtros();
    out.f2b = JSON.stringify(vis()) === JSON.stringify(["N°13"]);
    // buscando se ve TODO, aunque no sea de ese proveedor
    _ins.filtro = "N°41"; insRender();
    out.f3 = JSON.stringify(vis()) === JSON.stringify(["N°41"]);
    _ins.filtro = ""; insRender();
    // Cervantes → todos los flejes
    insBack(); closeIns(true);
    insRecibirCatGo("fleje");
    await hasta(function () { return bots().length > 1; });
    insUbicOrigen(bots().findIndex(function (t) { return /Cervantes/.test(t); }), "RI", "fleje");
    out.g0 = window._insProvFleje === null;
    window._insRiCat = "fleje";
    await showInsumoModal("RI", "104");
    out.g = !_ins.provFleje && JSON.stringify(vis()) === JSON.stringify(["N° 43", "N°13", "N°41", "N°56"].sort()) &&
      !/Flejes de <b>/.test(document.getElementById("insBody").innerHTML);
    closeIns(true);

    // ---- (h) EI: los inyectores que la base habilita
    // el #insUbicGp2 del modal de ubicación ya existe (quedó del paso anterior, oculto)
    window._insGp2Cache = null;
    window.insGp2Rpc = async function (n) {
      if (n === "material_virgilio_bundle") return { inyectores: ["JL Matriceria", "Kollplast", "Pat Bet Plast", "Pettofrezza Rafael"], materiales: [] };
      return null;
    };
    await _insGp2Opciones("EI", true);
    const hb = document.getElementById("insUbicGp2").innerHTML;
    out.h = /Kollplast/.test(hb) && /Pat Bet Plast/.test(hb) && /Pettofrezza/.test(hb) && !/JL Matriceria/.test(hb) &&
      (window._insGp2Cache.mv.inyectores || []).length === 3;
    /* ---- (i) v29.87 (Luis: "crea tabla si sólo está en el front el dato"): cajas por paquete,
       marcas y apodos salen de la BASE; si no contesta, quedan los defaults del front. */
    const defs = { paq: INS_CAJA_X_PAQ, marcas: INS_MARCAS.join(","), cajas: INS_CAJA_MARCAS.join(","), apodo: INS_INY_APODO["Pat Bet Plast"] };
    let cfgCae = false;
    window.fetch = async function (u) {
      if (cfgCae) return { ok: false, status: 500, json: async () => null };
      if (/gv_insumo_config/.test(String(u))) return { ok: true, json: async () => [
        { clave: "caja_x_paquete", valor: 30, valor_texto: null },
        { clave: "marcas", valor: null, valor_texto: "Loeke, Chef, Mixto, Krea" },
        { clave: "marcas_cajas", valor: null, valor_texto: "Loeke,Chef" }] };
      if (/gv_insumo_apodos/.test(String(u))) return { ok: true, json: async () => [{ nombre: "Kollplast", apodo: "Koll" }] };
      return { ok: true, json: async () => [] };
    };
    await insFetchConfig();
    out.i = INS_CAJA_X_PAQ === 30 && INS_MARCAS.join(",") === "Loeke,Chef,Mixto,Krea" &&
      INS_INY_APODO["Kollplast"] === "Koll" && INS_INY_APODO["Pat Bet Plast"] === undefined &&
      defs.paq === 25 && defs.marcas === "Loeke,Chef,Mixto" && defs.cajas === "Loeke,Chef" && defs.apodo === "Manolo";
    cfgCae = true;
    await insFetchConfig();   // la base no contesta: NO se pierde lo que ya había
    out.i2 = INS_CAJA_X_PAQ === 30 && INS_MARCAS.join(",") === "Loeke,Chef,Mixto,Krea";
    out.origCalls = origCalls.join(",");
    return out;
  });
  await b.close();
  const keys = ["a","b","a2","c","d","e","f0","ui","f","f2","f2b","f3","g0","g","h","i","i2"];
  const malos = keys.filter((k) => !r[k]);
  if (malos.length || errs.length) {
    console.error("✗ ins-ri-origen-menu:", malos.join(", ") || "(ok)", "| errores:", errs.join(" | ") || "(ninguno)");
    console.error(JSON.stringify(r, null, 1));
    process.exit(1);
  }
  console.log("✓ ins-ri-origen-menu: origen cerrado por categoría (" + r.origCalls + "), SC/SP sin preguntas, un solo Enviar, flejes por proveedor, inyectores habilitados");
})();
