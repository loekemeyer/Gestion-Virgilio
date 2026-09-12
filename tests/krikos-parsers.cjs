/* Regresión v15.90 — `admin/krikos-parsers.js`, el módulo que usa el importador
   automático de las OC de súper (Edge Function `krikos-auto-import` en el Supabase de LK).

   Lo que cuida:
   1. **Que sea EL MISMO código que el panel.** El archivo se genera copiando textualmente
      los parsers de `admin/admin-supercot.js`. Si alguien arregla un parser allá y no
      regenera, el importador automático sigue leyendo el PDF con la versión vieja y nadie
      se entera. Acá se regenera a un temporal y se compara byte a byte.
   2. Que el módulo exporte lo que la Edge Function importa (si falta uno, la función no
      bootea y las OC dejan de entrar, en silencio).
   3. Que parsee de verdad: se le da una OC de Coto sintética (códigos y precios
      inventados) y se chequea cadena, renglones, cajas, uxb, precio y total.
   4. El match por variantes de código (102 → 102E), que es lo que salva a la línea Loke.

   Sale 1 si falla. No necesita Playwright ni red. */
const { execFileSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const raiz = path.join(__dirname, "..");
const archivo = path.join(raiz, "admin", "krikos-parsers.js");

(async () => {
  const out = {};

  // ---- 1) el archivo está sincronizado con admin-supercot.js ----
  const tmp = path.join(os.tmpdir(), "krikos-parsers-" + process.pid + ".js");
  try {
    execFileSync("bash", [path.join(raiz, "scripts", "gen-krikos-parsers.sh"), tmp], { cwd: raiz });
    out.sincronizadoConElPanel = fs.readFileSync(tmp, "utf8") === fs.readFileSync(archivo, "utf8");
  } catch (e) {
    console.error("krikos-parsers: no se pudo regenerar:", e.message);
    process.exit(1);
  } finally { try { fs.unlinkSync(tmp); } catch (_e) {} }

  // ---- 2) exporta lo que la Edge Function importa ----
  const M = await import("file://" + archivo);
  out.exporta = ["detectSuper", "PARSERS", "extractPdfTotal", "codVariants", "findInPool", "parseNum"]
    .every((k) => M[k] != null);
  out.onceParsers = Object.keys(M.PARSERS).length === 11 &&
    Object.values(M.PARSERS).every((f) => typeof f === "function");

  // ---- 3) parsea una OC de Coto sintética (datos inventados) ----
  const oc = [
    "Prov: 12518 Pedido: 90000000001 L.Dest: 93",
    "Raz.Social: LOEKEMEYER HNOS. S.R.L.",
    "Consignación: NO Fecha de Entrega: 20/09/2026",
    "Usu Aprobador: 129947 L. de Entrega: CENTRO DE DISTRIBUCION",
    "PLU Dpto Descripción EAN C.Ped UC C.Tarifa T.IVA B.Cciales en % Recargo(2)",
    "Fabric Cod.Int.Prov Bultos por Línea Ot.Bonif(3) O.Bon CxB Percep. Imp.Int. Ot.Bonif(1) C.Neto",
    "11111 ARTICULO DE PRUEBA UNO . . 7790000000017 120 1 1000.000 21.000 0.00 0.00 0.00 0",
    "12518 102 10 0 0 12 0 0.000 0 1000.000",
    "22222 ARTICULO DE PRUEBA DOS . . 7790000000024 40 1 500.000 21.000 0.00 0.00 0.00 0",
    "12518 870E 10 0 0 4 0 0.000 0 500.000",
    "Tot. Unidades Tot.U.Bonific. Total Bultos Tot.Imp.Neto Total Cuota IVA Total Imp.Int. Total Imp. A Pagar",
    "160 0 20 140000.000 29400.000 0.000 169400.000",
    "Help line: ... | VV: OC_Coto | VDS: OrdCotoPlx | FGDS: 04/09/2026",
  ].join("\n");

  out.detectaCoto = M.detectSuper(oc) === "coto";
  const p = M.PARSERS.coto(oc);
  out.numeroDeOc = p.orderNumber === "90000000001";
  out.sucursal = String(p.branchId) === "93";
  out.dosRenglones = p.items.length === 2;
  const [a, b] = p.items;
  out.renglonUno = a && a.codLk === "102" && a.cajas === 10 && a.uxb === 12 && a.unitPrice === 1000;
  out.renglonDos = b && b.codLk === "870E" && b.cajas === 10 && b.uxb === 4 && b.unitPrice === 500;
  // El total del PDF y el calculado tienen que dar lo mismo: es la comprobación que
  // decide si la OC entra limpia o entra con el cartel de "el importe no dio".
  const calc = p.items.reduce((s, it) => s + it.unitPrice * it.cajas * it.uxb, 0);
  out.totalPdf = M.extractPdfTotal(oc, "coto") === 140000;
  out.totalCalculadoCoincide = calc === 140000;

  // ---- 4) variantes de código: la línea Loke entra como 102E ----
  const v = M.codVariants("102");
  out.variantesTraenE = v.includes("102E") && v[0] === "102";
  out.findInPool = !!M.findInPool([{ cod: "102E" }], v) && !M.findInPool([{ cod: "999" }], v);

  const fails = Object.keys(out).filter((k) => !out[k]);
  if (fails.length) { console.error("krikos-parsers FALLÓ:", fails, out); process.exit(1); }
  console.log("krikos-parsers OK —", Object.keys(out).length, "chequeos");
})();
