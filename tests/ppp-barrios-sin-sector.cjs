/* Un barrio SIN sector no puede volver a la regla vieja de 7 zonas. (v19.31, pedido de Thomas
   2026-09-17: *"en la PPP hay siete zonas, pero ya las habíamos separado más, porque por ejemplo
   Liniers y Núñez comparten una zona y eso estaría mal."*)

   Los 14 sectores de la v13.07 estaban bien y activos: Núñez (H) + Liniers (C) daba `false`.
   El agujero era el FALLBACK: `gv_ppp_web_sector` devuelve '~' || grupo_zona cuando el barrio no
   está en `GV_Barrios_Sector`, y el grupo 'Zonas 2+3' junta CABA Centro con CABA Oeste. O sea que
   cualquier barrio sin sector volvía a la regla de 7 zonas — medido el 17/09 antes del fix:
   Núñez + Floresta = true, Saavedra + Liniers = true, Villa Maipú + Del Viso = true (50 km).

   El arreglo vive entero en Supabase, así que desde acá se verifica el ARTEFACTO. La verificación
   real es el centinela de la base:

       select * from public.gv_ppp_barrios_sin_sector;   -- vacía = todo bien

   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");

const p = path.join(__dirname, "..", "sql", "gv_ppp_barrios_sector_v1931.sql");
if (!fs.existsSync(p)) {
  console.log("ppp-barrios-sin-sector: ✗ FAIL\n  - falta sql/gv_ppp_barrios_sector_v1931.sql");
  process.exit(1);
}
const src = fs.readFileSync(p, "utf8");
const fallas = [];

// 1) el fallback ya NO compara el grupo de zona. Si vuelve `v_ga is not distinct from v_gb` en la
//    rama del '~', vuelve el agujero entero.
const ramaTilde = src.match(/p_sector_a like '~%'[\s\S]{0,400}?end if;/);
if (!ramaTilde) {
  fallas.push("no se encuentra la rama del barrio sin sector en gv_ppp_web_compat");
} else if (/v_ga is not distinct from v_gb/.test(ramaTilde[0])) {
  fallas.push("el barrio sin sector sigue cayendo al GRUPO de zona ('Zonas 2+3' junta Centro con Oeste)");
} else if (!/btrim\(coalesce\(p_zona_a,''\)\) is not distinct from btrim\(coalesce\(p_zona_b,''\)\)/.test(ramaTilde[0])) {
  fallas.push("el barrio sin sector no compara la zona EXACTA");
}

// 2) el sector de fallback tampoco puede ser el grupo: si dos barrios desconocidos de Z2 y Z3
//    comparten el string '~Zonas 2+3', la regla "mismo sector" los junta ANTES de llegar al punto 1.
if (/'~' \|\| coalesce\(public\.gv_ppp_web_grupo_zona/.test(src)) {
  fallas.push("gv_ppp_web_sector sigue devolviendo '~'||grupo: dos barrios sin sector de Z2 y Z3 quedan 'mismo sector'");
}

// 3) los 30 barrios que faltaban, y los tres que se ubicaron a propósito lejos de Núñez
for (const b of ["saavedra", "san telmo", "floresta", "monte castro", "wilde", "haedo", "boulogne", "del viso"]) {
  if (!new RegExp("'" + b + "'").test(src)) fallas.push("falta el barrio " + b + " en GV_Barrios_Sector");
}
if (!/\('monte castro',\s*'C'/.test(src)) {
  fallas.push("Monte Castro no está en C: en E el par vecino E-H lo deja ir con Núñez");
}
if (!/\('villa santa rita',\s*'D'/.test(src)) {
  fallas.push("Villa Santa Rita no está en D: en E el par vecino E-H la deja ir con Núñez");
}

// 4) el centinela, con security_invoker (sin eso corre como postgres y saltea la RLS)
if (!/gv_ppp_barrios_sin_sector/.test(src)) fallas.push("falta el centinela gv_ppp_barrios_sin_sector");
if (!/alter view public\.gv_ppp_barrios_sin_sector set \(security_invoker = true\)/.test(src)) {
  fallas.push("el centinela sin security_invoker saltea la RLS");
}

// 5) el backup y el rollback tienen que estar escritos, no "aplicados en la base"
if (!/GV_Backup_BarriosSector_20260917/.test(src)) fallas.push("no dice dónde quedó el backup de GV_Barrios_Sector");
if (!/Rollback:/.test(src)) fallas.push("no está el rollback");

if (fallas.length) {
  console.log("ppp-barrios-sin-sector: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}
console.log("ppp-barrios-sin-sector: ✓ OK (el fallback compara la zona exacta y no quedan barrios sin sector)");
