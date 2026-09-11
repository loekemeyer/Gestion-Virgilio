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
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 400, height: 900 } });   // ancho de celular: es donde se rompia
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

    // --- (f) v15.82: VARIOS lugares de excedente no rompen el layout.
    // Luis, 11/09: con las 6 ubicaciones del 731 limpias, el texto grande se
    // desbordaba y el código se le encimaba. Va el PRIMERO grande y el resto abajo
    // en chico. Se mide con rectángulos reales, no mirando el HTML.
    _pk = { tanda: "E01F", legajo: "1", idx: 0, mode: "item", results: {},
            items: [{ art: "731", key: "731·EXC", esp: 3, isExc: true, exc: 33,
                      excUbic: "P13 · P04 · P03 · P25 · P16 · P08", sector: "P13",
                      emp: "CH", dual: null }] };
    pkRender();
    const big = document.querySelector("#tandaModal .pk-sector-big");
    const mas = document.querySelector("#tandaModal .pk-sector-mas");
    const cod2 = document.querySelector("#tandaModal .pk-cod-big");
    out.unSoloLugarGrande = !!big && big.textContent.trim() === "P13";
    out.elRestoAbajoEnChico = !!mas && mas.textContent.indexOf("P04") >= 0 && mas.textContent.indexOf("P08") >= 0;
    const rb = big.getBoundingClientRect(), rc = cod2.getBoundingClientRect();
    const row = document.querySelector("#tandaModal .pk-big-row").getBoundingClientRect();
    out.noSeEncimanUbicYCod = (rb.right <= rc.left + 1) || (rb.bottom <= rc.top + 1);
    out.noDesborda = rb.right <= row.right + 1 && document.documentElement.scrollWidth <= window.innerWidth + 1;

    // --- (g) v15.87: agrupar las góndolas seguidas (pedido de Luis: "limpiá el
    // formato, visualmente es horrible cuando lista varias góndolas"). Es la forma
    // que los operarios ya conocían — el aviso viejo decía "buscá en M13 a M15".
    out.fmtTresSeguidas = pkSectoresFmt("M13 · M14 · M15") === "M13 a M15";
    out.fmtDosSeguidas  = pkSectoresFmt("J13 · J14") === "J13 y J14";
    out.fmtOrdenaAntes  = pkSectoresFmt("F12 · F09 · F10 · F11") === "F09 a F12";
    out.fmtNoSeguidas   = pkSectoresFmt("A65 · P39") === "A65 · P39";
    out.fmtUnaSola      = pkSectoresFmt("L01") === "L01";
    out.fmtRackConSufijo = pkSectoresFmt("R01AD · R02AD · R03AD") === "R01AD a R03AD";
    out.fmtDosCorridas  = pkSectoresFmt("D18 · D19 · D20 · D01 · D02") === "D01 y D02 · D18 a D20";

    // y en el render real del 809E de Chef entra en UN renglón, sin encimarse
    _pk = { tanda: "E01F", legajo: "1", idx: 0, mode: "item", results: {},
            items: [{ art: "809E CH", key: "809E CH", esp: 4, sector: "M13 · M14 · M15", emp: "CH", dual: null }] };
    pkRender();
    const b3 = document.querySelector("#tandaModal .pk-sector-big");
    const c3 = document.querySelector("#tandaModal .pk-cod-big");
    out.gondolaAgrupadaEnPantalla = b3.textContent.trim() === "M13 a M15";
    const r3 = b3.getBoundingClientRect(), q3 = c3.getBoundingClientRect();
    out.gondolaNoSeEncima = (r3.right <= q3.left + 1) || (r3.bottom <= q3.top + 1);
    out.gondolaNoDesborda = document.documentElement.scrollWidth <= window.innerWidth + 1;
    return out;
  });
  const bad = Object.entries(r).filter(([, v]) => v !== true).map(([k]) => k);
  console.log("pk-ubic-empresa:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none");
  await b.close();
  if (bad.length || errs.length) { console.error("✗ FALLA:", bad.join(", ") || "pageerrors"); process.exit(1); }
  console.log("✓ OK");
})();
