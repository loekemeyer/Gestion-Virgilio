/* Regresión v22.44 — el envoltorio de `fetch` de supabase-config.js NO tiene que "completar"
   una request que YA trae un header `Range`. Ese es el caso de `supaFetchAll` (index.html), que
   pagina ÉL por Range. Si el envoltorio igual completa, re-pide con `offset=` reusando el `init`
   —o sea con ESE mismo `Range` puesto— y `offset=1000 + Range: 0-999` da HTTP 416 → 0 filas: los
   dos paginadores chocan. Se vio como el badge de «Completar Pedido» mostrando 404 (las NP de
   Facturacion_NP fuera del corte de 1.000 se contaban como "sin facturar").

   Se prueba stubbeando `fetch`: una respuesta de 1.000 filas (llega al tope) con y sin `Range`.
   CON Range: el envoltorio devuelve tal cual, SIN pedir una segunda página (offset).
   SIN Range: el envoltorio SÍ pide la segunda página (comportamiento normal de completado). */
"use strict";
const fs = require("fs"), path = require("path");

function mkResp(rows, contentRange) {
  return {
    ok: true, status: 200, statusText: "OK",
    headers: { get: function (k) { return String(k).toLowerCase() === "content-range" ? contentRange : null; } },
    json: function () { return Promise.resolve(rows); },
    text: function () { return Promise.resolve(JSON.stringify(rows)); }
  };
}

async function run() {
  const g = {};
  const calls = [];
  const page1 = []; for (let i = 0; i < 1000; i++) page1.push({ np: "N" + i });
  const page2 = [{ np: "N1000" }, { np: "N1001" }];
  // fetch base: 1ra llamada -> 1000 filas /*, 2da (offset) -> 2 filas
  g.fetch = function (input, init) {
    const url = typeof input === "string" ? input : (input && input.url) || "";
    calls.push({ url: url, headers: (init && init.headers) || (input && input.headers) || null });
    const off = /[?&]offset=(\d+)/.exec(url);
    if (off) return Promise.resolve(mkResp(page2, "1000-1001/*"));
    return Promise.resolve(mkResp(page1, "0-999/*"));
  };

  // cargar el envoltorio sobre este `g` (el IIFE usa `self`/globalThis; lo forzamos con vm)
  const src = fs.readFileSync(path.join(__dirname, "..", "supabase-config.js"), "utf8");
  // El archivo cierra con `})(typeof self...)`. Lo re-invocamos sobre nuestro `g`.
  const cuerpo = src.replace(/\}\)\(typeof self[^;]*\);?\s*$/, "})(g);");
  new Function("g", cuerpo)(g);

  const REST = "https://x.supabase.co/rest/v1/Facturacion_NP?select=np&order=np.asc";
  let fail = 0;

  // (1) CON Range: no debe completar → una sola llamada, 1000 filas
  calls.length = 0;
  const rCon = await g.fetch(REST, { headers: { Range: "0-999", "Range-Unit": "items" } });
  const filasCon = await rCon.json();
  const offsetConRange = calls.some(function (c) { return /[?&]offset=/.test(c.url); });
  if (offsetConRange) { console.error("FAIL: con Range el envoltorio pidió offset (chocan los dos paginadores)"); fail++; }
  if (filasCon.length !== 1000) { console.error("FAIL: con Range esperaba 1000 filas intactas, dio " + filasCon.length); fail++; }

  // (2) SIN Range: debe completar → pide offset, junta 1002 filas
  calls.length = 0;
  const rSin = await g.fetch(REST, {});
  const filasSin = await rSin.json();
  const offsetSinRange = calls.some(function (c) { return /[?&]offset=/.test(c.url); });
  if (!offsetSinRange) { console.error("FAIL: sin Range el envoltorio NO completó (debería pedir offset)"); fail++; }
  if (filasSin.length !== 1002) { console.error("FAIL: sin Range esperaba 1002 filas completadas, dio " + filasSin.length); fail++; }

  if (fail) { console.error("rest-tope-range: " + fail + " fallas"); process.exit(1); }
  console.log("rest-tope-range: OK — con Range no completa (1000), sin Range completa (1002).");
}
run().catch(function (e) { console.error("rest-tope-range: EXCEPCIÓN", e); process.exit(1); });
