/* Regresión v21.11 — FC s/Salida: LA "L" SE RESUELVE IGUAL EN EL FRONT Y EN LA BASE.

   Luis, 2026-09-22: *"si hay 11 que salen los 11 deberían aparecer como 026 y ninguno
   como 026L para fc s/salida, es rarísimo eso. Aplicá esa lógica a todos esos códigos."*

   `Entregas_Virgilio` guarda el código CRUDO con L (026L, 438EL) porque es el que va a
   la FACTURA. Para el badge de Stock hay que llevarlo al código de GÓNDOLA, que es lo
   que hace `pkResolveArt` en el front. `vista_fc_sin_salida` lo hacía con `norm_cod()`
   a secas, que NO pela la L: el 026 salía partido en dos filas (026 = 10, 026L = 1) y
   en los duales el badge quedaba en 0 de los dos lados.

   El arreglo vive en SQL (`gv_cod_stock_de_entrega`, ver
   sql/gv_fc_sin_salida_codigo_l_v2111.sql). Este test corre `pkResolveArt` DE VERDAD
   —extraído de index.html— y verifica que dé lo MISMO que la función de la base.
   Si alguien toca la regla de la L en el front, esto se pone en rojo y avisa que hay
   que tocar el SQL también: son dos copias de la misma regla. ≡ index.html

   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
const fallos = [];

/* ── 1. Traer las 5 funciones del front, tal como están ───────────────────── */
const NOMBRES = ["empresaDeNp", "pkCodEmpresa", "pkEmpresaArt", "pkStripL", "pkResolveArt"];
let codigo = "";
for (const n of NOMBRES) {
  // el cuerpo va hasta la primera llave de cierre en columna 0 (estilo del archivo)
  const re = new RegExp("^function " + n + "\\s*\\([\\s\\S]*?^\\}", "m");
  const m = re.exec(src);
  if (!m) { fallos.push("no encontré function " + n + "() en index.html"); continue; }
  codigo += m[0] + "\n";
}

if (!fallos.length) {
  /* GÓNDOLA: pkCodEmpresa sólo agrega el sufijo si esa góndola existe. Los 4 duales
     de `codigos_duales` viven de los dos lados; el resto, de uno solo. */
  const GONDOLA = {};
  ["437E", "438E", "439E", "809E"].forEach(function (c) { GONDOLA[c + " LK"] = 1; GONDOLA[c + " CH"] = 1; });

  const ctx = { window: { GONDOLA: GONDOLA }, console: console };
  ctx.globalThis = ctx;
  try { vm.runInNewContext(codigo, ctx); }
  catch (e) { fallos.push("no pude evaluar las funciones del front: " + e.message); }

  /* ── 2. Los casos, con lo que devuelve gv_cod_stock_de_entrega (medido 22/09) ── */
  const CASOS = [
    // [cod crudo de Entregas_Virgilio, NP,        código de stock esperado, por qué]
    ["026L",    "CH 0030", "26",      "no dual con L: la L sólo dice de qué góndola salió"],
    ["066L",    "CH 0030", "66",      "idem, otro código del mismo pedido"],
    ["505L",    "CH 0031", "505",     "idem"],
    ["598EL",   "CH 0031", "598E",    "termina en EL: la E queda, la L se va"],
    ["438EL",   "CH 0030", "438E LK", "DUAL con L: manda la L (LK), NO la NP (Chef)"],
    ["439EL",   "44600",   "439E LK", "DUAL con L en NP de ISIS de Chef: igual LK"],
    ["438E",    "CH 0030", "438E CH", "dual SIN L: ahí sí manda la NP"],
    ["438E",    "98615",   "438E LK", "dual sin L, NP de Loekemeyer"],
    ["505",     "98615",   "505",     "código normal, sin cambios"],
    ["026",     "CH 0030", "26",      "sin L: norm_cod le saca los ceros igual"],
    ["438E LK", "98615",   "438E LK", "ya resuelto: idempotente, no lo rompe"],
  ];

  /* norm_cod() de la base: saca ceros a la izquierda y pone mayúsculas. El front lo
     hace con _ocgNorm, que es lo mismo. */
  const normCod = function (c) { return String(c || "").toUpperCase().trim().replace(/^0+(?=.)/, ""); };

  if (!fallos.length) {
    CASOS.forEach(function (c) {
      const cod = c[0], np = c[1], esperado = c[2], porque = c[3];
      let dio;
      try { dio = normCod(ctx.pkResolveArt(cod, np)); }
      catch (e) { fallos.push("pkResolveArt('" + cod + "','" + np + "') explotó: " + e.message); return; }
      if (dio !== esperado) {
        fallos.push("pkResolveArt('" + cod + "','" + np + "') dio '" + dio + "' y la base da '" +
          esperado + "' — " + porque + ".\n    → el front y gv_cod_stock_de_entrega se desfasaron: " +
          "mirá sql/gv_fc_sin_salida_codigo_l_v2111.sql");
      }
    });

    /* ── 3. Candado invertido: la regla de la L no puede depender de la NP ──── */
    const conL = ctx.pkEmpresaArt("438EL", "CH 0030");
    if (conL !== "LK") {
      fallos.push("pkEmpresaArt('438EL','CH 0030') dio '" + conL + "': un código con L es de " +
        "LOEKEMEYER aunque la NP sea de Chef. Si esto cambia, el picking manda al operario " +
        "a la góndola equivocada y el badge de Stock mira la pila que no es.");
    }
    if (ctx.pkStripL("438E LK") !== "438E LK") {
      fallos.push("pkStripL se comió el sufijo ' LK': sólo pela la L pegada a dígito o E.");
    }
  }
}

/* ── 4. El SQL del repo tiene que seguir teniendo las dos piezas ───────────── */
const sqlPath = path.join(__dirname, "..", "sql", "gv_fc_sin_salida_codigo_l_v2111.sql");
if (!fs.existsSync(sqlPath)) {
  fallos.push("falta sql/gv_fc_sin_salida_codigo_l_v2111.sql");
} else {
  /* ⚠ Sacar los comentarios ANTES de buscar, mismo criterio que gv_reglas_perdidas:
     el propio archivo NOMBRA el bug en la nota de rollback, y sin esto el candado
     invertido de abajo se dispara contra su propia documentación (pasó, 22/09). */
  const sqlCrudo = fs.readFileSync(sqlPath, "utf8");
  const sql = sqlCrudo.replace(/\/\*[\s\S]*?\*\//g, "").replace(/--[^\n]*/g, "");
  if (!/gv_cod_stock_de_entrega\s*\(\s*e\.cod_art/.test(sql)) {
    fallos.push("la vista del .sql ya no resuelve el código con gv_cod_stock_de_entrega(e.cod_art, …)");
  }
  if (!/security_invoker\s*=\s*true/.test(sql)) {
    fallos.push("el .sql perdió el security_invoker: la vista correría como postgres y saltearía la RLS");
  }
  if (/norm_cod\s*\(\s*e\.cod_art\s*\)\s+AS\s+cod/i.test(sql)) {
    fallos.push("volvió el norm_cod(e.cod_art) AS cod: ése es el bug que este test cuida");
  }
}

if (fallos.length) {
  console.error("✗ fcs-codigo-l: " + fallos.length + " problema(s)\n  - " + fallos.join("\n  - "));
  process.exit(1);
}
console.log("✓ fcs-codigo-l: pkResolveArt y gv_cod_stock_de_entrega dan lo mismo en los 11 casos");
