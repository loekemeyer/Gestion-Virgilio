/* Regresión del pop-up de PROYECCIÓN (Stocks → Proy. caj/mes).

   v15.52 — las cajas que el PROVEEDOR ENTREGÓ cada mes (gv_entregas_mensuales_cod:
   talleristas + prov AT) se muestran junto a lo facturado. Lo que NO puede pasar: que un mes
   anterior al arranque del registro (prov AT desde 06/2026, talleristas desde 12/2025) se
   muestre como 0 entregado — la RPC lo marca `cubierto=false` y no se cuenta.

   v18.21 — el dueño mandó sacar el bloque de barras por mes ("con el gráfico ya alcanza") y
   pidió que lo que quedara se viera mucho más grande. Entonces: lo entregado dejó de ser una
   columna y pasó a ser su ficha, y el desglose de un mes —que se abría tocando el número de
   la barra— ahora se abre tocando el mes EN EL GRÁFICO.

   v18.24 — el MES EN CURSO sale de la ventana: el motor de LK ya la cierra en el último mes
   COMPLETO, así que la pantalla tiene que usar esa misma. El mes en curso se sigue dibujando,
   pero aparte: ficha propia con lo que da a ese ritmo (por días hábiles), punto hueco ámbar
   y asterisco. La serie del test se arma RELATIVA a hoy, para que el test no dependa de en
   qué mes se corra.

   v18.26 — vuelven los NÚMEROS mes a mes. Lo que el dueño mandó sacar en la v18.21 eran las
   BARRAS; se fue el bloque entero y con él los números, y al verlo: *"sacaste los números,
   que es lo que más me importa"*. Ahora hay una tabla sin barras, con lo facturado y lo
   entregado de cada mes de la ventana + el mes en curso marcado, y los números siguen siendo
   el botón que abre el desglose.

   v18.27 — el orden que pidió el dueño: la tabla PRIMERO ("cuánto entró quiero ver primero"),
   titulada «Estad. Madre», con columnas mes / vtas / entrega, y el gráfico al final ("abajo
   de eso, el gráfico, que ni uso tiene").

   ⚠ Este test estuvo en ROJO en main desde la v18.11 sin que nadie lo notara: esa versión
   cambió el orden de las columnas (pedido del dueño) y nadie lo actualizó. Se reescribió el
   15/09 contra lo que la pantalla hace hoy.

   Chequea, con fetch stubbeado (sin red):
   1) que pida gv_entregas_mensuales_cod con el código base,
   2) que el entregado esté en su ficha y sume SÓLO los meses cubiertos,
   3) que no queden rastros de las BARRAS (.proyv-row / .proyv-track) pero sí los números:
      una fila por mes de la ventana + el mes en curso, con factur. y entreg.,
   4) que el gráfico tenga una franja clicable por mes y que tocarla abra el desglose,
   5) que si la RPC de entregas no devuelve nada, la ficha de entregado NO aparezca,
   6) que el mes en curso NO entre en el promedio, el total ni "meses arriba", tenga su ficha
      "a este ritmo" y quede marcado con asterisco en el gráfico.
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
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = { urls: [] };
    function J(data){ return Promise.resolve({ ok: true, status: 200, json: function(){ return Promise.resolve(data); } }); }
    // 12 meses de ventas terminando en el MES EN CURSO (relativo a hoy, así el test no
    // depende del calendario). La ventana son los 6 meses CERRADOS: los índices 5..10.
    const hoyAR = new Date(Date.now() - 3 * 3600000);
    const meses = [];
    for (let k = 11; k >= 0; k--) {
      const d = new Date(Date.UTC(hoyAR.getUTCFullYear(), hoyAR.getUTCMonth() - k, 1));
      meses.push(d.toISOString().slice(0, 7));
    }
    const ventas = meses.map(function (m, i) { return { mes: m, cajas: 300 + i * 10 }; });
    out.mesCurso = meses[11];
    // entregas: el circuito arranca 6 meses atrás → los 6 primeros sin cobertura
    const entregas = ventas.map(function (v, i) {
      const cub = i >= 6;
      return { mes: v.mes, cajas: cub ? 500 : 0, cubierto: cub };
    });
    let conEntregas = true;
    window.fetch = function (url) {
      url = String(url); out.urls.push(url);
      if (url.indexOf("ventas_mensuales_cod") >= 0 && url.indexOf("clientes") < 0) return J(ventas);
      if (url.indexOf("gv_entregas_mensuales_cod") >= 0) return J(conEntregas ? entregas : []);
      if (url.indexOf("gv_ventas_clientes_mes_cod") >= 0) return J([{ cliente: "Osa", cajas: 120 }, { cliente: "Otros", cajas: 80 }]);
      if (url.indexOf("vista_historial_entregas") >= 0) {
        return J([{ fecha: meses[9] + "-04", cajas: 300, quien: "Carriero", remito: "R-9" },
                  { fecha: meses[9] + "-19", cajas: 200, quien: "Carriero", remito: "R-11" }]);
      }
      return J([]);
    };
    if (!document.getElementById("stkPopBody")) {
      const d = document.createElement("div"); d.id = "stkPopBody"; document.body.appendChild(d);
    }
    window._stkPopShell = function () {};

    await stkShowProyVentas(encodeURIComponent("321"), 367.2);
    let body = document.getElementById("stkPopBody");
    out.pidioEntregas = out.urls.some(function (u) { return u.indexOf("gv_entregas_mensuales_cod") >= 0; });

    const kpiTxt = function () {
      return Array.prototype.map.call(body.querySelectorAll(".proyv-kpi"), function (k) {
        return (k.querySelector("span") || {}).textContent + "=" + (k.querySelector("b") || {}).textContent;
      }).join("|");
    };
    const k = kpiTxt();
    // la ventana son los indices 5..10 (350+360+370+380+390+400 = 2250); el 11 es el mes en curso
    out.fichaEntregado = /entregado 6m=2500/.test(k);      // los cubiertos DE LA VENTANA: i 6..10 = 5 × 500
    out.fichaProy = /proy\. caj\/mes=367\.2/.test(k);
    out.fichaFacturado = /facturado 6m=2250/.test(k);
    out.fichaArriba = /meses arriba=4\/6/.test(k);         // 370,380,390,400 > 367,2
    const kCurso = body.querySelector(".proyv-kpi.curso");
    out.fichaCurso = !!kCurso && /a este ritmo/.test(kCurso.textContent) && /d\u00edas h\u00e1biles/.test(kCurso.textContent);
    out.cursoFueraDelProm = !/promedio 6m=410/.test(k);
    // el bloque de barras ya no existe
    out.sinBarras = !body.querySelector(".proyv-row") && !body.querySelector(".proyv-track") && !body.querySelector(".proyv-foot");
    // el gráfico: una franja clicable por mes (12)
    out.hits = body.querySelectorAll(".proyv-svg .hit").length;
    // v18.26 — la tabla de meses: 6 de la ventana + el mes en curso, con sus dos numeros
    const filasTab = Array.prototype.slice.call(body.querySelectorAll(".proyv-tab tr")).slice(1);
    out.filasMes = filasTab.length;
    out.mesCursoMarcado = filasTab.length ? /\*/.test(filasTab[filasTab.length - 1].textContent) : false;
    out.numerosAbren = body.querySelectorAll(".proyv-tab .proyv-lnk").length >= 12;
    // v18.27 — la tabla va ANTES que el grafico, y con los nombres que pidio el dueno
    const htmlCuerpo = body.innerHTML;
    out.tablaAntesDelGrafico = htmlCuerpo.indexOf('class="proyv-tab"') < htmlCuerpo.indexOf('class="proyv-svg"');
    out.tituloEstadMadre = /Estad\. Madre/.test(body.textContent);
    const ths = Array.prototype.map.call(body.querySelectorAll(".proyv-tab th"), function (t) { return t.textContent.trim(); });
    out.columnas = ths.join("|");
    // el mes en curso: asterisco en el eje y punto hueco ambar
    const svgTxt = body.querySelector(".proyv-svg").textContent;
    out.asterisco = svgTxt.indexOf("*") >= 0;
    out.puntoHueco = body.querySelectorAll('.proyv-svg circle[stroke="#d97706"]').length === 2;

    // tocar un mes abre el desglose, con las dos caras
    await stkProyMes(meses[9]);
    body = document.getElementById("stkPopBody");
    const det = body.querySelector(".proyv-det");
    out.abrioDet = !!det;
    const dt = det ? det.textContent : "";
    out.detTieneCliente = dt.indexOf("Osa") >= 0 && dt.indexOf("Otros") >= 0;
    out.detTieneRemito = dt.indexOf("R-9") >= 0 && dt.indexOf("Carriero") >= 0;
    out.detMarcado = body.querySelectorAll(".proyv-svg .hit.on").length === 1;
    // volver a tocarlo lo cierra
    await stkProyMes(meses[9]);
    out.cierraDet = !document.getElementById("stkPopBody").querySelector(".proyv-det");

    // sin entregas registradas → la ficha de entregado no aparece
    conEntregas = false;
    await stkShowProyVentas(encodeURIComponent("999"), 100);
    body = document.getElementById("stkPopBody");
    out.sinFichaEnt = kpiTxt().indexOf("entregado") < 0;
    return out;
  });

  const pass =
    r.pidioEntregas && r.fichaEntregado && r.fichaProy && r.fichaFacturado && r.fichaArriba &&
    r.fichaCurso && r.cursoFueraDelProm && r.asterisco && r.puntoHueco &&
    r.sinBarras && r.hits === 12 && r.filasMes === 7 && r.mesCursoMarcado && r.numerosAbren &&
    r.tablaAntesDelGrafico && r.tituloEstadMadre && r.columnas === "mes|vtas|entrega" &&
    r.abrioDet && r.detTieneCliente && r.detTieneRemito && r.detMarcado && r.cierraDet &&
    r.sinFichaEnt &&
    errs.length === 0;
  const { urls, ...vis } = r;
  console.log("proy-entregadas:", JSON.stringify(vis), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
