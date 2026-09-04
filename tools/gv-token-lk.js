#!/usr/bin/env node
/* ══════════════════════════════════════════════════════════════════════════
 * Genera el token del rol `gv_reader` de LK, para el armado automático de tandas
 * ══════════════════════════════════════════════════════════════════════════
 * Se corre UNA vez, en tu máquina. El JWT Secret de LK entra por variable de
 * entorno y NO se guarda en ningún lado: ni en el repo, ni en un archivo, ni
 * viaja por internet. Lo único que sale es el token.
 *
 * Uso:
 *   LK_JWT_SECRET='<el secret de LK>' node tools/gv-token-lk.js
 *
 * El secret está en: Supabase → proyecto de LK (kwkclwhmoygunqmlegrg) →
 * Project Settings → API → JWT Settings → JWT Secret → Reveal.
 *
 * Lo que imprime va a Virgilio → Edge Functions → Secrets, como
 * `GV_LK_SERVICE_KEY`.
 *
 * QUÉ PUEDE HACER ESE TOKEN (medido el 2026-09-04, no supuesto):
 *   · ejecutar 3 funciones: gv_pedidos_web_np_lk, gv_pedidos_web_np_chef,
 *     gv_cods_chef_de_lk
 *   · leer 0 tablas y 0 vistas   (la anon key, que es pública, lee 192)
 *   · no es superusuario, no tiene bypassrls, no se puede loguear con password
 * Las otras funciones que alcanza son las que ya alcanza `anon` con la key
 * pública del front: no agrega superficie.
 *
 * Sin dependencias: usa el `crypto` de Node. Probado con Node 20.
 * ══════════════════════════════════════════════════════════════════════════ */

const crypto = require("node:crypto");

const SECRET = process.env.LK_JWT_SECRET;
const REF = process.env.LK_PROJECT_REF || "kwkclwhmoygunqmlegrg";
const ROL = process.env.LK_ROL || "gv_reader";
const ANIOS = Number(process.env.LK_ANIOS || 5);

if (!SECRET) {
  console.error(
    "Falta LK_JWT_SECRET.\n\n" +
    "  LK_JWT_SECRET='<el secret>' node tools/gv-token-lk.js\n\n" +
    "Está en Supabase → proyecto LK → Project Settings → API → JWT Settings → JWT Secret.",
  );
  process.exit(1);
}

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const ahora = Math.floor(Date.now() / 1000);
const vence = ahora + ANIOS * 365 * 24 * 60 * 60;

const cuerpo = b64({ alg: "HS256", typ: "JWT" }) + "." +
  b64({ iss: "supabase", ref: REF, role: ROL, iat: ahora, exp: vence });
const firma = crypto.createHmac("sha256", SECRET).update(cuerpo).digest("base64url");

console.log(`\nToken para el rol "${ROL}" del proyecto ${REF}`);
console.log(`Vence: ${new Date(vence * 1000).toISOString().slice(0, 10)} (${ANIOS} años)\n`);
console.log(cuerpo + "." + firma);
console.log(
  "\nPegalo en: Supabase → proyecto VIRGILIO (hrxfctzncixxqmpfhskv) →\n" +
  "Edge Functions → Secrets → Add new secret\n" +
  "  Name:  GV_LK_SERVICE_KEY\n" +
  "  Value: (el token de arriba)\n",
);
