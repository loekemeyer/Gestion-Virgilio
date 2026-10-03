# -*- coding: utf-8 -*-
"""
PUNTAJE 1-10 DE PICKING POR OPERARIO (Luis, 03/10/2026: "un calculador para definir en puntos del 1 al 10 qué tan bueno fue
un empleado... sobre todo para cuando traigo un empleado nuevo... de manera objetiva y en función de los datos").
Solo lectura. Lee d17_tandas_dificultad.json (al lado) y, si está, ../../oper.json no: los nombres van acá.
Escribe d17_puntaje_operario.json y d17_puntaje_operario.md (la sección (j) del doc).

  índice de una tanda   = tamaño esperado (esquema D17) ÷ tiempo real (picking puro + cola topeada a 30 min)
  índice del operario   = Σ tamaños ÷ Σ tiempos reales (no el promedio de los cocientes: una tanda de 4 min no vale lo que una de 60)
  puntaje               = 5,5 + 10 × (índice − 1), redondeado y acotado a 1..10
                          -> 1 punto = 10 % de velocidad; 5 y 6 = el promedio del depósito en los 60 días de la calibración;
                             10 = 45 % más rápido que el promedio; 1 = 45 % más lento.
  ventana               = las ÚLTIMAS 20 tandas (lo que hace hoy) y el acumulado del período (lo que hizo). Un operario nuevo
                          arranca lento: se lee la tendencia por tanda 1-10, 11-20, 21-30...
  margen                = bootstrap sobre sus propias tandas: intervalo del 90 % del índice con n = 5 / 10 / 20 tandas, en puntos.
                          Con menos de 10 tandas el puntaje es PROVISORIO y no se publica solo.
"""
import json, os, random, statistics as st, collections
HERE = os.path.dirname(os.path.abspath(__file__))
NOM = {"104": "J. Moncayo «J. Colombia»", "277": "J. Cartaya «Jhonny»", "122": "Villalba", "504": "Latronico", "237": "F. Ortiz",
       "8": "Farias", "600": "(Entrevista)", "94": "Tevez"}
VENTANA, MIN_PUBLICA = 20, 10
def f(x, d=2):
    s = f"{x:,.{d}f}".replace(",", "X").replace(".", ",").replace("X", "."); return s
def idx(rs): return sum(r["tamano"] for r in rs) / sum(r["target"] for r in rs)
def puntaje(i): return max(1, min(10, round(5.5 + 10 * (i - 1))))
rows = [r for r in json.load(open(os.path.join(HERE, "d17_tandas_dificultad.json"))) if not r["outlier"]]
by = collections.defaultdict(list)
for r in sorted(rows, key=lambda r: (r["dia"], r["t"])): by[r["l"]].append(r)
random.seed(7); out = []
for l, rs in sorted(by.items(), key=lambda kv: -idx(kv[1][-VENTANA:])):
    ult = rs[-VENTANA:]; i_ult, i_tot = idx(ult), idx(rs)
    marg = {}
    for n in (5, 10, 20):
        if len(rs) >= n:
            bs = sorted(idx(random.choices(rs, k=n)) for _ in range(3000)); lo, hi = bs[int(0.05 * len(bs))], bs[int(0.95 * len(bs))]
            marg[n] = round(10 * (hi - lo) / 2, 1)
    tramos = [round(idx(rs[k:k + 10]), 2) for k in range(0, len(rs), 10)]
    out.append({"legajo": l, "nombre": NOM.get(l, ""), "tandas": len(rs), "cajas": round(sum(r["caj"] for r in rs)), "desde": rs[0]["dia"], "hasta": rs[-1]["dia"],
                "indice_ultimas_20": round(i_ult, 3), "puntaje_ultimas_20": puntaje(i_ult), "indice_periodo": round(i_tot, 3), "puntaje_periodo": puntaje(i_tot),
                "publicable": len(rs) >= MIN_PUBLICA, "margen_puntos_90pct": marg, "indice_por_tramo_de_10": tramos,
                "mediana_por_tanda": round(st.median(r["indice"] for r in rs), 2)})
