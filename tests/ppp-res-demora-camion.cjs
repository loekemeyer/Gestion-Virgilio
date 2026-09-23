/* v21.72 — el Resumen de la PPP: MAYOR demora (no el promedio) y los camiones sin tope de m³.

   Las dos cosas que se piden el 23/09:
   (1) *"en lugar de figurar los días de demora promedio, el día de mayor demora"*, y que la
       celda se pueda TOCAR y muestre, POR CAMIÓN, ordenado por mayor demora, la demora real
       de cada uno;
   (2) *"no hay límite para arriba en la cantidad de metros cúbicos por camión, puedo tener
       hasta 40 m³"* → un día de UN cliente con 12,33 m³ es UN camión, no tres.

   Y de paso la otra mitad de (2), que es la regla v21.56 de Thomas: un camión = UN GRUPO de
   zonas. Con las rutas viejas (Z1..Z4 = un camión) un día con Z2+Z3+Z4+Z6 decía 2 y salen 3.

   Se corre la pantalla de verdad: se dibuja el Resumen, se clickea la celda y se lee el
   pop-up. Un candado de texto no sirve acá — lo que importa es el número que queda y el
   ORDEN de las filas. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.setViewportSize({ width: 1400, height: 900 });
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "load" });

  const r = await p.evaluate(() => {
    const ped = function (np, rs, loc, m3, recep, entrega, tanda) {
      return { np: np, tanda: tanda || "E01A", cod: rs, razon_social: rs, m3: m3,
               localidad: loc, zona: "", fecha: recep, fecha_entrega: entrega, programmed: true };
    };
    const prog = [
      // (A) 28/10 — UN cliente, 12,33 m³, todo en GBA Sur: un camión. Demoras 35 y 76.
      ped("98426", "Matiz SA", "Burzaco", 6.167, "13/08/2026", "28/10/2026", "D63A"),
      ped("LK 0190", "Matiz SA", "Burzaco", 6.160, "23/09/2026", "28/10/2026", "E85A"),
      // (B) 23/09 — cuatro zonas en TRES camiones: Z2 y Z3 van juntas porque cada una < 1 m³ (v21.95, Luis)
      ped("98618", "Simon Zeitune", "Balvanera",  0.103, "26/08/2026", "23/09/2026", "E12J"),
      ped("98664", "Guini Jorge",   "Flores",     0.100, "31/08/2026", "23/09/2026", "E12G"),
      ped("98626", "Iro Iro",       "Burzaco",    0.365, "28/08/2026", "23/09/2026", "E39A"),
      ped("98622", "Martinelli",    "Bella Vista",0.325, "27/08/2026", "23/09/2026", "E33A"),
      // (C) 29/09 — 45 m³ en un solo grupo (no entran en un camión) + un súper + un retira
      ped("99001", "Mayorista Gde", "Barracas",  45.0, "25/09/2026", "29/09/2026", "E90A"),
      ped("99002", "Coto C.I.C.S.A.", "Esteban Echeverria", 2.2, "27/09/2026", "29/09/2026", "E91A"),
      ped("99003", "Retiro Propio", "Retira",     0.4, "28/09/2026", "29/09/2026", "E92A"),
      // (D) 30/09 — Z3 llega a 1 m³ -> Z2 y Z3 van SOLAS; Z6 + Z7 juntas (v21.95) = 3 camiones
      ped("99004", "Cli Z2", "Balvanera",   0.30, "25/09/2026", "30/09/2026", "E93A"),
      ped("99005", "Cli Z3", "Flores",      1.20, "25/09/2026", "30/09/2026", "E94A"),
      ped("99006", "Cli Z6", "Bella Vista", 0.20, "25/09/2026", "30/09/2026", "E95A"),
      ped("99007", "Cli Z7", "Pilar",       0.20, "25/09/2026", "30/09/2026", "E96A")
    ];
    const host = document.createElement("div");
    host.style.cssText = "position:absolute;left:0;top:0;width:1360px;";
    host.innerHTML = pppResumenHtml(prog);
    document.body.appendChild(host);

    const ths = [...host.querySelectorAll(".ppp-restbl thead th")].map(function (t) { return t.textContent.trim(); });
    const iCam = ths.findIndex(function (t) { return /^Cam/.test(t); });
    const iDem = ths.length - 1;
    const filas = [...host.querySelectorAll(".ppp-restbl tbody tr")].filter(function (tr) { return !tr.classList.contains("totrow"); });
    const dias = {};
    filas.forEach(function (tr) {
      const f = tr.children[0].textContent.trim();
      dias[f] = { cam: tr.children[iCam].textContent.trim(), dem: tr.children[iDem].textContent.trim(),
                  camClick: !!tr.children[iCam].getAttribute("onclick"), demClick: !!tr.children[iDem].getAttribute("onclick") };
    });
    const totrow = host.querySelector(".ppp-restbl tr.totrow");
    const tot = { cam: totrow.children[totrow.children.length - 2].textContent.trim(),
                  dem: totrow.children[totrow.children.length - 1].textContent.trim() };

    // clickear la celda de demora del 23/09 y leer el pop-up
    let camsPop = null, demPop = null, headPop = "";
    const fila2309 = filas.find(function (tr) { return tr.children[0].textContent.trim() === "23/09"; });
    if (fila2309) {
      fila2309.children[iDem].click();
      const ov = document.getElementById("pppResPopOv");
      if (ov && ov.classList.contains("show")) {
        headPop = (ov.querySelector(".pppres-sum") || { textContent: "" }).textContent.replace(/\s+/g, " ").trim();
        camsPop = [...ov.querySelectorAll("tr.camh")].map(function (tr) {
          return { nombre: tr.children[0].textContent.replace(/\s+/g, " ").trim(),
                   dem: parseInt(tr.children[tr.children.length - 1].textContent, 10) };
        });
        demPop = [...ov.querySelectorAll(".pppres-tbl tbody tr")].map(function (tr) {
          return tr.classList.contains("camh") ? "CAM:" + tr.children[0].textContent.replace(/\s+/g, " ").trim()
                                               : tr.children[0].textContent.trim() + "=" + tr.children[tr.children.length - 1].textContent.trim();
        });
      }
    }
    // y la del 28/10, que es el caso que se reportó
    let pop2810 = null;
    const fila2810 = filas.find(function (tr) { return tr.children[0].textContent.trim() === "28/10"; });
    if (fila2810) {
      fila2810.children[iCam].click();
      const ov = document.getElementById("pppResPopOv");
      pop2810 = !ov ? [] : [...ov.querySelectorAll("tr.camh")].map(function (tr) { return tr.children[0].textContent.replace(/\s+/g, " ").trim(); });
    }
    const leg = (host.querySelector(".ppp-res-leg") || { textContent: "" }).textContent;
    return { ths: ths, dias: dias, tot: tot, camsPop: camsPop, demPop: demPop, headPop: headPop, pop2810: pop2810, leg: leg };
  });

  const d = r.dias || {};
  const fallas = [];
  const eq = function (q, got, want) { if (String(got) !== String(want)) fallas.push(q + ": " + got + " (esperado " + want + ")"); };

  // (1) la columna es la MAYOR demora, no el promedio
  if (!/Mayor/i.test(r.ths[r.ths.length - 1] || "")) fallas.push("el encabezado no dice 'Mayor demora': " + r.ths[r.ths.length - 1]);
  if (/promedio/i.test(r.leg || "")) fallas.push("la leyenda todavía habla de promedio");
  eq("28/10 demora (máx de 35 y 76)", d["28/10"] && d["28/10"].dem, "76");   // el promedio daría 55,5
  eq("23/09 demora (máx de 28,23,26,27)", d["23/09"] && d["23/09"].dem, "28");
  eq("TOTAL demora = la peor de todas", r.tot.dem, "76");

  // (2) camiones sin tope de m³, por grupo de zonas
  eq("28/10 camiones (1 cliente, 12,33 m³)", d["28/10"] && d["28/10"].cam, "1");
  eq("23/09 camiones (Z2+Z3 juntas · Z4 · Z6)", d["23/09"] && d["23/09"].cam, "3");
  eq("30/09 camiones (Z2 sola · Z3 >= 1 m3 sola · Z6+Z7)", d["30/09"] && d["30/09"].cam, "3");
  eq("29/09 camiones (45 m³ = 2 + súper, retira no cuenta)", d["29/09"] && d["29/09"].cam, "3");
  eq("TOTAL camiones", r.tot.cam, String(1 + 3 + 3 + 3));

  // (3) las dos celdas abren el pop-up
  if (!(d["23/09"] && d["23/09"].demClick && d["23/09"].camClick)) fallas.push("las celdas de Cam./Demora no son clickeables");

  // (4) el pop-up: por camión, ordenado por mayor demora, con la demora real de cada uno
  if (!r.camsPop || !r.camsPop.length) fallas.push("el pop-up no se abrió");
  else {
    const noms = r.camsPop.map(function (c) { return c.nombre; }).join(" | ");
    const dems = r.camsPop.map(function (c) { return c.dem; });
    if (r.camsPop.length !== 3) fallas.push("el pop-up trae " + r.camsPop.length + " camiones, no 3: " + noms);
    for (let i = 1; i < dems.length; i++) if (dems[i] > dems[i - 1]) fallas.push("los camiones NO están ordenados por mayor demora: " + dems.join(","));
    if (!/^\S* ?Capital Centro-Oeste ·/.test(noms)) fallas.push("el primer camión no es el de mayor demora: " + noms);
    if (dems[0] !== 28) fallas.push("la demora del primer camión no es la real (28): " + dems[0]);
    const pedRows = (r.demPop || []).filter(function (x) { return !/^CAM:/.test(x); });
    if (!pedRows.some(function (x) { return /=28$/.test(x); }) || !pedRows.some(function (x) { return /=23$/.test(x); }))
      fallas.push("faltan las demoras reales de cada NP: " + pedRows.join(" · "));
  }
  if (!r.pop2810 || r.pop2810.length !== 1 || !/GBA Sur/.test(r.pop2810[0] || ""))
    fallas.push("el 28/10 no muestra UN camión de GBA Sur: " + JSON.stringify(r.pop2810));

  if (errs.length) fallas.push("pageerrors: " + errs.join(" | "));
  const ok = fallas.length === 0;
  console.log("ppp-res-demora-camion:", JSON.stringify({ dias: r.dias, tot: r.tot, cams: r.camsPop, pop2810: r.pop2810 }));
  if (!ok) console.log("  ✗ " + fallas.join("\n  ✗ "));
  console.log(ok ? "· ✓ OK" : "· ✗ FALLÓ");
  await b.close();
  process.exit(ok ? 0 : 1);
})();
