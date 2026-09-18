/* Submódulo "Pedidos atrasados" (v18.78, pedido de Luis 2026-09-16).

   Arriba de "Programación de entregas": una fila por día YA PASADO que todavía tiene pedidos
   sin registro de salida. La fila del día aparece sola cuando el día pasa y desaparece sola
   cuando esa NP se carga al camión.

   Lo que se cuida acá es el CRITERIO, que es donde esto se equivoca. Las dos formas de
   equivocarse, las dos medidas el mismo día:

     · mirar sólo la Carga Camión (CCN) y no el FSS posterior. La NP 98668 (Nexxo) tuvo CCN
       el 11/09 y FSS el 14/09: volvió al depósito, y el operario la veía —bien— ofrecida en
       Carga Camión mientras un conteo la daba por salida;
     · comparar la NP sin normalizar. La NP web viaja con espacio ("LK 0003") y la de ISIS con
       un ".0" que aparece y desaparece; comparar el texto crudo hace que NINGUNA NP web
       matchee contra su evento y que todas se cuenten como atrasadas. Ese error dio 24
       atrasados donde había 18.

   Por eso el criterio vive en el backend (`gv_ppp_atrasados`) y no en esta pantalla: el test
   verifica que el front lo PIDA y no lo recalcule.

   Chequea:
     1) que el submódulo lea la RPC y no arme el criterio por su cuenta;
     2) que se dibuje ARRIBA de "Programación de entregas";
     3) que las dos tablas compartan el render (una sola copia de día → tanda → NP);
     4) en vivo: agrupa por día, ordena **del más viejo al más nuevo** (v19.29, Luis: *"de los más
        antiguos a los más nuevos, de arriba para abajo"* — antes salía al revés), cuenta bien y
        marca hace cuántos días venció;
     5) en vivo: sin atrasados el módulo sigue estando y lo dice.
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
// utf8 y no latin1: acá se buscan textos con acentos ("Programación de entregas"), y leído
// como latin1 esos bytes no matchean nunca — el chequeo pasaría a ser un adorno.
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");

const fallas = [];

// 1) el criterio lo pone el backend
if (!src.includes("rpc/gv_ppp_atrasados")) fallas.push("el front no llama a la RPC gv_ppp_atrasados");
if (!src.includes("function patrNeed")) fallas.push("falta patrNeed (la carga del submódulo)");
if (!src.includes("function _patrHtml")) fallas.push("falta _patrHtml");

// 2) va arriba de la programación
const iPatr = src.indexOf("let h = _patrHtml();");
const iProg = src.indexOf('<div class="pn-h1">Programación de entregas</div>');
if (iPatr < 0) fallas.push("_pppArbolHtml no empieza por el submódulo de atrasados");
else if (iProg < 0 || iPatr > iProg) fallas.push("el submódulo no queda ARRIBA de «Programación de entregas»");

// 3) una sola copia del render día → tanda → NP
if (!src.includes("function _pgaCuerpoHtml")) fallas.push("falta _pgaCuerpoHtml (el render compartido)");
// sólo donde se GENERA la fila (el `.pga-nrow` del CSS no cuenta)
const cuerpos = (src.match(/<div class="pga-nrow">/g) || []).length;
if (cuerpos !== 1) fallas.push("el render de la fila de NP está duplicado (" + cuerpos + " copias): las dos tablas van a divergir");

// La banda «⏰ N atrasados» salió de ESTA vista (el árbol), donde ahora está el submódulo: tener
// las dos era mostrar dos números distintos de lo mismo, porque la banda no mira el FSS. Sigue
// viva en el TABLERO DE 6 DÍAS y en Resumen, que son otra pantalla — eso lo cubre
// `tests/ppp-atrasados.cjs` (v14.06) y no se tocó.
const iArbol = src.indexOf("function _pppArbolHtml");
const finArbol = src.indexOf("\nfunction ", iArbol + 10);
if (iArbol > 0 && finArbol > iArbol && src.slice(iArbol, finArbol).includes("pn-venc-band")) {
  fallas.push("la banda «⏰ N atrasados» volvió a la vista de árbol, al lado del submódulo: dos criterios para lo mismo");
}

if (fallas.length) {
  console.log("ppp-atrasados-modulo: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("ppp-atrasados-modulo: estático ✓ OK (sin Playwright para la parte en vivo)"); process.exit(0); }
}

(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ timezoneId: "America/Argentina/Buenos_Aires" });
  const p = await ctx.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  // Nada de red: lo que se prueba es el armado, no el fetch.
  await p.route("**/rest/v1/**", (r) => r.fulfill({ status: 200, headers: { "content-type": "application/json" }, body: "[]" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = {};
    const hoy = _pppHoyKey();                       // "YYYYMMDD"
    const dk = (n) => {                             // hace n días, en "YYYY-MM-DD"
      const d = _pppKeyDate(hoy); d.setDate(d.getDate() - n);
      return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    };
    const fila = (fecha, tanda, np, m3, estado) => ({
      fecha: fecha, tanda: tanda, np: np, np_num: null, cod: "123", razon_social: "Cliente " + np,
      localidad: "Soldati", zona: "Zona 1 - CABA Sur", zona_corta: "Zona 1", empresa: "LK",
      origen: "isis", m3: m3, estado: estado, estado_orden: 3, clave: np, pide_horario: false,
      horario_fecha: null, horario_franja: null, horario_origen: null, barrio: "Soldati", fecha_pedido: null
    });

    _pppSearch = "";
    _pgaOpenD = {}; _pgaOpenT = {}; _pgaOpenN = {};
    // ayer 2 NP en la misma tanda · hace 5 días 1 · hace 9 días 1 (ya es "grave")
    _patrRows = [
      fila(dk(1), "E30A", "98001", 0.5, "armado"),
      fila(dk(1), "E30A", "98002", 0.25, "armado"),
      fila(dk(5), "E20A", "LK 0003", 1.0, "facturado"),
      fila(dk(9), "E10A", "44605", 2.0, "pendiente")
    ];
    const h = _patrHtml();
    out.html = h;
    // ⚠ el regex pide el cierre de la clase: desde la v20.01 la fila del día trae adentro
    //   spans propios (`pga-sem`, `pga-m0`) y un `/class="pga-d/` suelto los contaba también.
    out.dias = (h.match(/class="pga-d[ "]/g) || []).length;
    // v19.29: el más viejo va ARRIBA. Lo que más tiempo lleva parado es lo primero que hay que ver.
    // v20.01: el día se escribe con `_pgaDiaHtml` (el nombre del día va en un span que el celular
    //   esconde), así que el texto plano de `_pgaDiaTxt` ya no aparece literal en el HTML.
    out.ordenAsc = h.indexOf(_pgaDiaHtml(dk(9).replace(/-/g, ""))) < h.indexOf(_pgaDiaHtml(dk(1).replace(/-/g, "")));
    out.dice4 = /<b>4<\/b> pedido/.test(h);
    out.dice3dias = /<b>3<\/b> día/.test(h);
    out.m3 = /<b>3,8<\/b> m³|<b>3,75<\/b> m³/.test(h);
    out.masViejo = /el más viejo hace <b>9<\/b> días/.test(h);
    out.chipAyer = /hace 1 día</.test(h);
    out.chipGrave = /patr-dias grave">hace 9 días/.test(h);
    out.noGraveAyer = !/patr-dias grave">hace 1 día/.test(h);

    // abrir un día muestra su tanda y sus NP, igual que la tabla de abajo
    _pgaOpenD[dk(1).replace(/-/g, "")] = true;
    const h2 = _patrHtml();
    out.abreTanda = /E30A/.test(h2);
    _pgaOpenT[dk(1).replace(/-/g, "") + "|E30A"] = true;
    const h3 = _patrHtml();
    out.abreNps = /98001/.test(h3) && /98002/.test(h3);

    // v18.82 — colapsable: colapsado se va la TABLA pero quedan los KPI, y la elección
    // se recuerda (si no, el refresco automático de la pantalla lo vuelve a abrir solo).
    try { localStorage.removeItem("vir_patr_colapsado"); } catch (_e) {}
    out.abrePorDefecto = !/class="patr col"/.test(_patrHtml());
    patrColapsar();
    const hc = _patrHtml();
    out.colapsaTabla = !/<table/.test(hc);
    out.colapsadoDejaKpi = /<b>4<\/b> pedido/.test(hc) && /el más viejo hace <b>9<\/b> días/.test(hc);
    out.recuerda = (function () { try { return localStorage.getItem("vir_patr_colapsado") === "1"; } catch (_e) { return false; } })();
    patrColapsar();
    out.vuelveAAbrir = /<table/.test(_patrHtml());

    // sin atrasados: el módulo no desaparece
    _patrRows = [];
    const h4 = _patrHtml();
    out.vacioDice = /Sin pedidos atrasados/.test(h4);
    out.vacioVerde = /class="patr ok"/.test(h4);

    // todavía leyendo
    _patrRows = null;
    out.cargando = /Leyendo…/.test(_patrHtml());
    return out;
  });

  const mal = [];
  const ok = (c, m) => { if (!c) mal.push(m); };

  ok(errs.length === 0, "errores de página: " + errs.join(" | "));
  ok(r.dias === 3, "debería armar 3 filas de día (una por fecha vencida) y armó " + r.dias);
  ok(r.ordenAsc, "los días no van del más VIEJO al más nuevo (v19.29, pedido de Luis)");
  ok(r.dice4, "el encabezado no cuenta los 4 pedidos");
  ok(r.dice3dias, "el encabezado no cuenta los 3 días");
  ok(r.m3, "el encabezado no suma los m³ (0,5+0,25+1+2 = 3,75)");
  ok(r.masViejo, "no dice hace cuánto es el más viejo");
  ok(r.chipAyer, "la fila del día no dice hace cuántos días venció");
  ok(r.chipGrave, "a los 9 días de atraso el chip no cambia de color");
  ok(r.noGraveAyer, "un solo día de atraso no debería pintarse como grave");
  ok(r.abreTanda, "abrir el día no muestra su tanda");
  ok(r.abreNps, "abrir la tanda no muestra sus NP");
  ok(r.abrePorDefecto, "la primera vez tiene que arrancar abierto");
  ok(r.colapsaTabla, "colapsado sigue mostrando la tabla");
  ok(r.colapsadoDejaKpi, "colapsado se lleva puestos los KPI: el resumen tiene que quedar a la vista");
  ok(r.recuerda, "no recuerda que quedó colapsado — el refresco automático lo volvería a abrir");
  ok(r.vuelveAAbrir, "volver a tocarlo no lo reabre");
  ok(r.vacioDice, "sin atrasados el módulo desaparece en vez de decir que no hay");
  ok(r.vacioVerde, "sin atrasados el módulo sigue en rojo");
  ok(r.cargando, "mientras carga no avisa");

  await b.close();

  if (mal.length) {
    console.log("ppp-atrasados-modulo: ✗ FAIL\n  - " + mal.join("\n  - "));
    process.exit(1);
  }
  console.log("ppp-atrasados-modulo: ✓ OK (submódulo arriba de Programación, criterio en el backend)");
})();
