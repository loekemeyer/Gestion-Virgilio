/* Regresión v19.91 (problema 427) — la demanda de un código DUAL es de UNA empresa, y la otra
   mitad no la muestra.

   Thomas, 18/09, sobre el 437E CH que decía 15 cajas pedidas: *"437E por ejemplo, tenemos el
   código de LK y el código de CH (productos que se consideran DIFERENTES, en diferentes lugares
   físicamente del depósito)"*. Las 15 eran TODAS de LK.

   Dos mitades del mismo arreglo:
   · BACKEND — `vista_stock_procesada` keyea la demanda con `gv_cod_stock_dem(articulo, pedido)`,
     que le vuelve a pegar la empresa cuando el código es dual. Antes caía en una fila pelada
     ("437E") que la pantalla esconde, y las dos mitades quedaban en 0.
   · FRONT (esto) — `_demOf` / `_proyOf` / `_demSPOf` hacían fallback al código base cuando no
     encontraban la clave exacta, así que la cifra de la fila pelada se mostraba en LAS DOS
     mitades. El fallback se conserva para los códigos comunes (un saldo con sufijo contra un
     mapa sin él) y se corta SÓLO cuando el código trae empresa.

   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const f = [];
    if (typeof _stkLookupEmp !== "function") { f.push("no existe _stkLookupEmp"); return { f }; }
    if (typeof _stkTieneSufijoEmp !== "function") { f.push("no existe _stkTieneSufijoEmp"); return { f }; }

    // 1) el que detecta la empresa pegada al código
    [["437E LK", true], ["437E CH", true], ["809E LOKE", true], ["437E", false], ["505", false], ["", false]]
      .forEach(([c, esp]) => { if (_stkTieneSufijoEmp(c) !== esp) f.push("_stkTieneSufijoEmp('" + c + "') != " + esp); });

    // 2) el caso de Thomas: la demanda está en LK y la fila de CH NO la puede mostrar
    const dem = { "437E LK": 15 };
    if (_stkLookupEmp(dem, "437E LK") !== 15) f.push("la mitad LK no ve sus 15 cajas");
    if (_stkLookupEmp(dem, "437E CH") !== 0)  f.push("la mitad CH ve las 15 cajas de LK (el bug de 427)");

    // 3) y si la cifra quedara en la fila PELADA (demanda sin empresa resuelta), tampoco se reparte
    const pelada = { "437E": 15 };
    if (_stkLookupEmp(pelada, "437E LK") !== 0) f.push("la mitad LK se cae a la fila pelada");
    if (_stkLookupEmp(pelada, "437E CH") !== 0) f.push("la mitad CH se cae a la fila pelada");
    if (_stkLookupEmp(pelada, "437E") !== 15)   f.push("la fila pelada dejo de ver lo suyo");

    // 4) NO-REGRESION: para un código común el fallback al base sigue vivo
    const comun = { "505": 630 };
    if (_stkLookupEmp(comun, "505") !== 630) f.push("un codigo comun dejo de encontrar su demanda");
    if (_stkLookupEmp(comun, "0505") !== 630) f.push("se perdio la normalizacion de ceros");
    // un saldo con sufijo de un codigo que NO es dual igual tiene que encontrar el base…
    // (no se puede saber si es dual desde el front, asi que el corte es el sufijo: es lo mismo
    //  que hacia la v8.88 para el caso comun sin sufijo)
    if (_stkLookupEmp({}, "505") !== 0) f.push("un mapa vacio deberia dar 0");
    if (_stkLookupEmp(null, "505") !== 0) f.push("un mapa nulo deberia dar 0");
    return { f };
  });
  await b.close();
  if (errs.length) { console.error("pageerror: " + errs.join(" | ")); process.exit(1); }
  if (r.f.length) { console.error("FALLA stk-dual-demanda-empresa:\n - " + r.f.join("\n - ")); process.exit(1); }
  console.log("OK stk-dual-demanda-empresa: la demanda de un dual no se duplica entre LK y CH");
})();
