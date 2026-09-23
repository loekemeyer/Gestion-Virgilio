/* v21.43 — el buscador de «Mover a góndola» (pantalla del operario, teclado numérico) filtra
   por PREFIJO del código, no por pedazo. Se corre la pantalla de verdad: el candado estático
   del otro test dice que la función NOMBRA al helper, no qué filas quedan.

   Lo que cambia para el operario: tipear "03" mostraba también el 103 y el 503E — una fila de
   más en esta pantalla es una caja guardada en la góndola equivocada. A cambio, el medio del
   código ya no encuentra: para el 513 se escribe "51" o "513", no "13". */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

const CODS = ["031", "034", "103", "503E", "505", "505I", "506", "513", "613", "809E CH"];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(({ CODS }) => {
    const out = {}, fallas = [];
    // la pantalla escribe en #mgBody; si no está en el DOM, la creamos (no se toca nada más)
    if (!document.getElementById("mgBody")) {
      const d = document.createElement("div"); d.id = "mgBody"; document.body.appendChild(d);
    }
    const items = CODS.map((c, i) => ({ cod: c, desc: "art " + c, disponible: 10, cargar: 0, exc: 0, ubic: "", cap: 20, stock: 1, prio: i }));

    // ⚠ `_mg` se declara con `let` a nivel de script: NO es window._mg, así que asignarlo por
    // ahí deja la variable real en null y mgRender se va por su primer return sin dibujar nada
    // (pasó al escribir este test: el body quedaba vacío y no había error). Se asigna con eval.
    const verCon = function (filtro) {
      eval("_mg = " + JSON.stringify({ items: items, filtro: filtro, legajo: "99" }));
      try { mgRender(); } catch (e) { fallas.push("mgRender(" + filtro + ") explotó: " + e.message); return []; }
      const html = document.getElementById("mgBody").innerHTML;
      // qué códigos quedaron dibujados (el código va en su propio chip)
      return CODS.filter((c) => html.indexOf(">" + c + "<") >= 0 || html.indexOf(c) >= 0 && html.indexOf("art " + c) >= 0);
    };

    out.tres = verCon("03");        // 031, 034 — nunca 103 ni 503E
    out.cincocero = verCon("50");   // los 5xx de dos dígitos… 505, 505I, 506, 503E
    out.trece = verCon("13");       // nada: ningún código EMPIEZA con 13
    out.completo = verCon("505");   // 505 y 505I

    if (out.tres.join() !== "031,034") fallas.push('"03" dio [' + out.tres + "], esperaba 031,034");
    if (out.cincocero.join() !== "503E,505,505I,506") fallas.push('"50" dio [' + out.cincocero + "], esperaba 503E,505,505I,506");
    if (out.trece.length) fallas.push('"13" dio [' + out.trece + "], esperaba vacío (ninguno empieza con 13)");
    if (out.completo.join() !== "505,505I") fallas.push('"505" dio [' + out.completo + "], esperaba 505,505I");
    return { out, fallas };
  }, { CODS });

  const ok = r.fallas.length === 0 && errs.length === 0;
  console.log("mg-buscar-prefijo:", JSON.stringify(r.out),
    (r.fallas.length ? " · FALLAS: " + r.fallas.join(" | ") : ""), "· pageerrors:", errs.length ? errs.join("|") : "none",
    "·", ok ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(ok ? 0 : 1);
})();
