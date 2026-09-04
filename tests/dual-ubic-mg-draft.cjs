/* Regresión v6.12 — (A) Picking: ubicación por ORIGEN (Loeke NP>90000 vs Chef) para
   809E/437E/438E. (B) MG guarda el borrador en CADA cambio (se puede "Seguir Guardar a
   góndola" aunque no toquen "Cerrar"). Sale 1 si falla.

   ⚠ La planimetría se FIJA acá (window.GONDOLA), no se toma la de producción.
   Antes el test la dejaba libre y pasaba o fallaba según qué hubiera en Supabase en
   ese momento: en una máquina sin red a la base quedaba vacía y corría el camino
   viejo (la tabla PICK_UBIC_DUAL), y en CI se cargaba la real y corría el camino
   nuevo (stock partido por empresa, claves "438E LK"/"438E CH"). El test esperaba
   el viejo, así que fallaba SOLO en CI — y no por un bug, sino porque estaba mirando
   datos vivos. Ahora se prueban los DOS caminos, cada uno con su planimetría puesta
   a mano, y el resultado no depende de cómo esté hoy el depósito. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  // El test corre SIN RED a Supabase. Al cargar, index.html dispara varias cargas
  // solas (planimetría, equivalencias, …) y sus respuestas pisan lo que el test
  // fija: no alcanza con stubbear las funciones desde adentro, porque para cuando
  // el test corre los pedidos ya salieron y vuelven después.
  // Ese era el bug: el resultado dependía de qué datos hubiera en producción y de
  // cuánto tardaran en llegar. En una máquina sin acceso a la base pasaba, y en CI
  // —donde sí llegan— fallaba. Cortando todo en la puerta, el test mide la LÓGICA
  // y no el estado del depósito de hoy.
  await p.route("**/rest/v1/**", function (route) { return route.abort(); });
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.alert = function () {};
    window.pkFetchExcedente = async function () { return {}; };
    window.pkNotifySinPlanim = function () {};

    function mapOf(obj) { const m = new Map(); Object.keys(obj).forEach(function (k) { m.set(k, obj[k]); }); return m; }

    // walk picking: recorrer los pasos y juntar code -> {sector, orig}
    async function walk() {
      const acc = {};
      for (let guard = 0; guard < 30; guard++) {
        const cod = document.querySelector("#tandaModal .pk-cod-big");
        if (!cod) break;
        const sec = document.querySelector("#tandaModal .pk-sector-big");
        const orig = document.querySelector("#tandaModal .pk-orig");
        acc[cod.textContent.trim()] = { sector: sec ? sec.textContent.trim() : null, orig: orig ? orig.textContent.replace(/\s+/g, " ").trim() : null };
        const adelante = document.querySelector("#tandaModal .pk-navbtn:last-child");
        if (!adelante || adelante.disabled) break;
        pkNext();
        await new Promise(function (res) { setTimeout(res, 15); });
      }
      return acc;
    }

    // La carga remota de planimetría puede resolver en cualquier momento y pisar la
    // que fija el test. Se la desactiva de entrada.
    window.loadPlanimetriaRemote = async function () {};

    // ===== (A) Camino FALLBACK: sin planimetría por empresa, manda PICK_UBIC_DUAL =====
    window.GONDOLA = {};
    localStorage.clear();
    window.fetchMonitorSheet = async function () { return mapOf({ "L01": { pedidos: [{ np: "98500" }] } }); };
    window.fetchPickingBase = async function () { return mapOf({ "98500": [{ art: "809E", cajas: 3 }, { art: "437E", cajas: 2 }, { art: "438E", cajas: 4 }] }); };
    await showPickingList("L01", "55");
    await new Promise(function (res) { setTimeout(res, 60); });
    out.loeke = await walk();

    // ===== (A2) Mismo camino, tanda de CHEF (NP<=90000) =====
    window.GONDOLA = {};
    localStorage.clear();
    window.fetchMonitorSheet = async function () { return mapOf({ "C01": { pedidos: [{ np: "44500" }] } }); };
    window.fetchPickingBase = async function () { return mapOf({ "44500": [{ art: "809E", cajas: 3 }, { art: "437E", cajas: 2 }, { art: "438E", cajas: 4 }] }); };
    await showPickingList("C01", "56");
    await new Promise(function (res) { setTimeout(res, 60); });
    out.chef = await walk();

    // ===== (B) Camino NUEVO: la planimetría trae el código partido por empresa.
    // Ahí NO manda PICK_UBIC_DUAL: cada renglón sale con el sector de su empresa.
    window.GONDOLA = {
      "809E LK": ["J13", 1], "437E LK": ["F09", 2], "438E LK": ["F13", 3],
      "809E CH": ["M13", 4], "437E CH": ["L07", 5], "438E CH": ["L05", 6]
    };
    localStorage.clear();
    window.fetchMonitorSheet = async function () { return mapOf({ "L02": { pedidos: [{ np: "98500" }] } }); };
    window.fetchPickingBase = async function () { return mapOf({ "98500": [{ art: "809E", cajas: 3 }, { art: "437E", cajas: 2 }, { art: "438E", cajas: 4 }] }); };
    await showPickingList("L02", "57");
    await new Promise(function (res) { setTimeout(res, 60); });
    out.porEmpresa = await walk();

    // ===== (C) MG auto-guarda el borrador sin "Cerrar" =====
    window.GONDOLA = {};
    localStorage.clear();
    window.loadArtNombres = async function () { return {}; };
    window.stockFetchSaldos = async function () { return { "502": { cod: "502", desc: "X", a_guardar: 10, terminado: 0 } }; };
    /* v8.40/v10.08 — showMGModal ahora también espera la capacidad de góndola y las
       celdas (para ordenar por prioridad y decir dónde va cada código). Sin stub, esos
       dos fetch salen a la red, el try/catch los come y _mg queda en null: el modal
       mostraba "Error:" y mgSet no tenía items que tocar. */
    window.ocgFetchCapacidad = async function () { return { "502": 20 }; };
    window.ocgFetchCeldas = async function () { return { "502": ["A1"] }; };
    // v12.14 (idea 4926) — showMGModal ahora también pide demanda y cajas×MC (best-effort)
    window.ocgDemanda = async function () { return {}; };
    window.rkbFetchCxM = async function () { return { cxm: {} }; };
    showMGModal("77");
    await new Promise(function (res) { setTimeout(res, 60); });
    out.draftAntes = !!opDraftLoad("77");            // false: sin progreso todavía
    mgSet(0, 5);                                     // cargar 5 (dispara mgRender → auto-save)
    await new Promise(function (res) { setTimeout(res, 20); });
    const d = opDraftLoad("77");
    out.draftDespues = !!d;
    out.draftOp = d ? d.op : null;
    out.draftLabel = d ? d.label : null;
    out.draftCargar = (d && d.snap && d.snap.items && d.snap.items[0]) ? d.snap.items[0].cargar : null;
    return out;
  });

  const L = r.loeke || {}, C = r.chef || {}, E = r.porEmpresa || {};
  const okLoeke = L["809E"] && L["809E"].sector === "J13" && /LOEKE/.test(L["809E"].orig || "") &&
                  L["437E"] && L["437E"].sector === "F9" && /F9 a F12/.test(L["437E"].orig || "") &&
                  L["438E"] && L["438E"].sector === "F13";
  const okChef  = C["809E"] && C["809E"].sector === "M13" && /CHEF/.test(C["809E"].orig || "") &&
                  C["437E"] && C["437E"].sector === "L7" &&
                  C["438E"] && C["438E"].sector === "L5" && /L5 y L6/.test(C["438E"].orig || "");
  // Camino nuevo: el renglón viene partido por empresa y el sector sale de la
  // planimetría, no de PICK_UBIC_DUAL. Sin nota de origen: ya lo dice la clave.
  const okEmpresa = E["809E LK"] && E["809E LK"].sector === "J13" &&
                    E["437E LK"] && E["437E LK"].sector === "F09" &&
                    E["438E LK"] && E["438E LK"].sector === "F13" &&
                    !E["809E"] && !E["437E"];
  const okMg = r.draftAntes === false && r.draftDespues === true && r.draftOp === "MG" && r.draftCargar === 5;
  const pass = okLoeke && okChef && okEmpresa && okMg && errs.length === 0;

  console.log("dual-ubic-mg-draft:", JSON.stringify(r));
  console.log("  pageerrors:", errs.length ? errs.join("|") : "none");
  console.log("  A loeke:", okLoeke ? "✓" : "✗", "· A chef:", okChef ? "✓" : "✗",
              "· B por-empresa:", okEmpresa ? "✓" : "✗", "· C mg-draft:", okMg ? "✓" : "✗",
              "·", pass ? "OK" : "FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
