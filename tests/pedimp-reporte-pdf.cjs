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
   cada pedido (gv_importados_curso_fob); y la fecha de llegada al mismo tamaño que las unidades.
   v26.39 (Luis): *"primero un resumen … después las cinco hojitas de lo que tengo que pedir, después las de
   lo que no estoy pidiendo y después las de discontinuos. No que esté por proveedor"* → con varios: hoja
   RESUMEN (proveedor · en curso · a pedir · % nacionalización · urgencia, por urgencia) y después UNA hoja
   por proveedor en cada tanda (pedido → sin pedir → discontinuos), en el orden del resumen. */
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
    if (/rpc\/gv_importados_pedidos_curso/.test(u)) return r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify([{ proveedor: "Fujian", usd: 260 }]) });
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
      const ths = [...d.querySelectorAll(".hoja:not(.res)")].slice(0, 1).map((h) => [...h.querySelectorAll("thead tr:last-child th")].map((x) => x.childNodes[0] ? x.childNodes[0].textContent : "").join("|"))[0] || "";
      const cods = [...d.querySelectorAll(".hoja:not(.res)")].map((h) => [...h.querySelectorAll("tbody tr:not(.prov)")].map((tr) => tr.cells[0].textContent.replace(/INAL$/, "")).join(","));
      // el renglón-rótulo de cada proveedor, por hoja (y en el pedido, sus totales en las columnas de FOB y m³)
      const bandas = [...d.querySelectorAll(".hoja")].map((h) => [...h.querySelectorAll("tbody tr.prov")].map((tr) => tr.cells[0].textContent).join(","));
      const tot = [...d.querySelectorAll(".hoja")].slice(0, 1).map((h) => [...h.querySelectorAll("tbody tr.prov")].map((tr) => [...tr.cells].map((c) => c.textContent).join("|")))[0] || [];
      const css = (/<style>([\s\S]*?)<\/style>/.exec(html) || [])[1] || "";
      return { ok, tits, ths, cods, bandas, tot, hojas: d.querySelectorAll(".hoja").length, portrait: /size:A4 portrait/.test(html), marca: /<th>Mca<\/th>/.test(html),
        pegado: /th,td\{[^}]*padding:1px 4px;/.test(css) && /th\.sp,td\.sp\{width:2px/.test(css),
        // arriba de «Llegan» de cada hoja de pedido (sólo si ese proveedor trae algo en camino)
        llega: Object.fromEntries([...d.querySelectorAll(".hoja")].filter((h) => /^Pedido/.test((h.querySelector("th.tit") || {}).textContent || ""))
          .map((h) => [h.querySelector("th.tit").textContent.replace(/\s+\d{2}\/\w{3}$/, ""), [...h.querySelectorAll("thead tr:last-child th")].some((x) => /^Llegan/.test(x.textContent)) ? (h.querySelector("thead tr").children[1] || {}).textContent : "sin Llegan"])),
        // v26.39: la hoja resumen (la primera) — sus filas y su encabezado
        res: [...d.querySelectorAll(".hoja.res tbody tr")].map((tr) => [...tr.cells].map((c) => c.childNodes[0] ? c.childNodes[0].textContent : "").join("|")),
        resTh: [...d.querySelectorAll(".hoja.res thead tr:last-child th")].map((x) => x.childNodes[0].textContent).join("|"),
        resPrio: [...d.querySelectorAll(".hoja.res tbody tr")].map((tr) => tr.cells[4] ? tr.cells[4].textContent : ""),
        resPrimera: !!d.querySelector(".hoja:first-child.res"),
        // v26.37: la fecha de llegada al mismo tamaño que las unidades (14 px, .fl), no en letra chica
        fecha: [...d.querySelectorAll(".hoja .fl")].map((x) => x.textContent).join(","), flCss: /\.fl\{display:block;font-size:14px/.test(css) };
    };
    btn[0].click();
    const provs = [...document.querySelectorAll("#impRepOv .imp-rep-prov")].map((c) => c.value + ":" + c.checked);
    const todos = await vista(false, false);
    const solo = await vista(true, false);
    const uno = await vista(false, true);
    // v26.39 — la URGENCIA por niveles (meses que le faltan a la línea para 8 meses, ponderado por consumo u$s)
    const it = (stk, proy, fob) => ({ cod: "X", proyUni: proy, stockUni: stk, enCurso: 0, fobUni: fob });
    const urg = {
      baja0: _pedImpUrgencia([it(900, 100, 1), it(1000, 100, 1)]),          // 9 y 10 m: ningún artículo < 8
      todos34: _pedImpUrgencia([it(300, 100, 1), it(400, 100, 1)]),         // 3 y 4 m → faltan 5 y 4
      mitad: _pedImpUrgencia([it(200, 100, 1), it(1200, 100, 1)]),          // 2 y 12 m → (6 + 0) / 2 = 3
      barato: _pedImpUrgencia([it(0, 100, 0.01), it(1000, 100, 10)]),       // el que casi no pesa en plata no manda
      sinProy: _pedImpUrgencia([it(5, 0, 1)])
    };
    // con sesión de supervisor: «Llegan» se valoriza con el FOB guardado del pedido, no con el de hoy
    window.sbAuth = Object.assign(window.sbAuth || {}, { getAccessToken: async () => "tok-prueba" });
    const guardado = await vista(true, false);
    return { provs, todos, solo, uno, guardado, urg, sinViejo: typeof _pedImpRepHtml === "undefined" };
  });
  if (r.err) { fail(r.err); await b.close(); return; }
  if (r.provs.join() !== "Fujian:true,Kangli:true") fail("el pop-up lista los proveedores tildados: " + r.provs);
  if (!r.todos.ok) fail("Imprimir tiene que mostrar la vista previa (iframe + botón Imprimir)");
  if (r.todos.tits.join("|") !== "Resumen|Pedido Kangli|Pedido Fujian|Sin pedir Kangli|Sin pedir Fujian|Discontinuos Kangli|Discontinuos Fujian")
    fail("varios proveedores: resumen, después una hoja de PEDIDO por proveedor, después las de SIN PEDIR y las de DISCONTINUOS: " + r.todos.tits.join("|"));
  if (!r.todos.resPrimera) fail("la hoja resumen va PRIMERA");
  if (r.todos.bandas.join("") !== "") fail("ya no hay renglones-rótulo: cada proveedor va en su propia hoja: " + r.todos.bandas.join(" / "));
  if (r.todos.resTh !== "Proveedor|En curso|A pedir|Nac.|Prioridad") fail("columnas del resumen: " + r.todos.resTh);
  // Fujian: 3 artículos a 8 · 1,5 · 3 meses → faltan 0 · 6,5 · 5 → 3,8 (prioridad 1); Kangli: 0,1 y 9 → 7,9 y 0 → 4,0 (prioridad 1)
  // → Kangli primero. En curso de Fujian = 260 de 🚢 En curso (no los 200 de sus artículos).
  const r0 = r.todos.res;
  if (!/^Kangli\|—\|1\.900\|\d+ %\|1$/.test(r0[0] || "") || !/^Fujian\|260\|3\.800\|\d+ %\|1$/.test(r0[1] || "") || !/^Total\|260\|5\.700\|\d+ %\|P1: 2$/.test(r0[2] || ""))
    fail("resumen: proveedor · en curso · a pedir · % nacionalización · prioridad, de la 1 a la 4, con su total: " + r0.join(" / "));
  if (!/^1faltan 4,0 m · 1 < 4 m · 1 < 8 m de 2/.test(r.todos.resPrio[0] || "") || !/^1faltan 3,8 m/.test(r.todos.resPrio[1] || ""))
    fail("la prioridad dice cuántos meses faltan (Kangli 4,0 · Fujian 3,8): " + r.todos.resPrio.join(" / "));
  if (!/^Cód\|Mca\|Descripción\|Foto\|/.test(r.todos.ths)) fail("columnas del PDF de Damián: " + r.todos.ths);
  if (!r.todos.portrait || !r.todos.marca) fail("A4 vertical y columna Marca (rótulo «Mca»), como el de Damián");
  if (!r.todos.pegado) fail("separadores de 2 px y 4 px de aire por lado en cada columna (v26.34, foto de Máx)");
  if (r.todos.cods.join(" / ") !== "904E / 902E,903E / 905E / 901E / ZZ2E / ZZ1E") fail("cada hoja con los artículos de SU proveedor, en el orden de urgencia: " + r.todos.cods.join(" / "));
  if (r.solo.tits.join("|") !== "Resumen|Pedido Kangli|Pedido Fujian") fail("«Sólo lo que genera pedido»: el resumen y las hojas de pedido: " + r.solo.tits.join("|"));
  if (r.uno.tits.join("|") !== "Pedido Fujian|Sin pedir Fujian|Discontinuos Fujian" || r.uno.bandas.join("") !== "") fail("un proveedor tildado: sus hojas con el nombre en el título y sin rótulos: " + r.uno.tits.join("|") + " · " + r.uno.bandas.join("|"));
  if (r.uno.cods[2] !== "ZZ1E") fail("un proveedor: sólo SUS discontinuos: " + r.uno.cods[2]);
  if (!r.sinViejo) fail("el reporte de una tabla (v24.76-79) no vuelve");
  if (r.todos.llega["Pedido Kangli"] !== "sin Llegan") fail("Kangli no trae nada en camino: su hoja no lleva «Llegan»: " + JSON.stringify(r.todos.llega));
  if (!fobLeido) fail("el PDF tiene que leer gv_importados_curso_fob con la sesión");
  if (r.todos.llega["Pedido Fujian"] !== "200" || r.uno.llega["Pedido Fujian"] !== "200") fail("arriba de «Llegan» (Fujian), el FOB de lo que viene (100 u × u$s 2): " + JSON.stringify(r.todos.llega) + " · " + JSON.stringify(r.uno.llega));
  if (r.guardado.llega["Pedido Fujian"] !== "350") fail("con el FOB guardado del pedido, lo que llega de Fujian vale 350 (100 u × u$s 3,50), no 200 con el FOB de hoy: " + JSON.stringify(r.guardado.llega));
  const U = r.urg;
  if (!(U.baja0.idx === 0 && U.baja0.etiqueta === "4")) fail("ningún artículo debajo de 8 meses → prioridad 4: " + JSON.stringify(U.baja0));
  if (!(Math.abs(U.todos34.idx - 4.5) < 1e-9 && U.todos34.etiqueta === "1" && U.todos34.c4 === 1 && U.todos34.c8 === 2)) fail("todos en 3-4 meses → prioridad 1 (faltan 4,5): " + JSON.stringify(U.todos34));
  if (!(Math.abs(U.mitad.idx - 3) < 1e-9 && U.mitad.nivel === 1)) fail("uno en 2 y otro en 12 meses → 3, prioridad 1: " + JSON.stringify(U.mitad));
  if (!(U.barato.idx < 0.01 && U.barato.etiqueta === "4")) fail("el artículo que casi no pesa en u$s no define la prioridad: " + JSON.stringify(U.barato));
  if (U.sinProy.etiqueta !== "SIN Est. Madre") fail("sin Est. Madre no hay urgencia que medir: " + JSON.stringify(U.sinProy));
  if (r.todos.fecha !== "01/11" || !r.todos.flCss) fail("la fecha de llegada al mismo tamaño que las unidades (.fl 14 px): " + r.todos.fecha + " · " + r.todos.flCss);
  await b.close();
  if (!process.exitCode) console.log("✓ pedimp-reporte-pdf");
})();
