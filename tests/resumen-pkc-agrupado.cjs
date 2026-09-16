/* v19.09 — EL DETALLE DEL PICKING, UNA LÍNEA POR TANDA (pedido de Luis, 16/09).

   Cada artículo confirmado emite su propio evento PKC, y el Resumen de hoy los mostraba de
   a una tarjeta. Medido el 16/09: el de Jhonny (lg 277) tenía **297 tarjetas y 247 eran PKC
   de 9 tandas** — casi 300 scrolls en el celular para ver lo que hizo. Los demás códigos NO
   se agrupan: emiten una fila por NP o por tanda, que ya es la granularidad correcta (lo
   más numeroso después de PKC eran 32 CRN en 32 NP distintas).

   Lo que se prueba: 247 PKC → 9 renglones, el detalle escondido, el contador de faltantes
   (`reales < esperadas`, que es lo que se va a buscar), y que el resto del Resumen no se
   toca. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = {};
    const T0 = new Date("2026-09-16T09:00:00-03:00").getTime();
    const ev = (o, t, ms, extra) => Object.assign({
      opcion: o, descripcion: "x", texto: t, ts: T0 + ms, ts_inicio_iso: null, status: "sent"
    }, extra || {});

    /* ---- una tanda con 3 artículos, uno corto; otra con 2, todos completos ---- */
    const lista = [
      ev("EP",  "E11C", 0),
      ev("PKC", "E11C|502|5|5|0|LK",  60000),
      ev("PKC", "E11C|546|10|7|0|LK", 120000),   // ← faltó
      ev("PKC", "E11C|031|2|2|0|LK",  180000),
      ev("TP",  "E11C", 240000, { ts_inicio_iso: new Date(T0).toISOString() }),
      ev("PKC", "E25A|505|1|1|0|LK",  300000),
      ev("PKC", "E25A|560|3|3|0|LK",  360000),
      ev("PB",  "", 420000)
    ];
    const g = _histAgruparPkc(lista.map(x => Object.assign({}, x)));

    // 8 eventos → 5 filas: EP, TP, PB (3) + 1 grupo por tanda (2), y los 5 PKC se fueron
    out.A_agrupa = g.length === 5;
    out.A_sin_pkc_sueltos = g.filter(x => x.opcion === "PKC" && !x._pkcItems).length === 0;
    const grupos = g.filter(x => x._pkcItems);
    out.A_dos_grupos = grupos.length === 2;
    const e11c = grupos.filter(x => x._pkcTanda === "E11C")[0];
    const e25a = grupos.filter(x => x._pkcTanda === "E25A")[0];
    out.A_E11C_3_articulos = !!(e11c && e11c._pkcItems.length === 3);
    out.A_E11C_1_faltante  = !!(e11c && e11c._pkcFaltan === 1);
    out.A_E25A_2_articulos = !!(e25a && e25a._pkcItems.length === 2);
    out.A_E25A_sin_faltante = !!(e25a && e25a._pkcFaltan === 0);
    // el grupo abarca del primer al último artículo, y se ordena por el último
    out.A_ventana = !!(e11c && e11c._pkcDesde === T0 + 60000 && e11c._pkcHasta === T0 + 180000);
    out.A_ts_es_el_ultimo = !!(e11c && e11c.ts === e11c._pkcHasta);
    // los artículos quedan en el orden en que se confirmaron
    out.A_orden = !!(e11c && e11c._pkcItems.map(a => a.art).join(",") === "502,546,031");
    // lo que NO es PKC no se toca
    out.A_resto_intacto = g.filter(x => ["EP","TP","PB"].indexOf(x.opcion) >= 0).length === 3;

    /* ---- el renglón renderizado ---- */
    const html = _histPkcHtml(e11c);
    out.B_dice_la_tanda      = html.indexOf("E11C") >= 0;
    out.B_dice_3_articulos   = /<b>3 artículos<\/b>/.test(html);
    out.B_avisa_el_faltante  = html.indexOf("1 con faltante") >= 0 && html.indexOf("pkc-falta") >= 0;
    out.B_detalle_escondido  = /class="pkc-det hidden"/.test(html);
    out.B_tiene_boton        = html.indexOf("histTogglePkc") >= 0 && html.indexOf("ver detalle") >= 0;
    out.B_detalle_trae_los_3 = html.indexOf("502") >= 0 && html.indexOf("546") >= 0 && html.indexOf("031") >= 0;
    out.B_dice_cuantas       = html.indexOf("7 de 10") >= 0;   // el que faltó, legible
    // el desplegable abre y cierra, y el estado sobrevive un re-render
    out.C_arranca_cerrado = !_pkcAbiertos.has("E11C");
    histTogglePkc("E11C");
    out.C_abre = _pkcAbiertos.has("E11C");
    out.C_html_abierto = /class="pkc-det"/.test(_histPkcHtml(e11c)) && /ocultar detalle/.test(_histPkcHtml(e11c));
    histTogglePkc("E11C");
    out.C_cierra = !_pkcAbiertos.has("E11C");

    /* ---- render completo del Resumen: 247 PKC de 9 tandas → 9 renglones ---- */
    const muchos = [];
    for (let t = 0; t < 9; t++) {
      for (let a = 0; a < 27; a++) {   // 9 × 27 = 243, más 4 abajo = 247
        muchos.push(ev("PKC", "T" + t + "|art" + a + "|1|1|0|LK", t * 100000 + a * 100));
      }
    }
    for (let k = 0; k < 4; k++) muchos.push(ev("PKC", "T0|extra" + k + "|1|1|0|LK", 999000 + k));
    out.D_eran_247 = muchos.length === 247;
    const gg = _histAgruparPkc(muchos);
    out.D_quedan_9 = gg.length === 9;
    out.D_todos_los_articulos = gg.reduce((s, x) => s + x._pkcItems.length, 0) === 247;

    // y en el DOM de verdad: una sola tarjeta por tanda
    const cont = document.getElementById("legajoHistoryContent");
    if (cont) {
      _historyCache["777::" + getTodayKey()] = muchos.map(x => Object.assign({}, x, { id: "r" + Math.random() }));
      renderLegajoHistory("777");
      out.E_tarjetas_9 = cont.querySelectorAll(".history-item").length === 9;
      out.E_hay_desplegables = cont.querySelectorAll(".pkc-det").length === 9;
      out.E_todos_cerrados = cont.querySelectorAll(".pkc-det.hidden").length === 9;
      delete _historyCache["777::" + getTodayKey()];
      cont.innerHTML = "";
    }
    return out;
  });

  const claves = Object.keys(r);
  const malas = claves.filter(k => r[k] !== true);
  const pass = malas.length === 0 && errs.length === 0;
  for (const k of claves) console.log((r[k] === true ? "ok  " : "FAIL") + "   " + k);
  if (errs.length) console.log("pageerrors: " + errs.join(" | "));
  console.log("\nresumen-pkc-agrupado: " + (pass ? "OK" : "FAIL (" + malas.join(", ") + ")"));
  await b.close(); process.exit(pass ? 0 : 1);
})();
