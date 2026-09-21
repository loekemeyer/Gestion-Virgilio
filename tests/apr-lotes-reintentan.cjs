/* v20.82 — UNA LISTA VACIA NO SE GUARDA COMO RESPUESTA.

   Luis, dos veces: *"¿cómo carajo no tiene cuit? imposible"* y después *"volvio a no aparecer
   el cuit de silvano, por que?"* — sobre LK 4282, que tiene el CUIT cargado en el padrón y la
   RPC devolviéndolo.

   Los lotes de A Programar / Clientes nuevos (CUIT, monto, teléfono, primer contacto y el
   pipeline) sólo se piden cuando su estado es `null`. Guardar `{}` con la lista vacía apaga la
   carga para el resto de la sesión.

   ⚠ La v20.71 intentó arreglarlo mirando si ya había PEDIDOS, y NO alcanzó: la lista que
     importa es la de RETENIDOS, que arma `cuarMarcarPedidos` en OTRA llamada, después. Con los
     pedidos ya cargados y los motivos todavía en camino, la lista sale vacía igual — que es
     exactamente la secuencia que se reproduce acá.

   No hay nada que optimizar: con la lista vacía no se hace ninguna llamada de red, así que
   reintentar en el próximo render es gratis. Sale 1 si falla. */
const path = require("path");
let chromium; try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (e) { try { ({ chromium } = require("playwright")); }
  catch (e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const pg = await b.newPage();
  const errs = []; pg.on("pageerror", e => errs.push(String(e)));
  await pg.goto("file:///home/user/Gestion-Virgilio/index.html");
  await pg.waitForTimeout(900);
  const r = await pg.evaluate(async () => {
    const out = { pidio: 0 };
    window.aprRpc = async function (fn) {
      if (fn === "gv_cuarentena_cuit_lote") { out.pidio++;
        return [{ empresa: "lk", cod: "4282", cuit: "20363599932" }]; }
      return [];
    };
    // el pedido REAL: llega SIN los motivos de cuarentena (los trae otra llamada)
    const ped = { order_id: "1448", empresa: "lk", cod: "4282", razon_social: "Silvano Lucas Martin",
                  zona: "Zona 1", m3: 0.428, np_total: 3, bloques: [] };
    _apr.listo = true; _apr.pedidos = [ped]; _apr.pedidosTodos = [ped];
    _apr.pipe = {}; _apr.cliValor = {}; _apr.cliWpp = {}; _apr.cuarComN = {};
    _apr.cliCuit = null; _apr.cliCuitLoading = false; _apr.pipeDemo = false;
    _apr.pipeCfg = {}; _apr.pipeStale = false;

    // 1) se dibuja con los pedidos cargados pero SIN motivos: la lista de retenidos sale vacía
    pipeHtml();
    await new Promise(r => setTimeout(r, 60));
    out.trasRenderSinMotivos = JSON.stringify(_apr.cliCuit);

    // 2) llegan los motivos y el pedido aparece en el pipeline
    ped.cuarentena_motivos = ["cliente_nuevo"];
    ped.cuarentena_detalle = { nuevo_pedidos: 1 };
    pipeHtml();
    await new Promise(r => setTimeout(r, 120));
    out.vecesQuePidio = out.pidio;
    const h = pipeHtml();
    out.celda = (h.match(/<td class="pipe-td-cuit">(.*?)<\/td>/) || [])[1] || "";
    out.cuitEnPantalla = /20-36359993-2/.test(h);
    return out;
  });
  console.log(JSON.stringify(r, null, 1));
  console.log("pageerrors:", errs.length ? errs.slice(0, 2) : "none");
  await b.close();
  const ok = r.trasRenderSinMotivos === "null" && r.vecesQuePidio === 1 &&
             r.cuitEnPantalla && !errs.length;
  if (!ok) console.error("FALLA: con la lista de retenidos vacía se guardó una respuesta, " +
                         "y el dato no se vuelve a pedir en toda la sesión.");
  process.exit(ok ? 0 : 1);
})();
