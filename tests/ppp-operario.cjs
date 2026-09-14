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
   (f) tocar un día abre su composición (NP ; Cliente ; Tanda ; Mt3 ; Estado)
       ORDENADA por número de NP —el orden lo pide la consulta, no el front—, con
       el estado tal cual lo manda el backend (Sin armar / Pickeado / Armado /
       Facturado) y "← Días" vuelve al resumen sin volver a consultarlo. */
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
  { np: "CH 0001", np_num: "1",     tanda: "E01F", m3: "0.326", razon_social: "Elbantonio",          cod: "2101", localidad: "Soldati",        estado: "Facturado", estado_orden: 4 },
  { np: "LK 0004", np_num: "4",     tanda: "E12L", m3: "0.102", razon_social: "Chen Li Yu",          cod: "4102", localidad: "Belgrano",       estado: "Armado",    estado_orden: 3 },
  { np: "CH 0011", np_num: "11",    tanda: "E03G", m3: "0.189", razon_social: "Bazar Mandarin S.R.L", cod: "2277", localidad: "Nueva Pompeya",  estado: "Pickeado",  estado_orden: 2 },
  { np: "44620",   np_num: "44620", tanda: "E03G", m3: "1.245", razon_social: "Gonzalez Pellegrini Dario", cod: "4024", localidad: "Ciudadela", estado: "Sin armar", estado_orden: 1 },
  { np: "98704",   np_num: "98704", tanda: "D69F", m3: "6.170", razon_social: "S.A.Imp Y Exp De La Patagonia", cod: "771", localidad: "Esteban Echeverria", estado: "Sin armar", estado_orden: 1 }
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

  // (f) tocar un día abre su composición, ordenada por número de NP
  await p.click("#pppOpBody tbody tr:nth-child(3)");          // Miércoles 16/09
  await p.waitForFunction(() => !!document.querySelector("#pppOpBody .pppop-det-top"), null, { timeout: 5000 });
  await p.waitForFunction(() => !!document.querySelector("#pppOpBody .pppop-tbl"), null, { timeout: 5000 });

  const det = await p.evaluate(() => {
    const tbl = document.querySelector("#pppOpBody .pppop-tbl");
    return {
      th: [...tbl.querySelectorAll("thead th")].map((x) => x.textContent.trim()),
      filas: [...tbl.querySelectorAll("tbody tr")].map((tr) => [...tr.querySelectorAll("td")].map((td) => td.textContent.trim())),
      tot: [...tbl.querySelectorAll("tfoot td")].map((td) => td.textContent.trim()),
      titulo: document.querySelector("#pppOpModal .pppop-title").textContent.trim(),
      alineNp: getComputedStyle(tbl.querySelector("tbody td:first-child")).textAlign,
      alineCli: getComputedStyle(tbl.querySelector("tbody td.pppop-cli")).textAlign,
      alineM3: getComputedStyle(tbl.querySelector("tbody td:nth-child(4)")).textAlign,
      estados: [...tbl.querySelectorAll("tbody td.pppop-est")].map((td) => td.textContent.trim()),
      sinArmarApagado: [...tbl.querySelectorAll("tbody tr")].filter((tr) => {
        const td = tr.querySelector("td.pppop-est");
        return td && td.textContent.trim() === "Sin armar" && td.classList.contains("pppop-est-0");
      }).length,
      pie: (document.querySelector("#pppOpBody .pppop-msg") || {}).textContent,
      pintadas: [...tbl.querySelectorAll("td")].filter((td) => {
        const bg = getComputedStyle(td).backgroundColor;
        return bg && bg !== "rgba(0, 0, 0, 0)" && bg !== "transparent";
      }).length,
      hayVolver: !!document.querySelector(".pppop-volver")
    };
  });
  if (det.th.join(";") !== "NP;Cliente;Tanda;Mt3;Estado") fail.push("encabezado del detalle != 'NP;Cliente;Tanda;Mt3;Estado' → " + det.th.join(";"));
  if (det.estados.join("|") !== "Facturado|Armado|Pickeado|Sin armar|Sin armar")
    fail.push("los estados no salen como vienen del backend → " + det.estados.join("|"));
  if (det.sinArmarApagado !== 2) fail.push('los "Sin armar" no quedan apagados (' + det.sinArmarApagado + " de 2)");
  if (String(det.pie || "").indexOf("1 facturado · 1 armado · 1 pickeado · 2 sin armar") < 0)
    fail.push("el pie no resume los estados → " + det.pie);
  if (det.pintadas) fail.push(det.pintadas + " celdas del detalle con relleno de color");
  if (det.filas.length !== DETALLE.length) fail.push("detalle: esperaba " + DETALLE.length + " filas, salieron " + det.filas.length);
  if (det.filas.map((f) => f[0]).join("|") !== "CH 0001|LK 0004|CH 0011|44620|98704")
    fail.push("el detalle no respeta el orden por número de NP → " + det.filas.map((f) => f[0]).join("|"));
  if (det.filas[4] && det.filas[4][3] !== "6,17") fail.push("m³ del detalle sin coma decimal: '" + det.filas[4][3] + "'");
  if (det.tot.join(";") !== "5 NP;4 tanda(s);;8,03;") fail.push("el pie del detalle no cierra → " + det.tot.join(";"));
  if (det.titulo.indexOf("Miércoles 16/09") < 0) fail.push("el título no dice qué día se está viendo → " + det.titulo);
  if (det.alineNp !== "left") fail.push("la NP no va a la izquierda (" + det.alineNp + ")");
  if (det.alineCli !== "left") fail.push("el cliente no va a la izquierda (" + det.alineCli + ")");
  if (det.alineM3 !== "right") fail.push("el m³ no va a la derecha (" + det.alineM3 + ")");
  if (!/fecha=eq\.2026-09-16/.test(detUrl)) fail.push("el detalle no pide el día tocado → " + detUrl);
  if (!/order=np_num\.asc/.test(detUrl)) fail.push("el orden por NP no lo pide la consulta → " + detUrl);
  if (!/select=[^&]*estado/.test(detUrl)) fail.push("la consulta del detalle no pide el estado → " + detUrl);
  if (!det.hayVolver) fail.push("no hay botón para volver a los días");

  // y ← Días vuelve al resumen sin volver a pedirlo
  const antes = pedidos;
  await p.click(".pppop-volver");
  await p.waitForFunction(() => !!document.querySelector("#pppOpBody thead th"), null, { timeout: 5000 });
  const volvio = await p.evaluate(() => document.querySelector("#pppOpBody thead th").textContent.trim());
  if (volvio !== "Fecha") fail.push("← Días no volvió al resumen (1ª columna: " + volvio + ")");
  if (pedidos !== antes) fail.push("volver re-consultó el resumen (" + antes + " → " + pedidos + ")");

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
