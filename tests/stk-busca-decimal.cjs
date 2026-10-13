/* Regresion v30.00 (Luis, 13/10/2026) — "como es que se guardo sin codigo?".

   El 13/10 09:09 el legajo 104 recibio 144 Kg de un fleje "13.6 x 0.8", NO lo encontro en
   la lista — se llama `N°19`, "13,6 x 0,8 · Fleje N° 19", con COMA — y lo dio de alta como
   insumo nuevo: el servidor lo numero TMP-0037 y los 144 Kg quedaron en un codigo que no
   existe para nadie.

   La causa es `stkMatchBusq`, que comparaba el texto tal cual: buscar "13.6" no encontraba
   "13,6". En los flejes la MEDIDA es el nombre y 39 de 48 tienen decimal (27 con coma, 12
   con punto), asi que el pozo estaba abierto para mas de la mitad.

   Mide las dos direcciones (punto->coma y coma->punto) y, sobre todo, que el arreglo SOLO
   AGREGUE matches: lo que no tiene nada que ver sigue sin matchear, y la busqueda por
   codigo con ceros (regla v16.23) no se movio. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const N19 = "13,6 x 0,8 · Fleje N° 19";      // el nombre real, con coma
    const P190 = "18.5 x 1.90";                   // el mismo caso al reves (el nombre con punto)
    return {
      // el caso que mordio: el operario escribe con PUNTO lo que esta escrito con COMA
      puntoEncuentraComa: stkMatchBusq("13.6", "N°19", N19, true),
      comaEncuentraComa:  stkMatchBusq("13,6", "N°19", N19, true),
      // y al reves: escribe con COMA lo que esta escrito con PUNTO
      comaEncuentraPunto: stkMatchBusq("18,5", "1060500", P190, true),
      puntoEncuentraPunto: stkMatchBusq("18.5", "1060500", P190, true),
      medidaCompleta: stkMatchBusq("13.6 x 0.8", "N°19", N19, true),
      // SOLO agrega: lo que no tiene nada que ver sigue afuera
      otroFlejeNo: !stkMatchBusq("77", "N°19", N19, true),
      textoAjenoNo: !stkMatchBusq("pelador", "N°19", N19, true),
      // y la busqueda por codigo no se movio: el prefijo matchea y lo ajeno no
      // (ojo: "58" NO tiene que encontrar al 058 — regla v21.09, derogo el prefijo con ceros)
      codPorPrefijo: stkMatchBusq("058", "058E", "Cuchillo", true),
      codAjenoNo: !stkMatchBusq("903", "058E", "Cuchillo", true)
    };
  });
  const malas = Object.keys(r).filter((k) => !r[k]);
  const pass = malas.length === 0 && errs.length === 0;
  console.log(pass ? "OK stk-busca-decimal" : "FALLA stk-busca-decimal");
  if (!pass) { console.log(JSON.stringify(r, null, 2)); if (errs.length) console.log("pageerror:", errs.join(" | ")); }
  await b.close(); process.exit(pass ? 0 : 1);
})();
