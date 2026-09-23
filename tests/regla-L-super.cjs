#!/usr/bin/env node
/*
 * tests/regla-L-super.cjs — REGLA v21.09 (Luis, 22/09/2026)
 *
 *   "lo de la L deberia aplicar unicamente a CENCOSUD y a pedidos que van a
 *    TIERRA DEL FUEGO"
 *
 * La L NO la decide quien FACTURA: la decide de quien son los ARTICULOS.
 * Cencosud factura por Chef y sus articulos son de LK  -> lleva L.
 * Dorinka  factura por Chef y sus articulos son de Chef -> NO lleva L.
 *
 * El criterio en el codigo es  isChefSuper(k) && !usesChefProducts(k).
 * Con `isChef` a secas (como estuvo hasta la v21.09) el pedido 229 de Dorinka
 * salio con 769L/840L/838L/865EL/798EL y del lado de LK no hay una sola caja.
 *
 * Este es un CANDADO ESTATICO sobre el espejo de admin-supercot.js: el fuente
 * vive en pagina-LK-copia / paginach, pero la copia de este repo se sirve por
 * GitHub Pages y es la que abre el supervisor desde "Panel Web LK".
 *
 * ⚠ Se corre sobre el archivo SIN COMENTARIOS: el comentario que explica la
 *   regla nombra `usesChefProducts` igual, y un candado que vigila su propio
 *   comentario no vigila nada (mismo pozo que gv_reglas_perdidas, v21.82).
 */
const fs = require("fs");
const path = require("path");

const ARCHIVO = path.join(__dirname, "..", "admin", "admin-supercot.js");
const src = fs.readFileSync(ARCHIVO, "utf8");

// fuera comentarios de bloque y de linea (aproximado, alcanza para este archivo)
const codigo = src
  .replace(/\/\*[\s\S]*?\*\//g, "")
  .replace(/^[ \t]*\/\/.*$/gm, "")
  .replace(/([^:])\/\/[^\n]*/g, "$1");

const out = {};

// cada asignacion de addLSuffix, con su lado derecho hasta el ';'
const asigns = [];
const re = /addLSuffix\s*=\s*([^;]+);/g;
let m;
while ((m = re.exec(codigo))) asigns.push(m[1].replace(/\s+/g, " ").trim());

out.hay_dos_asignaciones = asigns.length >= 2;        // submit + PDF
out.todas_niegan_chefproducts = asigns.length > 0 &&
  asigns.every((r) => /!\s*usesChefProducts\s*\(/.test(r));
// y ninguna se quedo en el criterio viejo "factura por Chef -> lleva L"
out.ninguna_es_isChef_a_secas = asigns.every(
  (r) => !/^isChef(Super\([^)]*\))?$/.test(r)
);
// las dos funciones siguen existiendo (si alguien las renombra, esto avisa)
out.existe_usesChefProducts = /function\s+usesChefProducts\s*\(/.test(codigo);
out.existe_isChefSuper = /function\s+isChefSuper\s*\(/.test(codigo);

const ok = Object.values(out).every(Boolean);
console.log("regla-L-super:", JSON.stringify(out));
console.log("  asignaciones halladas:", asigns.length, "->", asigns.join(" | "));
if (!ok) {
  console.error(
    "\n✗ La regla de la L se perdio en admin/admin-supercot.js.\n" +
      "  La L es de CENCOSUD y de TIERRA DEL FUEGO, de nadie mas:\n" +
      "  addLSuffix = isChefSuper(k) && !usesChefProducts(k)\n" +
      "  Ver CLAUDE.md, regla v21.09."
  );
}
process.exit(ok ? 0 : 1);