json.dump(out, open(os.path.join(HERE, "d17_puntaje_operario.json"), "w"), ensure_ascii=False, indent=1)
md = ["## (j) Puntaje 1-10 por operario (Luis, 03/10: *\"un calculador... objetivo y en función de los datos\"*)", "",
      "**Puntaje = 5,5 + 10 × (índice − 1)**, redondeado y acotado a 1..10, con **índice = Σ tamaños esperados ÷ Σ tiempos reales** (picking puro + cola topeada) de sus tandas. "
      "Un punto es un 10 % de velocidad; 5 y 6 son el promedio del depósito en estos 60 días; 10 es un 45 % más rápido que el promedio y 1 un 45 % más lento. "
      f"Se mira sobre las **últimas {VENTANA} tandas** (lo que hace hoy) y sobre el período entero. Con menos de {MIN_PUBLICA} tandas el puntaje es provisorio. "
      "Lo calcula `puntaje_operario.py` (sólo lectura) y queda en `d17_puntaje_operario.json`.", "",
      "| legajo | nombre | tandas | cajas | últimas 20: índice → puntaje | período: índice → puntaje | ± puntos (90 %) con 5 / 10 / 20 tandas | índice por tramo de 10 tandas |",
      "|---|---|---|---|---|---|---|---|"]
for o in out:
    m = o["margen_puntos_90pct"]; mm = " / ".join(f(m[n], 1) if n in m else "—" for n in (5, 10, 20))
    pub = "" if o["publicable"] else " (provisorio)"
    md.append(f"| {o['legajo']} | {o['nombre']} | {o['tandas']} | {o['cajas']:,}".replace(",", ".") + f" | {f(o['indice_ultimas_20'])} → **{o['puntaje_ultimas_20']}**{pub} | {f(o['indice_periodo'])} → {o['puntaje_periodo']}{pub} | {mm} | {' · '.join(f(t) for t in o['indice_por_tramo_de_10'])} |")
pub = [o for o in out if o["publicable"]]
md += ["", "Lo que hay que saber para leerlo:", "",
       f"- **El margen es grande con pocas tandas.** Con 10 tandas el puntaje de un operario se mueve ±{f(min(m['margen_puntos_90pct'][10] for m in pub if 10 in m['margen_puntos_90pct']),1)} a ±{f(max(m['margen_puntos_90pct'][10] for m in pub if 10 in m['margen_puntos_90pct']),1)} puntos; con 20, ±{f(min(m['margen_puntos_90pct'][20] for m in pub if 20 in m['margen_puntos_90pct']),1)} a ±{f(max(m['margen_puntos_90pct'][20] for m in pub if 20 in m['margen_puntos_90pct']),1)}. "
       "Un 7 y un 5 con 10 tandas pueden ser el mismo operario; un 9 y un 3 no. El margen es de cada uno: el que es parejo (122, 504) se lee con menos tandas que el que alterna (104).",
       "- **El nuevo arranca más lento y sube.** " + " · ".join(f"{o['legajo']}: {' → '.join(f(t) for t in o['indice_por_tramo_de_10'][:3])}" for o in pub if o["tandas"] >= 30) + ". Por eso se publican las últimas 20 y la curva por tramo, no sólo el acumulado: con un nuevo, lo que importa es si el tramo 3 es mejor que el 1.",
       "- **Es velocidad, no calidad.** Cajas de menos, faltantes mal declarados y artículos salteados no entran acá (están medidos aparte en `docs/PICKING-HUECOS-Y-CAJAS-DE-MENOS-D9.md`). Un 9 que deja cajas no es un 9.",
       "- **La escala se ancla al promedio de la calibración (60 días, 338 tandas).** Si el depósito entero se vuelve más rápido, todos suben de puntaje; se recalibra el esquema (y con él el 5,5) cuando se recalibre el tamaño, no antes.",
       "- **El índice del período es Σ ÷ Σ, no el promedio de los cocientes**: la mediana por tanda (columna `mediana_por_tanda` del json) sale más alta porque las tandas chicas, que son muchas, se hacen rápido; el Σ ÷ Σ pesa cada tanda por sus minutos.", ""]
open(os.path.join(HERE, "d17_puntaje_operario.md"), "w").write("\n".join(md))
for o in out: print(f"{o['legajo']:4} {o['nombre'][:24]:24} {o['tandas']:3} tandas · últimas {VENTANA}: {f(o['indice_ultimas_20'])} → {o['puntaje_ultimas_20']:2} · período: {f(o['indice_periodo'])} → {o['puntaje_periodo']:2} · ± {o['margen_puntos_90pct']} · tramos {o['indice_por_tramo_de_10']}")
