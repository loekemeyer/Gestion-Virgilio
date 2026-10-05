/* v26.77 — `admin/krikos-auto-import.js`, rama de las cadenas que facturan por CHEF
   (Luis, 05/10/2026: «DORINKA Y CENCOSUD QUIERO QUE SE CARGUEN AUTOMATICAMENTE»).

   Corre el handler DE VERDAD con las dos bases y el PDF de mentira (no hay red), y mira:
   A. Cencosud en modo prueba (sin KRIKOS_CHEF_AUTO): NO crea nada, marca 'prueba' con lo que cargaría.
   B. Cencosud con el interruptor en 'si': crea en Chef por la puerta, SIN renglones, con L al
      final de cada código, hoja "Pedidos CH", empresa CH; marca la fila con el pedido de Chef.
   C. Dorinka: catálogo de Chef, renglones con product_id de Chef, SIN L, y el remap 838 → 838E.
   D. OC de la casilla de Chef que ya está en Chef (cargada a mano), aunque esté vencida:
      no baja el PDF, no crea nada, la marca 'cargado' con ese pedido.
   E. dry_run contra un pedido a mano igual: comparacion.iguales = true, y no escribe nada.
   F. Si no se puede mirar si la OC ya está en Chef: NO crea (podría duplicar) y queda 'no'.
   G. Una cadena de LK (Coto) sigue por su camino de siempre (krikos_auto_crear_pedido).
   H. Vencida, con el número del mail distinto al del PDF, ya cargada: la encuentra por el del PDF.
   I. Vencida y no cargada: salteada (el guarda de vencidas va después de mirar Chef).

   Sale 1 si falla. Sin Playwright ni red. */
const fs = require("fs");
const os = require("os");
const path = require("path");
const { pathToFileURL } = require("url");

const raiz = path.join(__dirname, "..");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "krikos-auto-chef-"));

// ---------- stubs de los imports remotos ----------
fs.writeFileSync(path.join(tmp, "stub-supabase.mjs"), `
export function createClient(url) { return globalThis.__mk(url); }
`);
fs.writeFileSync(path.join(tmp, "stub-unpdf.mjs"), `
export async function getDocumentProxy(buf) {
  const lines = new TextDecoder().decode(buf).split("\\n");
  return { numPages: 1, getPage: async () => ({ getTextContent: async () => ({
    items: lines.map((l, i) => ({ str: l, transform: [1, 0, 0, 1, 0, 2000 - i * 10] })) }) }) };
}
`);
let src = fs.readFileSync(path.join(raiz, "admin", "krikos-auto-import.js"), "utf8");
src = src.replace('"https://esm.sh/@supabase/supabase-js@2.45.4"', JSON.stringify(pathToFileURL(path.join(tmp, "stub-supabase.mjs")).href))
         .replace('"https://esm.sh/unpdf@0.12.1"', JSON.stringify(pathToFileURL(path.join(tmp, "stub-unpdf.mjs")).href))
         .replace('"./krikos-parsers.js"', JSON.stringify(pathToFileURL(path.join(raiz, "admin", "krikos-parsers.js")).href));
fs.writeFileSync(path.join(tmp, "kai.mjs"), src);

