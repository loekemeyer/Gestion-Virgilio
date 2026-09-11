/* Regresión v15.81 — "¿quién me compró este mes?" en el detalle de Abastecimiento.

   Pedido del dueño (2026-09-11): *"desde stock y compras, poder tocar en 1 mes y ver quién
   me compró (solo los primeros 5 clientes de cada mes y un sexto con Resto)"* · *"3 cajas"*
   → la unidad es CAJAS.

   El backend (vista `gv_venta_mensual_cliente`) ya está chequeado contra
   `vista_venta_mensual`: 845 pares (cod, mes) en las dos y 0 diferencias de suma. Acá se
   testea la parte del FRONT, que es pura: el corte a 5 + "Resto", el orden, los %, el total
   y el aviso cuando el detalle no cuadra con la columna Vend.

   Cubre:
   - con 8 clientes: se listan los 5 más grandes, en orden desc, y el 6º renglón es
     "Resto (3 clientes)" con la suma de los 3 que quedaron;
   - con 5 o menos: NO aparece el renglón Resto;
   - el TOTAL es la suma de todos y los % cierran contra ese total;
   - las NP del Resto se suman;
   - si el detalle por cliente NO cuadra con el total del mes, se avisa (no se esconde);
   - un mes sin detalle no rompe: muestra el cartel y ya.
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
    const txt = (html) => { const d = document.createElement("div"); d.innerHTML = html; return d; };

    // 8 clientes en 2026-08: 40+25+20+15+10 = 110 en el top 5 · 6+3+1 = 10 en el Resto · total 120
    const a = { cliMes: { "2026-08": [
      { cod: "4150", rs: "Primer Precio S.A.",  cajas: 40, nps: 4 },
      { cod: "2527", rs: "The Runner Succes",   cajas: 25, nps: 3 },
      { cod: "2523", rs: "Peluncha S.A.",       cajas: 20, nps: 2 },
      { cod: "2529", rs: "Ferreyra Gonzalo",    cajas: 15, nps: 2 },
      { cod: "2385", rs: "Kindsvater Eduardo",  cajas: 10, nps: 1 },
      { cod: "2530", rs: "Danjor Comercial",    cajas:  6, nps: 1 },
      { cod: "637",  rs: "El Nuevo Emporio",    cajas:  3, nps: 1 },
      { cod: "4170", rs: "Ichariba Chode",      cajas:  1, nps: 1 }
    ],
    // 3 clientes: sin renglón Resto
    "2026-07": [
      { cod: "4150", rs: "Primer Precio S.A.", cajas: 7, nps: 1 },
      { cod: "2527", rs: "The Runner Succes",  cajas: 2, nps: 1 },
      { cod: "2523", rs: "Peluncha S.A.",      cajas: 1, nps: 1 }
    ] } };

    // ---- 1) 8 clientes → 5 filas + Resto + TOTAL ----
    const d = txt(abastClientesHtml(a, "2026-08", 120));
    const filas = [...d.querySelectorAll("tbody tr")];
    out.seisRenglones = filas.length === 7;                       // 5 top + Resto + TOTAL
    const nombres = filas.slice(0, 5).map(tr => tr.querySelector("td").textContent.trim());
    out.ordenDesc = nombres[0].startsWith("1. Primer Precio") && nombres[4].startsWith("5. Kindsvater");
    out.topEsElTop = !d.textContent.includes("Danjor");           // el 6º ya es Resto, no se lista

    const resto = filas[5].querySelectorAll("td");
    out.restoRotulo = resto[0].textContent.trim() === "Resto (3 clientes)";
    out.restoCajas = resto[1].textContent.trim() === "10";
    out.restoNps = resto[3].textContent.trim() === "3";           // 1+1+1

    const tot = filas[6].querySelectorAll("td");
    out.totalOk = tot[1].textContent.trim() === "120" && tot[2].textContent.trim() === "100%";
    out.pctOk = filas[0].querySelectorAll("td")[2].textContent.trim() === "33.3%";   // 40/120
    out.cabecera = /8 clientes/.test(d.textContent) && /120 cajas/.test(d.textContent);
    out.sinAviso = !/⚠/.test(d.textContent);                     // cuadra con Vend. → sin aviso

    // ---- 2) 3 clientes → sin renglón Resto ----
    const d2 = txt(abastClientesHtml(a, "2026-07", 10));
    const filas2 = [...d2.querySelectorAll("tbody tr")];
    out.sinResto = filas2.length === 4 && !/Resto/.test(d2.textContent);   // 3 + TOTAL
    out.total2 = filas2[3].querySelectorAll("td")[1].textContent.trim() === "10";

    // ---- 3) si NO cuadra con la columna Vend., se avisa ----
    const d3 = txt(abastClientesHtml(a, "2026-07", 99));
    out.avisaDescuadre = /⚠/.test(d3.textContent) && /99/.test(d3.textContent);

    // ---- 4) mes sin detalle: no rompe ----
    const d4 = txt(abastClientesHtml(a, "2026-06", 0));
    out.mesVacio = /Sin detalle de clientes/.test(d4.textContent);
    out.mesVacioSinTabla = d4.querySelectorAll("tbody tr").length === 0;

    // ---- 5) el toggle del mes es idempotente y lo limpia abastToggle ----
    // ⚠ `_abast` se declara con `let` en el scope global léxico: NO está en window, así que
    // hay que asignarle al identificador, no a window._abast (eso crea otra variable).
    _abast = { openMes: null, rows: [], openCod: null };
    const _r = window.abastRender; window.abastRender = function () {};
    abastToggleMes("2026-08"); out.abre = _abast.openMes === "2026-08";
    abastToggleMes("2026-08"); out.cierra = _abast.openMes === null;
    window.abastRender = _r;

    return out;
  });

  await b.close();
  const fails = Object.keys(r).filter(k => !r[k]);
  if (errs.length) { console.error("abast-clientes: errores de página:", errs); process.exit(1); }
  if (fails.length) { console.error("abast-clientes FALLÓ:", fails, r); process.exit(1); }
  console.log("abast-clientes OK —", Object.keys(r).length, "chequeos");
})();
