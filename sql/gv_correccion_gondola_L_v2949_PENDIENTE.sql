-- v29.49 · PENDIENTE DEL «sí» DE LUIS (D1). NO EJECUTADO.
-- Saca de góndola las cajas que el armado devolvió por error (pedidos con L / 809 corregido).
-- v29.50: SÓLO F58A y F48A (armadas, sin facturar): terminado −N y a_facturar +N.
-- Efecto: góndola −188 cajas (F58A 185 · F48A 3); a_facturar +188. Lo viejo y facturado NO se toca.
with sep as (
  select upper(trim(ref)) tanda, upper(regexp_replace(regexp_replace(trim(cod_art),' +(LK|CH)$',''),'^0+(?=.)','')) artn,
         max(cod_art) cod, coalesce(empresa,'Mixto') emp,
         sum(delta) filter (where deposito='terminado') te, coalesce(sum(delta) filter (where deposito='a_facturar'),0) af
    from public."Movimientos_Stock" where tipo='separado' and upper(trim(ref)) in ('F58A','F48A') group by 1,2,4),
ent as (select tanda, artn, emp_l, sum(ent) ent from public.gv_entregas_norm group by 1,2,3),
c as (select s.tanda, s.cod, s.emp,
        least(s.te, (select sum(e.ent) from ent e where e.tanda=s.tanda and e.artn=s.artn
                      and (e.emp_l is null or e.emp_l=s.emp or s.emp not in ('LK','CH'))) - s.af) n
        from sep s where s.te > 0)
insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa, client_id, descripcion)
select c.cod, x.dep, x.sig*c.n, 'ajuste', c.tanda, 'sistema', nullif(c.emp,'Mixto'),
       'v2949_corr_'||c.tanda||'_'||c.cod||'_'||x.dep, 'Corrección v29.49: el armado devolvió a góndola cajas de un pedido con L'
  from c cross join lateral (values ('terminado',-1), ('a_facturar',1)) x(dep, sig)
 where c.n > 0;
-- verificación: select * from public.gv_stock_tanda_pickeado_negativo; select * from public.gv_stock_negativos;
