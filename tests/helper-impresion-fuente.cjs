// v26.29 — el fuente del helper local de impresión vive en tools/helper-impresion/.
// Candado: (A) están los archivos; (B) el repo es PÚBLICO, así que lo de cada PC (config con nombres
// reales de impresoras, log) y los binarios (SumatraPDF.exe, el .exe) no se versionan; (C) el contrato
// del helper es el que el front usa (GET /, POST /print?tipo=, loopback, CORS con Private-Network).
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const root = path.join(__dirname, "..");
const dir = path.join(root, "tools", "helper-impresion");
let fallas = 0;
const chk = (n, c, d) => { console.log((c ? "  ✓ " : "  ✗ ") + n + (d ? " — " + d : "")); if (!c) fallas++; };

// (A)
for (const f of ["src/ImpresionVirgilio.cs", "compilar.bat", "README.md", "LEEME.txt",
                 "virgilio-impresion-EJEMPLO.json", ".gitignore"])
  chk("A existe " + f, fs.existsSync(path.join(dir, f)));

// (B) lo de cada PC y los binarios quedan afuera
const git = (...a) => { try { return execFileSync("git", a, { cwd: root, encoding: "utf8" }); } catch (e) { return null; } };
const ign = f => git("check-ignore", "-q", "tools/helper-impresion/" + f) !== null;
for (const f of ["SumatraPDF.exe", "Impresion Virgilio.exe", "virgilio-impresion.log",
                 "virgilio-impresion-DEPOSITO-PC.json", "virgilio-impresion-DISEÑO-PC.json"])
  chk("B ignorado " + f, ign(f));
chk("B el EJEMPLO NO está ignorado", !ign("virgilio-impresion-EJEMPLO.json"));
const ls = git("ls-files", "tools/helper-impresion") || "";
const versionados = ls.split("\n").filter(Boolean);
chk("B ningún .exe versionado", !versionados.some(f => /\.exe$/i.test(f)), versionados.join(", "));
chk("B ninguna config de PC versionada",
    !versionados.some(f => /virgilio-impresion-.*\.json$/i.test(f) && !/EJEMPLO\.json$/.test(f)));
chk("B ningún log versionado", !versionados.some(f => /\.log$/i.test(f)));
const ej = JSON.parse(fs.readFileSync(path.join(dir, "virgilio-impresion-EJEMPLO.json"), "utf8"));
chk("B el EJEMPLO tiene el formato { pc, puerto, reglas[] }",
    typeof ej.pc === "string" && ej.puerto === 17777 && Array.isArray(ej.reglas) &&
    ej.reglas.every(r => ["picking", "armado", "facturado"].includes(r.tipo) && typeof r.impresora === "string"));

// (C) contrato ≡ front
const cs = fs.readFileSync(path.join(dir, "src", "ImpresionVirgilio.cs"), "utf8");
const idx = fs.readFileSync(path.join(root, "index.html"), "latin1");
chk("C escucha sólo en loopback", /new TcpListener\(IPAddress\.Loopback/.test(cs));
chk("C GET / contesta «Impresion Virgilio OK»", /"Impresion Virgilio OK v"/.test(cs));
chk("C atiende /print y lee ?tipo=", /StartsWith\("\/print"\)/.test(cs) && /tipo/.test(cs));
chk("C CORS con Allow-Private-Network", /Access-Control-Allow-Private-Network: true/.test(cs));
chk("C el front pega a /print?tipo=", /gvHelperUrl\("\/print\?tipo="/.test(idx));
// v26.58 — el ping lleva la versión ("Impresion Virgilio OK v1.2.0"): el front mira el HTTP 200, no el texto.
const vivo = (idx.match(/async function helperVivo\(\)\{[\s\S]*?\n\}/) || [""])[0];
chk("C helperVivo da vivo por el HTTP 200 (r.ok), no por el texto del ping",
    /ok = r\.ok;/.test(vivo) && !/Impresion Virgilio/.test(vivo));
chk("C el puerto por defecto es el mismo (17777)", /17777/.test(cs) && /17777/.test(idx));
// v26.59 — la versión del fuente y la del README van juntas, y el EJEMPLO trae el papel global (v1.2.0).
const verCs = (cs.match(/VERSION = "([0-9.]+)"/) || [])[1];
const verRd = (fs.readFileSync(path.join(dir, "README.md"), "utf8").match(/Versión: \*\*([0-9.]+)\*\*/) || [])[1];
chk("C la versión del fuente es la del README", !!verCs && verCs === verRd, verCs + " / " + verRd);
chk("C el EJEMPLO trae el tamaño de hoja global (papel)", typeof ej.papel === "string");
chk("C compilar.bat compila src\\ImpresionVirgilio.cs", /src\\ImpresionVirgilio\.cs/.test(
    fs.readFileSync(path.join(dir, "compilar.bat"), "utf8")));

console.log(fallas ? "\nFALLAN " + fallas : "\nhelper-impresion-fuente OK");
process.exit(fallas ? 1 : 0);
