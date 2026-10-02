/* 🖨 IMPRIMIR PDF de arriba en Pedidos Importación.
   v24.76 (Luis): botón en la barra de arriba + pop-up con los proveedores + «Sólo lo que genera pedido»
   + vista previa.  v25.13 (Thomas, 30/09): *"que el de arriba tenga la misma funcionalidad de hoy (que
   te muestre todos) pero con la lógica del PDF de Damián"* → la salida son las hojas de Damián (pedido ·
   sin pedir · discontinuos) de CADA proveedor tildado, una tanda atrás de otra.
   v26.31 (Luis, 02/10): *"cuando se eligen múltiples proveedores debería agrupar en con pedido (todos
   los proveedores discriminando), sin pedido (…), discontinuo (…)"* → con varios tildados, UNA hoja de
   cada tipo con todos adentro y un renglón-rótulo (tr.prov) por proveedor; con uno solo, como antes.
   Y *"optimización horizontal absoluta"*: separadores de 2 px, rótulo «Mca»; v26.34: 4 px de aire por lado
   («el ancho de las columnas como la de la foto 1») y el FOB u$s de lo que llega en «Llegan».
   v26.37 (Luis): *"que guarde el FOB del pedido en curso"* → «Llegan» se valoriza con el FOB GUARDADO de
   cada pedido (gv_importados_curso_fob); y la fecha de llegada al mismo tamaño que las unidades. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1600, height: 900 } });
  // los discontinuos (Importados.activo = false): uno de Fujian y uno de Kangli; lo demás vacío.
  // v26.37: gv_importados_curso_fob = el FOB GUARDADO de lo que viene (902E: 100 u pedidas a u$s 3,50 = 350;
  // el maestro hoy dice u$s 2). Sólo responde si la request lleva sesión (sin sesión, el PDF usa el FOB de hoy).
  let fobLeido = 0;
  await p.route("**/rest/v1/**", (r) => {
    const u = r.request().url();
    if (/rpc\/gv_importados_curso_fob/.test(u)) { fobLeido++; return r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify([{ importado_id: "902E", pendiente: 100, usd: 350, uni_con_fob: 100 }]) }); }
    return r.fulfill({ status: 200, contentType: "application/json", body: /activo=eq\.false/.test(u)
    ? JSON.stringify([{ cod_art: "ZZ1E", marca: "LK", descripcion: "Viejo 1", stock_total: 3, proveedor: "Fujian" }, { cod_art: "ZZ2E", marca: "CH", descripcion: "Viejo 2", stock_total: 0, proveedor: "Kangli" }]) : "[]" }); });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  await p.waitForFunction(() => typeof pedImpRepImprimir === "function" && typeof _pedImpDamianHojas === "function", null, { timeout: 20000 });
  const r = await p.evaluate(async () => {
    const mk = (cod, prov, stk, cam, pide) => { const it = { cod, key: cod, prov, desc: "Art " + cod, proyUni: 100, objetivoUni: 1000, stockUni: stk, enCurso: cam, reingresoEst: cam ? "2026-11-01" : null, meses: 10,
      aPedirUni: pide ? 950 : 0, uniMaster: 50, uxc: 10, fobUni: 2, m3Master: 0.1, det: [{ id: cod, curso: 0, marca: "LK" }] }; it.aPedirCajas = pide ? 19 : 0; return it; };
    const items = [mk("901E", "Fujian", 800, 0, false), mk("902E", "Fujian", 50, 100, true), mk("903E", "Fujian", 300, 0, true), mk("904E", "Kangli", 10, 0, true), mk("905E", "Kangli", 900, 0, false)];
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items, meses: 10, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: true, mcOverride: {} };
    window._NAC_TASAS && (_NAC_TASAS.moq = 0);
    _pedImpRender();
    const btn = [...document.querySelectorAll("#stkPopBody .pedimp-rep-btn")];
    if (btn.length !== 1) return { err: "botón IMPRIMIR PDF: " + btn.length };
    const vista = async (soloPed, soloFujian) => {
      if (!document.getElementById("impRepOv")) btn[0].click();
      [...document.querySelectorAll("#impRepOv .imp-rep-prov")].forEach((c) => { c.checked = !soloFujian || c.value === "Fujian"; });
      document.getElementById("impRepSoloPed").checked = soloPed;
      await pedImpRepImprimir();
      const ifr = document.querySelector("#impRepOv iframe.imp-rep-prev");
      const ok = !!ifr && !!document.querySelector("#impRepOv .imp-rep-print");
      const html = ifr ? ifr.srcdoc : "";
      document.getElementById("impRepOv") && document.getElementById("impRepOv").remove();
      const d = new DOMParser().parseFromString(html, "text/html");
      const tits = [...d.querySelectorAll("th.tit, .tit3")].map((x) => x.textContent.replace(/\s+\d{2}\/\w{3}$/, "").trim());
      const ths = [...d.querySelectorAll(".hoja")].slice(0, 1).map((h) => [...h.querySelectorAll("thead tr:last-child th")].map((x) => x.childNodes[0] ? x.childNodes[0].textContent : "").join("|"))[0] || "";
      const cods = [...d.querySelectorAll(".hoja")].map((h) => [...h.querySelectorAll("tbody tr:not(.prov)")].map((tr) => tr.cells[0].textContent.replace(/INAL$/, "")).join(","));
      // el renglón-rótulo de cada proveedor, por hoja (y en el pedido, sus totales en las columnas de FOB y m³)
      const bandas = [...d.querySelectorAll(".hoja")].map((h) => [...h.querySelectorAll("tbody tr.prov")].map((tr) => tr.cells[0].textContent).join(","));
      const tot = [...d.querySelectorAll(".hoja")].slice(0, 1).map((h) => [...h.querySelectorAll("tbody tr.prov")].map((tr) => [...tr.cells].map((c) => c.textContent).join("|")))[0] || [];
      const css = (/<style>([\s\S]*?)<\/style>/.exec(html) || [])[1] || "";
      return { ok, tits, ths, cods, bandas, tot, hojas: d.querySelectorAll(".hoja").length, portrait: /size:A4 portrait/.test(html), marca: /<th>Mca<\/th>/.test(html),
        pegado: /th,td\{[^}]*padding:1px 4px;/.test(css) && /th\.sp,td\.sp\{width:2px/.test(css),
        topLlega: (d.querySelector(".hoja thead tr").children[1] || {}).textContent,
        // v26.37: la fecha de llegada al mismo tamaño que las unidades (14 px, .fl), no en letra chica
        fecha: [...d.querySelectorAll(".hoja .fl")].map((x) => x.textContent).join(","), flCss: /\.fl\{display:block;font-size:14px/.test(css) };
    };
    btn[0].click();
    const provs = [...document.querySelectorAll("#impRepOv .imp-rep-prov")].map((c) => c.value + ":" + c.checked);
    const todos = await vista(false, false);
    const solo = await vista(true, false);
    const uno = await vista(false, true);
    // con sesión de supervisor: «Llegan» se valoriza con el FOB guardado del pedido, no con el de hoy
    window.sbAuth = Object.assign(window.sbAuth || {}, { getAccessToken: async () => "tok-prueba" });
    const guardado = await vista(true, false);
    return { provs, todos, solo, uno, guardado, sinViejo: typeof _pedImpRepHtml === "undefined" };
  });
  if (r.err) { fail(r.err); await b.close(); return; }
  if (r.provs.join() !== "Fujian:true,Kangli:true") fail("el pop-up lista los proveedores tildados: " + r.provs);
  if (!r.todos.ok) fail("Imprimir tiene que mostrar la vista previa (iframe + botón Imprimir)");
  if (r.todos.tits.join("|") !== "Pedido|Sin pedir|Discontinuos")
    fail("varios proveedores: UNA hoja de cada tipo (pedido · sin pedir · discontinuos), no una tanda por proveedor: " + r.todos.tits.join("|"));
  if (r.todos.bandas.join(" / ") !== "Fujian,Kangli / Fujian,Kangli / Fujian,Kangli") fail("cada hoja discrimina a los proveedores con su renglón-rótulo: " + r.todos.bandas.join(" / "));
  if (r.todos.tot.join(" / ") !== "Fujian|200|10 m|||3.800|3,8 / Kangli|—|10 m|||1.900|1,9") fail("el rótulo del proveedor lleva SUS totales (FOB de lo que llega · meses · FOB · m³): " + r.todos.tot.join(" / "));
  if (!/^Cód\|Mca\|Descripción\|Foto\|/.test(r.todos.ths)) fail("columnas del PDF de Damián: " + r.todos.ths);
  if (!r.todos.portrait || !r.todos.marca) fail("A4 vertical y columna Marca (rótulo «Mca»), como el de Damián");
  if (!r.todos.pegado) fail("separadores de 2 px y 4 px de aire por lado en cada columna (v26.34, foto de Máx)");
  if (r.todos.topLlega !== "200") fail("arriba de «Llegan», el FOB general de lo que viene (100 u × u$s 2): " + r.todos.topLlega);
  if (r.todos.cods.join(" / ") !== "902E,903E,904E / 901E,905E / ZZ1E,ZZ2E") fail("cada hoja con los artículos de todos, por proveedor y por urgencia: " + r.todos.cods.join(" / "));
  if (r.solo.tits.join("|") !== "Pedido" || r.solo.bandas.join() !== "Fujian,Kangli") fail("«Sólo lo que genera pedido» deja sólo la hoja del pedido, con los dos: " + r.solo.tits.join("|") + " · " + r.solo.bandas.join());
  if (r.uno.tits.join("|") !== "Pedido Fujian|Sin pedir Fujian|Discontinuos Fujian" || r.uno.bandas.join("") !== "") fail("un proveedor tildado: sus hojas con el nombre en el título y sin rótulos: " + r.uno.tits.join("|") + " · " + r.uno.bandas.join("|"));
  if (r.uno.cods[2] !== "ZZ1E") fail("un proveedor: sólo SUS discontinuos: " + r.uno.cods[2]);
  if (!r.sinViejo) fail("el reporte de una tabla (v24.76-79) no vuelve");
  if (r.guardado.topLlega !== "350" || !/^Fujian\|350\|/.test(r.guardado.tot[0] || "")) fail("con el FOB guardado del pedido, lo que llega vale 350 (100 u × u$s 3,50), no 200 con el FOB de hoy: " + r.guardado.topLlega + " · " + r.guardado.tot[0]);
  if (!fobLeido) fail("el PDF tiene que leer gv_importados_curso_fob con la sesión");
  if (r.todos.fecha !== "01/11" || !r.todos.flCss) fail("la fecha de llegada al mismo tamaño que las unidades (.fl 14 px): " + r.todos.fecha + " · " + r.todos.flCss);
  await b.close();
  if (!process.exitCode) console.log("✓ pedimp-reporte-pdf");
})();
