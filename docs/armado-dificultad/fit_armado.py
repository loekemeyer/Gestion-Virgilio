# v29.48 (D5, Thomas 12/10) — calibración del modelo de ARMADO (NNLS, sin scipy).
# Datos: GV_Armado_Tanda ya calculada por gv_armado_tanda_calc (real = AP→TAP − pausas + cola ≤ 30):
#   select json_agg(json_build_object('t',tanda,'l',legajo,'np',nps,'li',lineas,'c30',cajas30,'ex',extra,'sup',super,
#          'y',real_min,'b',bruto_min)) from public."GV_Armado_Tanda";
# Medibles: 1 ≤ real ≤ 240, bruto ≤ 360, líneas > 0. Resultado del 12/10 (426 tandas):
#   NP 5,0628 · línea 0,6068 · caja (≤ 30/línea) 0,3515 · caja 30–330/línea 0,0757 · súper 30,4257 · corr 0,845.
# La primera versión de abajo (arm2.json, sin cola) es la exploración; los coeficientes finales salen del real con cola.
import json, numpy as np
def nnls(A,b,it=500):
    m,n=A.shape; P=[];x=np.zeros(n);w=A.T@(b-A@x)
    for _ in range(it):
        Z=[j for j in range(n) if j not in P]
        if not Z or max(w[Z])<=1e-9: break
        j=Z[int(np.argmax(w[Z]))]; P.append(j)
        while True:
            s=np.zeros(n); s[P]=np.linalg.lstsq(A[:,P],b,rcond=None)[0]
            if min(s[P])>0: x=s; break
            q=[k for k in P if s[k]<=0]; a=min(x[k]/(x[k]-s[k]) for k in q); x=x+a*(s-x)
            P=[k for k in P if x[k]>1e-12]
        w=A.T@(b-A@x)
    return x
d=json.load(open('arm2.json'))
rows=[r for r in d if r['lineas'] and r['nps']]
for r in rows: r['ret']=1 if r['retira'] else 0
for r in rows: r['y']=r['bruto']-r['pausa']; r['lios']=r['lios'] or 0; r['extra']=r['cajas']-r['cajas30']; r['sup']=1 if r["super"] else 0
rows=[r for r in rows if 1<=r['y']<=240]
y=np.array([r['y'] for r in rows])
def ev(cols, rs=rows, show=True):
    A=np.array([[1.0]+[float(r[c]) for c in cols] for r in rs]); yy=np.array([r['y'] for r in rs])
    c=nnls(A,yy); p=A@c
    if show: print(cols, dict(zip(['fijo']+cols,np.round(c,4))), "corr",round(np.corrcoef(p,yy)[0,1],3),"MAE",round(np.mean(abs(yy-p)),2))
    return c
for cols in (['nps','lineas','cajas30','extra','sup','ret'],['nps','lineas','cajas30','extra','sup'],['nps','lineas','cajas30','extra'],['nps','lineas','cajas30'],['lineas','cajas30'],['nps','lios','lineas','cajas30','extra','sup']):
    ev(cols)
# cross-validation 5-fold for chosen
cols=['nps','lineas','cajas30','extra','sup']
rng=np.random.default_rng(1); idx=rng.permutation(len(rows)); mae=[]
for k in range(5):
    te=set(idx[k::5]); tr=[r for i,r in enumerate(rows) if i not in te]; tst=[r for i,r in enumerate(rows) if i in te]
    c=ev(cols,tr,False); A=np.array([[1.0]+[float(r[c2]) for c2 in cols] for r in tst]); yy=np.array([r['y'] for r in tst])
    mae.append(np.mean(abs(yy-A@c)))
print("CV MAE",round(np.mean(mae),2))
# per operario index with chosen model
c=ev(cols,show=False); A=np.array([[1.0]+[float(r[c2]) for c2 in cols] for r in rows]); p=A@c
import collections
g=collections.defaultdict(lambda:[0,0,0])
for r,pp in zip(rows,p): g[r['l']][0]+=pp; g[r['l']][1]+=r['y']; g[r['l']][2]+=1
for l,(a,b,n) in sorted(g.items(), key=lambda x:-x[1][2]): print(l,n,round(a/b,3))
# residual by super
for s in (0,1):
    rs=[(r['y'],pp) for r,pp in zip(rows,p) if r['sup']==s]; print("sup",s,len(rs), round(sum(a for a,_ in rs)/sum(b for _,b in rs),3))
print("---- top extra")
cols=['nps','lineas','cajas30','extra','sup']; c=ev(cols,show=False)
for r in sorted(rows,key=lambda r:-r['extra'])[:14]:
    p=c[0]+sum(c[i+1]*r[k] for i,k in enumerate(cols)); print(r['t'],r['l'],r['nps'],r['lineas'],r['cajas'],round(r['extra']),'y',round(r['y'],1),'p',round(p,1))
print("excluded big:", [(r['t'],r['bruto'],r['cajas']) for r in d if r['t'] in ('E84A','E85A','D71A','E78A')])