// ---------- PDFs sintéticos (datos inventados) ----------
const PDF = {
  "cen.pdf": [
    "Empresa Cencosud S.A.",
    "Nro OC 198000001",
    "Pd.Emisor: CD Cordoba - 779",
    "Cond. Pago: 60 dias",
    "7798000000310 COLADOR DE PRUEBA 12 2 24 1000.00 900.00 21.00 0 0 D1234 0 %",
    "7798000008160 RALLADOR DE PRUEBA 6 3 18 2000.00 1800.00 21.00 0 0 D1234 0 %",
  ].join("\n"),
  "dor.pdf": [
    "COMPRADOR: DORINKA SRL",
    "ORDEN DE COMPRA: 9400000001",
    "LUGAR DE ENTREGA: 120 - CD MORENO",
    "Condicion Pago: 60 DIAS",
    "7798000000001 SKU1 838 FILTRO DE PRUEBA 12 3 36 120.00 360.00",
    "7798000000002 SKU2 0769 OTRO DE PRUEBA 6 2 12 60.00 120.00",
  ].join("\n"),
  "coto.pdf": [
    "Prov: 12518 Pedido: 90000000001 L.Dest: 93",
    "Raz.Social: LOEKEMEYER HNOS. S.R.L.",
    "Consignación: NO Fecha de Entrega: 20/12/2026",
    "PLU Dpto Descripción EAN C.Ped UC C.Tarifa T.IVA B.Cciales en % Recargo(2)",
    "Fabric Cod.Int.Prov Bultos por Línea Ot.Bonif(3) O.Bon CxB Percep. Imp.Int. Ot.Bonif(1) C.Neto",
    "11111 ARTICULO DE PRUEBA UNO . . 7790000000017 120 1 1000.000 21.000 0.00 0.00 0.00 0",
    "12518 102 10 0 0 12 0 0.000 0 1000.000",
    "Help line: ... | VV: OC_Coto | VDS: OrdCotoPlx | FGDS: 04/09/2026",
  ].join("\n"),
};

// ---------- estado de las dos bases de mentira ----------
const S = {
  secrets: { KRIKOS_INGEST_SECRET: "s", KRIKOS_CHEF_TOKEN: "tok" },
  inbox: [],
  ocCargada: {},          // oc -> array (lo que devuelve krikos_auto_chef_oc_cargada)
  ocCargadaFalla: false,
  rpc: [],                // [{base, name, args}]
  descargas: [],
  fetches: [],
  nextChefId: 300,
};
const CHEF_URL = "https://nkhzocgdpwtgrmwleihr.supabase.co";
const ctxCli = {
  cencosud: { cod_cliente_chef: "2444", cod_remap: null, usa_productos_chef: false,
    customer: { id: "cli-cen", cod_cliente: "2444", business_name: "Cencosud SA", vend: 20, debt: 0, credit_limit: null, payment_term: 60 } },
  dorinka: { cod_cliente_chef: "2686", cod_remap: { "838": "838E" }, usa_productos_chef: true,
    customer: { id: "cli-dor", cod_cliente: "2686", business_name: "Dorinka SRL", vend: 7, debt: 0, credit_limit: null, payment_term: 60 } },
};
const POOLS = {
  lk_products: [{ id: "lk-031", cod: "031", description: "Colador", list_price: 100, uxb: 12 },
                { id: "lk-102", cod: "102E", description: "Pinza", list_price: 50, uxb: 12 }],
  loke_products: [{ id: "loke-816", cod: "816E", description: "Rallador Loke", list_price: 200, uxb: 6 }],
  chef_products: [{ id: "ch-838e", cod: "838E", description: "Filtro", list_price: 10, uxb: 12, active: true },
                  { id: "ch-769", cod: "769", description: "Otro", list_price: 10, uxb: 6, active: true }],
};

function qb(resolver) {
  const st = { filtros: {}, range: null };
  const q = {
    select() { return q; }, not() { return q; }, order() { return q; }, limit() { return q; },
    is() { return q; }, update() { return q; },
    eq(k, v) { st.filtros[k] = v; return q; },
    in(k, v) { st.filtros[k] = v; return q; },
    range(a, b) { st.range = [a, b]; return q; },
    then(ok, ko) { return Promise.resolve(resolver(st)).then(ok, ko); },
  };
  return q;
}

