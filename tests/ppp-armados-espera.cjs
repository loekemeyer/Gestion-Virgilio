/* «⏸ Armados en espera» (v19.29, pedido de Luis 2026-09-17).

   Pedido textual: *"agregá un «día» en programación que sea «Armados en espera», va a servir para
   intencionalmente mandar pedidos que se arman sin fecha de entrega definida. Asegurate que se
   pueda enviar desde pedidos atrasados y desde programación de entregas"*.

   Lo que hay que cuidar, que es donde esto se rompe sin que nadie lo note:

     · NO es una fecha. Lo parado no tiene fecha de entrega: por eso no consume cupo, no entra en
       ningún camión y no figura como atrasado. Lo único que existe es la fecha CENTINELA
       (9999-12-31) con la que el backend devuelve esas filas para que la tabla las agrupe como un
       día. Si el front la dibujara como una fecha ("Vie 31/12"), en la pantalla diría que esos
       pedidos salen dentro de 7973 años.
     · El árbol hay que PEDIRLO hasta el centinela. Hasta la v19.25 se pedía hasta hoy+120, y con
       ese rango el día de espera no vuelve nunca: el módulo se vería vacío y nadie sabría por qué.
     · Se entra desde el pop-up de días, que es el MISMO para las dos pantallas que pidió Luis
       (Programación de entregas y Pedidos atrasados comparten `_pgaCuerpoHtml`). Si el botón se
       moviera a una de las dos tablas, la otra se quedaría sin la función.

   Chequea:
     1) el front pide el árbol hasta el centinela y llama a la RPC `gv_ppp_tanda_espera`;
     2) el día centinela se dibuja con su nombre, no con una fecha;
     3) en vivo: el día de espera queda ÚLTIMO, con su chip y su clase;
     4) en vivo: el pop-up ofrece el destino cuando se mueve una TANDA, dice "ya está" si la tanda
        ya está parada, y no lo ofrece al reprogramar una NP suelta de A Programar (no hay tanda).
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");

const fallas = [];

// 1) las dos puntas del backend
if (!src.includes("gv_ppp_tanda_espera")) fallas.push("el front no llama a la RPC gv_ppp_tanda_espera");
if (!src.includes('const PGA_ESPERA_ISO = "9999-12-31"')) fallas.push("falta la constante PGA_ESPERA_ISO");
if (!src.includes("function pppTandaEspera")) fallas.push("falta pppTandaEspera");
if (!src.includes("function pppMovEsperaElegir")) fallas.push("falta pppMovEsperaElegir (el botón del pop-up)");
// el árbol se pide hasta el centinela: con hoy+120 el día de espera no vuelve nunca
if (!/const hasta = PGA_ESPERA_ISO;/.test(src)) fallas.push("pgaNeed no pide el árbol hasta el centinela: el día de espera no va a venir");
// el SQL vive en el repo, no sólo aplicado en la base
if (!fs.existsSync(path.join(__dirname, "..", "sql", "gv_ppp_armados_espera_v1929.sql"))) {
  fallas.push("falta sql/gv_ppp_armados_espera_v1929.sql (la definición tiene que estar en el repo)");
}

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

    // 2) el centinela tiene nombre, no fecha
    out.nombre = _pgaDiaTxt(PGA_ESPERA_KEY);
    out.noEsFecha = !/\d+\/\d+/.test(out.nombre);

    _pppSearch = "";
    _pgaOpenD = {}; _pgaOpenT = {}; _pgaOpenN = {};
    _pgaRows = [
      fila(dk(1), "E31A", "98010", 0.5, "pendiente"),
      fila(PGA_ESPERA_ISO, "E30A", "98001", 0.5, "armado"),
      fila(PGA_ESPERA_ISO, "E30A", "98002", 0.25, "armado")
    ];
    const dias = _pgaArbol();
    out.nDias = dias.length;
    out.ultimo = dias.length ? dias[dias.length - 1].key : "";
    out.esperaUltimo = out.ultimo === PGA_ESPERA_KEY;   // el estacionamiento va al final, no en el medio
    const h = _pgaCuerpoHtml(dias, {});
    out.diceNombre = h.indexOf(PGA_ESPERA_TXT) >= 0;
    out.chip = /class="pga-esp">sin fecha( de entrega)?</.test(h);
    out.clase = /class="pga-d[^"]* espera"/.test(h);
    out.noDiceHace = !/hace \d+ día/.test(h);   // no es un atraso: no lleva el chip de días

    // el día se abre y muestra su tanda, igual que cualquier otro
    _pgaOpenD[PGA_ESPERA_KEY] = true;
    const h2 = _pgaCuerpoHtml(_pgaArbol(), {});
    out.abreTanda = /E30A/.test(h2);
    out.tieneSalida = /pgaTandaMoverAbrir\(&#039;99991231\|E30A|pgaTandaMoverAbrir\('99991231\|E30A/.test(h2)
                      || h2.indexOf("Cambiar de día") >= 0;   // de ahí se sale poniéndole día

    // 4) el pop-up: destino disponible al mover una TANDA
    const cal = [{ dia: dk(1), habil: true, m3: 1, cupo: 6, tandas: 1, np: 2, muy_pronto: false }];
    pppMovOverlay("prueba");
    _pppMov = { tanda: "E30A", np: 2, m3: 0.75, dias: 21, cal: cal, cargando: false,
                actual: dk(1), actualTxt: "x", arbolFilas: [], empezada: true, desdeArbol: true };
    pppMovRender();
    const b1 = document.getElementById("pppMovBody").innerHTML;
    out.ofrece = /Mandar a «Armados en espera»/.test(b1) && /pppMovEsperaElegir\(\)/.test(b1);

    // ya parada: el botón lo dice y no se puede volver a apretar
    _pppMov.actual = PGA_ESPERA_ISO;
    pppMovRender();
    const b2 = document.getElementById("pppMovBody").innerHTML;
    out.yaEsta = /Ya está en Armados en espera/.test(b2) && /mv-esp-b disabled|mv-esp-b" disabled/.test(b2);

    // reprogramar una NP suelta de A Programar: todavía no hay tanda que parar
    _pppMov = { reprogNps: ["98001"], reprogLabel: "98001", np: 1, m3: 0.2, dias: 21, cal: cal,
                cargando: false, actual: "", actualTxt: "" };
    pppMovRender();
    out.noEnReprog = !/Armados en espera/.test(document.getElementById("pppMovBody").innerHTML);
    pppMovCerrar();

    // 4b) la fecha centinela tampoco se muestra como fecha en «Modificar pedidos»
    out.pmod = _pmodFecha(PGA_ESPERA_ISO, true);
    return out;
  });

  const mal = [];
  const ok = (c, m) => { if (!c) mal.push(m); };

  ok(errs.length === 0, "errores de página: " + errs.join(" | "));
  ok(r.nombre === "⏸ Armados en espera", "el día centinela no se llama «⏸ Armados en espera» (dice «" + r.nombre + "»)");
  ok(r.noEsFecha, "el día centinela se está dibujando como una fecha: «" + r.nombre + "»");
  ok(r.nDias === 2, "debería armar 2 días (uno real + el de espera) y armó " + r.nDias);
  ok(r.esperaUltimo, "el día de espera tiene que quedar ÚLTIMO y quedó «" + r.ultimo + "»");
  ok(r.diceNombre, "la tabla no muestra «⏸ Armados en espera»");
  ok(r.chip, "falta el chip «sin fecha de entrega»: es lo que explica por qué ese día no es un día");
  ok(r.clase, "la fila del día de espera no lleva la clase que la pinta distinto");
  ok(r.noDiceHace, "el día de espera se está marcando como atrasado");
  ok(r.abreTanda, "abrir el día de espera no muestra su tanda");
  ok(r.tieneSalida, "desde el día de espera no se puede volver a poner fecha");
  ok(r.ofrece, "el pop-up de días no ofrece «Armados en espera» al mover una tanda");
  ok(r.yaEsta, "una tanda ya parada no avisa que ya está ahí (o deja apretar de nuevo)");
  ok(r.noEnReprog, "el destino aparece al reprogramar una NP suelta, donde todavía no hay tanda");
  ok(r.pmod === "⏸ En espera", "«Modificar pedidos» muestra el centinela como fecha: «" + r.pmod + "»");

  await b.close();

  if (mal.length) {
    console.log("ppp-armados-espera: ✗ FAIL\n  - " + mal.join("\n  - "));
    process.exit(1);
  }
  console.log("ppp-armados-espera: ✓ OK (el día que no es un día, y se entra y se sale desde el mismo pop-up)");
})();
