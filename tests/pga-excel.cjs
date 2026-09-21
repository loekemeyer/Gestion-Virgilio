/* v20.52/v20.57 (Thomas) — DENTRO DEL BOTÓN DE IMPRIMIR, TAMBIÉN EXCEL.
   v20.52: *"dentro del botón de imprimir. dejame imprimir o descargar excel"*.
   v20.57: *"misma idea, tabla optimizada, fuente grande, mínimo espacio entre columnas
   (doble fila de encabezados, etc)"*.

   Lo que fija este test:
     · el pop-up de «Imprimir» tiene los dos botones y comparten la misma selección de días;
     · «Ninguno» deshabilita LOS DOS — no se baja un Excel vacío;
     · el libro trae TRES hojas: Programación (una fila por NP), Tandas y Resumen;
     · la hoja de detalle va PLANA, con el día y la tanda repetidos en cada fila;
     · sólo entran los días tildados;
     · DOBLE FILA de encabezados: grupos combinados arriba, columnas abajo;
     · fuente Arial 14 (18 en el título), anchos pegados al dato, panel inmovilizado y autofiltro;
     · los m³ y el monto son NÚMEROS con su formato, y la fecha es una FECHA de verdad;
     · el monto de cada NP sale de `gv_ppp_np_valor` (valor de lista) y los totales cierran;
     · el archivo que se baja es un .xlsx de verdad (ZIP: PK\x03\x04);
     · al bajarlo se cierra el pop-up.
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
    _pppParsed = { prog: [] };
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    window.pppPaintTabs = function () {};
    window.pgaNeed = function () {};

    const mk = (f, t, np, rs, m3, est, o) => Object.assign({
      fecha: f, tanda: t, np: np, np_num: 0, cod: "2118", razon_social: rs, localidad: "Barracas",
      zona: "Zona 2 - CABA Centro", zona_corta: "Zona 2", empresa: np.startsWith("CH") ? "CH" : "LK",
      origen: /^(LK|CH) /.test(np) ? "web" : "isis", m3: m3, estado: est, estado_orden: 1,
      barrio: "Villa Crespo", fecha_pedido: "2026-09-11", pide_horario: false
    }, o || {});
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
    // v20.45: el destino (provincia) viaja aparte; la columna del Excel tiene que leerlo de ahí
    _pgaDest = new Map([["LK 0061", { provincia: "Misiones", expreso: "Andesmar", alerta: true }]]);
    // v20.57: el monto sale de `gv_ppp_np_valor`, que la pantalla cachea en `_pppValor`
    _pppValor = new Map([["LK 0058", { valor: 1234567, sinPrecio: 0 }],
                         ["98701", { valor: 89000, sinPrecio: 2 }],
                         ["LK 0060", { valor: 2500000, sinPrecio: 0 }],
                         ["LK 0061", { valor: 450000, sinPrecio: 0 }],
                         ["CH 0019", { valor: 77000, sinPrecio: 0 }]]);
    window.fetch = async function () {
      return { ok: true, status: 200, json: async () => [], text: async () => "[]", headers: { get: () => null } };
    };

    _pppTab = "plan"; _pppPlanTabla = true; _pppPlanDay = null;
    document.getElementById("pppOverlay").classList.add("show");
    pppRenderProg(); await new Promise((res) => setTimeout(res, 250));

    pgaImprimirAbrir();
    const m = document.getElementById("pgiModal");
    out.hayExcel = !!document.getElementById("pgiXls");
    out.hayImprimir = !!document.getElementById("pgiOk");
    out.textoExcel = out.hayExcel ? document.getElementById("pgiXls").textContent.trim() : "";
    out.mismaBotonera = !!(out.hayExcel &&
      document.getElementById("pgiXls").closest(".pgi-btns") ===
      document.getElementById("pgiOk").closest(".pgi-btns"));
    // el pop-up muestra el monto del día, para elegir sin adivinar
    out.montoEnPopup = /\$ 3\.823\.567/.test(m.textContent);

    pgaImprimirTodos(false);
    out.ningunoDeshabilitaExcel = !!document.getElementById("pgiXls").disabled;
    out.ningunoDeshabilitaPrint = !!document.getElementById("pgiOk").disabled;
    pgaImprimirTodos(true);
    out.todosHabilitaExcel = !document.getElementById("pgiXls").disabled;

    // se espía lo que se manda a armar, sin romper el armado de verdad
    const orig = window._pgxBlob;
    let hojas = null, nombre = null, clicks = 0;
    window._pgxBlob = function (h) { hojas = h; return orig.apply(null, arguments); };
    const origClick = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function () { clicks++; nombre = this.download; };

    const keys = _pgi.dias.map((d) => d.key);
    pgaImprimirTildar(keys[2], false);          // 2 de los 3 días
    pgaImprimirExcel();
    HTMLAnchorElement.prototype.click = origClick;
    window._pgxBlob = orig;

    out.clicks = clicks;
    out.nombre = nombre;
    out.cerroPopup = !!document.getElementById("pgiModal").hidden;
    out.hojas = (hojas || []).map((h) => h.nombre);
    const det = (hojas || [])[0] || { filas: [] };
    out.grupos = (det.filas[2] || []).map((c) => (c && c.v) || "");
    out.enc = (det.filas[3] || []).map((c) => (c && c.v) || "");
    out.filas = det.filas.slice(4, -1).map((f) => f.map((c) => (c ? c : {})));
    out.total = (det.filas[det.filas.length - 1] || []).map((c) => (c ? c.v : ""));
    out.merges = det.merges || [];
    out.congelar = det.congelar;
    out.filtro = det.filtro;
    out.cols = det.cols;
    out.tandas = ((hojas || [])[1] || { filas: [] }).filas;
    out.resumen = ((hojas || [])[2] || { filas: [] }).filas;

    // el blob que se baja tiene que ser un ZIP de verdad, y traer styles.xml
    const blob = orig(hojas);
    const bytes = new Uint8Array(await blob.arrayBuffer());
    out.magic = String.fromCharCode(bytes[0], bytes[1]) + "," + bytes[2] + "," + bytes[3];
    out.mime = blob.type;
    out.bytes = bytes.length;
    const txt = new TextDecoder("latin1").decode(bytes);
    out.tieneStyles = txt.indexOf("xl/styles.xml") >= 0;
    out.arial14 = /<sz val="14"\/><name val="Arial"\/>/.test(txt);
    out.arial18 = /<b\/><sz val="18"\/><name val="Arial"\/>/.test(txt);
    out.fmtM3 = txt.indexOf('formatCode="#,##0.000"') >= 0;
    out.fmtMoney = txt.indexOf('formatCode="#,##0"') >= 0;
    out.fmtFecha = txt.indexOf('formatCode="dd/mm/yyyy"') >= 0;
    // el orden que exige el esquema: cols → sheetData → autoFilter → mergeCells
    const i1 = txt.indexOf("<cols>"), i2 = txt.indexOf("<sheetData>"),
          i3 = txt.indexOf("<autoFilter"), i4 = txt.indexOf("<mergeCells");
    out.ordenSchema = i1 > 0 && i1 < i2 && i2 < i3 && i3 < i4;
    return out;
  });

  await b.close();

  const ok = [];
  const chk = (c, d) => ok.push([!!c, d]);
  const col = (n) => r.enc.indexOf(n);
  const cel = (f, n) => f[col(n)] || {};

  chk(r.hayExcel, "el pop-up de «Imprimir» trae un botón de Excel");
  chk(/excel/i.test(r.textoExcel), "y dice Excel: " + JSON.stringify(r.textoExcel));
  chk(r.hayImprimir, "el botón de imprimir sigue estando");
  chk(r.mismaBotonera, "los dos salen de la MISMA selección de días (misma botonera)");
  chk(r.montoEnPopup, "y cada día del pop-up muestra su monto, para elegir sin adivinar");
  chk(r.ningunoDeshabilitaExcel && r.ningunoDeshabilitaPrint,
      "«Ninguno» deshabilita los dos — no se baja un Excel vacío");
  chk(r.todosHabilitaExcel, "«Todos» vuelve a habilitar el de Excel");
  chk(r.clicks === 1, "baja el archivo una sola vez");
  chk(/^Programacion_20260915_a_20260916\.xlsx$/.test(r.nombre || ""),
      "el archivo se llama por el rango elegido: " + JSON.stringify(r.nombre));
  chk(r.cerroPopup, "al bajarlo se cierra el pop-up");
  chk(r.magic === "PK,3,4", "es un .xlsx de verdad (ZIP: PK\\x03\\x04): " + r.magic);
  chk(/spreadsheetml\.sheet$/.test(r.mime), "con el MIME de Excel: " + r.mime);
  chk(r.hojas.length === 3 && /Programaci/.test(r.hojas[0]) && r.hojas[1] === "Tandas" &&
      r.hojas[2] === "Resumen", "trae tres hojas: " + JSON.stringify(r.hojas));

  // ── v20.57: el formato ────────────────────────────────────────────────────
  chk(r.tieneStyles, "el libro lleva styles.xml — la v20.52 bajaba una grilla pelada");
  chk(r.arial14 && r.arial18, "con Arial 14 de cuerpo y 18 en el título");
  chk(r.fmtM3 && r.fmtMoney && r.fmtFecha,
      "y formato de número para m³ (#,##0.000), monto (#,##0) y fecha (dd/mm/yyyy)");
  chk(r.ordenSchema, "los elementos de la hoja van en el orden que exige el esquema " +
      "(cols → sheetData → autoFilter → mergeCells)");
  chk(r.grupos.filter((x) => x).join("|") === "ENTREGA|TANDA|PEDIDO|DESTINO|TOTALES|ESTADO",
      "DOBLE fila de encabezados: arriba los grupos, " + JSON.stringify(r.grupos.filter((x) => x)));
  chk(r.merges.some((m) => /^A1:/.test(m)) && r.merges.some((m) => /^E3:H3$/.test(m)),
      "con las celdas de grupo combinadas: " + JSON.stringify(r.merges.slice(0, 4)));
  chk(r.congelar === 4 && r.filtro === "A4:Q4",
      "panel inmovilizado bajo el encabezado y autofiltro en la fila de columnas: " +
      r.congelar + " / " + r.filtro);
  chk(r.cols.length === r.enc.length && r.cols.every((w) => w >= 6 && w <= 42),
      "y cada columna con su ancho, pegado al dato: " +
      JSON.stringify(r.cols.map((w) => Math.round(w))));

  // ── los datos ─────────────────────────────────────────────────────────────
  chk(r.filas.length === 5, "sólo los días tildados: 5 NP de las 6 (el 17 queda afuera)");
  chk(!r.filas.some((f) => cel(f, "Tanda").v === "E12A"), "y ninguna fila del día no tildado");
  chk(r.filas.filter((f) => cel(f, "Tanda").v === "E10A").length === 2 &&
      r.filas.every((f) => cel(f, "Tanda").v && cel(f, "Día").v),
      "sale PLANO: el día y la tanda se repiten en cada fila (filtrable en Excel)");
  chk(col("NP") >= 0 && col("Cliente") >= 0 && col("m³") >= 0 && col("Monto $ (lista)") >= 0,
      "el encabezado tiene las columnas de la operación: " + JSON.stringify(r.enc));

  const f58 = r.filas.find((f) => cel(f, "NP").v === "LK 0058");
  chk(!!f58 && cel(f58, "Cliente").v === "Ricci Gabriel Edgardo", "cada fila trae la razón social");
  chk(!!f58 && cel(f58, "Cód cliente").v === "2118" && cel(f58, "Emp").v === "LK",
      "el cód de cliente va en su columna, con la empresa al lado (la clave es (empresa, cod))");
  chk(!!f58 && cel(f58, "Estado").v === "Facturado", "y el estado en castellano");
  chk(!!f58 && cel(f58, "Fecha").n === true && cel(f58, "Fecha").v === 46280,
      "la fecha es una FECHA de verdad (serial de Excel), no texto: " + cel(f58 || [], "Fecha").v);
  chk(!!f58 && cel(f58, "m³").n === true && cel(f58, "m³").v === 1.2,
      "los m³ son número, no texto: " + JSON.stringify(cel(f58 || [], "m³").v));
  chk(!!f58 && cel(f58, "Monto $ (lista)").n === true && cel(f58, "Monto $ (lista)").v === 1234567,
      "y el monto también: " + JSON.stringify(cel(f58 || [], "Monto $ (lista)").v));

  const f701 = r.filas.find((f) => cel(f, "NP").v === "98701");
  chk(!!f701 && cel(f701, "Art. s/precio").v === 2,
      "la NP con artículos sin precio lo dice en su columna — el monto no se presenta como completo");
  const f61 = r.filas.find((f) => cel(f, "NP").v === "LK 0061");
  chk(!!f61 && cel(f61, "Provincia destino").v === "Misiones",
      "la provincia de destino sale en su columna (v20.45: la zona es dónde va el camión)");
  chk(!!f61 && /08:00/.test(cel(f61, "Horario").v || ""), "y el horario pactado, si lo pide");
  chk(r.filas.filter((f) => cel(f, "Provincia destino").v).length === 1,
      "sin provincia resuelta la celda queda vacía — no se inventa");

  chk(r.total[0] === "TOTAL" && r.total[12] === 6.35 && r.total[13] === 4350567,
      "la hoja cierra con su total de m³ y de plata: " + JSON.stringify([r.total[12], r.total[13]]));
  const tTot = r.tandas[r.tandas.length - 1].map((c) => (c ? c.v : ""));
  chk(r.tandas.length === 5 && tTot[0] === "TOTAL" && tTot[6] === 4350567,
      "la hoja Tandas trae una fila por tanda (3) y su total: " + JSON.stringify(tTot));
  const dTot = r.resumen[r.resumen.length - 1].map((c) => (c ? c.v : ""));
  chk(r.resumen.length === 4 && dTot[0] === "TOTAL" && dTot[3] === 5 && dTot[5] === 4350567,
      "y el Resumen una fila por día (2) y su total: " + JSON.stringify(dTot));

  chk(errs.length === 0, "sin errores de JS: " + JSON.stringify(errs));

  let malas = 0;
  for (const [bien, d] of ok) { console.log((bien ? "  ok   " : "  FALLA") + " " + d); if (!bien) malas++; }
  console.log(malas ? "\n✗ " + malas + " de " + ok.length + " fallaron" : "\n✓ " + ok.length + " chequeos ok");
  process.exit(malas ? 1 : 0);
})();
