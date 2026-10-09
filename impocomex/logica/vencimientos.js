// Cuanto falta para que venza un certificado. Fechas 'YYYY-MM-DD', contadas en dias de
// calendario con la fecha local de la PC (la base usa UTC y de noche daria un dia menos).
// Plan: .planning/PLAN-2026-09-14-vencimientos-inal.md

// Mismo umbral que impo_comex.v_certificados_estado ("por_vencer").
export const AVISO_DIAS = 90;

const partes = (iso) => {
  const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
  return { y, m, d };
};
const aDia = ({ y, m, d }) => Date.UTC(y, m - 1, d) / 86400000;

export function hoyLocal(ahora = new Date()) {
  const dos = (n) => String(n).padStart(2, '0');
  return `${ahora.getFullYear()}-${dos(ahora.getMonth() + 1)}-${dos(ahora.getDate())}`;
}

export function diasEntre(desde, hasta) {
  return aDia(partes(hasta)) - aDia(partes(desde));
}

// Suma meses; si el dia no existe en el mes destino (31 -> febrero) queda en el ultimo dia.
function sumarMeses({ y, m, d }, n) {
  const total = y * 12 + (m - 1) + n;
  const ny = Math.floor(total / 12);
  const nm = total - ny * 12 + 1;
  const ultimo = new Date(Date.UTC(ny, nm, 0)).getUTCDate();
  return { y: ny, m: nm, d: Math.min(d, ultimo) };
}

// Diferencia de calendario entre dos fechas (desde <= hasta).
export function descomponer(desde, hasta) {
  const a = partes(desde), b = partes(hasta);
  let meses = (b.y - a.y) * 12 + (b.m - a.m);
  if (aDia(sumarMeses(a, meses)) > aDia(b)) meses--;
  const dias = aDia(b) - aDia(sumarMeses(a, meses));
  return { anios: Math.floor(meses / 12), meses: meses % 12, dias };
}

const plural = (n, uno, varios) => `${n} ${n === 1 ? uno : varios}`;

function enPalabras({ anios, meses, dias }) {
  const t = [];
  if (anios) t.push(plural(anios, 'año', 'años'));
  if (meses) t.push(plural(meses, 'mes', 'meses'));
  if (dias || !t.length) t.push(plural(dias, 'día', 'días'));
  return t.length > 1 ? `${t.slice(0, -1).join(', ')} y ${t[t.length - 1]}` : t[0];
}

// { dias, estado, texto } para un vencimiento. Sin fecha -> dias null.
export function falta(vencimiento, hoy = hoyLocal()) {
  if (!vencimiento) return { dias: null, estado: 'sin_vencimiento', texto: 'Sin fecha de vencimiento' };
  const dias = diasEntre(hoy, vencimiento);
  if (dias === 0) return { dias, estado: 'por_vencer', texto: 'Vence hoy' };
  if (dias < 0) return { dias, estado: 'vencido', texto: `Venció hace ${enPalabras(descomponer(vencimiento, hoy))}` };
  return { dias, estado: dias <= AVISO_DIAS ? 'por_vencer' : 'vigente', texto: enPalabras(descomponer(hoy, vencimiento)) };
}

// % de la vigencia ya transcurrido (0-100). null si falta la emision o el vencimiento.
export function vigenciaUsada(emision, vencimiento, hoy = hoyLocal()) {
  if (!emision || !vencimiento) return null;
  const total = diasEntre(emision, vencimiento);
  if (total <= 0) return null;
  return Math.max(0, Math.min(100, Math.floor((diasEntre(emision, hoy) * 100) / total)));
}
