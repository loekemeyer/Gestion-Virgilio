# -*- coding: utf-8 -*-
"""
ESQUEMA FINAL — corrida COLA (sintesis de los 3 modelos reajustados con neto_cola + los 2 veredictos).
Gana el RESTRINGIDO (NNLS monotono por altura + prior lambda = 10 hacia las medianas medidas por altura), con las
correcciones que los dos jueces marcaron como verificadas:
  1. La cola NO se reajusta cruda: es un fijo por tanda que ninguna variable de la tanda predice (R2 0,02-0,05), y
     reajustar sobre neto_cola crudo le carga +0,18 min por parada que son DOS tandas (E37F 196 min, D52C 119).
     Target = neto_sh + cola TOPEADA (juez 1: 30 min; juez 2: 60 min -> se ajusta con 30 y se mide 60 como sensibilidad).
  2. Los 2 'cap' con cola de horas (D40F 519 min, D67D 320 min; neto_cola > 240) son outliers EXPLICITOS: fuera del ajuste.
  3. DIFICULTAD sin la constante: (tamano - arranque) / cajas (los dos jueces, y ya estaba en la sintesis anterior).
  4. MX y F sin prior son ruido (bootstrap desde 0): se ATAN a R4 (MX = 2 x R4, F = R4), el promedio con criterio de
     lo que recomendaron los jueces (MX 1,2 / 1,0 · F 0,5 / 0,6).
  5. Del esquema anterior (sintesis sobre neto_sh, verificada por los jueces de esa corrida): cajas topeadas a 30 por
     linea y arranque proporcional hasta 5 lineas (con constante fija el modelo sobrepredecia 85 % las tandas chicas).
Modelo: y = cfijo + c_arr*min(n,5)/5 + c_par*paradas + c_caj*caj30 + sum_h c_h*n_h + MX*n_MX + F*n_F,  todo >= 0,
        c_h no decreciente con la altura dentro de A/P y dentro de B..N~ (piso + incrementos >= 0),
        penalizacion cuadratica (lambda = 10, pesada por lineas de la clase) hacia las medianas medidas en 60 dias.
Solo lectura. Lee ../d17_feat.json, ../d17_cods.json, ../cap_celdas.json, ../d17_stock_ini.json, ../m3.txt, ../oper.json,
../d17_restringido/resultado_cola.json, ../d17_v3_netosh/d17_esquema.json (para comparar; no se copia ningun numero a mano).
Escribe: ../d17_esquema.json, ../d17_tandas_dificultad.json, ../d17_esquema.md, y aca resultado_cola.json y salida_cola.txt
"""
import json, os, collections
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__)); UP = os.path.dirname(HERE)
out = []
def P(*a):
    s = " ".join(str(x) for x in a); out.append(s); print(s)
def f(x, d=1):
    if x is None or (isinstance(x, float) and np.isnan(x)): return "—"
    s = f"{x:,.{d}f}".replace(",", "X").replace(".", ",").replace("X", "."); return s.replace("-", "−", 1) if s.startswith("-") else s

# ------------------------------------------------------------------ datos
feat = json.load(open(os.path.join(UP, "d17_feat.json")))
cods = {r["t"]: r for r in json.load(open(os.path.join(UP, "d17_cods.json")))}
cap = json.load(open(os.path.join(UP, "cap_celdas.json")))
si = {(a, c): s for a, l, c, s in json.load(open(os.path.join(UP, "d17_stock_ini.json")))}
m3 = {k: float(v) for k, v in (kv.split(":") for kv in open(os.path.join(UP, "m3.txt")).read().strip().split(","))}
NOM = {o["l"]: o["nom"] for o in json.load(open(os.path.join(UP, "oper.json")))}
APODO = {"104": "«J. Colombia»", "277": "«Jhonny»"}
REST = json.load(open(os.path.join(UP, "d17_restringido", "resultado_cola.json")))          # refit crudo del modelador
V3 = json.load(open(os.path.join(UP, "d17_v3_netosh", "d17_esquema.json")))                 # sintesis anterior (neto_sh)
CL = ["A1","A2","A3","A4","A5","R1","R2","R3","R4","MX","F"]
TOPE_COLA = 30.0; TOPE_ALT = 60.0; CORTE_OUT = 240.0
outl = [r["t"] for r in feat if r["neto_cola"] > CORTE_OUT]
OUT = [r for r in feat if r["t"] in outl]
D = [r for r in feat if r["t"] not in outl]; N = len(D)
P(f"tandas {len(feat)} · outliers por regla (neto_cola > {f(CORTE_OUT,0)}): {outl} " +
  " · ".join(f"{r['t']} leg {r['l']} neto_sh {f(r['neto_sh'],1)} + cola {f(r['cola'],1)} '{r['cola_sig']}' = {f(r['neto_cola'],1)} min por {r['n']} lineas / {f(r['caj'],0)} cajas" for r in OUT) + f" · usadas {N}")
ysh = np.array([r["neto_sh"] for r in D]); cola = np.array([r["cola"] for r in D]); ycr = ysh + cola
y = ysh + np.minimum(cola, TOPE_COLA); y60 = ysh + np.minimum(cola, TOPE_ALT)
par = np.array([r["paradas"] for r in D], float); caj = np.array([r["caj"] for r in D]); n = np.array([r["n"] for r in D], float)
NH = {h: np.array([r["n_"+h] for r in D], float) for h in CL}
esc = np.array([r["esc"] for r in D], float); ninf = np.array([r["n_inferidas"] for r in D], float)
leg = np.array([r["l"] for r in D]); sig = np.array([r["cola_sig"] for r in D])
TOPE = 30; KARR = 5
def cajas_tope(rows, T):
    return np.array([sum(min(cj, T*ln) for cod, ln, cj, co, ex in cods[r["t"]]["cods"]) for r in rows])
caj30 = cajas_tope(D, TOPE)
colaF = np.array([r["cola"] for r in feat])
P(f"cola (340): mediana {f(np.median(colaF),1)} · media {f(colaF.mean(),1)} · p90 {f(np.percentile(colaF,90),1)} · p95 {f(np.percentile(colaF,95),1)} · > 60 min: " +
  ", ".join(f"{r['t']} {f(r['cola'],0)} '{r['cola_sig']}'" for r in sorted(feat, key=lambda r: -r["cola"]) if r["cola"] > 60) +
  f" · tipo: " + " · ".join(f"{k} {sum(1 for r in feat if r['cola_sig']==k)}" for k in ("sig","cap","cubierta")))
P(f"cola (338): suma cruda {f(cola.sum(),0)} min = {f(cola.sum()/ysh.sum()*100,1)} % de neto_sh · topeada a {f(TOPE_COLA,0)}: {f(np.minimum(cola,TOPE_COLA).sum(),0)} ({f(np.minimum(cola,TOPE_COLA).sum()/ysh.sum()*100,1)} %), "
  f"media {f(np.minimum(cola,TOPE_COLA).mean(),2)} · topeada a {f(TOPE_ALT,0)}: {f(np.minimum(cola,TOPE_ALT).sum(),0)} ({f(np.minimum(cola,TOPE_ALT).sum()/ysh.sum()*100,1)} %) · tandas tocadas por el tope: {int((cola>TOPE_COLA).sum())} / {int((cola>TOPE_ALT).sum())}")
P("cola por legajo (338): " + " · ".join(f"{L} med {f(np.median(cola[leg==L]),1)} media {f(cola[leg==L].mean(),1)} = {f(cola[leg==L].sum()/ysh[leg==L].sum()*100,0)} % de su neto_sh" for L in sorted(set(leg), key=lambda L: -int((leg==L).sum()))))
P(f"cajas reales {f(caj.sum(),0)} · con tope {TOPE}/linea {f(caj30.sum(),0)} ({f((1-caj30.sum()/caj.sum())*100,1)} % recortado en {int((caj30 < caj).sum())} tandas)")

# ------------------------------------------------------------------ NNLS (Lawson-Hanson)
def nnls(A, b, tol=1e-10):
    m, k = A.shape; x = np.zeros(k); Pm = np.zeros(k, bool); w = A.T @ (b - A @ x); it = 0
    while (~Pm).any() and (w[~Pm] > tol).any() and it < 50*k:
        it += 1; j = np.argmax(np.where(Pm, -np.inf, w)); Pm[j] = True
        while True:
            s = np.zeros(k); s[Pm] = np.linalg.lstsq(A[:, Pm], b, rcond=None)[0]
            if (s[Pm] > 0).all(): x = s; break
            neg = Pm & (s <= 0); al = np.min(x[neg] / (x[neg] - s[neg] + 1e-300))
            x = x + al*(s - x); Pm &= x > 1e-12; x[~Pm] = 0
        w = A.T @ (b - A @ x)
    return x

PRIOR = {"A1":16/60,"A2":23/60,"A3":23/60,"A4":50/60,"A5":64/60,"R1":16/60,"R2":20/60,"R3":26/60,"R4":37/60}
ROWS = {"A1":[0],"A2":[0,1],"A3":[0,1,2],"A4":[0,1,2,3],"A5":[0,1,2,3,4],"R1":[5],"R2":[5,6],"R3":[5,6,7],"R4":[5,6,7,8]}
PN = ["cfijo","arranque","parada","caja","A_base","A_i2","A_i3","A_i4","A_i5","R_base","R_i2","R_i3","R_i4","MX","F"]
LAM = 10.0; K_MX = 2.0; K_F = 1.0     # MX = K_MX x R4 · F = K_F x R4 (atadas; ver cabecera)
def design(idx, cj=None, arrK=KARR, extra=()):
    cj = caj30 if cj is None else cj; A = {h: NH[h][idx] for h in CL}
    cols = [np.ones(len(idx)), (np.minimum(n[idx], arrK)/arrK if arrK else np.zeros(len(idx))), par[idx], cj[idx],
            A["A1"]+A["A2"]+A["A3"]+A["A4"]+A["A5"], A["A2"]+A["A3"]+A["A4"]+A["A5"], A["A3"]+A["A4"]+A["A5"], A["A4"]+A["A5"], A["A5"],
            A["R1"]+A["R2"]+A["R3"]+A["R4"], A["R2"]+A["R3"]+A["R4"], A["R3"]+A["R4"], A["R4"], A["MX"], A["F"]] + [e[idx] for e in extra]
    return np.column_stack(cols)
def costs(p):
    c = {"cfijo": p[0], "arranque": p[1], "parada": p[2], "caja": p[3]}
    c["A1"] = p[4]; c["A2"] = c["A1"]+p[5]; c["A3"] = c["A2"]+p[6]; c["A4"] = c["A3"]+p[7]; c["A5"] = c["A4"]+p[8]
    c["R1"] = p[9]; c["R2"] = c["R1"]+p[10]; c["R3"] = c["R2"]+p[11]; c["R4"] = c["R3"]+p[12]; c["MX"] = p[13]; c["F"] = p[14]
    return c
