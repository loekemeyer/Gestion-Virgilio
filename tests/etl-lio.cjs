/* Smoke de las etiquetas de lío (idea 5290, v6.89). Impresión AL CERRAR CADA LÍO
   (no al TAP), TODO detrás del switch `vir_etiqueta_lio` + SÓLO legajos de prueba 0/1.
   Verifica, sobre `_compAddLio` (el único punto de alta de líos) con `etlPost` stubeado:
   - switch APAGADO → agrega el lío pero NO encola nada (app = igual que hoy),
   - legajo real (104) → tampoco encola, aunque el switch esté prendido,
   - legajo 0 + on → agrega Y encola una etiqueta con np/cajas/items/razón/ZPL correctos,
   - secuencia monotónica: dos líos → client_id distintos (s1, s2) y lío 1/2,
   - _etlAbrev abrevia la razón social. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const out = {};
    out.fns = ["etlOn", "etlSetOn", "etlLoadGlobal", "etlToggleGlobal", "etlBuildLioRow", "etlEnqueueLio", "_compAddLio", "_etlAbrev", "_etlZpl"].every((n) => typeof window[n] === "function");
    const mkLio = () => ({ items: [{ cod: "502", qty: 3 }, { cod: "323E", qty: 2 }], cajas: 5, suelta: false });
    try { localStorage.removeItem("vir_etiqueta_lio"); } catch (_e) {}

    // corre _compAddLio con etlPost STUBEADO para capturar lo que se encolaría (sin red)
    function run(comp) {
      _comp = comp;                          // asignación BARE (setea el `let _comp` del script, como _pk)
      const n = comp.nps[0];
      window.__cap = [];
      const _p = window.etlPost; window.etlPost = function (row) { window.__cap.push(row); };
      _compAddLio(n, mkLio());
      window.etlPost = _p;
      return { n: n, cap: window.__cap };
    }

    // switch APAGADO → agrega el lío pero NO encola
    { const rr = run({ tanda: "C99Z", legajo: "0", nps: [{ np: "98001", rs: "X", liosArr: [] }] });
      out.offNoEnq = (rr.n.liosArr.length === 1 && rr.cap.length === 0); }

    etlSetOn(true);
    // SIN gate de legajo (v6.90 — switch global de la operadora): con el switch ON encola
    // para CUALQUIER legajo (ej. 104), no sólo 0/1.
    { const rr = run({ tanda: "C99Z", legajo: "104", nps: [{ np: "98001", rs: "X", liosArr: [] }] });
      out.anyLeg = (rr.n.liosArr.length === 1 && rr.cap.length === 1); }

    // legajo 0 + switch on → agrega Y encola UNA etiqueta correcta
    { const rr = run({ tanda: "C99Z", legajo: "0", nps: [{ np: "98001", rs: "DISTRIBUIDORA LA OSA S.R.L.", liosArr: [] }] });
      out.onEnq = (rr.n.liosArr.length === 1 && rr.cap.length === 1);
      const c = rr.cap[0];
      out.row = !!c && c.np === "98001" && c.cajas === 5 && Array.isArray(c.items) && c.items.length === 2 &&
        c.razon_social === "DISTRIBUIDORA LA OSA" && c.lio_idx === 1 && c.lio_total === 0 &&
        /502/.test(c.zpl) && /Lio 1\^FS/.test(c.zpl) && /TOTAL 5 cajas/.test(c.zpl) && /\^XA/.test(c.zpl) &&
        /\^PW800/.test(c.zpl) && /\^LL440/.test(c.zpl);   // etiqueta física 100×55mm @203dpi
      out.cid = /^etl_C99Z_s1_/.test(c.client_id); }

    // muchos ítems en un mismo lío → la fuente se achica pero TODOS los ítems entran (mismo PW/LL)
    { const manyItems = Array.from({ length: 12 }, (_, i) => ({ cod: "IT" + i, qty: i + 1 }));
      const row = etlBuildLioRow({ tanda: "C99Z", legajo: "0", _etlSeq: 0 }, { np: "98003", rs: "Z" }, { items: manyItems, cajas: 99 });
      const fsCount = (row.zpl.match(/\^FS/g) || []).length;
      out.manyItems = !!row && /\^PW800/.test(row.zpl) && /\^LL440/.test(row.zpl) && fsCount === (manyItems.length + 5); }

    // secuencia monotónica: dos líos seguidos → client_id distintos y lío 1/2
    { _comp = { tanda: "C99Z", legajo: "0", nps: [{ np: "98002", rs: "Y", liosArr: [] }] };
      const n = _comp.nps[0]; window.__cap = [];
      const _p = window.etlPost; window.etlPost = function (row) { window.__cap.push(row); };
      _compAddLio(n, mkLio()); _compAddLio(n, mkLio());
      window.etlPost = _p;
      out.seq = (window.__cap.length === 2 && window.__cap[0].client_id !== window.__cap[1].client_id && window.__cap[1].lio_idx === 2); }

    out.abrev = (_etlAbrev("Mundo Bazar S.A.") === "Mundo Bazar") &&
      (_etlAbrev("Comercial Del Plata S.R.L.") === "Comercial Del Plata") &&
      (_etlAbrev("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA").length <= 22);

    etlSetOn(false);
    return out;
  });
  await b.close();
  const ok = r.fns && r.offNoEnq && r.anyLeg && r.onEnq && r.row && r.cid && r.manyItems && r.seq && r.abrev && errs.length === 0;
  console.log("etl-lio:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none", "·", ok ? "✓ OK" : "✗ FALLÓ");
  process.exit(ok ? 0 : 1);
})();
