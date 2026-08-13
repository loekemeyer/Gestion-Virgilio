/* El "Op=SI" del Excel dejó de ser requisito para mostrar tandas (v10.28).
   Antes, una tanda sin ese "SI" no aparecía ni en la tele ni en el celular del
   operario — con 36 tandas reales quedando invisibles. Ahora entran todas y lo
   que acota la lista son los topes que YA existían (ventana de fechas y
   MAX_PLANNED_NO_ACT).
   Este test fija eso: si alguien repone un filtro por Op=SI, falla. */
const path = require("path");
const fs = require("fs");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}

const RAIZ = path.resolve(__dirname, "..");
const src = fs.readFileSync(path.join(RAIZ, "index.html"), "utf8");

(async () => {
  // (a) estático: no puede quedar NINGÚN filtro por opIsSi ni el marcador missingSi.
  //     Se ignoran los comentarios (las líneas que arrancan con // o *).
  // Se sacan primero los comentarios de bloque, si no las notas /* ... */ cuentan como código.
  const codigo = src.replace(/\/\*[\s\S]*?\*\//g, "");
  const lineas = codigo.split("\n");
  const filtros = lineas
    .map((l, i) => ({ n: i + 1, t: l.trim() }))
    .filter((x) => /opIsSi|missingSi|row-missing-si/.test(x.t))
    .filter((x) => !/^(\/\/|\*|\/\*)/.test(x.t))
    // el flag se sigue PARSEANDO (se guarda), eso está permitido; filtrar no.
    .filter((x) => !/opIsSi:\s*(!!v\.opIsSi|false)/.test(x.t))
    .filter((x) => !/entry\.opIsSi\s*=\s*true/.test(x.t));

  // (b) los topes de cantidad tienen que seguir estando
  const topeSinAct = /MAX_PLANNED_NO_ACT\s*=\s*(\d+)/.exec(src);
  const topeDias   = /TANDAS_LIST_VISIBLE_DAYS\s*=\s*(\d+)/.exec(src);

  // (c) dinámico: la lista del operario devuelve tandas SIN Op=SI
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const pageerrors = [];
  page.on("pageerror", (e) => pageerrors.push(String(e && e.message || e)));
  await page.route("**/*", (r) => r.request().url().startsWith("http")
    ? r.fulfill({ status: 200, contentType: "application/json", body: "[]" })
    : r.continue());
  await page.goto("file://" + path.join(RAIZ, "index.html"));
  await page.waitForFunction(() => typeof window.populateTandasList === "function");

  const dyn = await page.evaluate(async () => {
    // dos tandas: una CON "SI" y otra SIN. Las dos deben ofrecerse para picking.
    // OJO: son `let` de nivel script — NO cuelgan de window. Hay que asignarlas
    // por nombre pelado para pisar el binding léxico real.
    _pppOperatorCache = [
      { tanda: "AAA1", opIsSi: true,  fechaRaw: "2026-08-20", fechaDisplay: "20/08" },
      { tanda: "BBB2", opIsSi: false, fechaRaw: "2026-08-20", fechaDisplay: "20/08" },
    ];
    _pppOperatorTs = Date.now();
    _activityStatusCache = {
      pickingStarted: new Set(), pickingDone: new Set(), pickingDoneStrict: new Set(),
      armadoStarted: new Set(), armadoDone: new Set(), armadoDoneStrict: new Set(),
      pickingEnCursoBy: new Map(), armadoEnCursoBy: new Map(),
    };
    _activityStatusTs = Date.now();
    if (!document.getElementById("tandasList")) {
      const d = document.createElement("div"); d.id = "tandasList"; document.body.appendChild(d);
    }
    await window.populateTandasList("notStarted");
    const t = document.getElementById("tandasList").textContent;
    return { conSi: t.includes("AAA1"), sinSi: t.includes("BBB2") };
  });

  await browser.close();

  const ok = filtros.length === 0 && dyn.conSi && dyn.sinSi &&
             topeSinAct && Number(topeSinAct[1]) > 0 &&
             topeDias && Number(topeDias[1]) > 0 &&
             pageerrors.length === 0;

  console.log("sin-op-si:", JSON.stringify({
                filtrosQueQuedaron: filtros.map((f) => f.n + ": " + f.t.slice(0, 60)),
                listaOperario: dyn,
                MAX_PLANNED_NO_ACT: topeSinAct && topeSinAct[1],
                TANDAS_LIST_VISIBLE_DAYS: topeDias && topeDias[1],
              }),
              "· pageerrors:", pageerrors.length ? pageerrors.join(" | ") : "none",
              ok ? "· ✓ OK" : "· ✗ FALLÓ");
  process.exit(ok ? 0 : 1);
})();