def fit(idx, yy=None, lam=LAM, extra=(), atar=True, cj=None, arrK=KARR):
    """NNLS con prior; si atar: MX = K_MX*R4 y F = K_F*R4 (las columnas MX y F se absorben en la de R4 via sus multiplos)."""
    yy = y if yy is None else yy; X = design(idx, cj, arrK, extra)
    if atar:
        X = X.copy(); r4 = X[:, 12] + K_MX*X[:, 13] + K_F*X[:, 14]            # R_i4 pesa tambien a MX y F ...
        base = X[:, 9] + K_MX*X[:, 13] + K_F*X[:, 14]; i2 = X[:, 10] + K_MX*X[:, 13] + K_F*X[:, 14]; i3 = X[:, 11] + K_MX*X[:, 13] + K_F*X[:, 14]
        X[:, 9], X[:, 10], X[:, 11], X[:, 12] = base, i2, i3, r4             # ... porque R4 = base + i2 + i3 + i4
        X = X[:, [i for i in range(X.shape[1]) if i not in (13, 14)]]
    R = []; t = []
    for h, ix in ROWS.items():
        r = np.zeros(X.shape[1]); w = np.sqrt(lam*NH[h].sum()); r[[4+j for j in ix]] = w; R.append(r); t.append(w*PRIOR[h])
    if lam > 0: X = np.vstack([X, np.array(R)]); yy = np.concatenate([yy[idx], np.array(t)])
    else: yy = yy[idx]
    q = nnls(X, yy)
    if atar:
        r4 = q[9]+q[10]+q[11]+q[12]; q = np.concatenate([q[:13], [K_MX*r4, K_F*r4], q[13:]])
    return q
def predict(p, idx, cj=None, arrK=KARR, extra=()):
    return design(idx, cj, arrK, extra) @ p
def r2(a, b): return float(1 - np.sum((a-b)**2)/np.sum((a-a.mean())**2))
def rmse(a, b): return float(np.sqrt(np.mean((a-b)**2)))
ALL = np.arange(N)
def cv10(yy=None, seeds=(1,2,3,4,5), ytest=None, fitter=None):
    yy = y if yy is None else yy; ytest = yy if ytest is None else ytest; fitter = fitter or (lambda tr, te: predict(fit(tr, yy), te))
    es = []; r2s = []
    for sd in seeds:
        rg = np.random.default_rng(sd); perm = rg.permutation(N); folds = np.array_split(perm, 10); pv = np.zeros(N)
        for k in range(10):
            te = folds[k]; tr = np.setdiff1d(perm, te); pv[te] = fitter(tr, te)
        es.append(rmse(ytest, pv)); r2s.append(r2(ytest, pv))
    return float(np.mean(es)), float(np.mean(r2s))
def tramos(pv, var, cortes, yy=None):
    yy = y if yy is None else yy
    return [(f"{lo}-{hi}" if hi < 9999 else f"{lo}+", int(((var >= lo) & (var <= hi)).sum()), float(yy[(var >= lo) & (var <= hi)].sum()/pv[(var >= lo) & (var <= hi)].sum())) for lo, hi in cortes]
TL = [(1,3),(4,9),(10,19),(20,39),(40,9999)]; TC = [(0,19),(20,59),(60,199),(200,9999)]

# ------------------------------------------------------------------ eleccion del target (CV contra neto_cola CRUDO)
P(f"\nELECCION DEL TARGET (CV 10-fold x 5 semillas; error medido contra el neto_cola CRUDO de las 338, y contra el target de cada uno):")
opc = {}
for nom, yy in [("neto_sh (sin cola)", ysh), ("neto_sh + cola cruda", ycr), (f"neto_sh + cola topeada {f(TOPE_COLA,0)}", y), (f"neto_sh + cola topeada {f(TOPE_ALT,0)}", y60)]:
    e_cr, _ = cv10(yy, ytest=ycr); e_own, r_own = cv10(yy); p_ = fit(ALL, yy); c_ = costs(p_)
    opc[nom] = (e_cr, e_own, r_own, c_)
    P(f"  {nom:28s}: CV vs crudo {f(e_cr,2)} · CV vs su target {f(e_own,2)} (R2 {f(r_own,3)}) · cfijo+arranque {f(c_['cfijo']+c_['arranque'],2)} · parada {f(c_['parada'],3)} · caja {f(c_['caja'],4)} · A5 {f(c_['A5'],2)} · R4 {f(c_['R4'],2)}")
e_fijo, _ = cv10(ysh, ytest=ycr, fitter=lambda tr, te: predict(fit(tr, ysh), te) + np.minimum(cola[tr], TOPE_COLA).mean())
P(f"  {'neto_sh + fijo (media cola top.)':28s}: CV vs crudo {f(e_fijo,2)}  (lo que propuso el juez 2: el esquema de neto_sh mas un fijo por tanda)")
P(f"  -> da lo mismo en CV; se ajusta sobre neto_sh + cola topeada a {f(TOPE_COLA,0)} min (juez 1, verificado) y la cola queda en la constante, no en la parada. Con 60 (juez 2) los costos cambian lo que dice la fila de arriba.")

# ------------------------------------------------------------------ ajuste final
p = fit(ALL); c = costs(p); pred = predict(p, ALL); res = y - pred
p_lib = fit(ALL, atar=False); c_lib = costs(p_lib)
P(f"\nAJUSTE FINAL (target neto_sh + min(cola, {f(TOPE_COLA,0)}), lambda {f(LAM,0)}, tope {TOPE} cajas/linea, arranque hasta {KARR} lineas, MX = {f(K_MX,0)} x R4, F = {f(K_F,0)} x R4), minutos:")
P(f"  cfijo {f(c['cfijo'],2)} · arranque {f(c['arranque'],2)} (x min(n,{KARR})/{KARR}) · parada {f(c['parada'],3)} ({f(c['parada']*60,0)} s) · caja {f(c['caja'],4)} ({f(c['caja']*60,1)} s)")
P("  por linea (s): " + " · ".join(f"{h} {f(c[h]*60,0)}" for h in CL))
P("  contra el prior (s): " + " · ".join(f"{h} {f(c[h]*60,0)} vs {f(PRIOR[h]*60,0)}" for h in CL[:9]))
P(f"  restricciones activas (parametro en 0): {[PN[i] for i in range(len(p)) if p[i] <= 1e-9]}")
P(f"  R2 {f(r2(y,pred),3)} · RMSE {f(rmse(y,pred),2)} · MAE {f(np.mean(np.abs(res)),2)} min · sum tamano / sum real {f(pred.sum()/y.sum(),3)}")
P(f"  (MX y F LIBRES darian MX {f(c_lib['MX']*60,0)} s · F {f(c_lib['F']*60,0)} s con R2 {f(r2(y, predict(p_lib, ALL)),3)}: atarlas cuesta {f((r2(y, predict(p_lib, ALL)) - r2(y,pred))*1000,1)} milesimas de R2)")
P("  real/esperado por tramo de lineas: " + " · ".join(f"{a} ({k}) {f(v,2)}" for a, k, v in tramos(pred, n, TL)))
P("  real/esperado por tramo de cajas: " + " · ".join(f"{a} ({k}) {f(v,2)}" for a, k, v in tramos(pred, caj, TC)))
P(f"  contra el neto_cola CRUDO: R2 {f(r2(ycr,pred),3)} · RMSE {f(rmse(ycr,pred),2)} (lo que se pierde son las {int((cola>TOPE_COLA).sum())} colas topeadas)")
# sin alturas y OLS libre, de referencia
Xs = np.column_stack([np.ones(N), np.minimum(n, KARR)/KARR, par, caj30]); bs = nnls(Xs, y)
cv_sin, _ = cv10(fitter=lambda tr, te: Xs[te] @ nnls(Xs[tr], y[tr]))
P(f"  (referencia) SIN alturas, solo arranque + parada + caja: R2 {f(r2(y, Xs@bs),3)} · CV {f(cv_sin,2)}")

# ------------------------------------------------------------------ ESCALA DE ALTURAS DECIDIDA (Luis, 03/10/2026)
# Luis, 03/10: "las estanterias de la A y de la P son un poquito mas altas, pero tampoco mucho: agarrar de la 5.ª altura
# de la A no es mucho mas complicado que de la 4.ª de la B, es medio que lo mismo" · "de la 3.ª de la B a veces se agarra
# sin escalera si es chiquito: ponele un grado de dificultad, pero tampoco tan alto" · "aplica lo que te parezca".
# La escala va por ALTURA FISICA, 1 punto = linea de piso = 14 s: piso 1 · 2.ª 1,5 · 3.ª 2 · 4.ª 2,5 · 5.ª de A 3;
# A4 = 2,5 (queda entre la 3.ª y la 4.ª de B); MX = 2 x R4 = 5 · F = R4 = 2,5. Las alturas se FIJAN y se reajustan fijo,
# arranque, parada y caja con ellas puestas. Lo medido con alturas libres (arriba) queda de referencia en el JSON.
PT_ALT = {"A1":1.0,"A2":1.5,"A3":1.5,"A4":2.5,"A5":3.0,"R1":1.0,"R2":1.5,"R3":2.0,"R4":2.5,"MX":5.0,"F":2.5}; SEG_PT = 14.0
c_med = dict(c); r2_med = r2(y, pred); cv_med, _ = cv10()
PFIX = np.array([PT_ALT["A1"], PT_ALT["A2"]-PT_ALT["A1"], PT_ALT["A3"]-PT_ALT["A2"], PT_ALT["A4"]-PT_ALT["A3"], PT_ALT["A5"]-PT_ALT["A4"],
                 PT_ALT["R1"], PT_ALT["R2"]-PT_ALT["R1"], PT_ALT["R3"]-PT_ALT["R2"], PT_ALT["R4"]-PT_ALT["R3"], PT_ALT["MX"], PT_ALT["F"]]) * SEG_PT/60
def fit_fix(idx, yy=None, lam=LAM, extra=(), atar=True, cj=None, arrK=KARR):
    """alturas FIJAS en la escala decidida; NNLS solo sobre fijo, arranque, parada y caja (+ columnas extra)."""
    yy = y if yy is None else yy; X = design(idx, cj, arrK, extra)
    resto = yy[idx] - X[:, 4:15] @ PFIX; Xf = np.column_stack([X[:, :4]] + ([X[:, 15:]] if X.shape[1] > 15 else []))
    q = nnls(Xf, resto); return np.concatenate([q[:4], PFIX, q[4:]])
fit = fit_fix
p = fit(ALL); c = costs(p); pred = predict(p, ALL); res = y - pred
P(f"\nESCALA DECIDIDA (Luis 03/10; alturas fijas por altura fisica, 1 punto = {f(SEG_PT,0)} s), minutos:")
P(f"  cfijo {f(c['cfijo'],2)} · arranque {f(c['arranque'],2)} (x min(n,{KARR})/{KARR}) · parada {f(c['parada'],3)} ({f(c['parada']*60,0)} s) · caja {f(c['caja'],4)} ({f(c['caja']*60,1)} s)")
P("  por linea (s): " + " · ".join(f"{h} {f(c[h]*60,0)}" for h in CL) + "   (medido con alturas libres: " + " · ".join(f"{h} {f(c_med[h]*60,0)}" for h in CL) + ")")
P(f"  R2 {f(r2(y,pred),3)} (libre {f(r2_med,3)}) · RMSE {f(rmse(y,pred),2)} · MAE {f(np.mean(np.abs(res)),2)} min · sum tamano / sum real {f(pred.sum()/y.sum(),3)}")
P("  real/esperado por tramo de lineas: " + " · ".join(f"{a} ({k}) {f(v,2)}" for a, k, v in tramos(pred, n, TL)))
p_l0 = fit(ALL, lam=0); c_l0 = costs(p_l0)
P(f"  (referencia) NNLS sin prior (lambda 0): R2 {f(r2(y, predict(p_l0, ALL)),3)} · parada {f(c_l0['parada']*60,0)} s · " + " · ".join(f"{h} {f(c_l0[h]*60,0)}" for h in CL))

