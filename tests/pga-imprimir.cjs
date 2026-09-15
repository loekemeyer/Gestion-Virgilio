/* v17.97 (Luis, 2026-09-15) — IMPRIMIR LA PROGRAMACIÓN.
   Pedido: *"al lado del botón de «Actualizar» quiero que haya un botón de «Imprimir». Al
   apretarlo debería dar la opción de elegir qué días o rango de días imprimir, y la
   visualización debería ser al estilo la tabla de abajo abierta al nivel de tandas (que muestre
   las NPs y los datos pero no necesariamente el contenido individual de cada NP)"*.

   Lo que fija este test:
     · el botón está donde lo pidió: el renglón siguiente a «Actualizar», no al final de la fila;
     · el pop-up lista UN renglón por día con m³/tandas/NP y arranca con todo tildado;
     · el rango Desde/Hasta recorta la selección (y si lo dan al revés se ordena solo);
     · «Ninguno» deshabilita el botón de imprimir — no se manda una hoja vacía a la impresora;
     · la hoja sale ABIERTA hasta la NP y SIN el contenido de cada NP (lo que pidió textual);
     · sólo entran los días tildados;
     · al imprimir se cierra el pop-up ANTES de llamar a print(), si no sale en el papel;
     · en `media print` lo único visible es la hoja: el resto de la app se esconde;
     · la hoja imprime en NEGRO (heredaba el azul de la app y en papel salía gris).
   Estado inyectado; no pega contra la red. */
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
    window.getTodayKey = () => "2026-09-15";
    _pppParsed = { prog: [{ np: "98630", tanda: "D72B", fecha_entrega: "2026-09-15", m3: 1.8,
                            cod: "1000", razon_social: "Jumbo", zona: "Zona 2", programmed: true }] };
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    window.pppPaintTabs = function () {};
    window.pgaNeed = function () {};

    const mk = (f, t, np, rs, m3, est, o) => Object.assign({
      fecha: f, tanda: t, np: np, np_num: 0, cod: "2118", razon_social: rs, localidad: "Barracas",
      zona: "Zona 2 - CABA Centro", zona_corta: "Zona 2", empresa: np.startsWith("CH") ? "CH" : "LK",
      origen: /^(LK|CH) /.test(np) ? "web" : "isis", m3: m3, estado: est, estado_orden: 1,
      barrio: "Villa Crespo", fecha_pedido: "2026-09-11", pide_horario: false
    }, o || {});
    // 3 días: 15 (2 tandas / 3 NP), 16 (1 tanda / 2 NP), 17 (1 tanda / 1 NP)
    _pgaRows = [
      mk("2026-09-15", "E10A", "LK 0058", "Ricci Gabriel Edgardo", 1.2, "facturado"),
      mk("2026-09-15", "E10A", "98701", "Pettish Lacroze 2481", 0.9, "pendiente", { cod: "1974" }),
      mk("2026-09-15", "E10B", "LK 0060", "Lin Liqin", 2.5, "proceso", { cod: "4274" }),
      mk("2026-09-16", "E11A", "LK 0061", "Miguel Addoumie SRL", 1.35, "armado",
         { cod: "3958", pide_horario: true, horario_fecha: "2026-09-16", horario_franja: "08:00 a 12:00" }),
      mk("2026-09-16", "E11A", "CH 0019", "Osa Hermanos", 0.4, "pendiente", { cod: "2533" }),
      mk("2026-09-17", "E12A", "98700", "Andser Quimica", 1.3, "pendiente", { cod: "1000" })
    ];
    _pgaTs = Date.now();
    // el contenido de la NP NO tiene que pedirse ni salir en la hoja: si se pide, se ve acá
    const pedidosItems = [];
    window.fetch = async function (url) {
      const u = String(url);
      if (/gv_ppp_np_items/.test(u)) pedidosItems.push(u);
      return { ok: true, status: 200, json: async () => [], text: async () => "[]", headers: { get: () => null } };
    };

    _pppTab = "plan"; _pppPlanTabla = true; _pppPlanClasica = false; _pppPlanDay = null;
    document.getElementById("pppOverlay").classList.add("show");
    pppRenderProg(); await new Promise((res) => setTimeout(res, 250));

    // ── (1) el botón, al lado de Actualizar ────────────────────────────────
    const tools = [...document.querySelectorAll("#pppPreview .pn-tools button")]
      .map((e) => e.textContent.trim());
    out.botones = tools;
    out.hayBoton = tools.some((t) => /Imprimir/.test(t));
    out.alLadoDeActualizar = tools.findIndex((t) => /Imprimir/.test(t)) ===
                             tools.findIndex((t) => /Actualizar/.test(t)) + 1;
    out.tieneTitle = !![...document.querySelectorAll("#pppPreview .pn-tools button")]
      .find((e) => /Imprimir/.test(e.textContent) && (e.title || "").length > 10);

    // ── (2) el pop-up: un renglón por día, todo tildado ────────────────────
    pgaImprimirAbrir();
    const m = document.getElementById("pgiModal");
    out.abre = !!m && !m.hidden;
    const filas = [...m.querySelectorAll(".pgi-dia")];
    out.nDias = filas.length;                                   // 3
    out.diasTxt = filas.map((f) => f.querySelector("b").textContent.trim());
    out.todosTildados = filas.every((f) => f.querySelector("input").checked);
    // cada renglón dice m³ · tandas · NP (para elegir sin adivinar)
    out.renglonDatos = /2 tandas/.test(filas[0].textContent) && /3 NP/.test(filas[0].textContent) &&
                       /1 tanda[^s]/.test(filas[2].textContent) && /1 NP/.test(filas[2].textContent);
    out.btnDice = document.getElementById("pgiOk").textContent.trim();   // "🖨 Imprimir 3 días"

    // ── (3) el rango Desde/Hasta ───────────────────────────────────────────
    const keys = _pgi.dias.map((d) => d.key);
    out.rangoArranca = [document.getElementById("pgiD1").value, document.getElementById("pgiD2").value];
    document.getElementById("pgiD1").value = keys[1];
    document.getElementById("pgiD2").value = keys[2];
    pgaImprimirRango();
    out.trasRango = _pgi.dias.filter((d) => _pgi.sel[d.key]).map((d) => d.key);       // [16, 17]
    out.btnTrasRango = document.getElementById("pgiOk").textContent.trim();
    // al revés se ordena solo
    document.getElementById("pgiD1").value = keys[2];
    document.getElementById("pgiD2").value = keys[0];
    pgaImprimirRango();
    out.rangoAlReves = _pgi.dias.filter((d) => _pgi.sel[d.key]).length;               // los 3

    // ── (4) Ninguno deshabilita; Todos vuelve ──────────────────────────────
    pgaImprimirTodos(false);
    out.ningunoDeshabilita = !!document.getElementById("pgiOk").disabled;
    pgaImprimirTodos(true);
    out.todosHabilita = !document.getElementById("pgiOk").disabled;

    // ── (5) la hoja: día → tanda → NP, SIN el contenido ────────────────────
    let llamoPrint = 0; window.print = function () { llamoPrint++; };
    // se imprimen sólo 2 de los 3 días, para ver que el filtro manda
    pgaImprimirTildar(keys[2], false);
    pgaImprimirHacer();
    out.cerroPopup = !!document.getElementById("pgiModal").hidden;
    await new Promise((res) => setTimeout(res, 150));
    out.llamoPrint = llamoPrint;

    const hoja = document.getElementById("pgaPrint");
    out.hayHoja = !!hoja;
    const hh = hoja.innerHTML;
    out.diasEnHoja = [...hoja.querySelectorAll(".pgp-dia > h3")].map((e) => e.childNodes[0].textContent.trim());
    out.soloTildados = out.diasEnHoja.length === 2;
    out.tandasEnHoja = [...hoja.querySelectorAll("tr.pgp-t > td:first-child")].map((e) => e.textContent.trim());
    out.npsEnHoja = [...hoja.querySelectorAll("tr.pgp-np td:first-child b")].map((e) => e.textContent.trim());
    // lo que pidió textual: la NP con sus datos, NO su contenido
    out.sinContenido = !/pga-its|pga-it\b|apr-det/.test(hh) && !pedidosItems.length;
    // v18.02 (Luis): el cód va DENTRO de la celda del cliente, entre paréntesis — no en la de la NP
    out.codEnCliente = [...hoja.querySelectorAll("tr.pgp-np")].map((tr) => ({
      np: tr.children[0].textContent.trim(), cli: tr.children[1].textContent.trim() }));
    out.tieneCodCliente = /\(LK 2118\)/.test(hh) && /\(CH 2533\)/.test(hh);
    // ojo: la NP web ES "LK 0058", eso no es el cód. Lo que no tiene que estar es el cód entre
    // paréntesis, y la NP de ISIS tiene que quedar pelada ("98701", antes "98701 LK 1974").
    out.npSinCod = out.codEnCliente.every((x) => !/\(/.test(x.np)) &&
      out.codEnCliente.some((x) => x.np === "98701");
    out.cliConCod = out.codEnCliente.some((x) => /^Ricci Gabriel Edgardo \(LK 2118\)$/.test(x.cli));
    out.tieneCliente = /Ricci Gabriel Edgardo/.test(hh) && /Osa Hermanos/.test(hh);
    // el horario dejó de ser columna (estaba vacía casi siempre): es un 2º renglón dentro del cliente
    out.tieneHorario = /08:00/.test(hh);
    out.horEnCliente = !!hoja.querySelector("tr.pgp-np td.pgp-cli .pgp-hor");
    out.sinColHorario = [...hoja.querySelectorAll("table.pgp-tab thead th")]
      .every((e) => !/horario/i.test(e.textContent));
    // la zona no se repite: el renglón de la tanda ya la dice, la NP deja sólo el barrio
    out.lugares = [...hoja.querySelectorAll("tr.pgp-np td:nth-child(3)")].map((e) => e.textContent.trim());
    out.tieneEstado = [...hoja.querySelectorAll(".pgp-est")].map((e) => e.textContent.trim());
    out.tieneTotal = [...hoja.querySelectorAll("tr.pgp-tot")].length === 2;
    out.tieneEncabezado = /Programación de entregas/.test(hh) && /impreso el /.test(hh);
    // las columnas alinean entre días: cada tabla trae el mismo colgroup de 6
    out.colgroups = [...hoja.querySelectorAll("table.pgp-tab")].map((t) => t.querySelectorAll("col").length);
    // los anchos salen del dato, pero tienen que ser LOS MISMOS en todos los días (si no, no alinean)
    out.anchos = [...hoja.querySelectorAll("table.pgp-tab")].map((t) =>
      [...t.querySelectorAll("col")].map((c) => c.style.width).join("|"));
    out.anchosIguales = out.anchos.length === 2 && out.anchos[0] === out.anchos[1];
    // ojo: buscar "7%" con regex daba falso positivo dentro de "5.57%". Se compara el juego entero.
    out.anchosDelDato = (out.anchos[0] || "") !== "17%|28%|22%|14%|7%|12%" &&
      (out.anchos[0] || "").split("|").every((x) => /^\d+(\.\d+)?%$/.test(x));
    out.anchosSuman100 = Math.abs((out.anchos[0] || "").split("|")
      .reduce((a, x) => a + parseFloat(x || 0), 0) - 100) < 0.5;
    out.thRepetido = [...hoja.querySelectorAll("table.pgp-tab thead")].length === 2;

    // ── (6) en pantalla la hoja no se ve ───────────────────────────────────
    out.hojaEscondidaEnPantalla = getComputedStyle(hoja).display === "none";
    return out;
  });

  // ── (7) en `media print`: sólo la hoja, y en negro ────────────────────────
  // El viewport se lleva al ancho ÚTIL de una A4 con los márgenes de @page (190 mm ≈ 718 px): es el
  // único ancho en el que tiene sentido preguntar si algo se corta.
  await p.setViewportSize({ width: 718, height: 1100 });
  await p.emulateMedia({ media: "print" });
  const imp = await p.evaluate(() => {
    const hoja = document.getElementById("pgaPrint");
    const otros = [...document.body.children].filter((e) =>
      e.id !== "pgaPrint" && getComputedStyle(e).display !== "none").map((e) => e.id || e.tagName);
    const cli = hoja.querySelector("tr.pgp-np td:nth-child(2)");
    // nada truncado: con los anchos salidos del dato, ninguna celda puede desbordar su columna
    const cortadas = [...hoja.querySelectorAll("table.pgp-tab td")]
      .filter((td) => td.scrollWidth > td.clientWidth + 1)
      .map((td) => td.textContent.trim().slice(0, 40));
    const tab = hoja.querySelector("table.pgp-tab");
    // cuánto del ancho de cada columna usa de verdad su celda más larga (100 % = sin aire muerto)
    const uso = [...tab.querySelectorAll("thead th")].map((th, i) => {
      const tds = [...tab.querySelectorAll("tbody tr")].map((tr) => tr.children[i]).filter(Boolean);
      const need = Math.max(...tds.map((td) => td.scrollWidth));
      return Math.round(100 * need / th.getBoundingClientRect().width);
    });
    return {
      cortadas: cortadas,
      uso: uso,
      fontPx: parseFloat(getComputedStyle(tab).fontSize),
      fontInline: tab.getAttribute("style") || "",
      anchoTabla: tab.getBoundingClientRect().width,
      anchoCont: hoja.getBoundingClientRect().width,
      hojaVisible: getComputedStyle(hoja).display !== "none",
      otrosVisibles: otros,
      colorCliente: cli ? getComputedStyle(cli).color : null,
      colorHoja: getComputedStyle(hoja).color
    };
  });
  // (8) y el mismo papel, más ancho: la letra tiene que CRECER con él. La v18.02 la elegía en px
  // contra un ancho supuesto (718), así que en una hoja más ancha quedaba chica y sobraba aire.
  await p.setViewportSize({ width: 1000, height: 1100 });
  const ancho = await p.evaluate(() => {
    const tab = document.querySelector("#pgaPrint table.pgp-tab");
    return { fontPx: parseFloat(getComputedStyle(tab).fontSize),
      llena: tab.getBoundingClientRect().width /
             document.getElementById("pgaPrint").getBoundingClientRect().width };
  });
  await p.emulateMedia({ media: "screen" });
  await b.close();

  const ok = [];
  const chk = (c, d) => ok.push([!!c, d]);
  chk(r.hayBoton, "hay un botón «Imprimir» en la barra de Programación");
  chk(r.alLadoDeActualizar, "está al lado de «Actualizar» (el renglón siguiente), no al final");
  chk(r.tieneTitle, "el botón tiene tooltip que explica qué hace");
  chk(r.abre, "el botón abre el pop-up de selección");
  chk(r.nDias === 3, "el pop-up lista un renglón por día (3)");
  chk(r.diasTxt.length === 3 && /15/.test(r.diasTxt[0]) && /17/.test(r.diasTxt[2]),
      "los días salen en orden, con día de semana y fecha: " + JSON.stringify(r.diasTxt));
  chk(r.todosTildados, "arranca con todos los días tildados");
  chk(r.renglonDatos, "cada renglón dice m³ · tandas · NP");
  chk(/3 días/.test(r.btnDice), "el botón dice cuántos días va a imprimir: " + JSON.stringify(r.btnDice));
  chk(r.rangoArranca[0] === "20260915" && r.rangoArranca[1] === "20260917",
      "los selects del rango arrancan en el primer y el último día tildado");
  chk(r.trasRango.length === 2 && r.trasRango[0] === "20260916" && r.trasRango[1] === "20260917",
      "el rango 16→17 deja tildados sólo esos dos: " + JSON.stringify(r.trasRango));
  chk(/2 días/.test(r.btnTrasRango), "el botón se actualiza con el rango");
  chk(r.rangoAlReves === 3, "un rango dado al revés (17→15) se ordena solo, no vacía la selección");
  chk(r.ningunoDeshabilita, "«Ninguno» deshabilita el botón — no se manda una hoja vacía");
  chk(r.todosHabilita, "«Todos» lo vuelve a habilitar");
  chk(r.cerroPopup, "al imprimir se cierra el pop-up ANTES del print (si no, sale en el papel)");
  chk(r.llamoPrint === 1, "llama a window.print() una sola vez");
  chk(r.hayHoja, "arma la hoja en #pgaPrint");
  chk(r.soloTildados, "sólo entran los días tildados (2 de 3): " + JSON.stringify(r.diasEnHoja));
  chk(r.tandasEnHoja.join(",") === "E10A,E10B,E11A",
      "la hoja sale ABIERTA a nivel tanda: " + JSON.stringify(r.tandasEnHoja));
  chk(r.npsEnHoja.length === 5, "y abierta a nivel NP (5): " + JSON.stringify(r.npsEnHoja));
  chk(r.sinContenido, "pero SIN el contenido de cada NP (ni se pide gv_ppp_np_items)");
  chk(r.tieneCodCliente, "cada NP lleva su código de cliente con la empresa (LK 2118 / CH 2533)");
  chk(r.cliConCod, "y va DENTRO del cliente, entre paréntesis: " +
      JSON.stringify((r.codEnCliente[0] || {}).cli));
  chk(r.npSinCod, "la columna de la NP ya NO lo repite: " +
      JSON.stringify(r.codEnCliente.map((x) => x.np)));
  chk(r.tieneCliente, "y la razón social");
  chk(r.tieneHorario, "el horario pactado sale en la hoja");
  chk(r.horEnCliente, "como 2º renglón dentro del cliente, no como columna propia");
  chk(r.sinColHorario, "y la columna Horario —vacía en casi todas las filas— ya no existe");
  chk(r.lugares.indexOf("Villa Crespo") >= 0 && !r.lugares.some((x) => /^Zona 2 · Zona 2/.test(x)),
      "la NP no repite la zona que ya dice su tanda, deja el barrio: " + JSON.stringify(r.lugares));
  chk(r.tieneEstado.length === 5 && r.tieneEstado.indexOf("Facturado") >= 0 &&
      r.tieneEstado.indexOf("Armado") >= 0, "cada NP lleva su estado: " + JSON.stringify(r.tieneEstado));
  chk(r.tieneTotal, "cada día cierra con su total");
  chk(r.tieneEncabezado, "la hoja tiene título con el rango y la fecha de impresión");
  chk(r.colgroups.length === 2 && r.colgroups.every((n) => n === 5),
      "cada día trae el colgroup de 5 columnas: " + JSON.stringify(r.colgroups));
  chk(r.anchosIguales, "y los anchos son idénticos entre días → alinean de hoja en hoja");
  chk(r.anchosDelDato, "los anchos los calcula _pgpAnchos() del dato real, no son los % fijos viejos: " +
      JSON.stringify(r.anchos[0]));
  chk(r.anchosSuman100, "y suman 100 % → no queda papel muerto a la derecha");
  chk(r.thRepetido, "cada tabla tiene su thead (se repite al cortar de hoja)");
  chk(r.hojaEscondidaEnPantalla, "en pantalla la hoja no se ve");
  chk(imp.hojaVisible, "en `media print` la hoja SÍ se ve");
  chk(imp.otrosVisibles.length === 0,
      "y no se ve nada más de la app: " + JSON.stringify(imp.otrosVisibles));
  chk(imp.colorCliente === "rgb(0, 0, 0)" && imp.colorHoja === "rgb(0, 0, 0)",
      "la hoja imprime en negro, no hereda el azul de la app: " + imp.colorCliente);
  chk(imp.cortadas.length === 0,
      "al ancho de una A4 no se corta NINGUNA celda: " + JSON.stringify(imp.cortadas));
  chk(/vw/.test(imp.fontInline),
      "la letra va en `vw`, no en px contra un ancho supuesto: " + JSON.stringify(imp.fontInline));
  chk(imp.fontPx >= 14, "a 718 px (una A4) la letra da " + imp.fontPx.toFixed(1) +
      " px — la v18.02 daba 11,5 fijos");
  chk(imp.anchoTabla / imp.anchoCont > 0.97,
      "la tabla llena el ancho del papel: " +
      Math.round(100 * imp.anchoTabla / imp.anchoCont) + " %");
  chk(imp.uso.every((x) => x >= 90),
      "y CADA columna la usa entera — nada de aire entre columnas: " +
      JSON.stringify(imp.uso.map((x) => x + " %")));
  chk(ancho.fontPx > imp.fontPx * 1.2,
      "en un papel más ancho la letra CRECE con él: 718 px → " + imp.fontPx.toFixed(1) +
      " px, 1000 px → " + ancho.fontPx.toFixed(1) + " px");
  chk(ancho.llena > 0.97, "y ahí también llena el ancho: " + Math.round(100 * ancho.llena) + " %");
  chk(errs.length === 0, "sin errores de JS: " + JSON.stringify(errs));

  let malas = 0;
  for (const [bien, d] of ok) { console.log((bien ? "  ok   " : "  FALLA") + " " + d); if (!bien) malas++; }
  console.log(malas ? "\n✗ " + malas + " de " + ok.length + " fallaron" : "\n✓ " + ok.length + " chequeos ok");
  process.exit(malas ? 1 : 0);
})();
