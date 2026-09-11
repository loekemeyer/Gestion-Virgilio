/* v15.72 — Solapa "🚢 En curso" del módulo de importación: los pedidos YA HECHOS, separados del
   generador. Se verifica: que la solapa exista y abra, que arme UNA fila por pedido con las dos
   fechas (embarque y llegada) y los días que faltan, que avise los que no tienen embarque, que
   editar una fecha mande la RPC del PEDIDO entero (no línea por línea), y que el detalle por
   artículo se pida con gv_importado_pedido_lineas. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    // hoy fijo para que los "faltan N días" no dependan del día que se corra el test
    const HOY = "2026-09-11";
    window._impCursoHoy = () => HOY;
    const PEDIDOS = [
      { pedido_ref: "PI B260601", proveedor: "Becky", n_lineas: 19, unidades: 41944, pendiente: 41944,
        llegadas: 0, fecha_embarque: null, fecha_llegada: "2026-09-29", lineas_sin_fecha: 0,
        usd: "23622.48", m3: "27.752" },
      { pedido_ref: "PI OL-10139", proveedor: "Ownland", n_lineas: 13, unidades: 98376, pendiente: 98376,
        llegadas: 0, fecha_embarque: "2026-11-08", fecha_llegada: "2026-12-18", lineas_sin_fecha: 0,
        usd: "46626.00", m3: "21.941" },
      { pedido_ref: "PI VIEJO", proveedor: "Kangli", n_lineas: 2, unidades: 500, pendiente: 500,
        llegadas: 0, fecha_embarque: "2026-08-01", fecha_llegada: "2026-09-05", lineas_sin_fecha: 0,
        usd: "100.00", m3: "1.000" }
    ];
    const LINEAS = [
      { bache_id: 1, importado_id: 16, cod_art: "601E", marca: "LK", descripcion: "Rallador",
        unidades: 3600, pendiente: 3600, fecha_reingreso: "2026-09-29", usd: "2376.00", m3: "1.2" }
    ];
    const calls = [];
    window.fetch = async (u, o) => {
      const url = String(u); calls.push({ u: url.split("/rest/v1/")[1] || url, b: o && o.body });
      let data = [];
      if (url.indexOf("gv_importados_pedidos_curso") >= 0) data = PEDIDOS;
      else if (url.indexOf("gv_importado_pedido_lineas") >= 0) data = LINEAS;
      else if (url.indexOf("gv_importado_pedido_fechas") >= 0) data = { filas: 19 };
      return { ok: true, status: 200, json: async () => data, text: async () => "" };
    };

    // (1) la solapa está en la barra del módulo y abre la pantalla
    out.tab = _impTabsHtml("ped").indexOf("openImpEnCurso()") >= 0;
    await openImpEnCurso();
    out.kind = _stkPop && _stkPop.kind;
    const body = document.getElementById("stkPopBody");
    out.txt = body.innerText.replace(/\s+/g, " ");

    // (2) una fila por pedido, con las dos fechas visibles
    // OJO: ".imcu-tbl tbody tr" también matchea las filas de la tabla de detalle anidada.
    // Se cuentan sólo las filas propias del tbody externo, sacando la del detalle.
    const filasPedido = () => {
      const t = document.getElementById("stkPopBody").querySelector(".imcu-tbl");
      return t ? [...t.tBodies[0].rows].filter((tr) => !tr.querySelector(".imcu-det")) : [];
    };
    window.__filasPedido = filasPedido;
    const trs = filasPedido();
    out.filas = trs.length;
    out.fila0 = trs[0].innerText.replace(/\s+/g, " ").trim();
    out.inputs0 = [...trs[0].querySelectorAll("input")].map((i) => i.value);
    out.inputs1 = [...trs[1].querySelectorAll("input")].map((i) => i.value);

    // (3) días: llegada 29/09 desde el 11/09 = 18; embarque 08/11 = 58; el vencido da negativo
    out.d18 = _impCursoDias("2026-09-29");
    out.d58 = _impCursoDias("2026-11-08");
    out.dneg = _impCursoDias("2026-09-05");
    out.estadoSinEmb = _impCursoEstado(PEDIDOS[0]);
    out.estadoEspera = _impCursoEstado(PEDIDOS[1]);
    // ya embarcado y todavía en viaje (embarque pasado, llegada futura)
    out.estadoViaje = _impCursoEstado({ fecha_embarque: "2026-08-25", fecha_llegada: "2026-10-10", n_lineas: 1 });
    out.estadoAtras = _impCursoEstado(PEDIDOS[2]);
    out.aviso = /1 pedido\(s\) sin fecha de embarque/.test(out.txt);

    // (4) editar el EMBARQUE manda una sola RPC por el pedido entero
    calls.length = 0;
    await impCursoSetEmbarque(encodeURIComponent("PI B260601"), encodeURIComponent("Becky"), "2026-08-20");
    out.callEmb = calls.filter((c) => c.u.indexOf("rpc/gv_importado_pedido_fechas") === 0).map((c) => JSON.parse(c.b));

    // (5) editar la LLEGADA usa el otro flag (resync de reingreso_est en el backend)
    calls.length = 0;
    await impCursoSetLlegada(encodeURIComponent("PI B260601"), encodeURIComponent("Becky"), "2026-10-02");
    out.callLleg = calls.filter((c) => c.u.indexOf("rpc/gv_importado_pedido_fechas") === 0).map((c) => JSON.parse(c.b));

    // (6) fichas de filtro: proveedor y pedido, con los totales recalculados (v15.73)
    out.chipsProv = [...body.querySelectorAll(".imcu-fila")].length ? [...body.querySelectorAll("button")].map((b) => b.innerText.trim()) : [];
    impCursoSetProv(encodeURIComponent("Becky"));
    out.trasProv = filasPedido().length;
    out.kpiProv = document.getElementById("stkPopBody").innerText.replace(/\s+/g, " ");
    impCursoSetProv("");
    impCursoSetRef(encodeURIComponent("PI OL-10139"));
    await new Promise((res) => setTimeout(res, 60));
    const b2 = document.getElementById("stkPopBody");
    out.trasRef = filasPedido().length;
    out.kpiRef = b2.innerText.replace(/\s+/g, " ");
    out.refAbre = !!b2.querySelector(".imcu-det");
    out.dbg = { prov: _stkPop.provFiltro, ref: _stkPop.refFiltro, vista: _impCursoVista().length, abierto: _stkPop.abierto, nrows: (_stkPop.rows || []).length };   // parado en un pedido, el detalle se abre solo
    impCursoSetRef("");
    out.trasLimpiar = filasPedido().length;

    // (7) abrir el detalle del pedido pide las líneas
    calls.length = 0;
    await impCursoToggle(encodeURIComponent("PI B260601"), encodeURIComponent("Becky"));
    await new Promise((res) => setTimeout(res, 60));
    out.callLin = calls.filter((c) => c.u.indexOf("rpc/gv_importado_pedido_lineas") === 0).map((c) => JSON.parse(c.b));
    out.det = document.querySelector(".imcu-det") ? document.querySelector(".imcu-det").innerText.replace(/\s+/g, " ") : "";
    return out;
  });

  console.log(JSON.stringify(r, null, 1));
  if (!r.tab) fail("la solapa 🚢 En curso no está en la barra del módulo");
  if (r.kind !== "impCurso") fail("no quedó parado en la pantalla En curso: " + r.kind);
  if (r.filas !== 3) fail("debería haber 3 filas (una por pedido), hay " + r.filas);
  if (!/PI B260601/.test(r.fila0) || !/Becky/.test(r.fila0)) fail("la fila no muestra proveedor + PI: " + r.fila0);
  if (r.inputs0.join("|") !== "|29/09/26") fail("Becky: embarque vacío + llegada 29/09/26, vino " + r.inputs0);
  if (r.inputs1.join("|") !== "08/11/26|18/12/26") fail("Ownland: embarque 08/11/26 y llegada 18/12/26, vino " + r.inputs1);
  if (r.d18 !== 18 || r.d58 !== 58 || r.dneg !== -6) fail("cuenta de días mal: " + [r.d18, r.d58, r.dneg]);
  if (!/falta la fecha de embarque/.test(r.estadoSinEmb)) fail("sin embarque no avisa: " + r.estadoSinEmb);
  if (!/embarca en 58 d/.test(r.estadoEspera)) fail("embarque futuro debería decir 'embarca en N d': " + r.estadoEspera);
  if (!/embarcado hace 17 d/.test(r.estadoViaje)) fail("embarque pasado debería decir 'embarcado hace': " + r.estadoViaje);
  if (!/vencida/.test(r.estadoAtras)) fail("llegada pasada debería avisar vencida: " + r.estadoAtras);
  if (!r.aviso) fail("no avisa cuántos pedidos no tienen fecha de embarque");
  if (!/23\.622|46\.626/.test(r.txt)) fail("no muestra los u$s en camino: " + r.txt.slice(0, 200));
  if (r.callEmb.length !== 1) fail("el embarque debería mandar UNA sola RPC: " + JSON.stringify(r.callEmb));
  else {
    const c = r.callEmb[0];
    if (c.p_pedido_ref !== "PI B260601" || c.p_proveedor !== "Becky") fail("RPC sin el pedido correcto: " + JSON.stringify(c));
    if (c.p_embarque !== "2026-08-20" || c.p_set_embarque !== true) fail("no manda el embarque: " + JSON.stringify(c));
    if (c.p_set_llegada) fail("editar el embarque NO debe tocar la llegada: " + JSON.stringify(c));
  }
  if (r.callLleg.length !== 1 || r.callLleg[0].p_llegada !== "2026-10-02" || r.callLleg[0].p_set_llegada !== true
      || r.callLleg[0].p_set_embarque) fail("la llegada no se guarda bien: " + JSON.stringify(r.callLleg));
  if (r.callLin.length !== 1 || r.callLin[0].p_pedido_ref !== "PI B260601") fail("el detalle no pide las líneas del pedido: " + JSON.stringify(r.callLin));
  if (!/601E/.test(r.det)) fail("el detalle no muestra los artículos: " + r.det);
  // filtros (v15.73)
  if (!r.chipsProv.some((t) => /^Becky/.test(t)) || !r.chipsProv.some((t) => /^PI OL-10139$/.test(t)))
    fail("faltan las fichas de proveedor y de pedido: " + JSON.stringify(r.chipsProv));
  if (r.trasProv !== 1) fail("filtrando por Becky debería quedar 1 pedido, quedaron " + r.trasProv);
  if (!/23\.622/.test(r.kpiProv) || /46\.626/.test(r.kpiProv)) fail("los totales no se recalculan con el proveedor: " + r.kpiProv.slice(0, 300));
  if (r.trasRef !== 1) fail("parado en un pedido debería quedar 1 fila, quedaron " + r.trasRef);
  if (!/este pedido/i.test(r.kpiRef) || !/46\.626/.test(r.kpiRef) || /23\.622/.test(r.kpiRef))
    fail("parado en un pedido la plata debería ser sólo la de ese pedido: " + r.kpiRef.slice(0, 300));
  if (!r.refAbre) fail("parado en un pedido el detalle por artículo debería abrirse solo");
  if (r.trasLimpiar !== 3) fail("al sacar el filtro deberían volver los 3 pedidos, quedaron " + r.trasLimpiar);
  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("✓ imp-encurso OK");
})();