# ------------------------------------------------------------------ a quien se le cargo la cola (misma muestra, misma estructura, target neto_sh)
p_sh = fit(ALL, ysh); c_sh = costs(p_sh); pred_sh = predict(p_sh, ALL)
sums = {"cfijo": float(N), "arranque": float((np.minimum(n, KARR)/KARR).sum()), "parada": float(par.sum()), "caja": float(caj30.sum())}
sums.update({h: float(NH[h].sum()) for h in CL})
dmin = {k: (c[k]-c_sh[k])*sums[k] for k in sums}; tot = sum(dmin.values())
P(f"\nA QUIEN SE LE CARGA LA COLA (mismas 338 tandas, misma estructura; coeficiente con neto_sh -> con neto_sh + cola topeada):")
P("  " + " · ".join(f"{k} {f(c_sh[k],3)} -> {f(c[k],3)}" for k in ["cfijo","arranque","parada","caja"]) + "\n  alturas (s): " + " · ".join(f"{h} {f(c_sh[h]*60,0)} -> {f(c[h]*60,0)}" for h in CL))
P(f"  minutos absorbidos (delta coef x suma de la variable): " + " · ".join(f"{k} {f(v,0)} ({f(v/np.minimum(cola,TOPE_COLA).sum()*100,0)} %)" for k, v in sorted(dmin.items(), key=lambda kv: -abs(kv[1])) if abs(v) >= 5) +
  f" · total {f(tot,0)} de {f(np.minimum(cola,TOPE_COLA).sum(),0)} min de cola topeada")
P(f"  el refit CRUDO del modelador (d17_restringido/resultado_cola.json) daba const {f(REST['coef_min']['const'],2)} · parada {f(REST['coef_min']['parada'],3)} · caja {f(REST['coef_min']['caja'],4)} · A5 {f(REST['coef_min']['A5'],2)} · R4 {f(REST['coef_min']['R4'],2)}: "
  f"la parada +{f(REST['coef_min']['parada']-REST['coef_neto_sh_misma_muestra']['parada'],2)} min era el reparto de las dos colas 'sig' largas; con el tope la parada queda en {f(c['parada'],3)} (con neto_sh: {f(c_sh['parada'],3)})")
P(f"  sintesis anterior (neto_sh, d17_v3_netosh): cfijo {f(V3['coef_min']['cfijo'],2)} · arranque {f(V3['coef_min']['arranque'],2)} · parada {f(V3['coef_min']['parada'],3)} · caja {f(V3['coef_min']['caja'],4)} · A5 {f(V3['coef_min']['A5'],2)} · R4 {f(V3['coef_min']['R4'],2)} · R2 {f(V3['validacion']['r2'],3)} · CV {f(V3['validacion']['cv_rmse'],2)}")
# cola sola contra el diseno
Xc = design(ALL); bc = np.linalg.lstsq(Xc, np.minimum(cola, TOPE_COLA), rcond=None)[0]
P(f"  la cola topeada regresada SOLA sobre paradas, cajas y alturas: R2 {f(r2(np.minimum(cola,TOPE_COLA), Xc@bc),3)} · corr(cola, paradas) {f(np.corrcoef(cola,par)[0,1],2)} · corr(cola, cajas) {f(np.corrcoef(cola,caj)[0,1],2)} · corr(cola, lineas) {f(np.corrcoef(cola,n)[0,1],2)}")

# ------------------------------------------------------------------ sensibilidad: tope 60, con outliers, sin las colas sig largas
c60 = costs(fit(ALL, y60)); p60 = predict(fit(ALL, y60), ALL)
P(f"\nSENSIBILIDAD: tope {f(TOPE_ALT,0)} -> cfijo+arranque {f(c60['cfijo']+c60['arranque'],2)} (vs {f(c['cfijo']+c['arranque'],2)}) · parada {f(c60['parada'],3)} · caja {f(c60['caja'],4)} · A5 {f(c60['A5'],2)} · R4 {f(c60['R4'],2)} · R2 {f(r2(y60,p60),3)}")
# con los 2 outliers y la cola cruda (lo que pasa si no se topea ni se saca)
FA = feat; NA = len(FA)
def fit_all(yy_fn):
    global D, N, n, par, caj30, NH, y
    sv = (D, N, n, par, caj30, NH, y)
    D = FA; N = NA; n = np.array([r["n"] for r in D], float); par = np.array([r["paradas"] for r in D], float); caj30 = cajas_tope(D, TOPE)
    NH = {h: np.array([r["n_"+h] for r in D], float) for h in CL}; y = yy_fn(D)
    pp = fit(np.arange(N)); cc = costs(pp); pv = predict(pp, np.arange(N)); res_ = (r2(y, pv), rmse(y, pv), cc)
    D, N, n, par, caj30, NH, y = sv; return res_
r2a, rma, ca = fit_all(lambda rows: np.array([r["neto_cola"] for r in rows]))
r2b, rmb, cb = fit_all(lambda rows: np.array([r["neto_sh"] + min(r["cola"], TOPE_COLA) for r in rows]))
P(f"  CON los 2 outliers y la cola cruda (340): R2 {f(r2a,3)} · RMSE {f(rma,1)} · cfijo+arranque {f(ca['cfijo']+ca['arranque'],1)} · parada {f(ca['parada'],2)}: las dos se comen la constante")
P(f"  CON los 2 outliers pero cola topeada a {f(TOPE_COLA,0)} (340): R2 {f(r2b,3)} · RMSE {f(rmb,1)} · cfijo+arranque {f(cb['cfijo']+cb['arranque'],2)} · parada {f(cb['parada'],3)}: con el tope ni hace falta sacarlas; se sacan igual porque 5 y 8 horas sin registro no son picking")
sel = np.where(cola <= 60)[0]; cS = costs(fit(sel, y))
P(f"  sin las 2 colas 'sig' > 60 (E37F, D52C; {len(sel)} tandas): cfijo+arranque {f(cS['cfijo']+cS['arranque'],2)} · parada {f(cS['parada'],3)} · caja {f(cS['caja'],4)} · A5 {f(cS['A5'],2)} · R4 {f(cS['R4'],2)}")
cvl = {}
for lam in [0, 3, 10, 30, 100]:
    cvl[lam] = cv10(fitter=lambda tr, te, lam=lam: predict(fit(tr, y, lam=lam), te))[0]
P("  CV por lambda del prior: " + " · ".join(f"{k} {f(v,2)}" for k, v in cvl.items()) + "  (curva plana: lambda 10 se mantiene por continuidad con las corridas anteriores)")

# ------------------------------------------------------------------ bootstrap
rng = np.random.default_rng(17); B = 300; boots = collections.defaultdict(list)
for _ in range(B):
    idx = rng.integers(0, N, N); cb_ = costs(fit(idx))
    for k, v in cb_.items(): boots[k].append(v)
P(f"\nBOOTSTRAP por tanda ({B}), p5 / p50 / p95 en segundos por linea (min para cfijo/arranque/parada):")
for k in ["cfijo","arranque","parada","caja"] + CL:
    a = np.array(boots[k]); m = 60 if k not in ("cfijo","arranque","parada") else 1
    P(f"  {k}: {f(np.percentile(a,5)*m,1)} / {f(np.percentile(a,50)*m,1)} / {f(np.percentile(a,95)*m,1)}")

# ------------------------------------------------------------------ modelo previo
prev = 1.1 + 0.8*par + 0.117*caj + 0.98*esc
Xp = np.column_stack([np.ones(N), par, caj, esc]); bp = np.linalg.lstsq(Xp, y, rcond=None)[0]
cv_prev, _ = cv10(fitter=lambda tr, te: Xp[te] @ np.linalg.lstsq(Xp[tr], y[tr], rcond=None)[0])
P(f"\nMODELO PREVIO (1,1 + 0,8*paradas + 0,117*caj + 0,98*esc) sobre estas tandas y este target: R2 {f(r2(y,prev),3)} · RMSE {f(rmse(y,prev),1)} · sesgo {f(np.mean(prev-y),1)} min")
P(f"  misma forma re-ajustada: const {f(bp[0],2)} · parada {f(bp[1],3)} · caja {f(bp[2],4)} · esc {f(bp[3],3)} · R2 {f(r2(y,Xp@bp),3)} · CV {f(cv_prev,2)}")

# ------------------------------------------------------------------ validacion
cv_rmse, cv_r2 = cv10(); cv_cr, _ = cv10(ytest=ycr)
P(f"\nVALIDACION 10-fold por tanda (5 semillas): RMSE {f(cv_rmse,2)} · R2 {f(cv_r2,3)} · medido contra el neto_cola crudo {f(cv_cr,2)}")
plo = np.zeros(N); loo = {}
for L in sorted(set(leg), key=int):
    te = np.where(leg == L)[0]; tr = np.where(leg != L)[0]; plo[te] = predict(fit(tr), te)
    loo[L] = (len(te), rmse(y[te], plo[te]), float(y[te].sum()/plo[te].sum()))
loo_rmse = rmse(y, plo)
P(f"VALIDACION leave-one-operator-out: RMSE {f(loo_rmse,2)} · R2 {f(r2(y,plo),3)}")
for L, (k, e, ratio) in loo.items(): P(f"  legajo {L}: {k} tandas · RMSE {f(e,1)} · real/esperado {f(ratio,2)}")

# ------------------------------------------------------------------ inferida vs conocida
P("\nALTURA INFERIDA vs CONOCIDA:")
def clase(cod, t):
    cells = cap.get(cod)
    if not cells: return "F", "fuera"
    isA = cells[0][0][0] in ("A", "P"); alts = sorted(set(cc[1] for cc in cells))
    if len(alts) == 1: return ("A" if isA else "R") + str(alts[0]), "conocida"
    st = si.get((t, cod))
    if st is None or st <= 0: return "MX", "mx"
    capa = collections.defaultdict(float)
    for s, h, cp in cells: capa[h] += (cp or 0)
    hs = sorted(capa); asg = hs[-1]
    for h in hs:
        if st > sum(capa[k] for k in hs if k > h): asg = h; break
    return ("A" if isA else "R") + str(asg), "inferida"
KN = {h: np.zeros(N) for h in CL}; IN = {h: np.zeros(N) for h in CL}; mism = 0; mxcor = 0; mxlin = 0
for i, r in enumerate(D):
    cnt = collections.Counter()
    for cod, ln, cj, co, ex in cods[r["t"]]["cods"]:
        h, k = clase(cod, r["t"]); cnt[h] += ln; (IN if k == "inferida" else KN)[h][i] += ln
        if h == "MX": mxlin += ln; mxcor += co
    if any(cnt[h] != r["n_"+h] for h in CL): mism += 1
