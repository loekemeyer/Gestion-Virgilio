/* v29.74 (Luis) — UNA tabla canónica de equivalencias: GP2.insumo_equivalencia.
   Una bolsa plástica que NO está ahí NO puede pasar en silencio: los kg salen de Virgilio, el
   espejo los baja igual y no quedan en poder de ningún inyector (se evaporan). Era el caso de 7
   de las 9 bolsas con el mapeo viejo (componente.codigo_virgilio: NV, NR, PP…); hoy sólo EBA.
   (a) bolsa CON equivalencia → avisa a GP2 con el código real de Virgilio
   (b) bolsa SIN equivalencia → ok:false y nombra el código (el front pregunta antes de grabar)
   (c) en RECIBIR (RI) no frena: una bolsa que no está en esa OC es un caso legítimo */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); } catch (_e) { ({ chromium } = require("playwright")); }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage(); const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {}, llamadas = [];
    window.insGp2Rpc = async (name, args) => { llamadas.push({ name, args }); return { ok: true, virgilio_despues: 200 }; };
    // el bundle de GP2 trae el código REAL de Virgilio (v29.74: sale de insumo_equivalencia)
    const mv = { kg_x_bolsa: 25, materiales: [{ codigo_virgilio: "NY VIRGEN", codigo: "2475", inyectores: [{ proveedor: "Kollplast", bolsas_a_enviar: 4 }] }] };
    const gp2EI = { modo: "EI", inyector: "Kollplast", mv: mv };
    const ny  = { cod: "NY Virgen", nombre: "NYLON VIRGEN", qty: 2, unidad: "Bolsas", categoria: "plastico" };
    const eba = { cod: "EBA", nombre: "EBA", qty: 1, unidad: "Bolsas", categoria: "plastico" };

    const a = await _insGp2Enviar(gp2EI, [ny], "104", "");
    out.a = a.ok === true && llamadas.length === 1 && llamadas[0].name === "enviar_material_virgilio" &&
            llamadas[0].args.p_cod_virgilio === "NY VIRGEN" && llamadas[0].args.p_bolsas === 2 &&
            llamadas[0].args.p_inyector === "Kollplast";

    llamadas.length = 0;
    const c = await _insGp2Enviar(gp2EI, [eba], "104", "");
    out.b = c.ok === false && /EBA/.test(c.msg) && llamadas.length === 0;

    llamadas.length = 0;
    const d = await _insGp2Enviar(gp2EI, [ny, eba], "104", "");
    out.b_mezcla = d.ok === false && /EBA/.test(d.msg) && llamadas.length === 0;   // no manda nada a medias

    llamadas.length = 0;
    const gp2RI = { modo: "RI", oc: { oc_id: 9, numero: 7, items: [{ cod_virgilio: "NY VIRGEN", pendiente_bolsas: 4 }] } };
    const e = await _insGp2Enviar(gp2RI, [eba], "104", "R-1");
    out.c = e.ok === true && llamadas.length === 0;
    return out;
  });
  await b.close();
  const malas = Object.keys(r).filter((k) => !r[k]);
  if (malas.length || errs.length) {
    console.log("✗ ins-bolsa-sin-equivalencia:", malas.join(", "), errs.join(" | "));
    process.exit(1);
  }
  console.log("✓ ins-bolsa-sin-equivalencia: con equivalencia avisa a GP2 con el cod real; sin equivalencia frena y lo nombra; en RI no frena");
})();
