/* El SÚPER no se junta con clientes: el aviso dice si la tanda se armó MANUAL o AUTOMÁTICA,
   y la kangoo no cuenta como parte del camión. (v18.87, pedido de Luis 2026-09-16)

   Luis: *"Fijate que no pueda volver a pasar automáticamente y que si se rompe esa regla, que
   ese aviso mencione que la tanda se armó manual o automática."*

   La mitad de "que no pueda volver a pasar" vive en Supabase (`ppp_web_armar_tandas`: la tanda
   de un súper dejó de contar como tanda abierta) y se verifica con el centinela:

       select * from public.gv_ppp_super_mezclado;   -- vacía = todo bien

   Acá se prueba la otra mitad, la que se ve: el aviso. Dos cosas, las dos medidas sobre el caso
   real del 16/09 (camión E11):

     1) **la etiqueta MANUAL / AUTOMÁTICA**. Es la primera pregunta al ver la alerta, porque
        cambia qué hay que arreglar: si fue automática hay una puerta abierta en el armador, si
        fue a mano hay que hablar con la persona. El dato lo resuelve el backend
        (`gv_ppp_super_mezclado.camion_armado`) y el front sólo lo lee;
     2) **la kangoo no es el camión**. `E11A` (Extralimp, Luján) está marcada en
        `GV_Vehiculo_Propio` y comparte los tres primeros caracteres del código con `E11B`, la
        tanda del súper. Contarla hacía decir que la súper de Moreno viajaba con Luján — y el
        override de Thomas dice explícitamente lo contrario.

   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");

const fallas = [];
if (src.indexOf("function pppRefreshSuperOrigen") < 0) fallas.push("falta pppRefreshSuperOrigen (el origen lo resuelve el backend)");
if (src.indexOf("rest/v1/gv_ppp_super_mezclado") < 0) fallas.push("el front no lee la vista gv_ppp_super_mezclado: estaría recalculando el criterio");
if (src.indexOf("_pppVehPropio[tnd]") < 0) fallas.push("el aviso no saltea las tandas de vehículo propio (la kangoo contaría como camión)");
if (fallas.length) { console.log("ppp-super-mezclado: ✗ FAIL\n  - " + fallas.join("\n  - ")); process.exit(1); }

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("ppp-super-mezclado: estático ✓ OK (sin Playwright para la parte en vivo)"); process.exit(0); }
}

(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ timezoneId: "America/Argentina/Buenos_Aires" });
  const p = await ctx.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.fulfill({ status: 200, headers: { "content-type": "application/json" }, body: "[]" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = {};
    // El caso real del 16/09: camión E11 con Dorinka (súper, Chango Más) en E11B, Extralimp en
    // E11A (kangoo) y dos clientes comunes en E11C / E11D.
    _pppSupers = [{ empresa: "chef", cod: "2686", nombre: "Chango Mas" }];
    const fila = (np, tanda, cod, rs, emp) => ({
      np: np, tanda: tanda, cod: cod, cod_cliente: cod, razon_social: rs, empresa: emp,
      localidad: "Moreno", zona: "Zona 5 - GBA Oeste", fecha_entrega: "16/09/2026",
      programmed: true, _web: true, _err: []
    });
    const peds = [
      fila("chef 25", "E11B", "2686", "Dorinka S.R.L", "chef"),
      fila("98651",   "E11A", "4114", "Extralimp S.A.", "lk"),
      fila("lk 93",   "E11C", "1472", "Todo Bazar S.R.L.", "lk"),
      fila("lk 99",   "E11D", "4185", "Goldar Hector Maximiliano", "lk")
    ];

    // (a) sin la marca de vehículo propio y sin el origen: se comporta como antes
    _pppVehPropio = null; _pppSuperOrig = null;
    let e = _pppComputeErrors(peds.map(x => Object.assign({}, x)), null);
    out.detectaMezcla = (e.superMezcl || []).length === 1;
    out.sinMarcaCuentaKangoo = out.detectaMezcla && e.superMezcl[0].clientes.length === 3;
    out.sinOrigenNoInventa = out.detectaMezcla && !e.superMezcl[0].armado;
    out.sinOrigenRenderiza = /Súper mezclado/.test(pppErroresHtml(e));

    // (b) con la kangoo marcada: E11A sale del camión
    _pppVehPropio = { E11A: "kangoo" };
    e = _pppComputeErrors(peds.map(x => Object.assign({}, x)), null);
    out.kangooFuera = (e.superMezcl || []).length === 1 && e.superMezcl[0].clientes.length === 2 &&
                      e.superMezcl[0].clientes.every(x => x.tanda !== "E11A");

    // (c) con el origen del backend: el aviso dice AUTOMÁTICA y con qué detalle
    _pppSuperOrig = { "16/09/2026|E11": { armado: "AUTOMÁTICA", detalles: { "chef 25": "armado automatico 15/09 10:12" } } };
    e = _pppComputeErrors(peds.map(x => Object.assign({}, x)), null);
    const h = pppErroresHtml(e);
    out.diceArmado = /armada AUTOMÁTICA/.test(h);
    out.claseGrave = /ppp-arm warn/.test(h);
    out.diceDetalle = /armado automatico 15\/09 10:12/.test(h);

    // (d) manual: mismo aviso, otra etiqueta y sin el rojo de "hay una puerta abierta"
    _pppSuperOrig = { "16/09/2026|E11": { armado: "MANUAL", detalles: {} } };
    const h2 = pppErroresHtml(_pppComputeErrors(peds.map(x => Object.assign({}, x)), null));
    out.diceManual = /armada MANUAL/.test(h2) && !/armada AUTOMÁTICA/.test(h2);
    out.manualNoEsGrave = /ppp-arm ok/.test(h2);

    // (e) un camión sin súper no dispara nada
    const solos = peds.slice(2).map(x => Object.assign({}, x));
    out.sinSuperNoAvisa = ((_pppComputeErrors(solos, null).superMezcl) || []).length === 0;
    return out;
  });

  const mal = [];
  const ok = (c, m) => { if (!c) mal.push(m); };
  ok(errs.length === 0, "errores de página: " + errs.join(" | "));
  ok(r.detectaMezcla, "no detecta el camión que lleva súper y clientes juntos");
  ok(r.sinMarcaCuentaKangoo, "sin la marca de vehículo propio deberían contar los 3 clientes");
  ok(r.sinOrigenNoInventa, "sin dato del backend el aviso no debe inventar quién la armó");
  ok(r.sinOrigenRenderiza, "sin dato del backend el aviso tiene que salir igual");
  ok(r.kangooFuera, "la tanda en kangoo (GV_Vehiculo_Propio) sigue contando como parte del camión");
  ok(r.diceArmado, "el aviso no dice que la tanda se armó AUTOMÁTICA");
  ok(r.claseGrave, "una mezcla AUTOMÁTICA no se pinta como lo grave que es (hay una puerta abierta en el armador)");
  ok(r.diceDetalle, "el aviso no muestra el detalle de quién/cuándo");
  ok(r.diceManual, "el aviso no distingue MANUAL de AUTOMÁTICA");
  ok(r.manualNoEsGrave, "una mezcla MANUAL no debería pintarse igual que una automática");
  ok(r.sinSuperNoAvisa, "un camión sin súper dispara el aviso");

  await b.close();
  if (mal.length) { console.log("ppp-super-mezclado: ✗ FAIL\n  - " + mal.join("\n  - ")); process.exit(1); }
  console.log("ppp-super-mezclado: ✓ OK (dice manual/automática, y la kangoo no cuenta como camión)");
})();