P(f"  rederivacion linea por linea: coincide con d17_feat en {N-mism} de {N} tandas; MX = {mxlin} lineas de codigos con stock 0 al empezar, {mxcor} de ellas cortas")
P("  conocidas: " + " · ".join(f"{h} {int(KN[h].sum())}" for h in CL[:9]) + "\n  inferidas: " + " · ".join(f"{h} {int(IN[h].sum())}" for h in CL[:9]))
def fit_inf(idx):
    q = fit(idx, extra=(ninf, -ninf)); return q[15]-q[16]
k_inf = fit_inf(ALL); kb = np.array([fit_inf(rng.integers(0, N, N)) for _ in range(B)])
P(f"  (a) coeficiente extra sobre n_inferidas: {f(k_inf*60,1)} s/linea · bootstrap p5/p95 {f(np.percentile(kb,5)*60,1)} / {f(np.percentile(kb,95)*60,1)} s "
  f"({'incluye el 0' if np.percentile(kb,5) <= 0 <= np.percentile(kb,95) else 'NO incluye el 0'}; una linea de piso cuesta {f(c['R1']*60,0)} s)")
frac = ninf/np.maximum(n, 1); med = float(np.median(frac)); lo = np.where(frac <= med)[0]; hi = np.where(frac > med)[0]
p_lo = fit(lo); c_lo = costs(p_lo); p_hi = fit(hi); c_hi = costs(p_hi); pv_hi = predict(p_lo, hi)
P(f"  (b) ajustado con la mitad MENOS inferida ({len(lo)} tandas, fraccion <= {f(med,2)}) y aplicado a la mitad MAS inferida ({len(hi)}): "
  f"sesgo real-esperado {f(np.mean(y[hi]-pv_hi),2)} min sobre {f(np.mean(y[hi]),1)} reales ({f(np.mean(y[hi]-pv_hi)/np.mean(y[hi])*100,1)} %) · RMSE {f(rmse(y[hi],pv_hi),2)}")
P("      costos por altura en cada mitad (s): " + " · ".join(f"{h} {f(c_lo[h]*60,0)}/{f(c_hi[h]*60,0)}" for h in CL[:9]))
P(f"      corr(fraccion inferida, residuo relativo) {f(np.corrcoef(frac, res/np.maximum(pred,1))[0,1],3)}")

# ------------------------------------------------------------------ puntos (Blackjack)
base = c["R1"]; r05 = lambda v: round(v*2)/2
pts = {"arranque_por_linea": r05(c["arranque"]/KARR/base), "arranque_fijo": r05(c["cfijo"]/base), "parada": r05(c["parada"]/base), "caja_x10": r05(10*c["caja"]/base)}
for h in CL: pts[h] = r05(c[h]/base)
pts_min = base*(pts["arranque_fijo"] + pts["arranque_por_linea"]*np.minimum(n, KARR) + pts["parada"]*par + pts["caja_x10"]*caj30/10 + sum(pts[h]*NH[h] for h in CL))
P(f"\nPUNTOS (1 punto = linea de piso R1 = {f(base*60,0)} s):")
P(f"  fijo por tanda {f(pts['arranque_fijo'],1)} + arranque {f(pts['arranque_por_linea'],1)} por linea hasta {KARR} (max {f(pts['arranque_por_linea']*KARR,1)}) · parada {f(pts['parada'],1)} · cada 10 cajas (tope 30/linea) {f(pts['caja_x10'],1)}")
P("  por linea: " + " · ".join(f"{h} {f(pts[h],1)}" for h in CL))
P(f"  el esquema redondeado reproduce los minutos con R2 {f(r2(y,pts_min),3)} · RMSE {f(rmse(y,pts_min),2)} (puntos x {f(base,4)} = minutos)")

# ------------------------------------------------------------------ tamano, dificultad, niveles (sobre las 340: las 2 outliers se clasifican con los mismos umbrales)
tam = pred; arranque = c["cfijo"] + c["arranque"]*np.minimum(n, KARR)/KARR
dif = np.where(caj > 0, (tam - arranque)/np.maximum(caj, 1e-9), np.nan); ok = caj > 0
# Niveles (Luis, 03/10/2026: se retira «pajosa»; son CUATRO). La dificultad se corta en DECILES sobre las tandas con cajas
# -> grado 1..10; el nivel agrupa grados para que nivel y grado nunca se contradigan: Baja 1-2 · Media 3-5 · Alta 6-8 · Muy alta 9-10.
# El multiplicador del m3/h sale del grado: 1 + 0,1 x (grado - 5), de x0,6 a x1,5.
DEC = [float(v) for v in np.percentile(dif[ok], [10*k for k in range(1, 10)])]
t1, t2, t3 = DEC[1], DEC[4], DEC[7]
NIV = ["Baja", "Media", "Alta", "Muy alta"]
def grado_de(d, cj): return 10 if cj <= 0 else int(np.searchsorted(np.array(DEC), d, side="left")) + 1
def nivel_de(d, cj): return "Muy alta" if cj <= 0 else ("Baja" if d <= t1 else "Media" if d <= t2 else "Alta" if d <= t3 else "Muy alta")
def mult_de(g): return round(1 + 0.1*(g - 5), 1)
nivel = np.array([nivel_de(dif[i], caj[i]) for i in range(N)]); grado = np.array([grado_de(dif[i], caj[i]) for i in range(N)])
dif_c = np.where(ok, tam/np.maximum(caj, 1e-9), np.nan); u1, u2, u3 = np.percentile(dif_c[ok], [20, 50, 80])
nivel_c = np.where(~ok, "Muy alta", np.where(dif_c <= u1, "Baja", np.where(dif_c <= u2, "Media", np.where(dif_c <= u3, "Alta", "Muy alta"))))
P(f"\nDIFICULTAD = (tamano - arranque) / cajas reales, min/caja · deciles ({N} tandas) = grado 1-10 · Baja <= {f(t1,3)} (grado 1-2) · Media <= {f(t2,3)} (3-5) · Alta <= {f(t3,3)} (6-8) · Muy alta > {f(t3,3)} (9-10) · "
  + " · ".join(f"{k} {int((nivel==k).sum())}" for k in NIV))
P("  deciles: " + " · ".join(f"g{k+1} <= {f(v,3)}" for k, v in enumerate(DEC)) + " · g10 > " + f(DEC[-1],3))
P(f"  (con la constante adentro los cortes serian {f(u1,3)} / {f(u2,3)} / {f(u3,3)} y cambian de nivel {int((nivel != nivel_c).sum())} tandas)")
def sp(a, b):
    ra = np.argsort(np.argsort(a)); rb = np.argsort(np.argsort(b)); return float(np.corrcoef(ra, rb)[0,1])
fesc = (NH["A4"]+NH["A5"]+NH["R3"]+NH["R4"])/np.maximum(n, 1); altas = NH["A4"]+NH["A5"]+NH["R3"]+NH["R4"]
P(f"  Spearman dificultad~cajas {f(sp(dif[ok], caj[ok]),2)} · dificultad~fraccion con escalera {f(sp(dif[ok], fesc[ok]),2)} · dificultad~cajas por linea {f(sp(dif[ok], (caj/np.maximum(n,1))[ok]),2)}")
difl = (tam - arranque)/np.maximum(n, 1); l1, l2 = np.percentile(difl, [100/3, 200/3])
P(f"  (alternativa por LINEA: (tamano - arranque)/lineas, terciles {f(l1,2)} / {f(l2,2)} min/linea; Spearman con fraccion con escalera {f(sp(difl, fesc),2)}, con cajas por linea {f(sp(difl, caj/np.maximum(n,1)),2)})")
P("  tandas de 1 o 2 paradas con lineas con escalera:")
sel12 = sorted([i for i in range(N) if par[i] <= 2 and altas[i] > 0], key=lambda i: (NIV.index(nivel[i]), -caj[i]))
for i in sel12:
    r = D[i]
    P(f"    {r['t']} leg {r['l']}: {int(par[i])} par · {int(n[i])} lin (A4 {int(NH['A4'][i])} A5 {int(NH['A5'][i])} R3 {int(NH['R3'][i])} R4 {int(NH['R4'][i])}) · {f(caj[i],0)} caj · tamano {f(tam[i],1)} · "
      f"dif {f(dif[i],3)} · {nivel[i]} (con const: {nivel_c[i]}) · real {f(y[i],1)} (neto_sh {f(ysh[i],1)} + cola {f(min(cola[i],TOPE_COLA),1)})")
ej_tam = c["cfijo"] + c["arranque"]*min(4, KARR)/KARR + c["parada"]*1 + c["caja"]*40 + c["A5"]*4; ej_d = (ej_tam - (c["cfijo"] + c["arranque"]*min(4, KARR)/KARR))/40
P(f"  ejemplo sintetico: 1 parada, 4 lineas en A5, 40 cajas -> tamano {f(ej_tam,1)} min · dif {f(ej_d,3)} -> {nivel_de(ej_d, 40)}")

# ------------------------------------------------------------------ indice por operario (338; los 2 outliers aparte)
P(f"\nINDICE por operario = sum(tamano) / sum(neto_sh + cola topeada) (> 1 = mas rapido que el promedio):")
idx_op = []; mcomp = (n >= 10) & (n <= 40); m3t = np.array([m3.get(r["t"], np.nan) for r in D])
ind_sh_all = {L: float(predict(p_sh, np.where(leg==L)[0]).sum()/ysh[leg==L].sum()) for L in set(leg)}
for L in sorted(set(leg), key=int):
    m = leg == L; mm = m & mcomp; mh = m & ~np.isnan(m3t)
    ind = float(tam[m].sum()/y[m].sum()); indc = float(tam[mm].sum()/y[mm].sum()) if mm.sum() else None
    ind_cr = float(tam[m].sum()/ycr[m].sum()); m3h = float(m3t[mh].sum()/(y[mh].sum()/60)) if mh.sum() else None
    idx_op.append({"legajo": L, "nombre": NOM.get(L, ""), "apodo": APODO.get(L, ""), "tandas": int(m.sum()), "cajas": float(caj[m].sum()),
                   "indice": round(ind, 3), "indice_cola_cruda": round(ind_cr, 3), "indice_neto_sh": round(ind_sh_all[L], 3), "indice_10_40_lineas": (round(indc, 3) if indc else None), "tandas_10_40": int(mm.sum()),
                   "cola_pct_neto_sh": round(float(cola[m].sum()/ysh[m].sum()*100), 1), "m3_por_hora": (round(m3h, 3) if m3h else None), "loo_rmse": round(loo[L][1], 1), "publicable": bool(m.sum() >= 10)})
    P(f"  {L} {NOM.get(L,'')}: {int(m.sum())} tandas · {f(caj[m].sum(),0)} cajas · indice {f(ind,2)} (cola cruda {f(ind_cr,2)} · solo neto_sh {f(ind_sh_all[L],2)}) · en mix 10-40 lineas ({int(mm.sum())}) {f(indc,2) if indc else '—'} · m3/h {f(m3h,2) if m3h else '—'} · cola = {f(cola[m].sum()/ysh[m].sum()*100,0)} % de su neto_sh")
