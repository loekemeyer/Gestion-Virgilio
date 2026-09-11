/* Regresión v15.76 — el editor de LUGARES (GV_Lugar / GV_Lugar_Item).

   Reemplaza a los dos editores viejos (Planimetría + Capacidad por sector), que
   escribían a dos tablas que ahora son una. Lo que hay que proteger es el cambio de
   MODELO, no la pantalla:

     Planimetria    clave `cod`                 → un código, UN lugar
     GV_Lugar_Item  clave (sector, cod, clase)  → un código en VARIOS lugares

   Chequea:
   - La lista se para en el LUGAR y muestra los códigos que tiene adentro (chips).
   - Buscar por CÓDIGO filtra lugares: tipear "438E" trae los 4 lugares donde está.
     Eso es justo lo que la tabla vieja no podía contestar.
   - La pestaña "Por código" hace el camino inverso: un código → todos sus lugares,
     ordenados por el orden del recorrido.
   - Un lugar sin nada dice "libre".
   - `clase` separa artículo de insumo en el MISMO lugar y el MISMO código (son cosas
     distintas y por eso está en la PK).
   - Agregar manda sector+cod+clase y NO manda empresa: la empresa la da el lugar.
   - Borrar avisa distinto si al código le quedan otros lugares o si es el único.
   - Sin permisos de escritura (401/403) el editor lo DICE y nombra el SQL que falta,
     en vez de fallar mudo.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    const posts = [];
    // Datos de prueba: el 438E en cuatro lugares de LK y dos de CH, un lugar libre,
    // y el 437E como artículo E insumo en el mismo lugar.
    _lug = {
      lugares: [
        { sector: "F13", tipo: "gondola", empresa: "LK", orden: 104, uso: null, activo: true },
        { sector: "F14", tipo: "gondola", empresa: "LK", orden: 105, uso: null, activo: true },
        { sector: "L05", tipo: "gondola", empresa: "CH", orden: 174, uso: null, activo: true },
        { sector: "X11", tipo: "rack",    empresa: "LK", orden: 816, uso: null, activo: true },
        { sector: "Z99", tipo: "gondola", empresa: "LK", orden: 900, uso: null, activo: true },
        { sector: "K01", tipo: "rack",    empresa: "IN", orden: 700, uso: null, activo: true }
      ],
      items: [
        { sector: "F13", cod: "438E", clase: "articulo", cajas_max: 40, activo: true },
        { sector: "F14", cod: "438E", clase: "articulo", cajas_max: 40, activo: true },
        { sector: "L05", cod: "438E", clase: "articulo", cajas_max: 12, activo: true },
        { sector: "X11", cod: "438E", clase: "articulo", cajas_max: null, activo: true },
        { sector: "K01", cod: "437E", clase: "articulo", cajas_max: 5, activo: true },
        { sector: "K01", cod: "437E", clase: "insumo",   cajas_max: 9, activo: true }
      ]
    };
    window.requireSupervisor = function () { return true; };
    window.facAuthWriteHeaders = async function () { return { "Content-Type": "application/json" }; };
    window.authNoSesionMsg = function (m) { return m; };
    const realFetch = window.fetch;
    let httpStatus = 201;
    window.fetch = async function (url, opts) {
      posts.push({ url: String(url), method: (opts && opts.method) || "GET", body: opts && opts.body ? JSON.parse(opts.body) : null });
      return { ok: httpStatus < 400, status: httpStatus, json: async () => [] };
    };
    window.supaFetchAllSafe = async function () { return []; };   // lugFetch(true) no pisa _lug de prueba
    const origFetch = lugFetch;
    window.lugFetch = async function () { return _lug; };

    // --- (a) la lista se para en el LUGAR y muestra sus códigos
    lugRender("");
    const html = document.getElementById("lugList").innerHTML;
    out.listaPorLugar = html.indexOf(">F13<") >= 0 && html.indexOf(">L05<") >= 0;
    out.muestraCodigos = html.indexOf("438E") >= 0;
    out.muestraEmpresaDelLugar = html.indexOf("LK") >= 0 && html.indexOf("CH") >= 0;
    out.lugarLibreDiceLibre = html.indexOf("libre") >= 0;          // Z99 no tiene nada

    // --- (b) buscar por CÓDIGO filtra LUGARES (lo que la tabla vieja no podía)
    lugRender("438E");
    const h2 = document.getElementById("lugList").innerHTML;
    out.buscaPorCodTraeLugares = ["F13", "F14", "L05", "X11"].every(s => h2.indexOf(">" + s + "<") >= 0);
    out.buscaPorCodExcluyeElResto = h2.indexOf(">Z99<") < 0 && h2.indexOf(">K01<") < 0;

    // --- (c) artículo e insumo con el MISMO código en el MISMO lugar
    lugRender("K01");
    const h3 = document.getElementById("lugList").innerHTML;
    // dos chips para el mismo código en el mismo lugar: uno artículo, uno insumo.
    // (No se cuenta "437E" a secas: aparece varias veces por los onclick del ✕.)
    // ojo: el contenedor es class="lug-chips" y también empieza con lug-chip → se excluye
    const chipsK01 = (h3.match(/class="lug-chip(?: lug-chip-ins)?"/g) || []);
    out.claseSeparaArtDeInsumo = chipsK01.length === 2
      && chipsK01.filter(c => c.indexOf("lug-chip-ins") >= 0).length === 1;

    // --- (d) pestaña inversa: un código → todos sus lugares, por orden de recorrido
    lugSetTab("cod");
    lugRenderCod("438E");
    const h4 = document.getElementById("lugCodList").innerHTML;
    out.inversoLista4 = h4.indexOf("4 lugares") >= 0;
    out.inversoOrdenRecorrido = h4.indexOf("F13") < h4.indexOf("L05") && h4.indexOf("L05") < h4.indexOf("X11");

    // --- (e) agregar: manda sector+cod+clase, NUNCA empresa
    lugSetTab("lugar");
    lugRender("F13");
    document.getElementById("lugCod_F13").value = "505";
    document.getElementById("lugCap_F13").value = "30";
    await lugAddItem("F13");
    const post = posts.filter(x => x.method === "POST").pop();
    out.agregaPost = !!post && post.url.indexOf("GV_Lugar_Item") >= 0;
    out.agregaOnConflict = !!post && post.url.indexOf("on_conflict=sector,cod,clase") >= 0;
    out.agregaMandaLugar = !!post && post.body.sector === "F13" && post.body.cod === "505" && post.body.clase === "articulo";
    out.agregaCajasMax = !!post && post.body.cajas_max === 30;
    out.NOmandaEmpresa = !!post && !("empresa" in post.body);

    // --- (f) borrar: avisa distinto según le queden otros lugares o sea el único
    const avisos = [];
    window.confirm = function (m) { avisos.push(m); return true; };
    await lugDelItem("F13", "438E", "articulo");     // le quedan F14, L05, X11
    await lugDelItem("K01", "437E", "insumo");       // único lugar de ese (cod, clase)
    out.borraAvisaOtros = /otros 3 lugar/.test(avisos[0] || "");
    out.borraAvisaUnico = /ÚNICO lugar/.test(avisos[1] || "");
    const del = posts.filter(x => x.method === "DELETE").pop();
    out.borraPorLos3 = !!del && del.url.indexOf("sector=eq.K01") >= 0 && del.url.indexOf("cod=eq.437E") >= 0 && del.url.indexOf("clase=eq.insumo") >= 0;

    // --- (g) sin permisos: lo dice y nombra el SQL que falta
    httpStatus = 401;
    document.getElementById("lugCod_F13") && (document.getElementById("lugCod_F13").value = "600");
    lugRender("F13"); document.getElementById("lugCod_F13").value = "600";
    await lugAddItem("F13");
    const st = document.getElementById("lugStatus").textContent;
    out.sinPermisoAvisa = st.indexOf("401") >= 0 && st.indexOf("gv_lugar_editor.sql") >= 0;

    window.fetch = realFetch; window.lugFetch = origFetch;
    return out;
  });
  const bad = Object.entries(r).filter(([, v]) => v !== true).map(([k]) => k);
  console.log("lugar-editor:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none");
  await b.close();
  if (bad.length || errs.length) { console.error("✗ FALLA:", bad.join(", ") || "pageerrors"); process.exit(1); }
  console.log("✓ OK");
})();
