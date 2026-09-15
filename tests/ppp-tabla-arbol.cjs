/* v17.66 (Luis, 2026-09-14) — PROGRAMACIÓN COMO TABLA: día → tanda → NP → contenido.
   Pedido: *"una especie de tabla al estilo del módulo de operarios. Arranca con el día, M3,
   Tandas, NPs, y agrega 4 columnas que son el porcentaje de completado expresado en números
   (color coded): Facturado, Armado, En proceso y Pendientes. Cuando se aprieta sobre un día se
   expande para mostrar las tandas (color coded), cada tanda se puede apretar para mostrar las NPs,
   y cada NP se puede apretar para mostrar el contenido."*
   Estado inyectado (las filas que devolvería `gv_ppp_prog_arbol`); no pega contra la red. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 1000 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.getTodayKey = () => "2026-09-14";
    // lo mínimo para que la pestaña Programación se dibuje (el árbol no sale de acá)
    _pppParsed = { prog: [{ np: "98630", tanda: "D72B", fecha_entrega: "2026-09-14", m3: 1.8,
                            cod: "1000", razon_social: "Jumbo", zona: "Zona 2", programmed: true }] };
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    window.pppPaintTabs = function () {};

    const mk = (f, t, np, rs, m3, est, zona) => ({
      fecha: f, tanda: t, np: np, np_num: 0, cod: "1000", razon_social: rs, localidad: "Barracas",
      zona: zona, zona_corta: zona, empresa: np.startsWith("CH") ? "CH" : "LK",
      origen: /^(LK|CH) /.test(np) ? "web" : "isis", m3: m3, estado: est, estado_orden: 1,
      barrio: "Villa Crespo", fecha_pedido: "2026-09-11"
    });
    // martes 15: 5 NP → 1 facturada, 1 armada, 2 en proceso, 1 pendiente (20/20/40/20 %)
    _pgaRows = [
      mk("2026-09-14", "D72B", "98630", "Jumbo Retail", 1.8, "facturado", "Zona 2 - CABA Centro"),
      mk("2026-09-14", "D72B", "98631", "Jumbo Retail", 1.5, "facturado", "Zona 2 - CABA Centro"),
      mk("2026-09-14", "D72C", "LK 0052", "Arguello Marcelo", 1.86, "facturado", "Zona 1 - CABA Sur"),
      mk("2026-09-15", "D56D", "98640", "Perez Zarate SRL", 0.1, "armado", "Zona 1 - CABA Sur"),
      mk("2026-09-15", "D67E", "LK 0058", "Ricci Gabriel", 2.5, "proceso", "Zona 2 - CABA Centro"),
      mk("2026-09-15", "D67E", "CH 0019", "Osa Hermanos", 0.9, "proceso", "Zona 2 - CABA Centro"),
      mk("2026-09-15", "E01E", "98650", "Andser Quimica", 1.3, "facturado", "Zona 1 - CABA Sur"),
      mk("2026-09-15", "E01E", "98651", "Biaggio Valentin", 1.35, "pendiente", "Zona 1 - CABA Sur")
    ];
    _pgaTs = Date.now();
    const pedidos = [];
    window.pgaNeed = function () {};
    // el contenido de la NP sale de gv_ppp_np_items (ISIS o web, el mismo endpoint)
    const _fetch = window.fetch;
    window.fetch = async function (url, opt) {
      const u = String(url);
      if (/gv_ppp_np_items/.test(u)) {
        pedidos.push(u);
        return { ok: true, status: 200, json: async () => ([
          { art: "505", cajas: 20, uxb: 12, uni: 240 },
          { art: "323E", cajas: 20, uxb: 12, uni: 240 },
          { art: "508", cajas: 8, uxb: 6, uni: 48 }
        ]) };
      }
      return { ok: true, status: 200, json: async () => [], text: async () => "[]", headers: { get: () => null } };
    };

    _pppTab = "plan"; _pppPlanTabla = true; _pppPlanClasica = false; _pppPlanDay = null;
    document.getElementById("pppOverlay").classList.add("show");
    pppRenderProg(); await new Promise((res) => setTimeout(res, 250));
    const prev = document.getElementById("pppPreview");
    let html = prev.innerHTML;

    // (1) la tabla es lo que se ve por defecto, con las 8 columnas
    out.esDefault = /class="pga"/.test(html) && !/pn-days/.test(html);
    // v17.79: los 4 estados van a la DERECHA, angostos, con el encabezado partido en dos y con color
    out.cols = ["Día", "m³", "Tandas", "NPs"].every((c) => new RegExp(">" + c + "<").test(html)) &&
      /pga-h fac[^>]*>Factu<br>rado</.test(html) && /pga-h arm[^>]*>Ar<br>mado</.test(html) &&
      /pga-h pro[^>]*>En<br>proceso</.test(html) && /pga-h pen[^>]*>Pen<br>dientes</.test(html);
    out.estadosDerecha = (function () {
      const th = [...prev.querySelectorAll("table.pga thead th")].map((e) => e.className);
      return th.length === 8 && !th[0] && !th[1] && !th[2] && !th[3] &&
             /fac/.test(th[4]) && /arm/.test(th[5]) && /pro/.test(th[6]) && /pen/.test(th[7]);
    })();
    out.salidas = /pppPlanTabla\(false\)/.test(html) && /pppPlanClasica\(true\)/.test(html);
    // v17.79 (Luis): "Facturado azul, armado verde, en proceso amarillo, pendiente rojo"
    out.paleta = (function () {
      const fam = function (css) {
        const m = /(\d+),\s*(\d+),\s*(\d+)/.exec(css) || [0, 0, 0, 0];
        const r = +m[1], g = +m[2], b = +m[3];
        if (b > r + 30 && b > g + 30) return "azul";
        if (g > r + 30 && g > b + 30) return "verde";
        if (r > b + 60 && g > b + 60) return "amarillo";
        if (r > g + 40 && r > b + 40) return "rojo";
        return "otro";
      };
      const th = [...prev.querySelectorAll("table.pga thead th")].slice(4);
      // el martes es el único día con los 4 estados en juego (los que están en 0 % se pintan grises)
      const d15 = [...prev.querySelectorAll("tr.pga-d")].find((tr) => /15\/09/.test(tr.textContent));
      return {
        head: th.map((e) => fam(getComputedStyle(e).borderTopColor)),
        num: [...d15.querySelectorAll(".pga-pct")].map((e) => fam(getComputedStyle(e).color))
      };
    })();

    // (2) una fila por día, cerrada, con m³ / tandas / NPs
    const filaDe = (sel) => [...prev.querySelectorAll(sel)].map((tr) =>
      [...tr.children].map((td) => td.textContent.trim()));
    out.dias = filaDe("tr.pga-d");
    out.hoy = !!prev.querySelector("tr.pga-d.hoy");
    out.sinTandasCerrado = prev.querySelectorAll("tr.pga-t").length === 0;

    // (3) los 4 porcentajes del día, en números y con su color
    const mar = [...prev.querySelectorAll("tr.pga-d")].find((tr) => /15\/09/.test(tr.textContent));
    out.pctMartes = [...mar.querySelectorAll(".pga-pct")].map((e) => e.textContent.trim());
    out.pctClases = [...mar.querySelectorAll(".pga-pct")].map((e) => e.className.replace("pga-pct ", ""));

    // (4) tocar el día lo expande en sus tandas, con color por estado
    pgaAbrirDia("20260915"); await new Promise((res) => setTimeout(res, 120));
    out.tandas = [...prev.querySelectorAll("tr.pga-t")].map((tr) =>
      (/^[▸▾]?([A-Z]\d+[A-Z])/.exec(tr.children[0].textContent.trim()) || [])[1]);
    out.tandaClases = [...prev.querySelectorAll("tr.pga-t")].map((tr) => tr.className);
    out.sinNpsCerrado = prev.querySelectorAll("tr.pga-n").length === 0;

    // (5) tocar la tanda la expande en sus NP
    pgaAbrirTanda("20260915|D67E"); await new Promise((res) => setTimeout(res, 120));
    out.nps = [...prev.querySelectorAll("tr.pga-n .pga-np")].map((e) => e.textContent.trim());
    out.tam = (function () {
      const px = (sel) => {
        const e = prev.querySelector(sel);
        return e ? Math.round(parseFloat(getComputedStyle(e).fontSize) * 10) / 10 : 0;
      };
      return { dia: px("tr.pga-d > td"), tanda: px("tr.pga-t > td"), np: px("tr.pga-n > td") };
    })();
    // v17.95 (Luis): "que mantenga el mismo tamaño y POSICIÓN que día". Se mide dónde arranca el
    // CONTENIDO (el chevron), no el borde del td: el td nunca se movía, la sangría era padding.
    out.pos = (function () {
      const x = (sel) => {
        const e = prev.querySelector(sel);
        return e ? Math.round(e.getBoundingClientRect().left) : -1;
      };
      return { dia: x("tr.pga-d .pga-chev"), tanda: x("tr.pga-t .pga-chev"), np: x("tr.pga-n .pga-chev") };
    })();
    // v17.95: y el zoom de pppFitPantalla NO toca esta vista. Era lo que achicaba todo al abrir un
    // nivel: la tabla crece, el zoom la comprime, y cada nivel abierto la achicaba un poco más
    // (medido: caía al piso de 0,70 con la tanda abierta).
    out.zoom = (function () {
      const body = document.querySelector("#pppOverlay .planim-body");
      if (!body) return "sin-body";
      try { pppFitPantalla(); } catch (_e) { return "error"; }
      return String(body.style.zoom || "1");
    })();
    out.npPill = [...prev.querySelectorAll("tr.pga-n .pga-pill")].map((e) => e.textContent.trim());
    out.sinContenido = prev.querySelectorAll("td.pga-ncont").length === 0;
    // v17.76 (Luis): código de cliente con su prefijo, barrio al lado de la zona y fecha de pedido
    const fila58 = [...prev.querySelectorAll("tr.pga-n")].find((x) => x.textContent.indexOf("LK 0058") >= 0);
    out.npCod    = !!fila58 && (fila58.querySelector(".pga-cod") || {}).textContent === "LK 1000";
    out.npZonaBarrio = !!fila58 && (fila58.querySelector(".pga-loc") || {}).textContent === "Zona 2 - CABA Centro · Villa Crespo";
    out.npFechaPed   = !!fila58 && (fila58.querySelector(".pga-ped") || {}).textContent === "ped. 11/09";
    const filaCh = [...prev.querySelectorAll("tr.pga-n")].find((x) => x.textContent.indexOf("CH 0019") >= 0);
    out.npCodCh = !!filaCh && (filaCh.querySelector(".pga-cod") || {}).textContent === "CH 1000";

    // (6) tocar la NP muestra el contenido (códigos y cajas)
    pgaAbrirNp("20260915|D67E|LK 0058", "LK 0058"); await new Promise((res) => setTimeout(res, 250));
    html = prev.innerHTML;
    out.pidioItems = pedidos.some((u) => /gv_ppp_np_items\?select=art,cajas,uxb,uni&np=eq\.LK%200058&/.test(u));
    // v17.94 (Luis): el contenido pasó de una tabla de 3 columnas clavada en 520px a una GRILLA
    // que fluye, para que se abra en horizontal y no hacia adentro.
    // v17.96 (Luis): el contenido ya no va en un renglón aparte — ocupa las 6 celdas que quedaban
    // vacías en la MISMA fila de la NP (de Tandas a Pendientes).
    out.contenido = /class="pga-ncont"/.test(html) && /colspan="6"/.test(html) && /class="pga-its"/.test(html) &&
                    /pga-it-cod">505</.test(html) && /pga-it-cj">20 cj</.test(html) &&
                    /pga-it-tot">3 códigos · <b>48<\/b> cajas · <b>528<\/b> unidades/.test(html);
    // v17.96: la celda del contenido y la de la NP tienen que ser de la MISMA <tr>
    out.contenidoEnLaFila = (function () {
      const td = prev.querySelector("td.pga-ncont");
      if (!td) return false;
      const tr = td.parentElement;
      return tr.classList.contains("pga-n") && !!tr.querySelector(".pga-np") &&
             Number(td.getAttribute("colspan")) === 6;
    })();
    out.contenidoAncho = (function () {
      const g = prev.querySelector(".pga-its"), td = prev.querySelector("td.pga-ncont");
      if (!g || !td) return 0;
      return Math.round(g.getBoundingClientRect().width / td.getBoundingClientRect().width * 100);
    })();
    // una sola vuelta de red por NP
    const antes = pedidos.length;
    pppRenderProg(); await new Promise((res) => setTimeout(res, 120));
    out.cacheItems = pedidos.length === antes;

    // (7) el total de abajo suma todos los días
    out.total = filaDe("table.pga > tfoot > tr")[0];

    // (8) volver al tablero de 6 días y a la tabla
    pppPlanTabla(false); await new Promise((res) => setTimeout(res, 150));
    out.tablero = /pn-days/.test(prev.innerHTML) && !/class="pga"/.test(prev.innerHTML);
    pppPlanTabla(true); await new Promise((res) => setTimeout(res, 150));
    out.vuelve = /class="pga"/.test(prev.innerHTML);

    window.fetch = _fetch;
    return out;
  });

  let ok = true;
  const t = (c, m) => { console.log((c ? "  ✅ " : "  ❌ ") + m); if (!c) ok = false; };
  const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

  t(r.esDefault, "(1) la tabla es la vista por defecto de Programación");
  t(r.cols, "(1) columnas Día · m³ · Tandas · NPs + los 4 estados con el encabezado partido y su color");
  t(r.estadosDerecha, "(1) los 4 estados van últimos, bien a la derecha");
  const _pal = ["azul", "verde", "amarillo", "rojo"];
  t(r.paleta && JSON.stringify(r.paleta.head) === JSON.stringify(_pal),
    "(1) facturado azul · armado verde · en proceso amarillo · pendiente rojo, en el encabezado — " +
    JSON.stringify(r.paleta && r.paleta.head));
  t(r.paleta && JSON.stringify(r.paleta.num) === JSON.stringify(_pal),
    "(1) y el número de cada uno con el mismo color — " + JSON.stringify(r.paleta && r.paleta.num));
  t(r.salidas, "(1) botones para el tablero de 6 días y la vista clásica");
  t(r.dias.length === 2, "(2) una fila por día con programación (2)");
  t(eq(r.dias[0].slice(0, 4), ["▸Lunes 14/09", "5,2", "2", "3"]), "(2) el día trae m³, tandas y NPs — " + JSON.stringify(r.dias[0].slice(0, 4)));
  t(r.hoy, "(2) el día de hoy está marcado");
  t(r.sinTandasCerrado, "(2) arranca cerrado: no se ven tandas");
  t(eq(r.pctMartes, ["20 %1", "20 %1", "40 %2", "20 %1"]), "(3) los 4 % del martes en números — " + JSON.stringify(r.pctMartes));
  t(eq(r.pctClases, ["fac", "arm", "pro", "pen"]), "(3) cada % con su color (fac/arm/pro/pen)");
  t(eq(r.tandas, ["D56D", "D67E", "E01E"]), "(4) el día se expande en sus tandas, ordenadas — " + JSON.stringify(r.tandas));
  t(r.tandaClases.some((c) => /e-armado/.test(c)) && r.tandaClases.some((c) => /e-proceso/.test(c)),
    "(4) las filas de tanda van color coded por estado");
  t(r.sinNpsCerrado, "(4) las tandas arrancan cerradas");
  t(eq(r.nps, ["LK 0058", "CH 0019"]) || eq(r.nps, ["CH 0019", "LK 0058"]), "(5) la tanda se expande en sus NP — " + JSON.stringify(r.nps));
  t(r.npPill.every((s) => s === "En proceso"), "(5) cada NP muestra su estado");
  t(r.sinContenido, "(5) las NP arrancan cerradas");
  t(r.npCod, "(5) la NP muestra el código de cliente con su prefijo (LK 1000)");
  t(r.npCodCh, "(5) y con CH si el pedido es de Chef");
  t(r.npZonaBarrio, "(5) el barrio al lado de la zona");
  t(r.npFechaPed, "(5) y la fecha de pedido");
  t(r.pidioItems, "(6) abrir la NP pide su contenido a gv_ppp_np_items");
  t(r.contenido, "(6) y muestra los códigos, las cajas y las unidades");
  t(r.contenidoAncho >= 90, "(6) el contenido usa el ancho, no queda encajonado — " + r.contenidoAncho + " % del td");
  t(r.contenidoEnLaFila, "(6) y va en la MISMA fila de la NP, en las celdas que estaban vacías");
  t(r.cacheItems, "(6) una sola vuelta de red por NP");
  // 1,8 + 1,5 + 1,86 + 0,1 + 2,5 + 0,9 + 1,3 + 1,35 = 11,31 m³ · 5 tandas · 8 NP
  // v17.94 (Luis): "letra más grande, que mantenga el tamaño al expandirse". Antes se ACHICABA
  // por nivel (14 → 13 → 12,5): la fila con más info era la que menos se leía.
  const _t = r.tam || {};
  t(_t.dia >= 16 && _t.tanda >= 16 && _t.np >= 16,
    "(9) la letra es de 16 px o más en los tres niveles — " + JSON.stringify(_t));
  t(_t.dia === _t.tanda && _t.tanda === _t.np,
    "(9) y es LA MISMA: no se achica al expandir — " + JSON.stringify(_t));
  const _p = r.pos || {};
  t(_p.dia > 0 && _p.dia === _p.tanda && _p.tanda === _p.np,
    "(9) y los tres arrancan en la MISMA posición: no se abre hacia adentro — " + JSON.stringify(_p));
  t(r.zoom === "1", "(9) pppFitPantalla no achica esta vista (antes caía a 0,70) — zoom " + r.zoom);
  t(eq(r.total.slice(0, 4), ["Total", "11,3", "5", "8"]), "(7) el total suma todos los días — " + JSON.stringify(r.total.slice(0, 4)));
  t(r.tablero, "(8) se puede volver al tablero de 6 días");
  t(r.vuelve, "(8) y volver a la tabla");
  t(errs.length === 0, "sin errores de JS" + (errs.length ? ": " + errs[0] : ""));

  await b.close();
  console.log(ok ? "\nOK ppp-tabla-arbol" : "\nFALLÓ ppp-tabla-arbol");
  process.exit(ok ? 0 : 1);
})();