P("  orden por m3/h: " + " > ".join(o["legajo"] for o in sorted([o for o in idx_op if o["publicable"] and o["m3_por_hora"]], key=lambda o: -o["m3_por_hora"]))
  + " · orden por indice: " + " > ".join(o["legajo"] for o in sorted([o for o in idx_op if o["publicable"]], key=lambda o: -o["indice"])))
# los 2 outliers, con el esquema aplicado
def tam_de(r):
    cj30 = sum(min(cj, TOPE*ln) for cod, ln, cj, co, ex in cods[r["t"]]["cods"])
    return c["cfijo"] + c["arranque"]*min(r["n"], KARR)/KARR + c["parada"]*r["paradas"] + c["caja"]*cj30 + sum(c[h]*r["n_"+h] for h in CL)
for r in OUT:
    tm = tam_de(r); arr_ = c["cfijo"] + c["arranque"]*min(r["n"], KARR)/KARR
    P(f"  outlier {r['t']} leg {r['l']}: tamano {f(tm,1)} min · real neto_sh {f(r['neto_sh'],1)} (indice {f(tm/r['neto_sh'],2)}) · con cola topeada {f(r['neto_sh']+min(r['cola'],TOPE_COLA),1)} ({f(tm/(r['neto_sh']+min(r['cola'],TOPE_COLA)),2)}) · con la cola cruda {f(r['neto_cola'],1)} ({f(tm/r['neto_cola'],2)})")

# ------------------------------------------------------------------ rarezas
P("\nRAREZAS:")
P(f"  A1 {f(c['A1']*60,0)} s vs R1 {f(c['R1']*60,0)} s · A3 atada a A2: {'si' if abs(c['A3']-c['A2']) < 1e-9 else 'no'} · R3 (con escalera) {f(c['R3']*60,0)} s vs R2 {f(c['R2']*60,0)} s")
big = np.argsort(-np.abs(res))[:6]
P("  residuos mas grandes (real vs esperado): " + " · ".join(f"{D[i]['t']} leg {D[i]['l']} {f(y[i],0)}/{f(tam[i],0)} ({int(n[i])} lin, {f(caj[i],0)} caj, huecos {f(D[i]['hue'],0)}, cola {f(cola[i],0)})" for i in big))
ratio = tam/y
P(f"  tamano/real: p10 {f(np.percentile(ratio,10),2)} · mediana {f(np.median(ratio),2)} · p90 {f(np.percentile(ratio,90),2)}")

# ------------------------------------------------------------------ salidas
coef = {k: round(float(v), 4) for k, v in c.items()}
esquema = {
    "target": "neto_cola",
    "target_detalle": f"neto_cola = neto_sh + cola, con la cola TOPEADA a {int(TOPE_COLA)} min por tanda al ajustar (neto_sh = EP->TP menos pausas declaradas menos huecos > 5 min entre confirmaciones; cola = minutos sin registro entre el TP y la proxima tarea registrada o el fin de jornada)",
    "coef_min": coef,
    "escala_alturas": "DECIDIDA por Luis (03/10/2026), por altura fisica: piso 1 · 2.ª 1,5 · 3.ª 2 · 4.ª 2,5 · 5.ª de A 3 (A4 2,5 entre la 3.ª y la 4.ª de B); MX 5 · F 2,5; 1 punto = 14 s. Fijo, arranque, parada y caja reajustados con las alturas fijas.",
    "coef_medido_alturas_libres_min": {k: round(float(v), 4) for k, v in c_med.items()},
    "r2_alturas_libres": round(float(r2_med), 4), "cv_rmse_alturas_libres": round(float(cv_med), 3),
    "puntos": {k: float(v) for k, v in pts.items()},
    "punto_en_min": round(float(base), 4),
    "tope_cajas_por_linea": TOPE, "arranque_hasta_lineas": KARR, "tope_cola_min": TOPE_COLA, "lambda_prior": LAM, "prior_min": PRIOR,
    "mx_f_atadas": f"MX = {K_MX:g} x R4, F = {K_F:g} x R4 (sin prior propio son ruido; promedio con criterio de lo recomendado por los dos jueces)",
    "umbrales": {"baja": round(t1, 4), "media": round(t2, 4), "alta": round(t3, 4)},
    "niveles": "Luis 03/10/2026: cuatro niveles, sin «pajosa». Grado 1-10 = decil de la dificultad; Baja = grado 1-2 · Media = 3-5 · Alta = 6-8 · Muy alta = 9-10; sin cajas = grado 10. Multiplicador del m3/h = 1 + 0,1 x (grado - 5) (x0,6 a x1,5).",
    "deciles_grado": [round(v, 4) for v in DEC],
    "validacion": {"r2": round(r2(y, pred), 3), "rmse": round(rmse(y, pred), 2), "cv_rmse": round(cv_rmse, 2), "cv_r2": round(cv_r2, 3),
                   "loo_operario_rmse": round(loo_rmse, 2), "mae": round(float(np.mean(np.abs(res))), 2), "cv_sin_alturas": round(cv_sin, 2),
                   "contra_neto_cola_crudo": {"r2": round(r2(ycr, pred), 3), "rmse": round(rmse(ycr, pred), 2), "cv_rmse": round(cv_cr, 2)},
                   "corrida_neto_sh_v3": {"r2": V3["validacion"]["r2"], "rmse": V3["validacion"]["rmse"], "cv_rmse": V3["validacion"]["cv_rmse"], "loo_operario_rmse": V3["validacion"]["loo_operario_rmse"]},
                   "refit_crudo_restringido": {"r2": REST["r2"], "rmse": REST["rmse"], "cv_rmse": REST["cv_rmse"], "loo_operario_rmse": REST["loo_rmse"]},
                   "previo": {"r2": round(r2(y, prev), 3), "rmse": round(rmse(y, prev), 2), "sesgo_min": round(float(np.mean(prev-y)), 2)}},
    "eleccion_target_cv_vs_crudo": {k: round(v[0], 2) for k, v in opc.items()} | {"neto_sh + fijo (media cola topeada)": round(e_fijo, 2)},
    "cola_absorbida_min": {k: round(float(v), 1) for k, v in dmin.items()},
    "coef_neto_sh_misma_estructura": {k: round(float(v), 4) for k, v in c_sh.items()},
    "sensibilidad": {"tope_60": {k: round(float(v), 4) for k, v in c60.items()}, "sin_colas_sig_mayores_60": {k: round(float(v), 4) for k, v in cS.items()},
                     "con_outliers_cola_cruda": {"r2": round(r2a, 3), "rmse": round(rma, 1)}, "con_outliers_cola_topeada": {"r2": round(r2b, 3), "rmse": round(rmb, 1)},
                     "mx_f_libres": {"MX": round(float(c_lib["MX"]), 4), "F": round(float(c_lib["F"]), 4)}, "cv_por_lambda": {str(k): round(v, 2) for k, v in cvl.items()}},
    "formula_tamano": f"tamano_min = {coef['cfijo']} + {coef['arranque']}*min(lineas,{KARR})/{KARR} + {coef['parada']}*paradas + {coef['caja']}*cajas_tope30 + "
                      + " + ".join(f"{coef[h]}*n_{h}" for h in CL) + "  (cajas_tope30 = suma por linea de min(cajas,30); paradas = modulos distintos, el par enfrentado cuenta uno; "
                      "n_A1..A5 lineas en gondolas A y P por altura, 1 = piso; n_R1..R4 idem en B a N~; MX = codigo con stock 0 en gondola al empezar; F = sin sector de gondola). "
                      "El fijo y el arranque ya incluyen la cola (acomodar en la mesa): ritmo = tamano / (neto_sh + min(cola,30)).",
    "formula_dificultad": f"dificultad_min_por_caja = (tamano_min - ({coef['cfijo']} + {coef['arranque']}*min(lineas,{KARR})/{KARR})) / cajas_reales; "
                          f"grado 1-10 = decil sobre {N} tandas; nivel: Baja <= {round(t1,3)} (grado 1-2), Media <= {round(t2,3)} (3-5), Alta <= {round(t3,3)} (6-8), Muy alta > {round(t3,3)} (9-10); sin cajas = Muy alta (grado 10)",
    "regla_altura_inferida": "altura dentro del modulo = ((celda-1) mod alto) + 1, 1 = piso; A y P 5 alturas, B..N~ 4. Codigo con celdas en una sola altura: esa. "
                             "Codigo con celdas en varias alturas: se toma el stock de gondola al abrir el picking (EP) y la capacidad (cajas) de cada celda; se apila el stock "
                             "de la altura mas alta hacia abajo y se asigna la altura MAS BAJA que seguro tiene stock (stock > suma de capacidades de las alturas de arriba). "
                             "Stock mayor que la capacidad total = piso. Stock 0 o sin dato = clase MX. Es una cota a favor del operario.",
    "regla_cola": f"cola = minutos sin registro desde el TP hasta la proxima tarea registrada del legajo ('sig') o el fin de jornada ('cap'); 0 si al cerrar ya habia otro tramo abierto ('cubierta'). "
                  f"Es picking de esa tanda (Luis 02/10). Para el esquema entra TOPEADA a {int(TOPE_COLA)} min por tanda y se absorbe en el fijo/arranque (no en la parada ni en la altura); "
                  f"las dos 'cap' de horas (D40F, D67D) quedan fuera del ajuste. Recomendacion para la base: aplicar el mismo tope ({int(TOPE_COLA)} min) y no dejar correr 'cap' hasta la hora de salida.",
    "indice_operario": f"indice = suma(tamano) / suma(neto_sh + min(cola,{int(TOPE_COLA)})) sobre sus tandas; > 1 mas rapido que el promedio, < 1 mas lento. Publicable con >= 10 tandas.",
    "outliers": [f"{r['t']} (leg {r['l']}, {r['n']} lineas, {int(r['caj'])} cajas): neto_sh {r['neto_sh']} + cola {r['cola']} '{r['cola_sig']}' = {r['neto_cola']} min; fuera del ajuste, clasificada igual en d17_tandas_dificultad.json" for r in OUT],
    "fecha_datos": "60 días al 02/10/2026", "n_tandas": N, "n_tandas_total": len(feat),
    "k_inferidas_s": round(float(k_inf*60), 2), "k_inferidas_boot_s": [round(float(np.percentile(kb, q)*60), 2) for q in (5, 95)],
    "bootstrap_p5_p95": {k: [round(float(np.percentile(boots[k], q)), 4) for q in (5, 95)] for k in ["cfijo","arranque","parada","caja"]+CL},
    "indice_por_operario": idx_op,
}
json.dump(esquema, open(os.path.join(UP, "d17_esquema.json"), "w"), ensure_ascii=False, indent=1)
json.dump(esquema, open(os.path.join(HERE, "resultado_cola.json"), "w"), ensure_ascii=False, indent=1)
tand = []
for i, r in enumerate(D):
    tand.append({"t": r["t"], "l": r["l"], "dia": r["dia"], "caj": r["caj"], "paradas": r["paradas"], "esc": r["esc"], "n_inferidas": r["n_inferidas"],
                 "neto_sh": r["neto_sh"], "cola": r["cola"], "cola_sig": r["cola_sig"], "neto_cola": r["neto_cola"], "target": round(float(y[i]), 2),
                 "tamano": round(float(tam[i]), 2), "dificultad": (round(float(dif[i]), 4) if ok[i] else None),
                 "nivel": str(nivel[i]), "grado": int(grado[i]), "multiplicador": mult_de(int(grado[i])), "indice": round(float(tam[i]/y[i]), 3), "outlier": False})
