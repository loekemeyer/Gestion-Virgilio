/* v18.14 (Luis, 2026-09-15) — PPP · «Modificar Pedidos»: buscador, filtros y tabla POR PEDIDO.

   Pedido: *"debería poder buscar pedidos (que estén en A programar y en Programación) — y ojo acá
   digo PEDIDOS, no NPs, ya que un pedido puede estar dividido en múltiples NPs. De momento hacé
   que tenga filtros, barra de búsqueda y muestre una tabla con los pedidos actuales a programar y
   programados (pedidos y que todavía no hayan salido)"*. Y: *"poné la pestaña entre Ocupación y
   Config. Cuarentena"*.

   ⚠ Lo que de verdad hay que fijar es que la unidad sea EL PEDIDO. Medido en la base el 15/09:
   26 de los 74 pedidos web programados están partidos en varias NP (hasta 4) — listando NP, el
   mismo pedido saldría tres veces. El fixture reproduce ese caso a propósito.

   Lo que fija este test:
     · la solapa quedó entre Ocupación y Config. Cuarentena;
     · un pedido de 3 NP es UN renglón, con sus 3 NP y la suma de sus m³;
     · una NP de ISIS es su propio pedido (su `clave` es la NP y no se repite);
     · entran los de A Programar y los programados, y NO los que ya salieron;
     · si SOLO ALGUNAS NP del pedido salieron, el pedido sigue con las que quedan;
     · la búsqueda encuentra por número de pedido, por CUALQUIERA de sus NP, por cliente y por tanda;
     · los filtros (dónde, empresa, estado) recortan, y «Limpiar» los devuelve;
     · el contador dice pedidos y NP por separado.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 950 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.getTodayKey = () => "2026-09-15";
    _pppParsed = { prog: [] };
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    window.pgaNeed = function () {};
    window.aprCargar = function () { return Promise.resolve(); };

    const np = (o) => Object.assign({
      fecha: "2026-09-17", tanda: "E12L", np: "LK 0004", np_num: 4, cod: "3843",
      razon_social: "Chen Li Yu", localidad: "Flores", zona: "Zona 3 - CABA Oeste",
      zona_corta: "Zona 3", empresa: "LK", origen: "web", m3: 0.5, estado: "pendiente",
      estado_orden: 1, clave: "1343", barrio: "Flores", fecha_pedido: "2026-09-11"
    }, o || {});

    /* El pedido 1343 está partido en TRES NP — el caso que motivó todo. Más: un pedido de dos NP
       del que una ya salió, dos NP de ISIS (cada una su propio pedido, `clave` = NP) y un pedido
       entero ya salido, que no tiene que aparecer. */
    _pgaRows = [
      np({ np: "LK 0004", m3: 0.5 }),
      np({ np: "LK 0005", m3: 0.3 }),
      np({ np: "LK 0006", m3: 0.2 }),
      np({ np: "LK 0007", clave: "1344", cod: "288", razon_social: "Torres Y Liva S.A Cif",
           tanda: "E01A", fecha: "2026-09-15", m3: 0.8, estado: "armado" }),
      np({ np: "LK 0008", clave: "1344", cod: "288", razon_social: "Torres Y Liva S.A Cif",
           tanda: "E01A", fecha: "2026-09-15", m3: 0.2, estado: "armado" }),
      np({ np: "98701", clave: "98701", origen: "isis", cod: "1974",
           razon_social: "Pettish Lacroze 2481", tanda: "D67E", m3: 0.9, estado: "facturado" }),
      np({ np: "98702", clave: "98702", origen: "isis", cod: "1974",
           razon_social: "Pettish Lacroze 2481", tanda: "D67E", m3: 0.4, estado: "facturado" }),
      np({ np: "CH 0020", clave: "1001430", empresa: "CH", cod: "2643",
           razon_social: "El Martillo Srl", tanda: "E12H", fecha: "2026-09-21", m3: 1.1 }),
      // este pedido entero YA SALIÓ: no tiene que aparecer
      np({ np: "LK 0099", clave: "1399", cod: "9999", razon_social: "Ya Salio SA",
           tanda: "E09Z", m3: 2.0 })
    ];
    _pgaTs = Date.now();
    // lo que ya salió: la LK 0099 entera, y UNA sola NP del pedido 1344
    _pppEnSalida = new Map([["LK 0099", {}], ["LK 0008", {}]]);
    window.pppLoadEntregados = function () { return new Set(); };

    // A Programar: dos pedidos, uno de ellos con 2 bloques
    _apr.listo = true; _apr.cargando = false;
    _apr.pedidos = [
      { order_id: 1360, empresa: "lk", cod: "4321", razon_social: "Web Nueva SRL",
        fecha_recep: "2026-09-14", zona: "Zona 1 - CABA Sur", localidad: "Barracas",
        m3: 0.3, lineas: 3, cajas: 5, bloques: [{ np_idx: 1 }, { np_idx: 2 }] },
      { order_id: 217, empresa: "chef", cod: "2533", razon_social: "Osa Hermanos",
        fecha_recep: "2026-09-13", zona: "Zona 2 - CABA Centro", localidad: "Almagro",
        m3: 0.9, lineas: 2, cajas: 4, bloques: [{ np_idx: 1 }] }
    ];

    document.getElementById("pppOverlay").classList.add("show");

    // ── (1) la solapa, entre Ocupación y Config. Cuarentena ────────────────
    pppPaintTabs();
    const tabs = [...document.querySelectorAll("#pppTabsBar .ppp-tab")].map((e) => e.textContent.trim());
    out.tabs = tabs;
    const iM = tabs.findIndex((t) => /Modificar Pedidos/.test(t));
    out.entreOcupYCuar = iM > 0 && /Ocupación/.test(tabs[iM - 1]) && /Cuarentena/.test(tabs[iM + 1]);

    pppTab("modif");
    await new Promise((res) => setTimeout(res, 150));
    const box = document.getElementById("pppPreview");
    const filas = () => [...box.querySelectorAll("tr.pmod-row")].map((tr) => ({
      ped: tr.children[0].textContent.trim(), nps: tr.children[1].textContent.trim(),
      rs: tr.children[2].textContent.trim(), tanda: tr.children[5].textContent.trim(),
      m3: tr.children[6].textContent.trim(), est: tr.children[7].textContent.trim()
    }));

    // ── (2) UN renglón por pedido, no por NP ───────────────────────────────
    const f = filas();
    out.nFilas = f.length;                       // 7 pedidos (9 NP - 1 salida... ver abajo)
    out.peds = f.map((x) => x.ped);
    const p1343 = f.find((x) => /1343/.test(x.ped));
    out.partidoUnaFila = f.filter((x) => /1343/.test(x.ped)).length === 1;
    out.partidoTraeSusNps = !!p1343 && /LK 0004/.test(p1343.nps) && /LK 0005/.test(p1343.nps) &&
                            /LK 0006/.test(p1343.nps);
    out.partidoDice3 = !!p1343 && /3 NP/.test(p1343.nps);
    out.partidoSumaM3 = !!p1343 && p1343.m3 === "1,0";       // 0,5 + 0,3 + 0,2
    // ISIS: cada NP es su propio pedido
    out.isisSeparadas = f.filter((x) => /98701|98702/.test(x.ped)).length === 2;

    // ── (3) lo que ya salió ────────────────────────────────────────────────
    out.salidaFuera = !f.some((x) => /1399/.test(x.ped) || /LK 0099/.test(x.nps));
    // del 1344 salió UNA sola NP: el pedido queda, con la que falta
    const p1344 = f.find((x) => /1344/.test(x.ped));
    out.parcialQueda = !!p1344 && /LK 0007/.test(p1344.nps) && !/LK 0008/.test(p1344.nps);
    out.parcialM3 = !!p1344 && p1344.m3 === "0,8";           // sólo la NP que no salió

    // ── (4) los de A Programar están ───────────────────────────────────────
    out.aprEstan = f.some((x) => /1360/.test(x.ped)) && f.some((x) => /217/.test(x.ped));
    const p1360 = f.find((x) => /1360/.test(x.ped));
    out.aprSinNpTodavia = !!p1360 && /bloques|sin NP/.test(p1360.nps);

    // ── (5) el contador: pedidos y NP por separado ─────────────────────────
    out.resumen = box.querySelector(".pmod-res").textContent.replace(/\s+/g, " ").trim();

    // ── (6) la búsqueda ────────────────────────────────────────────────────
    const buscar = function (q) { pmodBuscar(q); return filas(); };
    out.porPedido = buscar("1343").length === 1;
    // ⚠ lo importante: buscar por una NP del MEDIO encuentra el pedido entero
    const porNp = buscar("LK 0005");
    out.porNpDelMedio = porNp.length === 1 && /1343/.test(porNp[0].ped) && /LK 0004/.test(porNp[0].nps);
    out.porCliente = buscar("torres").length === 1;
    out.porTanda = buscar("D67E").length === 2;
    out.porCod = buscar("2643").length === 1;
    out.sinCoincidencias = buscar("zzzz").length === 0 &&
      /Sin coincidencias/.test(box.textContent);
    pmodBuscar("");

    // ── (7) los filtros ────────────────────────────────────────────────────
    pmodFiltro("donde", "apr");   out.soloApr = filas().length === 2;
    pmodFiltro("donde", "plan");  out.soloPlan = filas().length === 5;
    pmodFiltro("donde", "todos");
    pmodFiltro("emp", "CH");      out.soloCh = filas().every((x) => /^CH /.test(x.ped));
    out.nCh = filas().length;
    pmodFiltro("emp", "todas");
    pmodFiltro("estado", "armado"); out.soloArmado = filas().length === 1 && /1344/.test(filas()[0].ped);
    // se combinan: estado armado + empresa Chef no da nada
    pmodFiltro("emp", "CH");      out.combinados = filas().length === 0;
    pmodLimpiar();
    out.limpiarVuelve = filas().length === out.nFilas &&
      box.querySelector(".pmod-q").value === "";
    return out;
  });

  await b.close();
  const ok = [];
  const chk = (c, d) => ok.push([!!c, d]);
  chk(r.entreOcupYCuar, "la solapa quedó entre Ocupación y Config. Cuarentena: " + JSON.stringify(r.tabs));
  chk(r.partidoUnaFila, "un pedido partido en 3 NP es UN renglón, no tres ← el punto de Luis");
  chk(r.partidoTraeSusNps, "y trae sus tres NP: " + JSON.stringify(r.peds));
  chk(r.partidoDice3, "con el contador «3 NP» al lado");
  chk(r.partidoSumaM3, "y los m³ sumados de los tres bloques (1,0)");
  chk(r.isisSeparadas, "dos NP de ISIS son dos pedidos distintos (su clave es la NP)");
  // y se llaman por su NP pelada: no existe un "LK 98701"
  chk(r.peds.indexOf("98701") >= 0 && !r.peds.some((x) => /LK 98701/.test(x)),
      "un pedido de ISIS se nombra por su NP, sin prefijo de empresa: " + JSON.stringify(r.peds));
  chk(r.salidaFuera, "un pedido que ya salió no aparece");
  chk(r.parcialQueda, "si salió UNA sola NP del pedido, el pedido queda con la que falta");
  chk(r.parcialM3, "y los m³ son sólo los de la NP que no salió (0,8)");
  chk(r.aprEstan, "los de A Programar también están");
  chk(r.aprSinNpTodavia, "y se ve que todavía no tienen NP asignada");
  /* NP REALES, no bloques: los dos pedidos de A Programar todavía no tienen NP (se asigna al
     programarlos), así que van aparte. Contar sus bloques como NP decía 10 cuando existen 7. */
  chk(/7 pedidos/.test(r.resumen) && /7 NP/.test(r.resumen) && /3 bloques sin NP/.test(r.resumen),
      "el contador separa pedidos, NP reales y bloques sin NP: " + JSON.stringify(r.resumen));
  chk(r.porPedido, "la búsqueda encuentra por número de pedido");
  chk(r.porNpDelMedio, "y por CUALQUIERA de sus NP — buscando la del medio sale el pedido entero");
  chk(r.porCliente, "por cliente");
  chk(r.porTanda, "por tanda");
  chk(r.porCod, "y por código de cliente");
  chk(r.sinCoincidencias, "sin coincidencias lo dice, no deja la tabla vacía y muda");
  chk(r.soloApr, "el filtro «Sólo A Programar» deja 2");
  chk(r.soloPlan, "«Sólo programados» deja 5");
  chk(r.soloCh && r.nCh === 2, "el filtro por empresa deja sólo los de Chef (" + r.nCh + ")");
  chk(r.soloArmado, "el filtro por estado deja sólo el armado");
  chk(r.combinados, "los filtros se combinan (armado + Chef = ninguno)");
  chk(r.limpiarVuelve, "«Limpiar» devuelve todo y vacía la búsqueda");
  chk(errs.length === 0, "sin errores de JS: " + JSON.stringify(errs));

  let malas = 0;
  for (const [bien, d] of ok) { console.log((bien ? "  ok   " : "  FALLA") + " " + d); if (!bien) malas++; }
  console.log(malas ? "\n✗ " + malas + " de " + ok.length + " fallaron" : "\n✓ " + ok.length + " chequeos ok");
  process.exit(malas ? 1 : 0);
})();
