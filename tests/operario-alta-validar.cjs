/* v27.51 (Thomas) — Validar Operarios: el operario que no está en la lista ni tiene legajo
   tipea su nombre y entra (legajo 600, nombre sellado), y queda en GV_Operario_Alta para que un
   admin lo valide (Configuración → Validar Operarios), le dé legajo y lo ponga en la lista del login.
   Candado estático sobre index.html: las dos puntas (login + admin) tienen que seguir cableadas. */
const path = require("path"), fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
const fallas = [];
const exige = (re, msg) => { if (!re.test(src)) fallas.push(msg); };

// --- Login: opción de entrar con el nombre bajo «No estoy en la lista» (tvLegajoStep) ---
exige(/id="nombreLoginInput"/, "falta el input de nombre en el login");
exige(/onclick="loginConNombre\(\)"/, "falta el botón «Entrar con mi nombre»");
exige(/window\.loginConNombre = async function/, "falta la función loginConNombre");
exige(/rpc\/gv_operario_alta_crear/, "loginConNombre no registra el alta (gv_operario_alta_crear)");
exige(/const emp = \{ legajo: legRpc \|\| INTERVIEW_LEGAJO,/, "el login por nombre no usa el legajo de entrevista propio (v28.66; 600 de respaldo)");

// --- Admin: botón en Configuración + overlay + funciones ---
exige(/onclick="cfgGo\(openValidarOperarios\)"/, "falta el botón «Validar Operarios» en Configuración");
exige(/id="validarOperariosOverlay"/, "falta el overlay de Validar Operarios");
exige(/function openValidarOperarios\(/, "falta openValidarOperarios");
exige(/sb\.rpc\("gv_operario_alta_lista"\)/, "no lee la lista (gv_operario_alta_lista)");
exige(/sb\.rpc\("gv_operario_alta_validar"/, "no valida (gv_operario_alta_validar)");
exige(/sb\.rpc\("gv_operario_alta_sacar"/, "no saca (gv_operario_alta_sacar)");
// el badge de pendientes se refresca al abrir Configuración
exige(/voLoadBadge\(\);.*v27\.37|try \{ voLoadBadge\(\); \} catch/, "Configuración no refresca el badge de pendientes");
// no se puede validar con un legajo prohibido (lo frena el front además del backend)
exige(/leg === "0" \|\| leg === "1" \|\| esLegajoEntrevista\(leg\)\) \{ voSetStatus/, "voValidar no bloquea legajo 0/1/600/6001-6999");

if (fallas.length) { console.log("operario-alta-validar: ✗ FAIL\n  - " + fallas.join("\n  - ")); process.exit(1); }
console.log("operario-alta-validar: estático ✓ OK");
process.exit(0);
