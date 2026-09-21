-- v20.74 — El badge de destino dice lo que dice EL PEDIDO, no la ficha del padron
-- Pedido de Thomas, 2026-09-21: "que puso el cliente? que retira o que se lo entreguemos en algun
-- lado? eso es lo que tiene que decir el badge y asi es como lo tiene que tomar el sistema a menos
-- que se cambie de alguna forma" · y despues: "el badge deberia reflejar la realidad, por que lo
-- que eligio el cliente no seria la realidad?".
--
-- TIENE RAZON, Y LA PRECISION ES UNA SOLA
-- Lo que el cliente eligio ES la realidad del pedido. Lo que no alcanza es leer el NOMBRE de la
-- sucursal que eligio: hay que leer su DIRECCION.
--   "Convenir en Av. Panamericana" (Muller y Muller) -> direccion = Virgilio 2788 = el deposito
--                                                       -> RETIRA, aunque el nombre no lo diga
--   "Burgwardt 903 - Longchamps"   (Iro Iro)          -> direccion real -> ENTREGA ahi
-- Eso ya lo resuelve `es_retira` de gv_np_destino, que mira la direccion y el barrio que viajan
-- con la NP (`^retira$`, `Exp. Retira — …`, `virgilio\s*2788`). Lo que faltaba era USARLO para el
-- badge: el badge salia de `nombre_expreso` del PADRON, que es otro campo, lo mantiene otra gente
-- y no dice nada del pedido.
--
-- QUE CAMBIA, en una sola expresion (la columna `expreso` de gv_np_destino):
--   antes:  CASE WHEN ok THEN nombre_expreso ELSE NULL END
--   ahora:  CASE WHEN es_retira THEN 'Retira'
--                WHEN ok AND nombre_expreso NO ES 'Retira' THEN nombre_expreso
--                ELSE NULL END
-- Las dos mitades hacen falta:
--   (a) el pedido dice retira -> el badge dice Retira, aunque el padron calle (eran 9 NP mudas);
--   (b) el pedido dice que se entrega -> el badge NUNCA dice Retira, aunque el padron lo diga.
-- (b) es el problema 470 resuelto de RAIZ: ahi el Retira arrastrado en la ficha se limpio a mano
-- en 4 clientes, y quedaban 8 fichas con el mismo arrastre esperando su turno. Ahora el dato del
-- padron no puede mentirle al badge: manda el pedido.
--
-- ⚠ EL PADRON SIGUE SIRVIENDO PARA LO QUE ES: `nombre_expreso` dice POR QUE MEDIO viaja (Snaider,
-- Arias, Tim Car…), y eso se sigue mostrando. Lo unico que ya no puede hacer es decidir si retira.
--
-- MEDICION (21/09, 337 NP programadas — web + ISIS)
--   badge "Retira" ................ antes 17, ahora 24
--   zona Retira sin badge ......... antes  9, ahora  0
--   se reparte y el badge decia Retira .. 0 (las 4 fichas ya estaban limpias; la regla lo blinda)
--   con expreso real .............. 118, sin cambio
--   gv_destino_sin_provincia ...... 24, sin cambio
--
-- ⚠ COMO SE APLICO, Y EL PASO EN FALSO QUE CONVIENE NO REPETIR
-- Se parcheo la vista con pg_get_viewdef -> replace -> create or replace. El primer intento uso
-- un regexp con \s+ y 'g' pensando que agarraba las dos apariciones del CASE (la columna `expreso`
-- y la de `destino_txt`): agarro la de destino_txt y NO la de la columna, asi que la vista quedo a
-- medias y las 6 NP de Retira seguian mudas. Lo canto la prueba, no la lectura. El segundo intento
-- uso replace() LITERAL contra el texto exacto terminado en 'END AS expreso,' — con eso anduvo.
-- Moraleja: al parchear una vista por texto, verificar el resultado CONSULTANDO la vista, y no dar
-- por bueno el "reemplazos: N".
--
-- ⚠ Y ACORDARSE DEL security_invoker: `create or replace view` sin WITH borra las reloptions. El
-- bloque de abajo lo chequea ANTES (si la vista no lo tiene, frena) y lo repone DESPUES.

do $outer$
declare
  v_def text; v_new text; v_opts text;
  v_old text := E'        CASE\n            WHEN ok THEN nombre_expreso\n            ELSE NULL::text\n        END AS expreso,';
  v_rep text := E'        CASE\n            WHEN es_retira THEN \'Retira\'::text\n            WHEN ok AND COALESCE(nombre_expreso, \'\'::text) !~* \'^retira$\'::text THEN nombre_expreso\n            ELSE NULL::text\n        END AS expreso,';
begin
  select array_to_string(reloptions, ',') into v_opts from pg_class where oid = 'public.gv_np_destino'::regclass;
  if coalesce(v_opts,'') not like '%security_invoker%' then
    raise exception 'gv_np_destino NO tiene security_invoker (%): freno.', coalesce(v_opts,'(sin opciones)');
  end if;
  v_def := pg_get_viewdef('public.gv_np_destino'::regclass, true);
  if position('es_retira THEN' in v_def) > 0 and position(v_old in v_def) = 0 then
    raise notice 'ya aplicado'; return;
  end if;
  if position(v_old in v_def) = 0 then
    raise exception 'no encontre el CASE de la columna expreso tal cual: no toco nada';
  end if;
  v_new := replace(v_def, v_old, v_rep);
  execute 'create or replace view public.gv_np_destino as ' || v_new;
  execute 'alter view public.gv_np_destino set (security_invoker = true)';
end $outer$;

-- ── CHEQUEO ──────────────────────────────────────────────────────────────────
-- Las dos mitades de la regla, sobre lo programado (web + ISIS). Las dos tienen que dar 0:
-- with prog as (
--   select public.gv_ppp_web_np_label(w.empresa,w.np,w.np_idx) np, w.zona from public."PPP_Web_Programacion" w
--   union all
--   select regexp_replace(upper(btrim(d.np)),'\.0+$',''), d.zona from public.gv_ppp_programacion_diaria d where d.np is not null)
-- select count(*) filter (where d.expreso = 'Retira' and p.zona !~* '^retira')     as se_reparte_y_dice_retira,
--        count(*) filter (where p.zona ~* '^retira' and coalesce(d.expreso,'') <> 'Retira') as retira_sin_badge
--   from prog p left join public.gv_np_destino d on d.np = p.np;
--
-- y los centinelas de siempre:
-- select * from public.gv_retira_contradictorio;   -- vacia
-- select * from public.gv_retira_sin_etiqueta;     -- vacia
-- select * from public.gv_destino_sin_provincia;   -- 24 al 21/09, sin cambio por esto
