// v21.87 — el hook "¿quién sos?" (scripts/claude-quien-habla-prompt.sh) tiene que
// DETECTAR la respuesta y CALLARSE después. Luis, 23/09: "seguís preguntando incluso
// después de que te contestan". Su primer mensaje fue "luis\n<pedido largo>" y la
// versión anterior no lo veía (sólo "soy X" o mensajes de ≤ 3 palabras).
const { execFileSync } = require("child_process");
const fs = require("fs"), os = require("os"), path = require("path");
const HOOK = path.join(__dirname, "..", "scripts", "claude-quien-habla-prompt.sh");
const home = fs.mkdtempSync(path.join(os.tmpdir(), "qh-"));
const env = { ...process.env, HOME: home, TMPDIR: home };
const tr = path.join(home, "t.jsonl");
fs.writeFileSync(tr, [
  { type: "user", message: { role: "user", content: "luis\nhabia puesto una traba…" } },
  { type: "assistant", message: { role: "assistant", content: [{ type: "text", text: "ok" }] } },
].map(o => JSON.stringify(o)).join("\n"));

function t(sid, prompt, transcript = "") {
  const out = execFileSync("bash", [HOOK], { input: JSON.stringify({ session_id: sid, prompt, transcript_path: transcript }), env }).toString();
  if (!out.trim()) return "silencio";
  const c = JSON.parse(out).hookSpecificOutput.additionalContext;
  let m = c.match(/CONFIRMADA: \*\*([^*]+)\*\*.*employee_id (\d+)/);
  if (m) return m[1] + "#" + m[2];
  if (/AMBIGUO/.test(c)) return "ambiguo";
  return "pregunta";
}
// v21.91 (Luis: "que acepte otros nombres, el chiste es mandar tareas a Planify"): el padrón
// sale de scripts/planify-padron.json y la respuesta trae el employee_id.
const casos = [
  ["a", "luis\nhabia puesto una traba para mover NPs", "", "Luis Ignacio Rial Otero#52"],
  ["a", "otra cosa sin nombre", "", "silencio"],          // ya contestó: se calla
  ["b", "Luis pidió que muevas la tanda E74A", "", "pregunta"], // de pasada no cuenta
  ["c", "soy marianela, fijate la tanda", "", "Becker Marianela#38"],
  ["d", "Thomas: mirá esto", "", "Thomas#20"],
  ["e", "hola, necesito mover una tanda de martin", "", "pregunta"],
  ["f", "dale seguí", tr, "pregunta"],                   // la charla NO se relee
  ["g", "martin", "", "ambiguo"],                        // Cornejo y Pregelj
  ["g", "soy martin cornejo", "", "Cornejo Martin#34"],  // el apellido lo resuelve
  ["h", "Giuliana\nnecesito un reporte", "", "Giuliana De La Vega#63"],
  ["i", "vivi", "", "Gauna Viviana#4"],
  ["j", "tomas", "", "ambiguo"],                         // Beviglia y Gonzalez
  ["k", "Juan Cruz: mirá esto", "", "Juan Cruz Karaygan#51"],
  ["l", "hola elías", "", "Elias Irace#1"],
];
let mal = 0;
for (const [sid, pr, trp, esp] of casos) {
  const r = t(sid, pr, trp);
  const ok = r === esp; if (!ok) mal++;
  console.log(`${ok ? "ok  " : "FAIL"} ${JSON.stringify(pr).slice(0, 45).padEnd(46)} -> ${r} (esperado ${esp})`);
}
fs.rmSync(home, { recursive: true, force: true });
console.log(mal ? `claude-quien-habla: ${mal} FALLAN` : "claude-quien-habla OK");
process.exit(mal ? 1 : 0);
