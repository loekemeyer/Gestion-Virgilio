/* Regresión v21.12 — "438E LK" NO ES UN CÓDIGO: el artículo va pelado y la empresa al lado.

   Luis, 2026-09-22: *"COMO QUE «438E LK»… NO EXISTE ESE CÓDIGO. Debería ser en todos lados
   «438E» de la empresa «LK» o de la empresa «CH» como dato en una columna aparte que viaje
   con el código a todos lados."*

   `Entregas_Virgilio` guarda el código CRUDO con L (026L, 438EL) porque es el que va a la
   FACTURA. Para mirar stock hay que partirlo en sus DOS datos:
       gv_cod_stock_de_entrega  -> el ARTÍCULO   (026L -> 026, 438EL -> 438E)
       gv_empresa_de_entrega    -> la EMPRESA    (LK / CH)
   y nunca volver a pegarlos. Ver sql/gv_fc_sin_salida_codigo_l_v2112.sql.

   Este test corre `pkResolveArt` / `pkStripL` / `pkEmpresaArt` DE VERDAD —extraídos de
   index.html— y verifica que el front y la base separen el código de la empresa igual. Si
   alguien toca la regla de la L en uno de los dos lados, esto se pone en rojo. ≡ index.html

   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
const fallos = [];

/* ── 1. Traer las funciones del front, tal como están ─────────────────────── */
const NOMBRES = ["empresaDeNp", "pkCodEmpresa", "pkEmpresaArt", "pkStripL", "pkResolveArt", "codBase", "_ocgNorm", "_fcsClave"];
let codigo = "";
for (const n of NOMBRES) {
  const re = new RegExp("^function " + n + "\\s*\\([\\s\\S]*?^\\}", "m");
  const m = re.exec(src);
  if (!m) { fallos.push("no encontré function " + n + "() en index.html"); continue; }
  codigo += m[0] + "\n";
}

