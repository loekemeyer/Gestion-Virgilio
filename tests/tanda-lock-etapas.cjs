/* Regresión v18.65 — una tanda tomada no se puede volver a tomar hasta que se ANULE o PASE
   a la etapa siguiente. Pedido de Luis, 15/09.

   Lo que había antes, y por qué no alcanzaba:
     · el lock vencía a las 10 h (`tanda_reservar` borraba por tiempo), así que un picking
       abierto de ayer quedaba libre hoy sin que nadie lo hubiera cerrado;
     · y el TP lo BORRABA, así que una tanda ya pickeada se podía volver a abrir. De ahí los
       «EP fantasma»: 6 medidos en 120 días, dos todavía abiertos desde julio y agosto.
   Eso último es peligroso de verdad: `anular_picking_virgilio` pone en cero TODO el picking
   de la tanda sin filtrar por legajo, así que anular un EP fantasma de D30A borraría los 36
   movimientos del picking bueno, que además ya está armado.

   Chequea sobre el front (con las RPC mockeadas, sin tocar la base):
     1) que se llame a las RPC NUEVAS (gv_tanda_reservar / gv_tanda_completar /
        gv_tanda_lock_anular) y no a las viejas, que las sigue usando Producción;
     2) que al terminar (TP/TAP) se COMPLETE, no se borre;
     3) que anular sí borre (la tanda vuelve a estar libre);
     4) que el guard bloquee cuando la tiene otro Y cuando la fase ya terminó, con mensajes
        distintos — y que el de «ya terminada» diga cómo destrabarla;
     5) que siga fallando ABIERTO: sin red no bloquea a nadie.
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");

const fallas = [];

// ---- 1) estático: las RPC nuevas, y ninguna llamada a las viejas ----
for (const rpc of ["gv_tanda_reservar", "gv_tanda_completar", "gv_tanda_lock_anular"]) {
  if (!src.includes("rpc/" + rpc)) fallas.push("no se llama a rpc/" + rpc);
}
for (const vieja of ["rpc/tanda_reservar", "rpc/tanda_liberar"]) {
  if (src.includes(vieja)) {
    fallas.push("todavía se llama a " + vieja + " — ésa es la de Producción, que borra el " +
      "lock a las 10 h y rompe el invariante");
  }
}
if (!/function tandaLockAnular\(/.test(src)) fallas.push("falta la función tandaLockAnular");

if (fallas.length) {
  console.log("tanda-lock-etapas: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("tanda-lock-etapas: estático ✓ OK (sin Playwright para la parte en vivo)"); process.exit(0); }
}

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    const llamadas = [];
    let respuesta = null;
    const realFetch = window.fetch;
    window.fetch = function (url, opts) {
      const u = String(url);
      if (/\/rpc\/gv_tanda_/.test(u)) {
        let body = {}; try { body = JSON.parse(opts.body); } catch (_e) {}
        llamadas.push({ rpc: u.split("/rpc/")[1], fase: body.p_fase, tanda: body.p_tanda });
        return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(respuesta) });
      }
      return Promise.resolve({ ok: true, status: 200,
        headers: { get: () => "0-0/0" }, json: () => Promise.resolve([]) });
    };

    // ---- 2) terminar = COMPLETAR, no borrar ----
    llamadas.length = 0;
    await tandaLiberar("E01A", "picking", "99");
    out.terminarCompleta = llamadas.length === 1 && llamadas[0].rpc === "gv_tanda_completar";

    // ---- 3) anular = soltar de verdad ----
    llamadas.length = 0;
    await tandaLockAnular("E01A", "picking", "99");
    out.anularSuelta = llamadas.length === 1 && llamadas[0].rpc === "gv_tanda_lock_anular";

    // ---- 4) el guard ----
    const avisos = [];
    const realAlert = window.alert;
    window.alert = (m) => avisos.push(String(m));
    /* `send()` no toma argumentos: lee el legajo, la opción y la tanda de la pantalla.
       Hay que dejarle el estado puesto, y limpio el estado local del legajo para no chocar
       con el guard de «ya tenés un armado abierto», que corre ANTES que el del lock. */
    const tocar = async (opcion, tanda) => {
      try { localStorage.removeItem("prod_state_v2_supa::" + legajoDeHoy() + "::77"); } catch (_e) {}
      try { const st = getLegajoState("77"); st.picking = { active: false, value: "", ts_inicio: null };
            st.armado = { active: false, value: "", ts_inicio: null }; setLegajoState("77", st); } catch (_e) {}
      legajoInput.value = "77";
      textInput.value = tanda;
      selected = opcion;
      await send();
    };

    // (a) la tiene OTRO → bloquea y dice quién
    respuesta = { ok: false, motivo: "tomada", legajo: "277", nombre: "JC" };
    avisos.length = 0;
    await tocar("EP", "E25A");
    out.bloqueaSiLaTieneOtro = avisos.length === 1 && /ya la está pickeando/i.test(avisos[0]);
    out.diceQuienLaTiene = avisos.length === 1 && /JC/.test(avisos[0]) && /277/.test(avisos[0]);

    // (b) la fase YA terminó → bloquea con otro mensaje, y dice cómo destrabarla
    respuesta = { ok: false, motivo: "ya_completada", legajo: "8", nombre: "FO" };
    avisos.length = 0;
    await tocar("EP", "D71A");
    out.bloqueaSiYaTermino = avisos.length === 1 && /ya está PICKEADA/i.test(avisos[0]);
    out.diceComoDestrabarla = avisos.length === 1 && /Anular picking/i.test(avisos[0]);

    // (c) el armado ya terminado avisa del suyo, no del picking
    avisos.length = 0;
    await tocar("AP", "D71A");
    out.armadoDiceLoSuyo = avisos.length === 1 && /ya está ARMADA/i.test(avisos[0]) &&
                           /No la armo yo/i.test(avisos[0]);

    // (d) es MÍA → no molesta
    respuesta = { ok: true, motivo: "propia", legajo: "99" };
    avisos.length = 0;
    await tocar("EP", "E30A");
    /* No bloquea: sigue de largo y registra el evento. El aviso que sale es el de éxito,
       así que lo que se chequea es que NO haya salido un ⛔. */
    out.propiaNoBloquea = !avisos.some((m) => /⛔/.test(m));

    // ---- 5) falla ABIERTO: sin red no bloquea ----
    window.fetch = function () { return Promise.reject(new Error("sin red")); };
    avisos.length = 0;
    await tocar("EP", "E31A");
    out.sinRedNoBloquea = !avisos.some((m) => /⛔/.test(m));

    window.alert = realAlert;
    window.fetch = realFetch;
    return out;
  });
  const pass = Object.keys(r).every((k) => r[k]) && errs.length === 0;
  console.log("tanda-lock-etapas:", JSON.stringify(r), "· pageerrors:",
    errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
