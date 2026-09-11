/* Regresión v15.81 — la ubicación del excedente se limpia, y la empresa va aparte
   del código.

   Dos cosas que Luis vio en pantalla el 11/09, en la tanda E01F:

   1. La UBICACIÓN del excedente salía "P13 · P4 · CH · P3 · CH · P03 · P4 · P25 ·
      P3 · P16 · P8". Hasta la v15.43 el operario tipeaba libre, y en
      Movimientos_Stock.ubicacion quedaron 34 de 78 valores con el separador " · "
      ADENTRO y la empresa pegada ("P12 · CH", "P15 · LOKE"). Después el join los
      volvía a unir.
   2. El CÓDIGO salía "809E CH" de una: la convención vieja (empresa metida en el
      nombre), que encima parece otro código.

   Chequea:
   - pkUbicLimpia corta en el separador, normaliza (P4 → P04) y descarta lo que no
     tiene forma de sector (CH, LOKE, vacío).
   - La lista de ubicaciones del excedente queda sin duplicados: P3 y P03 son el
     mismo lugar y cuentan una vez.
   - El código se muestra PELADO y la empresa como etiqueta aparte, tanto en el
     bloque grande como en "próximas ubicaciones".
   - `rec` (lo que se usa para buscar equivalencias y para el evento) NO se toca.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};

    // --- (a) la limpieza, caso por caso (los valores son REALES de la base)
    out.cortaElSeparador = pkUbicLimpia("P12 · CH") === "P12";
    out.cortaLoke        = pkUbicLimpia("P15 · LOKE") === "P15";
    out.normalizaElCero  = pkUbicLimpia("P4") === "P04" && pkUbicLimpia("P3") === "P03";
    out.tiraLoQueNoEsLugar = pkUbicLimpia("CH") === "" && pkUbicLimpia("LK") === "" && pkUbicLimpia("") === "";
    out.dejaElRackConSufijo = pkUbicLimpia("R01AD") === "R01AD";

    // --- (b) la lista del 731, tal cual está en la base, queda sin duplicados
    const crudas = ["P13", "P4 · CH", "P3 · CH", "P4", "P8", "P3", "P25", "P03", "P16"];
    const limpias = crudas.map(pkUbicLimpia).filter(Boolean);
    const unicas = limpias.filter((x, i) => limpias.indexOf(x) === i).sort();
    out.sinDuplicados = unicas.length === 6;                       // P03 P04 P08 P13 P16 P25
    out.p3yP03SonUno  = unicas.filter(x => x === "P03").length === 1;
    out.sinCH         = unicas.indexOf("CH") < 0;
    out.listaFinal    = unicas.join(" · ") === "P03 · P04 · P08 · P13 · P16 · P25";

    // --- (c) el código se muestra pelado + etiqueta
    _pk = { tanda: "E01F", legajo: "1", idx: 0, mode: "item", results: {},
            items: [{ art: "809E CH", key: "809E CH", esp: 4, sector: "M13", emp: "CH", dual: null },
                    { art: "825", key: "825", esp: 1, sector: "L01", emp: "CH", dual: null }] };
    pkRender();
    const html = document.getElementById("tandaModal").innerHTML;
    out.codigoPelado   = html.indexOf(">809E<") >= 0;
    out.noMuestraPegado = html.indexOf("809E CH") < 0;
    out.empresaEtiqueta = html.indexOf("pk-cod-emp-ch") >= 0;

    // --- (d) en "próximas ubicaciones" también
    const nx = pkNextHtml();
    out.proximasPelado = nx.indexOf("809E CH") < 0;

    // --- (e) `rec` no se toca: la clave del paso sigue con el sufijo
    out.claveIntacta = _pk.items[0].key === "809E CH" && _pk.items[0].art === "809E CH";
    return out;
  });
  const bad = Object.entries(r).filter(([, v]) => v !== true).map(([k]) => k);
  console.log("pk-ubic-empresa:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none");
  await b.close();
  if (bad.length || errs.length) { console.error("✗ FALLA:", bad.join(", ") || "pageerrors"); process.exit(1); }
  console.log("✓ OK");
})();