globalThis.__mk = (url) => {
  const esChef = url === CHEF_URL;
  const base = esChef ? "chef" : "lk";
  return {
    rpc(name, args) {
      S.rpc.push({ base, name, args });
      if (esChef) {
        if (name === "krikos_crear_pedido_super") {
          if (args.p_token !== "tok") return Promise.resolve({ data: null, error: { message: "token inválido" } });
          return Promise.resolve({ data: { ok: true, order_id: S.nextChefId++, duplicado: false }, error: null });
        }
        return Promise.resolve({ data: null, error: { message: "rpc chef desconocida " + name } });
      }
      switch (name) {
        case "krikos_secret": return Promise.resolve({ data: S.secrets[args.p_name] || null, error: null });
        case "krikos_auto_cadenas": return Promise.resolve({ data: [
          { super_key: "cencosud", label: "Cencosud", empresa: "chef", cod_cliente_lk: null, cod_cliente_chef: "2444", usa_productos_chef: false, payment_code: 2, pdf_ratio: 1.19047619 },
          { super_key: "dorinka", label: "Dorinka", empresa: "chef", cod_cliente_lk: null, cod_cliente_chef: "2686", usa_productos_chef: true, payment_code: 3, pdf_ratio: 1.19760479 },
          { super_key: "coto", label: "Coto", empresa: "lk", cod_cliente_lk: "801", payment_code: 1, pdf_ratio: 1 },
        ], error: null });
        case "krikos_auto_precios": return Promise.resolve({ data: [{ super_key: "cencosud", cod: "031", price: 1500 }], error: null });
        case "krikos_auto_chef_ctx": return Promise.resolve({ data: ctxCli[args.p_super_key] || null, error: null });
        case "krikos_auto_chef_oc_cargada":
          if (S.ocCargadaFalla) return Promise.resolve({ data: null, error: { message: "FDW caído" } });
          return Promise.resolve({ data: S.ocCargada[args.p_oc] || [], error: null });
        case "krikos_auto_crear_pedido": return Promise.resolve({ data: 9001, error: null });
        default: return Promise.resolve({ data: null, error: null });
      }
    },
    from(tabla) {
      return qb((st) => {
        if (esChef && tabla === "products") return { data: st.range && st.range[0] > 0 ? [] : POOLS.chef_products, error: null };
        if (esChef && tabla === "customer_delivery_addresses") {
          return { data: st.filtros.super_branch_id === "779"
            ? [{ slot: 1, label: "Cd Cordoba", direccion_entrega: "J Troxler 3259", zona_expreso: "Soldati", super_branch_id: "779" }] : [], error: null };
        }
        if (tabla === "krikos_oc_inbox") {
          const ids = st.filtros.id;
          return { data: S.inbox.filter((f) => !ids || ids.includes(f.id)), error: null };
        }
        if (tabla === "products") return { data: st.range && st.range[0] > 0 ? [] : POOLS.lk_products, error: null };
        if (tabla === "loke_products") return { data: st.range && st.range[0] > 0 ? [] : POOLS.loke_products, error: null };
        if (tabla === "customers") return { data: [{ id: "cli-coto", cod_cliente: "801", business_name: "Coto", vend: 1, debt: 0 }], error: null };
        return { data: [], error: null };
      });
    },
    storage: { from: () => ({ download: async (p) => {
      S.descargas.push(p);
      const txt = PDF[p];
      if (!txt) return { data: null, error: { message: "no existe " + p } };
      return { data: { arrayBuffer: async () => new TextEncoder().encode(txt).buffer }, error: null };
    } }) },
  };
};
globalThis.Deno = { env: { get: (k) => ({ SUPABASE_URL: "https://lk.test", SUPABASE_SERVICE_ROLE_KEY: "srv", SUPABASE_ANON_KEY: "anon" })[k] } };
globalThis.fetch = async (url, init) => { S.fetches.push({ url, body: init && init.body ? JSON.parse(init.body) : null }); return { ok: true, json: async () => ({}) }; };

const fila = (id, p, extra) => Object.assign({ id, cadena: "X", nro_documento: "", sucursal: "", fecha_entrega: "20/12/2026",
  storage_path: p, estado: "pendiente", mail_fecha: "2026-10-05", auto_estado: null, mail_uid: "chef:INBOX:1:" + id }, extra || {});

