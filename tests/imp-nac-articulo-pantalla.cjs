/* v24.01 (Luis, 29/09) — la NACIONALIZACIÓN POR ARTÍCULO en la pantalla 🚢 En curso.
   Corre la pantalla de verdad (no es un candado de texto): abre el detalle de un pedido y mira
   que cada artículo traiga su costo de nacionalización, que los tres criterios de reparto se
   puedan cambiar, y que el u$s/m³ se guarde en la TABLA del proveedor (no en el front).

   Lo que fija:
     A) la banda dice el costo del embarque y el % sobre el FOB;
     B) hay una columna de nacionalización por artículo y una de "puesto por unidad";
     C) lo repartido SUMA el costo del embarque, y no cambia al cambiar el criterio;
     D) tocar "por m³" reparte por volumen: con m³ iguales los dos artículos pagan igual,
        aunque uno valga mucho más — y con "por FOB" deja de ser igual;
     E) el u$s/m³ manda gv_imp_proveedor_guardar con SÓLO {proveedor, valor_m3}: mandar el
        resto pisaría lo que otro esté editando en el ⚙ (regla v23.95). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
const okk = (c, m) => { if (c) console.log("✓ " + m); else fail(m); };

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 950 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window._impCursoHoy = () => "2026-09-11";
    const PED = [{ pedido_ref: "PI TEST", proveedor: "Becky", n_lineas: 2, unidades: 2000, pendiente: 2000,
      llegadas: 0, fecha_embarque: "2026-09-19", fecha_llegada: "2026-11-01", lineas_sin_fecha: 0,
      usd: "33000", m3: "20" }];
    // MISMO m³, FOB muy distinto: es el caso donde los criterios se separan
    const LIN = [
      { bache_id: 1, cod_art: "601E", marca: "LK", descripcion: "Caro",  unidades: 1000, pendiente: 1000, fecha_reingreso: "2026-11-01", usd: "30000", m3: "10" },
      { bache_id: 2, cod_art: "602E", marca: "LK", descripcion: "Barato", unidades: 1000, pendiente: 1000, fecha_reingreso: "2026-11-01", usd: "3000",  m3: "10" }
    ];
    const calls = [];
    window.sbAuth = { getAccessToken: async () => "JWT-SUP" };
    window.fetch = async (u, o) => {
      const url = String(u); calls.push({ u: url.split("/rest/v1/")[1] || url, b: o && o.body });
      let data = [];
      if (url.indexOf("gv_importados_pedidos_curso") >= 0) data = PED;
      else if (url.indexOf("gv_importado_pedido_lineas") >= 0) data = LIN;
      else if (url.indexOf("gv_imp_proveedor_guardar") >= 0) data = { ok: true };
      return { ok: true, status: 200, json: async () => data, text: async () => "" };
    };
    window.__calls = calls;

    await openImpEnCurso();
    // v24.32 (Luis: "apretás sobre el proveedor y debería expandirse las unidades"): el detalle
    // se abre CLICKEANDO LA CELDA DEL PROVEEDOR, no sólo el número de PI.
    const tdProv = document.querySelector("#stkPopBody .imcu-tbl tbody td.imcu-provtd");
    out.provClickeable = !!tdProv;
    if (tdProv) { tdProv.click(); await new Promise((r) => setTimeout(r, 80)); }
    out.abrioDesdeProv = !!document.querySelector("#stkPopBody .imcu-det");
    if (!out.abrioDesdeProv) await impCursoToggle(_impCursoEnc("PI TEST"), _impCursoEnc("Becky"));
    const det = () => document.querySelector("#stkPopBody .imcu-det");
    const txt = () => det().innerText.replace(/\s+/g, " ");
    const nums = () => [...det().querySelectorAll("tbody tr")]
      .filter((tr) => !/TOTAL/.test(tr.innerText))
      .map((tr) => [...tr.cells].map((c) => c.innerText.trim()));

    out.banda = txt().indexOf("Nacionalización del embarque") >= 0;
    out.tieneFactor = /% del FOB/.test(txt());
    // ⚠ el <th> viene en MAYÚSCULAS por CSS (text-transform), así que el innerText no matchea
    // el texto tal como está escrito: se compara sobre el HTML, que es lo que la función escribe.
    out.colNac = det().innerHTML.indexOf("Nac. u$s") >= 0;
    out.colPuesto = /Puesto<small[^>]*>u\$s\/u<\/small>/.test(det().innerHTML);
    out.hayInputM3 = !!det().querySelector('input[type="number"]');
    out.crits = ["mixto", "por m³", "por FOB"].every((t) => txt().indexOf(t) >= 0);

    // el número del embarque y el TOTAL repartido, en los tres criterios
    const leerTot = () => {
      const tr = [...det().querySelectorAll("tbody tr")].find((x) => /TOTAL/.test(x.innerText));
      return tr ? tr.innerText.replace(/\s+/g, " ") : "";
    };
    const nac = _impCursoNac(_stkPop.rows[0], _stkPop.lineas[_impCursoKey(_stkPop.rows[0])]);
    out.noRecup = Math.round(nac.res.noRecup);
    out.tot = {}; out.reparto = {};
    ["mixto", "m3", "fob"].forEach(function (c) {
      impCursoNacCrit(c);
      out.tot[c] = leerTot();
      const n = _impCursoNac(_stkPop.rows[0], _stkPop.lineas[_impCursoKey(_stkPop.rows[0])]);
      out.reparto[c] = n.rep.items.map((x) => Math.round(x * 100) / 100);
    });

    // el u$s/m³: se escribe en el input y se dispara el change
    impCursoNacCrit("mixto");
    const inp = det().querySelector('input[type="number"]');
    out.m3Antes = inp.value;
    inp.value = "150"; inp.dispatchEvent(new Event("change", { bubbles: true }));
    await new Promise((res) => setTimeout(res, 120));
    const g = calls.filter((c) => String(c.u).indexOf("gv_imp_proveedor_guardar") >= 0);
    out.guardo = g.length;
    out.payload = g.length ? JSON.parse(g[g.length - 1].b) : null;
    out.errs = (window.__errs || []);
    return out;
  });

  okk(r.provClickeable, "(0) el PROVEEDOR de 🚢 En curso abre el detalle (celda clickeable)");
  okk(r.abrioDesdeProv, "(0) tocando el proveedor se expanden las unidades con la nacionalización");
  okk(r.banda, "(A) la banda dice el costo de nacionalización del embarque");
  okk(r.tieneFactor, "(A) dice el % sobre el FOB");
  okk(r.colNac, "(B) hay columna de nacionalización por artículo");
  okk(r.colPuesto, "(B) hay columna «Puesto u$s/u» (FOB + nacionalización, por unidad)");
  okk(r.crits, "(B) están los tres criterios de reparto");
  okk(r.hayInputM3, "(B) el u$s/m³ es editable en la pantalla");

  const tot = (s) => Number(String(s).replace(/[^\d]/g, ""));
  ["mixto", "m3", "fob"].forEach(function (c) {
    const d = Math.abs(tot(r.tot[c]) - r.noRecup);
    okk(d <= 2, "(C) criterio " + c + ": lo repartido suma el costo del embarque (" + tot(r.tot[c]) + " vs " + r.noRecup + ")");
    const s = r.reparto[c].reduce((a, x) => a + x, 0);
    okk(Math.abs(s - r.noRecup) <= 2, "(C) criterio " + c + ": la suma de las filas también cierra");
  });

  okk(Math.abs(r.reparto.m3[0] - r.reparto.m3[1]) < 0.02,
    "(D) por m³: los dos artículos de 10 m³ pagan lo mismo aunque uno valga 10x  (" + r.reparto.m3.join(" / ") + ")");
  okk(r.reparto.fob[0] > r.reparto.fob[1] * 5,
    "(D) por FOB: el caro paga mucho más que el barato  (" + r.reparto.fob.join(" / ") + ")");
  okk(r.reparto.mixto[0] > r.reparto.m3[0] && r.reparto.mixto[0] < r.reparto.fob[0],
    "(D) mixto queda entre los dos: el flete por m³ y los derechos por FOB  (" + r.reparto.mixto.join(" / ") + ")");

  okk(r.guardo === 1, "(E) cambiar el u$s/m³ guarda una sola vez en la base");
  const pay = r.payload && r.payload.p;
  okk(pay && Number(pay.valor_m3) === 150 && pay.proveedor === "Becky", "(E) manda el proveedor y el valor nuevo");
  okk(pay && Object.keys(pay).length === 2,
    "(E) manda SÓLO {proveedor, valor_m3}: toda clave ausente queda intacta (regla v23.95)  [mandó " + (pay ? Object.keys(pay).join(",") : "—") + "]");

  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("\n✓ nacionalización por artículo en pantalla OK");
})();