for r in OUT:
    tm = tam_de(r); arr_ = c["cfijo"] + c["arranque"]*min(r["n"], KARR)/KARR; d_ = (tm-arr_)/r["caj"] if r["caj"] > 0 else None; tg = r["neto_sh"] + min(r["cola"], TOPE_COLA)
    tand.append({"t": r["t"], "l": r["l"], "dia": r["dia"], "caj": r["caj"], "paradas": r["paradas"], "esc": r["esc"], "n_inferidas": r["n_inferidas"],
                 "neto_sh": r["neto_sh"], "cola": r["cola"], "cola_sig": r["cola_sig"], "neto_cola": r["neto_cola"], "target": round(tg, 2),
                 "tamano": round(tm, 2), "dificultad": (round(d_, 4) if d_ is not None else None), "nivel": nivel_de(d_ if d_ is not None else 9e9, r["caj"]), "grado": grado_de(d_ if d_ is not None else 9e9, r["caj"]), "multiplicador": mult_de(grado_de(d_ if d_ is not None else 9e9, r["caj"])),
                 "indice": round(tm/tg, 3), "outlier": True})
tand.sort(key=lambda z: (z["dia"], z["t"]))
json.dump(tand, open(os.path.join(UP, "d17_tandas_dificultad.json"), "w"), ensure_ascii=False, indent=0)
open(os.path.join(HERE, "salida_cola.txt"), "w").write("\n".join(out) + "\n")
P(f"\nescritos: d17_esquema.json · d17_tandas_dificultad.json ({len(tand)} tandas) · d17_final/resultado_cola.json · d17_final/salida_cola.txt")

# ------------------------------------------------------------------ documento para Luis
S = lambda h: f"{c[h]*60:.0f}".replace(".", ",")
def ejemplo(i):
    r = D[i]; m3v = m3.get(r["t"]); ct = min(cola[i], TOPE_COLA)
    return (f"**{r['t']}** (legajo {r['l']}, {r['dia'][8:10]}/{r['dia'][5:7]}): {int(par[i])} parada{'s' if par[i] > 1 else ''}, {int(n[i])} línea{'s' if n[i] > 1 else ''} "
            f"(A1 {int(NH['A1'][i])} · A2 {int(NH['A2'][i])} · A3 {int(NH['A3'][i])} · A4 {int(NH['A4'][i])} · A5 {int(NH['A5'][i])} · R1 {int(NH['R1'][i])} · R2 {int(NH['R2'][i])} · R3 {int(NH['R3'][i])} · R4 {int(NH['R4'][i])} · MX {int(NH['MX'][i])} · F {int(NH['F'][i])}), "
            f"{f(caj[i],0)} cajas reales ({f(caj30[i],0)} con tope), {f(m3v,3) if m3v else '—'} m³. "
            f"Fijo y arranque {f(arranque[i],1)} min + paradas {f(c['parada']*par[i],1)} + cajas {f(c['caja']*caj30[i],1)} + alturas {f(sum(c[h]*NH[h][i] for h in CL),1)} = **tamaño {f(tam[i],1)} min**. "
            f"Dificultad ({f(tam[i],1)} − {f(arranque[i],1)}) ÷ {f(caj[i],0)} = **{f(dif[i],3)} min/caja → {nivel[i]}**. "
            f"Tiempo real {f(y[i],1)} min (picking {f(ysh[i],1)} + cola {f(ct,1)}): ritmo {f(tam[i]/y[i],2)} (tamaño ÷ real)" + (f", contra {f(m3v/(y[i]/60),2)} m³/h." if m3v else "."))
ej1 = next((i for i in sel12 if nivel[i] in ("Baja", "Media") and (NH["A5"][i] + NH["A4"][i]) > 0), next(i for i in sel12 if nivel[i] in ("Baja", "Media")))
paj = [i for i in range(N) if nivel[i] in ("Alta", "Muy alta") and ok[i] and n[i] >= 10]
medp = np.median(dif[paj]); cand = [i for i in paj if abs(dif[i]-medp) <= 0.06 and 0.8 <= tam[i]/y[i] <= 1.25] or paj
ej2 = sorted(cand, key=lambda i: abs(tam[i]/y[i]-1) + abs(dif[i]-medp))[0]
tab_ej = [f"| {D[i]['t']} | {int(par[i])} | {int(n[i])} | {int(altas[i])} | {f(caj[i],0)} | {f(tam[i],1)} | {f(dif[i],3)} | {nivel[i]} ({int(grado[i])}) | {f(y[i],1)} |" for i in sel12]
op_rows = []
for o in sorted(idx_op, key=lambda o: (-o["publicable"], -o["indice"])):
    nm = (o["nombre"] + (" " + o["apodo"] if o["apodo"] else "")).strip()
    op_rows.append(f"| {o['legajo']} | {nm} | {o['tandas']} | {f(o['cajas'],0)} | {f(o['cola_pct_neto_sh'],0)} % | {f(o['m3_por_hora'],2) if o['m3_por_hora'] else '—'} | "
                   f"{f(o['indice'],2) if o['publicable'] else f(o['indice'],2) + ' (no vale: ' + str(o['tandas']) + ' tandas)'} | {f(o['indice_neto_sh'],2)} | {f(o['indice_10_40_lineas'],2) if o['indice_10_40_lineas'] else '—'} |")
kn = {h: int(KN[h].sum()) for h in CL[:9]}; inn = {h: int(IN[h].sum()) for h in CL[:9]}
grandes = {}
for cod in ["505","501","513","504","506","586","544","510"]:
    cnt = collections.Counter()
    for r in D:
        for cc, ln, cj, co, ex in cods[r["t"]]["cods"]:
            if cc == cod: cnt[clase(cc, r["t"])[0]] += ln
    grandes[cod] = cnt
