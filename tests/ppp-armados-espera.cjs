/* «⏸ Armados en espera» — v21.41 (Luis, 2026-09-23): *"No tiene que existir «Armados en espera»"*.

   Historia: se creó en la v19.29 (Luis: un «día» sin fecha para tandas armadas a propósito), en
   la v19.32 pasó a estar SIEMPRE en la tabla aunque vacío, en la v21.40 el botón del pop-up pasó a
   ser un casillero de la grilla, y en la v21.41 Luis lo sacó entero. Este test es el CANDADO
   INVERTIDO: si alguien vuelve a poner la fila vacía en la tabla o el destino en el pop-up de
   «Cambiar de día», se pone en rojo.

   Lo que se conserva a propósito (y el test lo exige): las funciones y la constante centinela
   siguen en el archivo sin puerta —como `gv_ppp_np_desarmar` en la v18.77—, y una tanda que el
   backend devuelva con la fecha centinela SE MUESTRA con su nombre, no como fecha: lo que existe
   no se esconde. El badge `armado_espera` de `gv_ppp_avisos` (v20.86) sigue vigilando la tabla
   `GV_PPP_Armados_Espera`.

   Chequea:
     1) estático: `_pgaConEspera` no tiene llamador; el pop-up no dibuja `.mv-d espera` ni el
        botón `.mv-esp-b` de espera; las funciones y la constante siguen;
     2) en vivo: sin nada parado, la tabla NO tiene el día de espera;
     3) en vivo: con una tanda parada devuelta por el backend, se muestra con su nombre;
     4) en vivo: el pop-up de «Cambiar de día» no ofrece el destino.
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");

const fallas = [];
if (/^\s*if \(!_pppSearch\) _pgaConEspera\(dias\);/m.test(src)) fallas.push("volvió la fila vacía del día de espera (_pgaConEspera con llamador)");
if (/class="mv-d espera/.test(src)) fallas.push("volvió el casillero «Armados en espera» en la grilla del pop-up");
if (/onclick="pppMovEsperaElegir\(\)"/.test(src)) fallas.push("volvió la puerta al destino «Armados en espera» en el pop-up");
if (!src.includes('const PGA_ESPERA_ISO = "9999-12-31"')) fallas.push("falta la constante PGA_ESPERA_ISO (el backend sigue devolviendo esa fecha para lo parado)");
if (!src.includes("function pppTandaEspera")) fallas.push("falta pppTandaEspera (queda sin puerta, no se borra)");
if (!/const hasta = PGA_ESPERA_ISO;/.test(src)) fallas.push("pgaNeed dejó de pedir el árbol hasta el centinela: una tanda parada vieja no se vería nunca");

if (fallas.length) {
  console.log("ppp-armados-espera: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("ppp-armados-espera: estático ✓ OK (sin Playwright para la parte en vivo)"); process.exit(0); }
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
    const hoy = _pppHoyKey();
    const dk = (n) => {
      const d = _pppKeyDate(hoy); d.setDate(d.getDate() + n);
      return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    };
    const fila = (fecha, tanda, np, m3, estado) => ({
      fecha: fecha, tanda: tanda, np: np, np_num: null, cod: "123", razon_social: "Cliente " + np,
      localidad: "Soldati", zona: "Zona 1 - CABA Sur", zona_corta: "Zona 1", empresa: "LK",
      origen: "isis", m3: m3, estado: estado, estado_orden: 3, clave: np, pide_horario: false,
      horario_fecha: null, horario_franja: null, horario_origen: null, barrio: "Soldati", fecha_pedido: null
    });
    _pppSearch = "";
    _pgaOpenD = {}; _pgaOpenT = {}; _pgaOpenN = {};

    // 2) sin nada parado: el día de espera NO está
    _pgaRows = [fila(dk(1), "E31A", "98010", 0.5, "pendiente")];
    const h1 = _pppArbolHtml([]);
    out.sinEspera = h1.indexOf("Armados en espera") < 0 && /pga-d/.test(h1);

    // 3) con una tanda parada devuelta por el backend: se muestra, con nombre y no como fecha
    _pgaRows = [
      fila(dk(1), "E31A", "98010", 0.5, "pendiente"),
      fila(PGA_ESPERA_ISO, "E30A", "98001", 0.5, "armado")
    ];
    const h2 = _pppArbolHtml([]);
    out.paradaSeVe = h2.indexOf(PGA_ESPERA_TXT) >= 0 && !/31\/12/.test(h2);

    // 4) el pop-up de «Cambiar de día» no ofrece el destino
    const cal = [{ dia: dk(1), habil: true, m3: 1, cupo: 6, tandas: 1, np: 2, muy_pronto: false }];
    pppMovOverlay("prueba");
    _pppMov = { tanda: "E30A", np: 2, m3: 0.75, dias: 21, cal: cal, cargando: false,
                actual: dk(1), actualTxt: "x", arbolFilas: [], empezada: true, desdeArbol: true };
    pppMovRender();
    const b1 = document.getElementById("pppMovBody").innerHTML;
    out.noOfrece = !/Armados en espera/.test(b1) && !/pppMovEsperaElegir/.test(b1) && /class="mv-d/.test(b1);
    pppMovCerrar();
    return out;
  });

  const mal = [];
  const ok = (c, m) => { if (!c) mal.push(m); };
  ok(errs.length === 0, "errores de página: " + errs.join(" | "));
  ok(r.sinEspera, "la tabla sigue dibujando el día «Armados en espera» sin nada parado");
  ok(r.paradaSeVe, "una tanda parada que devuelve el backend no se muestra (o se muestra como fecha)");
  ok(r.noOfrece, "el pop-up de «Cambiar de día» sigue ofreciendo el destino «Armados en espera»");

  await b.close();
  if (mal.length) { console.log("ppp-armados-espera: ✗ FAIL\n  - " + mal.join("\n  - ")); process.exit(1); }
  console.log("ppp-armados-espera: ✓ OK (v21.41: el día «Armados en espera» no existe más; lo parado viejo se sigue viendo)");
})().catch((e) => { console.log("ppp-armados-espera: ✗ ERROR " + (e && e.message ? e.message : e)); process.exit(1); });
