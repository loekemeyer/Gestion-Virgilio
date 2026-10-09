// Búsqueda por palabras en el manual: el respaldo cuando no hay ningún LLM disponible.
// Sin tipos a propósito: tests/ayuda-chat.cjs la corre en Node tal cual.
const VACIAS = new Set(("a al ante con de del el en es la las lo los me mi para por que se si sin su te tu un una y o como cuando donde hago hacer tengo puedo quiero cual cuales hay esta este esto eso").split(" "));
export function norm(s) {
  return String(s || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9ñ ]+/g, " ");
}
export function secciones(md) {
  const out = [];
  let cur = null;
  for (const ln of String(md).split("\n")) {
    if (ln.startsWith("## ")) { cur = { titulo: ln.slice(3).trim(), texto: "" }; out.push(cur); }
    else if (cur) cur.texto += ln + "\n";
  }
  return out;
}
export function buscarEnManual(md, pregunta, max) {
  // raíz simple: «bajo», «bajar» y «bajada» comparten «baj»
  const terms = norm(pregunta).split(/\s+/).filter((t) => t.length >= 2 && !VACIAS.has(t))
    .map((t) => t.length <= 3 ? t : t.slice(0, Math.max(3, t.length - 2)));
  if (!terms.length) return [];
  const sc = secciones(md).map((s) => {
    const tit = norm(s.titulo), tx = norm(s.texto);
    let p = 0, hits = 0;
    for (const t of terms) {
      if (tit.includes(t) || tx.includes(t)) hits++;
      if (tit.split(/\s+/).some((w) => w.startsWith(t))) p += 5; else if (tit.includes(t)) p += 3;
      const n = tx.split(t).length - 1; p += Math.min(n, 3);
    }
    // al menos la mitad de las palabras tiene que estar: si no, es otro tema
    return { s, p: hits * 2 >= terms.length ? p : 0 };
  }).filter((x) => x.p > 0).sort((a, b) => b.p - a.p);
  return sc.slice(0, max || 1).map((x) => x.s);
}
