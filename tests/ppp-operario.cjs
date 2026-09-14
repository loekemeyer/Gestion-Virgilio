/* Botón PPP de la botonera del operario (v17.48 / v17.54). Verifica, headless y
   con la respuesta de Supabase mockeada, que:
   (a) el botón está en la botonera (row4) y NO se deshabilita en tiempo muerto
       — es solo mirar, así que va en ALWAYS_ALLOWED_CODES;
   (b) la tabla sale con las 4 columnas pedidas por el dueño, en ese orden:
       Fecha ; Mt3 ; Tandas ; NPs;
   (c) los días quedan en orden cronológico y el m³ con COMA decimal y 2 decimales;
   (d) la tabla NO se estira al ancho de la tarjeta (regla del dueño: nada de
       ocupar el 100% porque sí) y los números van a la derecha;
   (e) sin red, muestra lo último que bajó (cache) en vez de una pantalla vacía;
   (f) tocar un día abre su composición SEPARADA POR CAMIÓN y ordenada por número
       de NP —el orden lo pide la consulta, no el front—, con los tres tics
       (Pick / Arm / Fact) tal cual los manda el backend, el filtro LK / CH que no
       vuelve a consultar, y "← Días" que vuelve al resumen sin re-consultar. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

const FILAS = [
  { fecha: "2026-09-14", dia: "Lunes",     m3: "5.16",  tandas: 4,  nps: 12 },
  { fecha: "2026-09-15", dia: "Martes",    m3: "6.15",  tandas: 12, nps: 28 },
  { fecha: "2026-09-16", dia: "Miércoles", m3: "17.86", tandas: 20, nps: 43 },
  { fecha: "2026-09-18", dia: "Viernes",   m3: "1234.5", tandas: 5, nps: 24 }
];

const DETALLE = [
  { np: "CH 0002", np_num: "2",     tanda: "E01E", m3: "0.070", razon_social: "Elbantonio",   cod: "2101", localidad: "Soldati",     camion: "E01", empresa: "CH", pickeado: true,  armado: true,  facturado: true },
  { np: "LK 0031", np_num: "31",    tanda: "E01A", m3: "0.640", razon_social: "Chen Li Yu",   cod: "4102", localidad: "Belgrano",    camion: "E01", empresa: "LK", pickeado: false, armado: false, facturado: false },
  { np: "44612",   np_num: "44612", tanda: "D72B", m3: "0.250", razon_social: "CENCOSUD S.A.", cod: "2444", localidad: "Tortuguitas", camion: "D72", empresa: "CH", pickeado: true,  armado: true,  facturado: false },
  { np: "98652",   np_num: "98652", tanda: "D67A", m3: "0.090", razon_social: "Milera Patricia Lorena", cod: "3958", localidad: "Mataderos", camion: "D67", empresa: "LK", pickeado: true, armado: false, facturado: false },
  { np: "98704",   np_num: "98704", tanda: "D67M", m3: "1.180", razon_social: "S.A.Imp Y Exp De La Patagonia", cod: "771", localidad: "Esteban Echeverria", camion: "D67", empresa: "LK", pickeado: false, armado: false, facturado: false }
];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.setViewportSize({ width: 412, height: 900 });   // celular del operario

  let pedidos = 0, ultimaUrl = "", detUrl = "";
  await p.route("**/rest/v1/**", (route) => {
    const url = route.request().url();
    if (url.indexOf("gv_ppp_detalle_dia") >= 0) {
      detUrl = url;
      return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(DETALLE) });
    }
    if (url.indexOf("gv_ppp_resumen_dias") < 0) return route.abort();
    pedidos++; ultimaUrl = url;
    return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(FILAS) });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const fail = [];

  // (a) el botón existe, está en row4 y no se lo come el tiempo muerto
  const boton = await p.evaluate(() => {
    const el = document.querySelector('#row4 .box[data-code="PPP"]');
    return {
      hay: !!el,
      titulo: el ? el.querySelector(".box-title").textContent.trim() : "",
      siempre: (typeof ALWAYS_ALLOWED_CODES !== "undefined") && ALWAYS_ALLOWED_CODES.indexOf("PPP") >= 0
    };
  });
  if (!boton.hay) fail.push("no hay botón PPP en la botonera (#row4)");
  if (boton.titulo !== "PPP") fail.push("el título del botón no es 'PPP' sino '" + boton.titulo + "' (updateCoreButtonsState lee el título como código)");
  if (!boton.siempre) fail.push("PPP no está en ALWAYS_ALLOWED_CODES: se deshabilitaría en tiempo muerto");

  // (b)(c)(d) abrir y mirar la tabla
  await p.evaluate(() => { window.getTodayKey = function () { return "2026-09-14"; }; pppOpAbrir(); });
  await p.waitForFunction(() => !!document.querySelector("#pppOpBody .pppop-tbl"), null, { timeout: 5000 });

  const t = await p.evaluate(() => {
    const tbl = document.querySelector("#pppOpBody .pppop-tbl");
    const card = document.querySelector("#pppOpModal .pppop-card");
    const th = [...tbl.querySelectorAll("thead th")].map((x) => x.textContent.trim());
    const filas = [...tbl.querySelectorAll("tbody tr")].map((tr) =>
      [...tr.querySelectorAll("td")].map((td) => td.textContent.trim()));
    const tot = [...tbl.querySelectorAll("tfoot td")].map((td) => td.textContent.trim());
    const cs = getComputedStyle(tbl.querySelector("tbody td:nth-child(2)"));
    const cs1 = getComputedStyle(tbl.querySelector("tbody td:first-child"));
    return {
      th: th, filas: filas, tot: tot,
      anchoTabla: tbl.getBoundingClientRect().width,
      anchoCard: card.getBoundingClientRect().width,
      alineNum: cs.textAlign, alineTxt: cs1.textAlign,
      hoyBold: tbl.querySelector("tbody tr").className.indexOf("pppop-hoy") >= 0,
      celdasPintadas: [...tbl.querySelectorAll("td")].filter((td) => {
        const bg = getComputedStyle(td).backgroundColor;
        return bg && bg !== "rgba(0, 0, 0, 0)" && bg !== "transparent";
      }).length
    };
  });

  if (t.th.join(";") !== "Fecha;Mt3;Tandas;NPs") fail.push("encabezado != 'Fecha;Mt3;Tandas;NPs' → " + t.th.join(";"));
  if (t.filas.length !== FILAS.length) fail.push("filas: esperaba " + FILAS.length + ", salieron " + t.filas.length);
  if (t.filas[0] && t.filas[0][0].indexOf("Lunes 14/09") !== 0) fail.push("la 1ª fila no es 'Lunes 14/09…' sino '" + (t.filas[0] || [])[0] + "'");
  if (t.filas[0] && t.filas[0][0].indexOf("(hoy)") < 0) fail.push("el día de hoy no está marcado");
  if (!t.hoyBold) fail.push("la fila de hoy no lleva la clase pppop-hoy");
  const orden = t.filas.map((f) => f[0].replace(/\s*›\s*$/, ""));   // el › es la flecha de "tocá para ver el día"
  if (orden.join("|") !== ["Lunes 14/09 (hoy)", "Martes 15/09", "Miércoles 16/09", "Viernes 18/09"].join("|"))
    fail.push("los días no quedaron en orden cronológico → " + orden.join("|"));
  if (t.filas[2] && t.filas[2][1] !== "17,86") fail.push("m³ sin coma decimal: '" + t.filas[2][1] + "' (esperaba 17,86)");
  if (t.filas[3] && t.filas[3][1] !== "1.234,50") fail.push("m³ sin punto de miles: '" + t.filas[3][1] + "' (esperaba 1.234,50)");
  if (t.filas[1] && (t.filas[1][2] !== "12" || t.filas[1][3] !== "28")) fail.push("tandas/NPs mal en la 2ª fila → " + t.filas[1].join(";"));
  if (t.tot.join(";") !== "Total;1.263,67;41;107") fail.push("el total no cierra → " + t.tot.join(";"));
  if (t.alineNum !== "right") fail.push("los números no van a la derecha (" + t.alineNum + ")");
  if (t.alineTxt !== "left") fail.push("la fecha no va a la izquierda (" + t.alineTxt + ")");
  if (t.anchoTabla > t.anchoCard - 20) fail.push("la tabla se estira a la tarjeta (" + Math.round(t.anchoTabla) + " de " + Math.round(t.anchoCard) + " px)");
  if (t.celdasPintadas) fail.push(t.celdasPintadas + " celdas con relleno de color (el dueño las quiere sin color)");
  if (!/fecha=gte\.2026-09-14/.test(ultimaUrl)) fail.push("la consulta no filtra desde hoy → " + ultimaUrl);

  // (f) tocar un día abre su composición: agrupada por CAMIÓN, ordenada por NP,
  //     con los tres tics, y el filtro LK / CH
  await p.click("#pppOpBody tbody tr:nth-child(3)");          // Miércoles 16/09
  await p.waitForFunction(() => !!document.querySelector("#pppOpBody .pppop-cam"), null, { timeout: 5000 });

  const leer = () => p.evaluate(() => {
    const tbl = document.querySelector("#pppOpBody .pppop-tbl");
    const filas = [...tbl.querySelectorAll("tbody tr")].map((tr) =>
      tr.classList.contains("pppop-cam")
        ? { cam: tr.textContent.trim() }
        : { np: tr.children[0].textContent.trim(),
            tic: [...tr.querySelectorAll("td.pppop-tic")].map((td) => td.textContent.trim()) });
    return {
      th: [...tbl.querySelectorAll("thead th")].map((x) => x.textContent.trim()),
      filas: filas,
      tot: [...tbl.querySelectorAll("tfoot td")].map((td) => td.textContent.trim()),
      titulo: document.querySelector("#pppOpModal .pppop-title").textContent.trim(),
      chipOn: (document.querySelector(".pppop-chip.on") || {}).textContent,
      alineNp: getComputedStyle(tbl.querySelector("tbody tr:not(.pppop-cam) td:first-child")).textAlign,
      alineCli: getComputedStyle(tbl.querySelector("tbody td.pppop-cli")).textAlign,
      alineM3: getComputedStyle(tbl.querySelector("tbody tr:not(.pppop-cam) td:nth-child(4)")).textAlign,
      anchoTabla: tbl.getBoundingClientRect().width,
      anchoCard: document.querySelector(".pppop-card").getBoundingClientRect().width,
      scrollW: document.documentElement.scrollWidth,
      pintadas: [...tbl.querySelectorAll("td")].filter((td) => {
        const bg = getComputedStyle(td).backgroundColor;
        return bg && bg !== "rgba(0, 0, 0, 0)" && bg !== "transparent";
      }).length,
      hayVolver: !!document.querySelector(".pppop-volver")
    };
  });

  const det = await leer();
  if (det.th.join(";") !== "NP;Cliente;Tanda;Mt3;Pick;Arm;Fact")
    fail.push("encabezado del detalle != 'NP;Cliente;Tanda;Mt3;Pick;Arm;Fact' → " + det.th.join(";"));
  // el orden: camión por camión, en el orden de la NP más baja; adentro, por NP
  const secuencia = det.filas.map((x) => x.cam ? "[" + x.cam.replace(/\s+/g, " ") + "]" : x.np);
  const esperado = ["[🚚 Camión E01 · 2 NP · 2 tandas · 0,71 m³]", "CH 0002", "LK 0031",
                    "[🚚 Camión D72 · 1 NP · 1 tanda · 0,25 m³]", "44612",
                    "[🚚 Camión D67 · 2 NP · 2 tandas · 1,27 m³]", "98652", "98704"];
  if (secuencia.join("|") !== esperado.join("|"))
    fail.push("no quedó separado por camión / ordenado por NP →\n     " + secuencia.join("|") + "\n     esperaba: " + esperado.join("|"));
  // los tics salen tal cual los manda el backend
  const tics = det.filas.filter((x) => !x.cam).map((x) => x.tic.join(""));
  if (tics.join("|") !== "✓✓✓||✓✓|✓|") fail.push("los tics no salen como los manda el backend → " + tics.join("|"));
  if (det.tot.join(";") !== "5 NP;3 camiones;;2,23;3;2;1") fail.push("el pie del detalle no cierra → " + det.tot.join(";"));
  if (det.titulo.indexOf("Miércoles 16/09") < 0) fail.push("el título no dice qué día se está viendo → " + det.titulo);
  if (det.alineNp !== "left") fail.push("la NP no va a la izquierda (" + det.alineNp + ")");
  if (det.alineCli !== "left") fail.push("el cliente no va a la izquierda (" + det.alineCli + ")");
  if (det.alineM3 !== "right") fail.push("el m³ no va a la derecha (" + det.alineM3 + ")");
  if (det.pintadas) fail.push(det.pintadas + " celdas del detalle con relleno de color");
  if (det.anchoTabla > det.anchoCard) fail.push("la tabla del detalle se pasa de la tarjeta (" + Math.round(det.anchoTabla) + " > " + Math.round(det.anchoCard) + ")");
  if (det.scrollW > 412) fail.push("el detalle hace scroll horizontal en un celular de 412px (" + det.scrollW + ")");
  if (String(det.chipOn || "").trim() !== "Todos") fail.push("el filtro no arranca en Todos → " + det.chipOn);
  if (!/fecha=eq\.2026-09-16/.test(detUrl)) fail.push("el detalle no pide el día tocado → " + detUrl);
  if (!/order=np_num\.asc/.test(detUrl)) fail.push("el orden por NP no lo pide la consulta → " + detUrl);
  if (!/select=[^&]*camion/.test(detUrl) || !/select=[^&]*pickeado/.test(detUrl))
    fail.push("la consulta no pide camión / tics → " + detUrl);
  if (!det.hayVolver) fail.push("no hay botón para volver a los días");

  // el filtro LK deja sólo lo de LK, sin volver a consultar, y recalcula los subtotales
  const antesFiltro = pedidos, antesDet = detUrl;
  await p.evaluate(() => pppOpFiltrar("LK"));
  const lk = await leer();
  const secLk = lk.filas.map((x) => x.cam ? "[" + x.cam.replace(/\s+/g, " ") + "]" : x.np);
  if (secLk.join("|") !== ["[🚚 Camión E01 · 1 NP · 1 tanda · 0,64 m³]", "LK 0031",
                           "[🚚 Camión D67 · 2 NP · 2 tandas · 1,27 m³]", "98652", "98704"].join("|"))
    fail.push("el filtro LK no dejó sólo LK (ni recalculó el camión) → " + secLk.join("|"));
  if (lk.tot.join(";") !== "3 NP;2 camiones;;1,91;1;0;0") fail.push("el pie no se recalcula con el filtro → " + lk.tot.join(";"));
  if (pedidos !== antesFiltro || detUrl !== antesDet) fail.push("filtrar volvió a consultar al servidor");

  await p.evaluate(() => pppOpFiltrar("CH"));
  const ch = await leer();
  const secCh = ch.filas.map((x) => x.cam ? "cam" : x.np);
  if (secCh.join("|") !== "cam|CH 0002|cam|44612") fail.push("el filtro CH no dejó sólo CH → " + secCh.join("|"));
  await p.evaluate(() => pppOpFiltrar(""));

  // (e) sin red → sale el cache, no una pantalla vacía
  await p.unroute("**/rest/v1/**");
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.evaluate(() => { pppOpCerrar(); pppOpAbrir(); });
  await p.waitForFunction(() => {
    const b = document.querySelector("#pppOpBody");
    return b && b.textContent.indexOf("Cargando") < 0;
  }, null, { timeout: 5000 });
  const off = await p.evaluate(() => ({
    hayTabla: !!document.querySelector("#pppOpBody .pppop-tbl"),
    txt: document.querySelector("#pppOpBody").textContent
  }));
  if (!off.hayTabla) fail.push("sin red no mostró el cache (quedó sin tabla)");
  if (off.txt.indexOf("Sin conexión") < 0) fail.push("sin red no avisó que los datos son viejos");

  if (errs.length) fail.push("errores de página: " + errs.join(" | "));
  await b.close();

  if (fail.length) { console.error("ppp-operario FALLÓ:\n - " + fail.join("\n - ")); process.exit(1); }
  console.log("ppp-operario OK — botón en la botonera, Fecha;Mt3;Tandas;NPs, " + (pedidos) + " consulta(s), cache offline.");
})();
