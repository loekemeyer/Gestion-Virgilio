/* Regresión v7.39 — "picking difiere de la mesa" NO infla góndola fantasma.
   La regla "de menos + no hay en góndola" ahora sólo COMPENSA una góndola que el picking dejó
   NEGATIVA (lee el saldo vivo y devuelve, a lo sumo, lo justo para llegar a 0). Antes devolvía
   `qty` SIEMPRE y, cuando el picking ya había descontado bien, creaba stock fantasma (caso real
   535/D05B: góndola en 0 y tres NPD "de menos" la subieron a 4).

   Chequea:
   - Góndola en 0 (faltante real ya registrado): NO se toca el stock (sin fantasma).
   - Góndola en -5 (picking marcó de más): devuelve min(qty, 5) para llevarla a 0.
   - El evento NPD (aviso al picking) se emite SIEMPRE, con formato correcto.
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
    const wait = function (ms) { return new Promise(function (res) { setTimeout(res, ms); }); };
    window.alert = function () {};
    window._compRenderSep = function () {};
    window.trySendOneReport = function () { return Promise.resolve({ ok: false }); };
    let npd = null; window.enqueueReport = function (pl) { if (pl && pl.opcion === "NPD") npd = pl; };
    let moved = null; window.stockMove = function (rows) { moved = rows; return Promise.resolve(); };
    window.esOperadorPrueba = function () { return false; };

    function setup() {
      _comp = { legajo: "8", tanda: "D05B", sepDif: { npIdx: 0, ci: 0 },
        nps: [{ np: "98140", codes: [{ cod: "535", sale: 2 }] }] };
      const inp = document.createElement("input"); inp.id = "csep-difreal"; inp.value = "0"; // real=0 → qty = sale-0 = 2
      const old = document.getElementById("csep-difreal"); if (old) old.remove();
      document.body.appendChild(inp);
    }

    // ---- CASO 1: góndola en 0 (faltante real). NO debe tocar el stock. ----
    window._stkGondolaSaldoVivo = async function () { return 0; };
    setup(); moved = null; npd = null;
    _compDifResolve("menos", "no");
    await wait(40);
    out.caso0_sinStock = moved === null;
    out.caso0_npd = !!npd && npd.texto === "98140|535|menos|no|2|2|D05B";

    // ---- CASO 2: góndola en -5 (picking marcó de más). Devuelve min(qty=2, 5) = 2. ----
    window._stkGondolaSaldoVivo = async function () { return -5; };
    setup(); moved = null; npd = null;
    _compDifResolve("menos", "no");
    await wait(40);
    out.caso_neg_stock = !!moved && moved[0] && moved[0].deposito === "terminado" && moved[0].delta === 2 && moved[0].ref === "picking_difiere";
    out.caso_neg_npd = !!npd;

    // ---- CASO 3: góndola en -1, qty=2 → clamp a 1 (sólo hasta 0, no por debajo) ----
    window._stkGondolaSaldoVivo = async function () { return -1; };
    setup(); moved = null;
    _compDifResolve("menos", "no");
    await wait(40);
    out.caso_clamp = !!moved && moved[0] && moved[0].delta === 1;

    // ---- CASO 4: sin dato de saldo (fetch falló → null) → NO toca el stock ----
    window._stkGondolaSaldoVivo = async function () { return null; };
    setup(); moved = null;
    _compDifResolve("menos", "no");
    await wait(40);
    out.caso_null_sinStock = moved === null;
    return out;
  });
  const pass = r.caso0_sinStock && r.caso0_npd && r.caso_neg_stock && r.caso_neg_npd &&
    r.caso_clamp && r.caso_null_sinStock && errs.length === 0;
  console.log("comp-dif-nofantasma:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