pub = [o for o in idx_op if o["publicable"]]
o104 = next(o for o in idx_op if o["legajo"] == "104")
colas60 = [r for r in sorted(feat, key=lambda r: -r["cola"]) if r["cola"] > 60]
md = f"""# Tamaño y dificultad de una tanda de picking — esquema «Blackjack», con la cola

Datos: 340 tandas de picking de Virgilio, 60 días al 02/10/2026 (04/08 al 02/10), un picker por tanda, legajos de prueba afuera. El tiempo que se modela es el picking más la cola: desde que se abre el picking (EP) hasta que se cierra (TP), sin pausas declaradas (baño, comida, limpieza) y sin huecos de más de 5 minutos entre dos confirmaciones, **más los minutos sin registro que siguen al TP hasta la próxima tarea** (regla de Luis del 02/10: quien cierra el picking antes de acomodar las cajas en la mesa no se beneficia). Esa cola entra **topeada a {f(TOPE_COLA,0)} minutos** por tanda; el porqué está en (d). Los números salen de un ajuste reproducible (`d17_final/esquema_final_cola.py`); los costos por altura están ordenados y acotados por las medianas medidas en los mismos 60 días, porque las 340 tandas solas no alcanzan para separarlos de la parada.

Qué cambió contra el esquema anterior (sobre el picking puro, `d17_v3_netosh/`): la cola se suma al tiempo que se compara, y lo que se sumó cayó casi todo en el fijo por tanda y algo en la parada; las alturas quedaron donde estaban. Lo que no cambió: cajas topeadas a 30 por línea, arranque proporcional hasta 5 líneas y dificultad sin el arranque, las tres correcciones que verificaron los revisores de la corrida anterior.

## (a) Puntos por altura

1 punto = una línea de piso en las góndolas B a Ñ = {S('R1')} segundos. Lo que cuesta cada línea es por SACAR UNA CAJA de ahí; las cajas de más se cobran aparte.

| de dónde sale | A y P (5 alturas) | B a Ñ (4 alturas) |
|---|---|---|
| piso (1.ª) | {f(pts['A1'],1)} pts · {S('A1')} s | {f(pts['R1'],1)} pt · {S('R1')} s |
| 2.ª | {f(pts['A2'],1)} pts · {S('A2')} s | {f(pts['R2'],1)} pts · {S('R2')} s |
| 3.ª | {f(pts['A3'],1)} pts · {S('A3')} s | {f(pts['R3'],1)} pts · {S('R3')} s (escalera) |
| 4.ª | {f(pts['A4'],1)} pts · {S('A4')} s (escalera) | {f(pts['R4'],1)} pts · {S('R4')} s (escalera) |
| 5.ª | {f(pts['A5'],1)} pts · {S('A5')} s (escalera) | — |

| qué más se cobra | puntos | segundos |
|---|---|---|
| código con stock 0 en góndola al empezar (va, no encuentra; {mxcor} de {mxlin} líneas vuelven cortas) | {f(pts['MX'],1)} | {S('MX')} |
| línea fuera de góndola (racks, excedente, sin sector) | {f(pts['F'],1)} | {S('F')} |
| cada parada (módulo; el par enfrentado A-B, G-E, F-D, H-J, L-M es UNA) | {f(pts['parada'],1)} | {f(c['parada']*60,0)} |
| cada 10 cajas (una línea cuenta hasta 30 cajas: el pallet entero no se pickea de a una) | {f(pts['caja_x10'],1)} | {f(c['caja']*600,0)} |
| arranque de la tanda: {f(pts['arranque_por_linea'],1)} pts por línea hasta {KARR} líneas | hasta {f(pts['arranque_por_linea']*KARR,1)} | hasta {f(c['arranque']*60,0)} |
| fijo por tanda (cerrar, acomodar en la mesa, pasar a lo siguiente: es la cola) | {f(pts['arranque_fijo'],1)} | {f(c['cfijo']*60,0)} |

Leído como Blackjack: una parada vale como {f(pts['parada'],1)} líneas de piso, una línea de la 5.ª de A como {f(pts['A5'],1)}, una de la 4.ª de B a Ñ como {f(pts['R4'],1)}; 10 cajas valen {f(pts['caja_x10'],1)}; cerrar la tanda vale {f(pts['arranque_fijo'],1)}. En minutos: puntos × {f(base,3)}. El esquema redondeado reproduce los minutos del ajuste con el mismo R² ({f(r2(y,pts_min),3)}).

Tres cosas que hay que saber de esta tabla:

- Los costos de piso, 2.ª y 3.ª no los midieron las 340 tandas: paradas y líneas van casi juntas (correlación {f(np.corrcoef(par,n)[0,1],3)}) y sin un ancla el ajuste pone todas las líneas bajas en 0 y carga todo en la parada (sin ancla: parada {f(c_l0['parada']*60,0)} s, piso 0, A5 {f(c_l0['A5']*60,0)} s). El ancla son las medianas de segundos entre confirmaciones medidas en 60 días (piso 16 s, 2.ª 20-23, 3.ª 26, 4.ª 37-50, 5.ª 64). El dato sólo mueve de ahí lo que puede: A5 sube a {S('A5')} s, A2-A3 bajan a {S('A2')} (iguales al piso de A), R2 y R3 quedan en {S('R2')} y {S('R3')}. Es una decisión explícita, no una medición; sin alturas el modelo predice igual (en (e)).
- La 3.ª de B a Ñ lleva escalera por regla y acá cuesta lo mismo que la 2.ª ({S('R3')} s): el dato no ve la escalera de la 3.ª. Lo mismo A1 ({S('A1')} s) por encima de R1 ({S('R1')}).
- «Sin dato de stock» (MX) y «fuera de góndola» (F) no tienen ancla y sueltos salen con intervalo bootstrap desde 0 (en las corridas anteriores MX fue de 50 a 102 s según el target). Los dos revisores pidieron atarlos: MX = 2 veces la 4.ª de B a Ñ ({S('MX')} s: ir, buscar, no encontrar, volver) y F = la 4.ª de B a Ñ ({S('F')} s); es el promedio de lo que recomendó cada uno (MX 1,2 y 1,0 min; F 0,5 y 0,6). Atarlos cuesta {f((r2(y, predict(p_lib, ALL)) - r2(y,pred))*1000,1)} milésimas de R².

## (b) Tamaño y dificultad

**Tamaño** = minutos esperados para el operario promedio, cola incluida: fijo {f(c['cfijo'],2)} min + arranque {f(c['arranque']/KARR,2)} por línea hasta {KARR} líneas + {f(c['parada'],2)} min por parada + {f(c['caja'],3)} min por caja (cada línea cuenta hasta 30) + la suma de los puntos por línea de la tabla. Reemplaza al m³ en el ritmo: **ritmo = tamaño ÷ tiempo real**, con el tiempo real = picking + cola topeada (1,00 = el promedio de estos 60 días; 1,20 = un 20 % más rápido).

**Dificultad** = (tamaño − fijo − arranque) ÷ cajas reales, en minutos por caja. Se saca el fijo y el arranque porque con ellos adentro una tanda de 1 línea y 2 cajas daba más de 2 min/caja y salía Muy alta siendo trivial (lo marcaron los revisores de las dos corridas); la cola es tiempo de tanda, no de caja, y va en el fijo. **Niveles (Luis, 03/10: cuatro, sin «pajosa»)**: cada tanda tiene un **grado 1 a 10**, que es su decil de dificultad sobre las {N} tandas (grado 1 = el 10 % más fácil), y el nivel agrupa grados, así nivel y grado nunca se contradicen: **Baja ≤ {f(t1,3)} (grado 1-2) · Media ≤ {f(t2,3)} (3-5) · Alta ≤ {f(t3,3)} (6-8) · Muy alta > {f(t3,3)} (9-10)** min/caja ({int((nivel=='Baja').sum())} / {int((nivel=='Media').sum())} / {int((nivel=='Alta').sum())} / {int((nivel=='Muy alta').sum())} tandas; sin cajas = Muy alta). Deciles: {' · '.join(f"g{k+1} ≤ {f(v,3)}" for k, v in enumerate(DEC))}. El **multiplicador del m³/h** sale del grado: 1 + 0,1 × (grado − 5), de ×0,6 (grado 1) a ×1,5 (grado 10); está topeado a propósito y no nivela una tanda de cajas sueltas: para eso está el índice tamaño ÷ real.

Lo que la dificultad así definida mide, hay que decirlo: correlación de rangos con las cajas de la tanda {f(sp(dif[ok], caj[ok]),2)} y con la fracción de líneas con escalera {f(sp(dif[ok], fesc[ok]),2)}. Una tanda con muchas cajas por línea es Baja casi siempre, con pocas es Alta o Muy alta casi siempre, y la altura corre la aguja poco. Si lo que se quiere es «qué tan difícil es la tanda por el recorrido y la altura», el denominador tendría que ser líneas y no cajas: por línea los terciles serían {f(l1,2)} / {f(l2,2)} min/línea y el nivel deja de seguir a las cajas (correlación con cajas por línea {f(sp(difl, caj/np.maximum(n,1)),2)}, con la escalera {f(sp(difl, fesc),2)}). Es decisión de Luis (al final).

Ejemplo de pocas paradas con cajas altas, que queda {nivel[ej1]} como pedía Luis:

{ejemplo(ej1)}

Ejemplo de dificultad Alta típica (10 líneas o más, grado 6 a 10, dificultad cerca de la mediana de ésas y tiempo real cerca del esperado):

{ejemplo(ej2)}

Todas las tandas de 1 o 2 paradas con alguna línea con escalera:

| tanda | par. | líneas | c/esc. | cajas | tamaño min | min/caja | nivel (grado) | real min |
|---|---|---|---|---|---|---|---|---|
{chr(10).join(tab_ej)}

Las que quedan Alta o Muy alta tienen entre 1 y 5 cajas: con pocas cajas cada parada y cada línea con escalera pesa mucho por caja, y eso es lo que el cociente mide. Ejemplo sintético: 1 parada, 4 líneas en la 5.ª de A, 40 cajas → tamaño {f(ej_tam,1)} min, {f(ej_d,3)} min/caja → {nivel_de(ej_d, 40)}.

Cómo cambia el ritmo medido en tamaño en vez de m³: en las dos tandas de arriba, por m³/h {D[ej1]['t']} hace {f(m3[D[ej1]['t']]/(y[ej1]/60),2)} y {D[ej2]['t']} {f(m3[D[ej2]['t']]/(y[ej2]/60),2)} m³/h ({'la primera parece ' + f(m3[D[ej1]['t']]/(y[ej1]/60)/(m3[D[ej2]['t']]/(y[ej2]/60)),1) + ' veces más rápida' if m3[D[ej1]['t']]/(y[ej1]/60) >= m3[D[ej2]['t']]/(y[ej2]/60) else 'la segunda parece ' + f((m3[D[ej2]['t']]/(y[ej2]/60))/(m3[D[ej1]['t']]/(y[ej1]/60)),1) + ' veces más rápida'}); por tamaño ÷ real son {f(tam[ej1]/y[ej1],2)} contra {f(tam[ej2]/y[ej2],2)}: el m³ no ve las {int(par[ej2])} paradas ni las {int(altas[ej2])} líneas con escalera de la segunda{', ni los ' + f(min(cola[ej2],TOPE_COLA),0) + ' min de cola que ahora se le cobran' if cola[ej2] >= 5 else ''}. Por operario (tabla en (f)): por m³/h el orden es {' > '.join(o['legajo'] for o in sorted([o for o in pub if o['m3_por_hora']], key=lambda o: -o['m3_por_hora']))} y por tamaño {' > '.join(o['legajo'] for o in sorted(pub, key=lambda o: -o['indice']))}; por m³/h el primero hace {f(max(o['m3_por_hora'] for o in pub)/min(o['m3_por_hora'] for o in pub),1)} veces lo del último, por tamaño {f(max(o['indice'] for o in pub)/min(o['indice'] for o in pub),1)} veces. El m³ premia a quien lleva pallets enteros de pocos códigos; el tamaño cobra las paradas, la altura y la cola.

## (c) La altura cuando el artículo ocupa varias celdas

Altura dentro del módulo = ((celda − 1) mód alto) + 1, con la 1 abajo; A y P tienen 5 alturas, B a Ñ tienen 4; escalera en A y P desde la 4.ª y en las demás desde la 3.ª. Un código con celdas en una sola altura tiene altura conocida ({f(sum(kn.values()),0)} líneas en las {N} tandas). Para un código con celdas en varias alturas la app no registra de qué celda salió la caja, así que se infiere con la regla de Luis: stock de góndola del código al abrir el picking contra la capacidad en cajas de cada celda, apilando el stock de arriba hacia abajo; la línea toma la altura MÁS BAJA que seguro tiene stock. Con 4 alturas de 100 cajas y 300 de stock, seguro hay en la 2.ª → 2.ª. Stock mayor que la capacidad total → piso. Es una cota a favor del operario: si había en el piso, la línea costó menos de lo asignado. Stock 0 o sin dato → clase MX ({int(NH['MX'].sum())} líneas, {mxcor} de ellas cortas: el operario fue y no estaba).

Resultado: {f(sum(inn.values()),0)} líneas con altura inferida, {f(sum(kn.values()),0)} conocidas, {int(NH['MX'].sum())} MX y {int(NH['F'].sum())} fuera de góndola. Por clase, conocidas / inferidas: {' · '.join(f"{h} {f(kn[h],0)}/{f(inn[h],0)}" for h in CL[:9])}. A5 es toda conocida y A1 casi toda inferida: dentro de una clase casi no hay con qué comparar.

Cómo cayeron los artículos grandes (líneas por altura asignada): {' · '.join(cod + ' → ' + ', '.join(f"{k} {v}" for k, v in sorted(cnt.items())) for cod, cnt in grandes.items())}.

Prueba de que la inferida se comporta como la conocida: (1) un coeficiente extra por línea inferida, con todo lo demás en el modelo, da {f(k_inf*60,1)} s por línea con intervalo bootstrap {f(np.percentile(kb,5)*60,0)} a {f(np.percentile(kb,95)*60,0)} s: incluye el 0, pero el intervalo es más ancho que lo que cuesta una línea de piso, así que no prueba igualdad, sólo que no hay un sesgo grande. (2) Lo que sí la sostiene para el uso que importa: ajustando sólo con la mitad de tandas menos inferida ({len(lo)} tandas, fracción ≤ {f(med,2)}) y prediciendo la otra mitad ({len(hi)} tandas), el sesgo es {f(np.mean(y[hi]-pv_hi),2)} min sobre {f(np.mean(y[hi]),1)} reales ({f(np.mean(y[hi]-pv_hi)/np.mean(y[hi])*100,1)} %), con error menor que el del modelo completo ({f(rmse(y[hi],pv_hi),1)} min), y los costos por altura salen parecidos en las dos mitades (A1 {f(c_lo['A1']*60,0)}/{f(c_hi['A1']*60,0)} s · A5 {f(c_lo['A5']*60,0)}/{f(c_hi['A5']*60,0)} · R1 {f(c_lo['R1']*60,0)}/{f(c_hi['R1']*60,0)} · R4 {f(c_lo['R4']*60,0)}/{f(c_hi['R4']*60,0)}). Los revisores de esta corrida lo midieron por su lado con el mismo resultado: en B a Ñ, donde está el grueso de las inferidas, la inferida sale unos 4 s por línea más cara que la conocida, que es la dirección que se espera de una cota «la más baja que seguro tiene stock», y dentro del ruido. Vale para el tamaño y para el índice por operario; si cada altura cuesta lo mismo conocida que inferida lo va a decir el registro por paso.

## (d) La cola

La cola de una tanda son los minutos sin ningún registro entre su TP y la próxima tarea registrada del operario («sig», {sum(1 for r in feat if r['cola_sig']=='sig')} tandas), o hasta la hora de salida si no hubo nada más («cap», {sum(1 for r in feat if r['cola_sig']=='cap')}); vale 0 si al cerrar ya tenía otro tramo abierto («cubierta», {sum(1 for r in feat if r['cola_sig']=='cubierta')}). Cuánto pesa: mediana {f(np.median(colaF),1)} min, media {f(colaF.mean(),1)}, p90 {f(np.percentile(colaF,90),1)}, p95 {f(np.percentile(colaF,95),1)}; en total es el {f(cola.sum()/ysh.sum()*100,0)} % del picking puro. Cuatro tandas pasan de una hora: {' · '.join(f"{r['t']} (legajo {r['l']}) {f(r['cola'],0)} min «{r['cola_sig']}»" for r in colas60)}.

Las dos «cap» de horas (D40F: 5 líneas, 28 cajas, 10 min de picking y 8,6 h de cola; D67D: 36 líneas, 70 min de picking y 5,3 h de cola) son **outliers explícitos**: un operario que no registró nada más ese día no estuvo 8 horas acomodando 28 cajas. Con ellas adentro y la cola cruda el ajuste se rompe (R² {f(r2a,3)}, error {f(rma,0)} min, el fijo sube a {f(ca['cfijo']+ca['arranque'],0)} min). Quedan fuera del ajuste y en la lista de tandas van marcadas; su índice con la cola cruda sería {f(tam_de(OUT[0])/OUT[0]['neto_cola'],2)} y {f(tam_de(OUT[1])/OUT[1]['neto_cola'],2)}.

Por qué el tope: la cola no depende de nada de la tanda. Regresada sola contra paradas, cajas y alturas explica el {f(r2(np.minimum(cola,TOPE_COLA), Xc@bc)*100,0)} % de su variación (correlación con paradas {f(np.corrcoef(cola,par)[0,1],2)}, con cajas {f(np.corrcoef(cola,caj)[0,1],2)}, con líneas {f(np.corrcoef(cola,n)[0,1],2)}): es un fijo por tanda con mucho ruido, y es sobre todo un hábito del operario ({' · '.join(f"{o['legajo']} {f(o['cola_pct_neto_sh'],0)} %" for o in sorted(pub, key=lambda o: o['cola_pct_neto_sh']))} de su picking puro). Sumada cruda al tiempo, le carga a la parada +0,18 min que son dos tandas con cola «sig» de 2 y 3 horas (E37F, D52C), y baja el R² de 0,55 a 0,42 sin mover las alturas: eso midieron los tres modelos y los dos revisores. Topeada a {f(TOPE_COLA,0)} min toca {int((cola>TOPE_COLA).sum())} de las 338 tandas, cuesta lo mismo en validación que cualquier otra forma de meterla (error contra el tiempo crudo {f(opc[f'neto_sh + cola topeada {f(TOPE_COLA,0)}'][0],1)} min; cola cruda {f(opc['neto_sh + cola cruda'][0],1)}; tope 60 {f(opc[f'neto_sh + cola topeada {f(TOPE_ALT,0)}'][0],1)}; picking puro más un fijo {f(e_fijo,1)}) y deja un esquema que todavía explica el picking (R² {f(r2(y,pred),3)} contra {f(opc['neto_sh + cola cruda'][2],3)} con la cola cruda).

A quién se le cargó, comparando con el mismo modelo ajustado sobre el picking puro de las mismas 338 tandas: de los {f(np.minimum(cola,TOPE_COLA).sum(),0)} min de cola topeada, el fijo por tanda se lleva {f(dmin['cfijo'],0)} ({f(dmin['cfijo']/np.minimum(cola,TOPE_COLA).sum()*100,0)} %: {f(c_sh['cfijo'],2)} → {f(c['cfijo'],2)} min), la parada {f(dmin['parada'],0)} ({f(dmin['parada']/np.minimum(cola,TOPE_COLA).sum()*100,0)} %: {f(c_sh['parada']*60,0)} → {f(c['parada']*60,0)} s por parada), el arranque {f(dmin['arranque'],0)} y la caja {f(dmin['caja'],0)}; las alturas no se mueven (A5 {f(c_sh['A5']*60,0)} → {S('A5')} s, R4 {f(c_sh['R4']*60,0)} → {S('R4')} s). Lo que va a la parada no es de dos tandas: sin E37F y D52C la parada queda en {f(cS['parada']*60,0)} s. Con tope 60 en vez de 30 el fijo más arranque baja a {f(c60['cfijo']+c60['arranque'],2)} min y la parada sube a {f(c60['parada']*60,0)} s; el resto, igual.

## (e) Qué tan bien predice

| | R² | error típico (RMSE) | validación cruzada 10-fold | sin un operario (LOO) |
|---|---|---|---|---|
| esquema final (picking + cola topeada {f(TOPE_COLA,0)}) | {f(r2(y,pred),3)} | {f(rmse(y,pred),1)} min | {f(cv_rmse,1)} min | {f(loo_rmse,1)} min |
| el mismo esquema sobre el picking puro (corrida anterior) | {f(V3['validacion']['r2'],3)} | {f(V3['validacion']['rmse'],1)} min | {f(V3['validacion']['cv_rmse'],1)} min | {f(V3['validacion']['loo_operario_rmse'],1)} min |
| reajuste sobre picking + cola cruda (los tres modelos) | {f(REST['r2'],3)} | {f(REST['rmse'],1)} min | {f(REST['cv_rmse'],1)} min | {f(REST['loo_rmse'],1)} min |
| sólo fijo + arranque + parada + cajas (sin alturas) | {f(r2(y, Xs@bs),3)} | — | {f(cv_sin,1)} min | — |
| modelo previo v26.25 (1,1 + 48 s/parada + 7 s/caja + 59 s/escalera) | {f(r2(y,prev),3)} | {f(rmse(y,prev),1)} min | — | — |

Contra el tiempo con la cola cruda, cualquiera de las variantes predice con ±{f(cv_cr,0)} min; ese error no es del modelo, es de la cola, que ninguna variable del picking predice. El esquema final explica la mitad de la variación del picking + cola topeada con un error típico de ±{f(cv_rmse,0)} min por tanda (mediana de tiempo real {f(np.median(y),0)} min): el índice sirve para la suma de decenas de tandas, no para una suelta. El error está en las colas: {' · '.join(f"{D[i]['t']} {f(y[i],0)} reales contra {f(tam[i],0)} esperados" for i in big[:4])}. El previo aplicado tal cual predice {f(np.mean(prev-y),1)} min de más por tanda: sus 7 s por caja son {f(0.117/c['caja'],1)} veces los {f(c['caja']*60,1)} s que ajustan acá (fue medido contra otro target). Las alturas no mejoran la predicción contra «fijo + arranque + parada + cajas» ({f(cv_sin,1)} vs {f(cv_rmse,1)} min): lo que aportan es que el reparto entre parada, línea y altura tenga sentido y se pueda leer. Real ÷ esperado por tramo de líneas: {' · '.join(f"{a} {f(v,2)}" for a, _, v in tramos(pred, n, TL))} — las tandas de 4-9 líneas siguen saliendo sobrepredichas.

## (f) Índice por operario

Índice = suma de tamaños ÷ suma de tiempos reales (picking + cola topeada) de sus tandas. **1,00 = el promedio; más de 1 = más rápido**. La columna «picking puro» es el mismo índice sin la cola (corrida anterior, mismas 338 tandas) y «10-40 líneas» repite la cuenta sólo con tandas de ese tamaño, para comparar con el mismo mix. «Cola» es cuánto pesa su cola sobre su picking puro. Con menos de 10 tandas el número no se publica.

| legajo | nombre | tandas | cajas | cola | m³/h | índice | picking puro | 10-40 líneas |
|---|---|---|---|---|---|---|---|---|
{chr(10).join(op_rows)}

(La consigna decía «104 Cartaya»; el padrón que se usó acá dice 104 J. Moncayo «J. Colombia» y 277 J. Cartaya «Jhonny».) La cola mueve el índice como pide la regla: 122, que cierra el TP con la tanda acomodada (cola {f(next(o['cola_pct_neto_sh'] for o in idx_op if o['legajo']=='122'),0)} %), sube de {f(next(o['indice_neto_sh'] for o in idx_op if o['legajo']=='122'),2)} a {f(next(o['indice'] for o in idx_op if o['legajo']=='122'),2)}; 277 y 504, con cola de un cuarto de su picking, bajan. Sacando cada operario del ajuste y prediciéndolo con los demás, los lentos siguen saliendo lentos y 104 rápido: el índice mide al operario, no el mix de tandas. 237 y 600 tienen una tanda menos que en la corrida anterior (los dos outliers).

## (g) Riesgos

- La cola sin tope rompe el índice: dos tandas «cap» valen 5 y 8 horas y una «sig» de 3 horas (E37F) mueve el índice de 60 días del 277 de {f(sum(tam[(leg=='277') & (np.array([r['t'] for r in D]) != 'E37F')])/sum(ycr[(leg=='277') & (np.array([r['t'] for r in D]) != 'E37F')]),2)} a {f(next(o['indice_cola_cruda'] for o in idx_op if o['legajo']=='277'),2)}. El tope de {f(TOPE_COLA,0)} min y que «cap» no corra hasta la hora de salida tienen que vivir en la regla de la base, no sólo acá.
- Los costos de piso, 2.ª y 3.ª vienen del ancla de medianas, no de estas tandas; el dato no distingue una parada de una línea, no ve la escalera de la 3.ª en B a Ñ, y MX y F están atados por decisión.
- El nivel de dificultad con cajas en el denominador ordena por cajas (correlación {f(sp(dif[ok], caj[ok]),2)}), no por altura; y el índice individual con menos de 10 tandas (8, 94, 237, 600) no se sostiene (sin un operario, el error del 94 es de {f(loo['94'][1],0)} min por tanda).

## (h) Lo que falta medir

El registro por paso que arranca el lunes 05/10 (`GV_Picking_Paso_Evento`: mostrado, ok, faltan, sin stock, adelante, atrás) da el tiempo de cada línea por separado, y con eso se mide de verdad lo que acá está anclado: cuánto cuesta la parada contra la línea, el piso contra la 2.ª y la escalera de la 3.ª en B a Ñ, cuánto tarda un código con stock 0 (MX) y uno fuera de góndola (F), si la altura inferida cuesta lo mismo que la conocida por clase, y cuánto de la cola es acomodar en la mesa y cuánto es no registrar. Para que eso se pueda medir sin inferir hace falta cambiar la app en dos lugares: que el picking registre la CELDA de la que se sacó la caja (hoy sólo el código) y que el guardado a góndola registre en qué celda se puso; con los dos la altura deja de ser una cota y los costos por altura se recalculan con dato propio. Mientras tanto, el tope de 30 cajas por línea, el arranque hasta 5 líneas y el tope de la cola conviene fijarlos también en la app, que es donde se va a calcular el tamaño.
"""
open(os.path.join(UP, "d17_esquema.md"), "w").write(md)
P("escrito: d17_esquema.md")
