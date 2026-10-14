-- D3 (Luis, 14/10/2026): el Analisis Productivo NO publica el indice mientras la cola del operario
-- sigue abierta (cola_tipo='cap' y la tanda es de hoy: todavia no hay evento siguiente).
-- Caso: F89A mostro 328 % con 1,4 min pelados; al cerrar la cola (+1,8 min) quedo en 144 %.
-- Aplicado sobre la definicion VIVA con replace() (gv_analisis_tanda tiene regla protegida: se mantuvo).
-- REGLA_CONFIRMADA_POR_USUARIO
do $d$
declare l text := pg_get_functiondef('public.gv_analisis_lista(int,text,text)'::regprocedure);
        t text := pg_get_functiondef('public.gv_analisis_tanda(text,text)'::regprocedure);
        l2 text; t2 text;
        prov text := 'case when t.cola_tipo = ''cap'' and (t.tp at time zone ''America/Argentina/Buenos_Aires'')::date = v_hoy then null else t.indice end indice';
begin
  if t ~ 'v29.86-cola-abierta' then return; end if;
  l2 := replace(l, 't.real_min, t.indice, t.grado', 't.real_min, ' || prov || ', t.grado');
  t2 := replace(t, '  select e.tamano_inicial into v_est_pk',
'  -- v29.86-cola-abierta (D3, Luis 14/10): la cola del operario sigue abierta (hoy, sin evento siguiente):
  -- el indice es provisorio y no se publica (F89A mostro 328 % y al cerrar la cola quedo en 144 %)
  if v_pk.cola_tipo = ''cap'' and (v_pk.tp at time zone ''America/Argentina/Buenos_Aires'')::date = (now() at time zone ''America/Argentina/Buenos_Aires'')::date then v_pk.indice := null; end if;
  if v_ar.cola_tipo = ''cap'' and (v_ar.tp at time zone ''America/Argentina/Buenos_Aires'')::date = (now() at time zone ''America/Argentina/Buenos_Aires'')::date then v_ar.indice := null; end if;
  select e.tamano_inicial into v_est_pk');
  execute l2; execute t2;
end $d$;