if (!fallos.length) {
  const GONDOLA = {};
  ["437E", "438E", "439E", "809E"].forEach(function (c) { GONDOLA[c + " LK"] = 1; GONDOLA[c + " CH"] = 1; });
  const ctx = { window: { GONDOLA: GONDOLA }, console: console };
  ctx.globalThis = ctx;
  try { vm.runInNewContext(codigo, ctx); }
  catch (e) { fallos.push("no pude evaluar las funciones del front: " + e.message); }

  /* ── 2. Artículo y empresa, por separado ────────────────────────────────── */
  const CASOS = [
    // [cod crudo de Entregas_Virgilio, NP,   artículo, empresa, por qué]
    ["026L",  "CH 0030", "26",   "LK", "no dual con L: la L sólo dice de qué góndola salió"],
    ["066L",  "CH 0030", "66",   "LK", "idem, otro código del mismo pedido"],
    ["505L",  "CH 0031", "505",  "LK", "idem"],
    ["598EL", "CH 0031", "598E", "LK", "termina en EL: la E queda, la L se va"],
    ["438EL", "CH 0030", "438E", "LK", "DUAL con L: manda la L (LK), NO la NP (Chef)"],
    ["439EL", "44600",   "439E", "LK", "DUAL con L en NP de ISIS de Chef: igual LK"],
    ["438E",  "CH 0030", "438E", "CH", "dual SIN L: ahí sí manda la NP"],
    ["438E",  "98615",   "438E", "LK", "dual sin L, NP de Loekemeyer"],
    ["505",   "98615",   "505",  "LK", "código normal"],
    ["026",   "CH 0030", "26",   null, "sin L en NP de Chef: ver la nota de abajo"],
  ];

  /* ⚠ `empresa: null` = el front y la base NO usan el mismo criterio, a propósito.
     En un código NO dual la base la resuelve por el ARTÍCULO (`gv_empresa_de_articulo`,
     regla v19.26 de Luis: *"en un código no dual la empresa la da el artículo"*), y el
     front la resuelve por la NP. No tiene consecuencia: `pkCodEmpresa` sólo le pega el
     sufijo si esa góndola EXISTE, y "26 CH" no existe, así que el picking termina en el
     mismo lugar. Donde la empresa sí decide algo —los 4 duales— los dos coinciden, y eso
     es lo que este test verifica. */

  if (!fallos.length) {
    CASOS.forEach(function (c) {
      const cod = c[0], np = c[1], art = c[2], emp = c[3], porque = c[4];
      let resuelto;
      try { resuelto = ctx.pkResolveArt(cod, np); }
      catch (e) { fallos.push("pkResolveArt('" + cod + "','" + np + "') explotó: " + e.message); return; }

      const dioArt = ctx._ocgNorm(ctx.codBase(resuelto));
      const dioEmp = ctx.pkEmpresaArt(cod, np);
      if (dioArt !== art) {
        fallos.push("el ARTÍCULO de '" + cod + "' (NP " + np + ") dio '" + dioArt + "' y la base da '" +
          art + "' — " + porque);
      }
      if (emp !== null && dioEmp !== emp) {
        fallos.push("la EMPRESA de '" + cod + "' (NP " + np + ") dio '" + dioEmp + "' y la base da '" +
          emp + "' — " + porque);
      }
    });

    /* ── 3. La clave del badge es artículo + empresa, nunca el string pegado ── */
    if (ctx._fcsClave("438E LK") !== "438E|LK") {
      fallos.push("_fcsClave('438E LK') dio '" + ctx._fcsClave("438E LK") +
        "': tiene que partir el sufijo heredado en artículo + empresa ('438E|LK').");
    }
    if (ctx._fcsClave("26", "LK") !== "26|LK") {
      fallos.push("_fcsClave('26','LK') dio '" + ctx._fcsClave("26", "LK") + "' y esperaba '26|LK'.");
    }
    if (ctx._fcsClave("438E LK") === ctx._fcsClave("438E CH")) {
      fallos.push("_fcsClave da lo mismo para las dos empresas del dual: el badge las contaría juntas.");
    }

    /* ── 4. Candado invertido: la regla de la L no puede depender de la NP ──── */
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

/* ── 5. El front lee el número de la FILA, no de un cruce por código ───────── */
if (!/_fcArtCajas\s*=\s*function\s*\(a\)/.test(src)) {
  fallos.push("_fcArtCajas volvió a recibir un código suelto: el número de FC s/Salida sale de " +
    "`fc_sin_salida` de la propia fila, que el backend ya resolvió por artículo + empresa. " +
    "Cruzando por código, `codBase` le da las mismas cajas a las DOS filas de un dual.");
}
if (/_fcArt\[_ocgNorm\(codBase\(/.test(src)) {
  fallos.push("volvió el fallback `_fcArt[_ocgNorm(codBase(cod))]`: ése es el que contaba doble en los duales");
}

/* ── 6. El SQL del repo tiene que seguir teniendo las piezas ───────────────── */
const sqlPath = path.join(__dirname, "..", "sql", "gv_fc_sin_salida_codigo_l_v2112.sql");
if (!fs.existsSync(sqlPath)) {
  fallos.push("falta sql/gv_fc_sin_salida_codigo_l_v2112.sql");
} else {
  /* ⚠ Sacar los comentarios ANTES de buscar, mismo criterio que gv_reglas_perdidas: el
     archivo NOMBRA el bug en la nota de rollback, y sin esto los candados invertidos se
     disparan contra su propia documentación (pasó, 22/09). */
  const sql = fs.readFileSync(sqlPath, "utf8").replace(/\/\*[\s\S]*?\*\//g, "").replace(/--[^\n]*/g, "");
  if (!/gv_cod_stock_de_entrega\s*\(\s*e\.cod_art/.test(sql)) {
    fallos.push("la vista ya no resuelve el artículo con gv_cod_stock_de_entrega(e.cod_art, …)");
  }
  if (!/gv_empresa_de_entrega\s*\(\s*e\.cod_art/.test(sql)) {
    fallos.push("la vista ya no publica la empresa en su columna: sin eso el dual no se desambigua");
  }
  if (!/security_invoker\s*=\s*true/.test(sql)) {
    fallos.push("el .sql perdió el security_invoker: la vista correría como postgres y saltearía la RLS");
  }
  if (/norm_cod\s*\(\s*e\.cod_art\s*\)\s+AS\s+cod/i.test(sql)) {
    fallos.push("volvió el norm_cod(e.cod_art) AS cod: dejaba la L pegada al código");
  }
  if (/\|\|\s*'\s'\s*\|\|\s*(x\.)?emp\b/.test(sql)) {
    fallos.push("el SQL volvió a CONCATENAR el código con la empresa ('438E' || ' ' || 'LK'). " +
      "Luis, 22/09: ese código no existe — la empresa va en su propia columna.");
  }
  if (!/norm_cod\(scr\.cod_base\)/.test(sql)) {
    fallos.push("el refresh ya no cruza por cod_base: con `scr.cod = fc.cod` los duales quedan en 0");
  }
}

if (fallos.length) {
  console.error("✗ fcs-codigo-l: " + fallos.length + " problema(s)\n  - " + fallos.join("\n  - "));
  process.exit(1);
}
console.log("✓ fcs-codigo-l: artículo y empresa van separados — 10 casos, front y base coinciden");
