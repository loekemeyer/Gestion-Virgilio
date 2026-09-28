-- v23.37 (Luis, 28/09): el centinela vigila tambien TRIGGERS (clase 'trigger': pg_get_triggerdef por
-- tgname) y el freno de súper tiene sus dos filas. Probado: dropeando el trigger en transaccion
-- abortada, gv_reglas_perdidas pasa de 0 a 1 ("EL OBJETO NO EXISTE").
create or replace view public.gv_reglas_perdidas with (security_invoker = true) as
 SELECT r.objeto, r.regla, r.quien_pidio, r.version,
        CASE WHEN x.cuerpo IS NULL THEN 'EL OBJETO NO EXISTE'::text
             ELSE 'LA REGLA SE PERDIO (alguien reemplazo el objeto con una copia vieja)'::text END AS que_paso,
        r.patron
   FROM "GV_Reglas_Centinela" r
     LEFT JOIN LATERAL ( SELECT
                CASE
                    WHEN r.clase = 'vista'::text THEN ( SELECT pg_get_viewdef(c.oid, true)
                       FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                      WHERE n.nspname = 'public'::name AND c.relname = r.objeto AND (c.relkind = ANY (ARRAY['v'::"char", 'm'::"char"])))
                    WHEN r.clase = 'trigger'::text THEN ( SELECT pg_get_triggerdef(t.oid)
                       FROM pg_trigger t WHERE t.tgname = r.objeto AND NOT t.tgisinternal LIMIT 1)
                    ELSE ( SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                      WHERE n.nspname = 'public'::name AND p.proname = r.objeto LIMIT 1)
                END AS cuerpo) x ON true
  WHERE r.activo AND (x.cuerpo IS NULL OR NOT gv_regla_presente(x.cuerpo, r.patron));
alter view public.gv_reglas_perdidas set (security_invoker = true);
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
 ('gv_ppp_web_super_tanda_sola','funcion','raise exception .SUPER_TANDA_SOLA',
  'Pedido de súper siempre en su propia tanda: ni con clientes ni con otro pedido del mismo súper, aunque sea el mismo día y la misma condición de entrega','Luis','v23.36'),
 ('gv_ppp_web_super_tanda_sola','trigger','BEFORE INSERT OR UPDATE OF tanda ON public\."PPP_Web_Programacion"',
  'El freno de súper en su propia tanda tiene que seguir enganchado a PPP_Web_Programacion (si se dropea el trigger la función queda muerta)','Luis','v23.36');
