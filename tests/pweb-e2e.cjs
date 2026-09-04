/* End-to-end de la idea 3717 con DATOS REALES de producción (traídos el 2026-09-04
   y congelados acá como fixture). Corre el código de verdad, de punta a punta, sin
   escribir nada en Supabase:

     pedido de la página → corte en NP → numeración → m³ → entra a la PPP
     → armar tandas → confirmar → lo que se guardaría
     → lo que vería el operario en el celular → el Excel para importar a ISIS

   Es el paso que no se puede hacer con la pantalla desde el sandbox (el proxy
   bloquea Supabase), y el que faltaba para no estar validando sólo por partes. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

// ---- datos REALES (v_pedidos_web_np de LK, 03/09) ----
const NPS = [
  { empresa:"lk", order_id:1342, np_idx:1, cod:"4109", razon_social:"Di Leo Rossi Echarri Pedro SH",
    fecha_recep:"2026-09-03", hora_recep:"16:03:54", direccion:"Bragado 5742 - Mataderos", localidad:"Mataderos", zona_expreso:"Mataderos", v:"21",
    lineas:15, cajas:84, enviado_a_compras:false, items:[
    {art:"027",cajas:1,uxb:24},{art:"220",cajas:2,uxb:12},{art:"224",cajas:1,uxb:12},{art:"438E",cajas:1,uxb:24},
    {art:"501",cajas:15,uxb:6},{art:"505",cajas:25,uxb:12},{art:"506",cajas:5,uxb:12},{art:"513",cajas:6,uxb:12},
    {art:"521",cajas:2,uxb:12},{art:"529E",cajas:12,uxb:12},{art:"544",cajas:1,uxb:12},{art:"586",cajas:5,uxb:12},
    {art:"587",cajas:2,uxb:12},{art:"811E",cajas:1,uxb:12},{art:"816E",cajas:5,uxb:12}] },
  { empresa:"lk", order_id:1341, np_idx:1, cod:"4188", razon_social:"Orfali Alfredo Luciano",
    fecha_recep:"2026-09-03", hora_recep:"15:46:51", direccion:"Juncal 2869 - Martinez", localidad:"Martinez", zona_expreso:"Martinez", v:"7",
    lineas:15, cajas:358, enviado_a_compras:false, items:[
    {art:"031",cajas:10,uxb:24},{art:"280",cajas:10,uxb:12},{art:"315",cajas:10,uxb:12},{art:"502",cajas:15,uxb:12},
    {art:"505",cajas:150,uxb:12},{art:"506",cajas:20,uxb:12},{art:"521",cajas:3,uxb:12},{art:"530",cajas:4,uxb:12},
    {art:"574E",cajas:25,uxb:12},{art:"580",cajas:15,uxb:12},{art:"586",cajas:50,uxb:12},{art:"598E",cajas:25,uxb:12},
    {art:"599E",cajas:3,uxb:12},{art:"811E",cajas:3,uxb:12},{art:"816E",cajas:15,uxb:12}] },
  { empresa:"lk", order_id:1340, np_idx:1, cod:"4210", razon_social:"Garbarino Franco Tomas",
    fecha_recep:"2026-09-03", hora_recep:"15:11:17", direccion:"Retira", localidad:null, v:"21",
    lineas:2, cajas:5, enviado_a_compras:false, items:[{art:"404E",cajas:4,uxb:4},{art:"984E",cajas:1,uxb:12}] }
];
// m³ reales de Volumen_Articulos
const VOL = [["027",0.0051],["031",0.0035],["220",0.0111],["224",0.0051],["280",0.007],["315",0.0068],
  ["404E",0.0065],["438E",0.0185],["501",0.0035],["502",0.0051],["505",0.0024],["506",0.0024],["513",0.0035],
  ["521",0.024],["529E",0.0023],["530",0.0024],["544",0.0134],["574E",0.003],["580",0.0024],["586",0.0035],
  ["587",0.0051],["598E",0.0033],["599E",0.0024],["811E",0.008],["816E",0.003],["984E",0.0072]]
  .map(([codigo,m3])=>({codigo,m3}));
// v12.77 — el m³ ya viene calculado del backend (v_pedidos_web_np lo expone), así que
// el mock tiene que traerlo igual que la vista real. Se computa acá desde los mismos
// m³ de Volumen_Articulos, para que los totales esperados no cambien.
const _VOLMAP = Object.fromEntries(VOL.map(v => [v.codigo, v.m3]));
NPS.forEach(n => {
  let m3 = 0, parcial = false;
  (n.items || []).forEach(i => {
    const v = _VOLMAP[i.art];
    if (v === undefined) { parcial = true; return; }
    m3 += (Number(i.cajas) || 0) * v;
  });
  n.m3 = Number(m3.toFixed(3));
  n.m3_parcial = parcial;
});
// zonas reales de Zonas_Barrios
const ZONAS = { mataderos:"Zona 3 - CABA Oeste", martinez:"Zona 6 - GBA Norte", retira:"Retira" };

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async ({ NPS, VOL, ZONAS }) => {
    const posts = [], volUrl = [], resync = [];
    window.sbAuth = { getAccessToken: async () => "tok" };
    window._pppZonaSupa = ZONAS;
    const json = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o) });
    window.fetch = async (url, opt) => {
      const u = String(url);
      if (opt && opt.method === "POST" && u.includes("PPP_Web_")) { posts.push({ u, b: JSON.parse(opt.body) }); return json([]); }
      if (u.includes("admin-login-otp"))      return json({ email:"a@b.c", tmp_password:"x" });
      if (u.includes("/auth/v1/token"))       return json({ access_token:"lk", expires_in:3600 });
      if (u.includes("v_pedidos_web_np"))     return json(NPS);
      if (u.includes("ppp_web_np_asignar"))   return json(NPS.map((n,i)=>({ r_order_id:n.order_id, r_np_idx:n.np_idx, r_np:1343+i })));
      // v12.75 — el m³ sale de la VISTA que resuelve la "L" final, no de la tabla
      // cruda. Si alguien vuelve a apuntar a `Volumen_Articulos`, este mock no
      // matchea, el m³ da 0 y el test cae: es el guardarraíl del cambio.
      // v12.77 — el m³ ya no se pide acá: viene en la fila de la NP. Si alguien
      // vuelve a sumarlo en el front, estos mocks devuelven vacío y el test cae.
      if (u.includes("vista_volumen_articulo_resuelto")) { volUrl.push(u); return json([]); }
      if (u.includes("Volumen_Articulos"))    return json([]);
      // El resync: el pedido cambió → el backend reacomoda. Acá sólo se verifica
      // que se llame, con las filas vivas y antes de leer la programación.
      if (u.includes("rpc/ppp_web_resync")) { resync.push(JSON.parse(opt.body)); return json([]); }
      if (u.includes("PPP_Web_Programacion")) return json([]);
      if (u.includes("PPP_Programacion_Diaria")) return json([]);
      return json([]);
    };

    // ---- 1) el pedido entra a la PPP ----
    const filas = await pppTraerPedidosWeb("lk");
    _pppParsed.prog = filas.slice();
    localStorage.removeItem("vir_ppp_edits");

    const m3_1342 = (filas.find(f => f._wOrder === 1342) || {}).m3;
    const zonas = filas.map(f => f.zona);

    // ---- 2) armar tandas (el botón de la PPP, con el algoritmo de la PPP) ----
    await pppSugerirTandas();
    const ed = pppLoadEdits();
    const tandas = filas.map(f => (ed[f.np] || {}).tanda || f.tanda);

    // ---- 3) confirmar → qué se guardaría ----
    pppConfirmarProgramar();
    await new Promise(r => setTimeout(r, 250));
    const cab  = (posts.find(x => x.u.includes("PPP_Web_Programacion")) || {}).b || [];
    const base = (posts.find(x => x.u.includes("PPP_Web_Base")) || {}).b || [];

    // ---- 4) lo que vería el OPERARIO, alimentado con lo que se acaba de guardar ----
    window.fetch = async (url) => {
      const u = String(url);
      if (u.includes("PPP_Web_Programacion")) return json(cab.map(c => ({
        empresa:c.empresa, np:c.np, tanda:c.tanda, zona:c.zona, fecha_entrega:c.fecha_entrega,
        cod_cliente:c.cod_cliente, razon_social:c.razon_social, direccion:c.direccion, barrio:c.barrio, m3:c.m3 })));
      if (u.includes("PPP_Web_Base")) return json(base);
      return json([]);
    };
    window.fetchMonitorFromSupabase = async () => new Map();
    const mapa = await fetchMonitorSheet();
    const pick = new Map(); await mergePickingBasePppWeb(pick);
    // Se sigue el pedido que SÍ recibió tanda. Los otros dos no llegan al mínimo
    // de 0,60 m³ de su zona y quedan sin programar — es la regla, no un fallo.
    const t = cab.find(c => c.order_id === 1341) || {};
    const tandaObj = t.tanda ? mapa.get(String(t.tanda).toUpperCase()) : null;
    const artsOper = (pick.get("LK 01344") || []).map(x => x.art + ":" + x.cajas).join(",");

    // ---- 5) el Excel para ISIS ----
    window.fetch = async (url) => {
      const u = String(url);
      if (u.includes("Entregas_Virgilio")) return json(
        (base.filter(x => x.np_label === "LK 01344")).map((x,i) => ({ id:i+1, np:"LK 01344", cod_art:x.articulo, cajas_pedidas:x.cajas, cajas_entregadas:x.cajas })));
      if (u.includes("PPP_Web_Programacion")) return json([{ np:1344, empresa:"lk", fecha_recep:"2026-09-03" }]);
      if (u.includes("vista_uxb_articulo"))   return json([{cod:"31",uxb:24},{cod:"505",uxb:12}]);
      return json([]);
    };
    window._facLastTandas = [{ pedidos:[{ np:"LK 01344", cod:"4188", razonSocial:"Orfali" }] }];
    const xls = await _facXlsArmar(["LK 01344"]);

    return {
      filas: filas.length,
      np: filas.map(f => f.np).join(" · "),
      m3_1342: m3_1342,
      zonas: zonas.join(" · "),
      tandas: tandas.join(" · "),
      tandasDistintasPorZona: new Set(tandas).size,
      guardadas: cab.length,
      sinTanda: tandas.filter(x => x === "—").length,   // los que no llegan al mínimo de m³
      cabNp: t.np, cabM3: t.m3, cabTanda: t.tanda, cabZona: t.zona, cabFechaEnt: !!t.fecha_entrega,
      lineasBase: base.length,
      operVeTanda: !!tandaObj,
      operNp: tandaObj ? tandaObj.pedidos[0].np : null,
      operEmpresa: empresaDeNp(tandaObj ? tandaObj.pedidos[0].np : ""),
      artsOper: artsOper,
      xlsFilas: xls.length,
      xlsFecha: xls[0] ? xls[0].fechaTxt : null,
      xlsLineas: xls[0] ? xls[0].lineas.length : 0,
      volPideVista: volUrl.length > 0,
      resyncLlamado: resync.length,
      resyncEmpresa: resync[0] ? resync[0].p_empresa : null,
      resyncFilas: resync[0] ? resync[0].p_filas.length : 0,
      resyncTraeM3: !!(resync[0] && resync[0].p_filas[0] && resync[0].p_filas[0].m3 != null)
    };
  }, { NPS, VOL, ZONAS });

  const ok =
    r.filas === 3 &&
    r.np === "LK 01343 · LK 01344 · LK 01345" &&
    r.m3_1342 === 0.336 &&                                   // calculado a mano sobre los m³ reales
    r.zonas === "Zona 3 - CABA Oeste · Zona 6 - GBA Norte · Retira" &&
    r.sinTanda === 2 &&                                      // 0,336 y 0,033 m³ no llegan al mínimo de 0,60
    r.guardadas === 1 && r.cabNp === 1344 && r.cabM3 === 1.184 &&
    r.cabZona === "Zona 6 - GBA Norte" && r.cabFechaEnt === true &&
    r.lineasBase === 15 &&
    r.operVeTanda && r.operNp === "LK 01344" && r.operEmpresa === "LK" &&
    r.artsOper === "031:10,280:10,315:10,502:15,505:150,506:20,521:3,530:4,574E:25,580:15,586:50,598E:25,599E:3,811E:3,816E:15" &&
    r.xlsFilas === 1 && /03\/09\/2026/.test(String(r.xlsFecha)) && r.xlsLineas === 15 &&
    r.volPideVista === false &&                              // v12.77: el m³ ya no se pide, viene en la fila
    r.resyncLlamado === 1 && r.resyncEmpresa === "lk" &&      // v12.77: se reacomoda la programación
    r.resyncFilas === 3 && r.resyncTraeM3 === true;

  console.log("pweb-e2e:", JSON.stringify(r, null, 0));
  console.log("  pageerrors:", errs.length ? errs.join("|") : "none", "·", (ok && !errs.length) ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit((ok && !errs.length) ? 0 : 1);
})();