(async () => {
  const M = await import(pathToFileURL(path.join(tmp, "kai.mjs")).href);
  const correr = async (body) => {
    S.rpc = []; S.descargas = []; S.fetches = [];
    const r = await M.handler({ headers: { get: () => "s" }, json: async () => body });
    return JSON.parse(await r.text());
  };
  const rpcs = (n) => S.rpc.filter((x) => x.name === n);
  const out = {};

  // A. Cencosud en modo prueba
  S.inbox = [fila(1, "cen.pdf", { nro_documento: "198000001" })];
  let r = await correr({});
  let d = r.docs && r.docs[0];
  out.A_prueba = !!d && d.resultado === "prueba" && rpcs("krikos_crear_pedido_super").length === 0 &&
    rpcs("krikos_auto_marcar").some((x) => x.args.p_auto_estado === "prueba" && /MODO PRUEBA/.test(x.args.p_auto_aviso));

  // B. Cencosud con el interruptor en 'si'
  S.secrets.KRIKOS_CHEF_AUTO = "si";
  r = await correr({});
  d = r.docs && r.docs[0];
  const pb = rpcs("krikos_crear_pedido_super")[0];
  const ob = pb && pb.args.p_order;
  out.B_crea = !!ob && d.resultado === "importada" && d.order_id === 300;
  out.B_sinRenglones = !!ob && Array.isArray(ob.items) && ob.items.length === 0;
  out.B_conL = !!ob && ob.sheets_payload.items.map((x) => x.cod_art).join(",") === "031L,816EL";
  out.B_hojaCH = !!ob && ob.sheets_payload.target_sheet === "Pedidos CH" && ob.sheets_payload.empresa === "CH" &&
    ob.sheets_payload.is_chef === true && ob.sheets_payload.cod_cliente === "2444" && ob.sheets_payload.pdf_oc === "198000001" &&
    ob.sheets_payload.condicion_pago_code === 2 && ob.sheets_payload.sucursal_entrega === "Cd Cordoba" && ob.customer_id === "cli-cen";
  out.B_precioSuper = !!ob && ob.subtotal === 1000 * 2 * 12 + 2000 * 3 * 6;
  out.B_marca = rpcs("krikos_auto_marcar_chef").some((x) => x.args.p_id === 1 && x.args.p_order_id === 300);
  out.B_hojas = S.fetches.some((f) => /sheets-proxy/.test(f.url) && f.body.order_number === "300") &&
    S.fetches.some((f) => /sheets-entregas-proxy/.test(f.url) && f.body.empresa === "CH" && f.body.items[0].cod_art === "031L");

  // C. Dorinka
  S.inbox = [fila(2, "dor.pdf", { nro_documento: "9400000001" })];
  r = await correr({});
  d = r.docs && r.docs[0];
  const oc = rpcs("krikos_crear_pedido_super")[0];
  const o = oc && oc.args.p_order;
  out.C_renglonesChef = !!o && o.items.map((x) => x.product_id).join(",") === "ch-838e,ch-769";
  out.C_sinL_remap = !!o && o.sheets_payload.items.map((x) => x.cod_art).join(",") === "838E,769" &&
    o.sheets_payload.condicion_pago_code === 3 && o.customer_id === "cli-dor";
  out.C_resultado = !!d && d.resultado === "importada";

  // D. ya cargada a mano, aunque vencida
  S.inbox = [fila(3, "cen.pdf", { nro_documento: "198000009", fecha_entrega: "01/01/2020" })];
  S.ocCargada["198000009"] = [{ order_id: 242 }, { order_id: 245 }];
  r = await correr({});
  d = r.docs && r.docs[0];
  out.D_yaCargada = !!d && d.resultado === "ya_cargada" && d.order_id === 245 && S.descargas.length === 0 &&
    rpcs("krikos_crear_pedido_super").length === 0 &&
    rpcs("krikos_auto_marcar_chef").some((x) => x.args.p_id === 3 && x.args.p_order_id === 245);

  // E. dry_run contra un pedido a mano idéntico
  S.inbox = [fila(4, "cen.pdf", { nro_documento: "198000001" })];
  S.ocCargada["198000001"] = [{ order_id: 247, total: 1000 * 2 * 12 + 2000 * 3 * 6, sheets_payload: {
    cod_cliente: "2444", vend: "20", condicion_pago: "60 dias", condicion_pago_code: 2, sucursal_entrega: "Cd Cordoba",
    is_chef: true, target_sheet: "Pedidos CH", empresa: "CH", fecha_entrega: "20/12/2026",
    items: [{ cod_art: "031L", cajas: 2, uxb: 12 }, { cod_art: "816EL", cajas: 3, uxb: 6 }] } }];
  r = await correr({ dry_run: true, ids: [4], force: true });
  d = r.docs && r.docs[0];
  out.E_compara = !!d && d.resultado === "ya_cargada" && d.comparacion && d.comparacion.order_id === 247 && d.comparacion.iguales === true;
  out.E_noEscribe = rpcs("krikos_crear_pedido_super").length === 0 && rpcs("krikos_auto_marcar_chef").length === 0 &&
    rpcs("krikos_auto_marcar").length === 0 && S.fetches.length === 0;
  delete S.ocCargada["198000001"];

  // F. no se puede mirar si ya está en Chef
  S.ocCargadaFalla = true;
  S.inbox = [fila(5, "cen.pdf", { nro_documento: "198000001" })];
  r = await correr({});
  d = r.docs && r.docs[0];
  out.F_noCrea = !!d && d.resultado === "no_importada" && rpcs("krikos_crear_pedido_super").length === 0 &&
    rpcs("krikos_auto_marcar").some((x) => x.args.p_id === 5 && x.args.p_auto_estado === "no");
  S.ocCargadaFalla = false;

  // H. el número del mail no coincide con el del PDF y está vencida: la encuentra por el del PDF (no "salteada")
  S.inbox = [fila(7, "cen.pdf", { nro_documento: "OTRO-NRO", fecha_entrega: "01/01/2020" })];
  S.ocCargada["198000001"] = [{ order_id: 250 }];
  r = await correr({});
  d = r.docs && r.docs[0];
  out.H_yaCargadaPorPdf = !!d && d.resultado === "ya_cargada" && d.order_id === 250 &&
    rpcs("krikos_auto_marcar_chef").some((x) => x.args.p_id === 7 && x.args.p_order_id === 250);
  delete S.ocCargada["198000001"];

  // I. vencida y NO cargada: salteada, sin crear nada
  S.inbox = [fila(8, "cen.pdf", { nro_documento: "198000001", fecha_entrega: "01/01/2020" })];
  r = await correr({});
  d = r.docs && r.docs[0];
  out.I_vencida = !!d && d.resultado === "salteada" && rpcs("krikos_crear_pedido_super").length === 0 &&
    rpcs("krikos_auto_marcar").some((x) => x.args.p_id === 8 && x.args.p_auto_estado === "salteada");

  // G. Coto (LK) sigue igual
  S.inbox = [fila(6, "coto.pdf", { mail_uid: "INBOX:1:6", nro_documento: "90000000001" })];
  r = await correr({});
  d = r.docs && r.docs[0];
  out.G_lk = !!d && d.resultado === "importada" && d.order_id === 9001 && rpcs("krikos_auto_crear_pedido").length === 1 &&
    rpcs("krikos_crear_pedido_super").length === 0 && rpcs("krikos_auto_chef_oc_cargada").length === 0;

  fs.rmSync(tmp, { recursive: true, force: true });
  const malos = Object.entries(out).filter(([, v]) => !v).map(([k]) => k);
  if (malos.length) {
    console.error("krikos-auto-chef FALLA:", malos.join(", "));
    console.error(JSON.stringify(out, null, 1));
    process.exit(1);
  }
  console.log("krikos-auto-chef OK — " + Object.keys(out).length + " chequeos");
})().catch((e) => { console.error("krikos-auto-chef:", e); process.exit(1); });
