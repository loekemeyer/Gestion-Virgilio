-- ═══════════════════════════════════════════════════════════════════════════════════════
-- ANCLA DE CLIENTE · v20.27 (2026-09-20)
--
-- Luis, 20/09, sobre el cartel rojo de la PPP (*"2 cliente(s) con entregas en días distintos
-- de la misma semana — tendrían que ir juntos … Movelo a mano al día que corresponda"*):
-- ***"esto hay que arreglarlo"***.
--
-- El cartel no era un error: el armado dejaba el choque A LA VISTA a propósito y esperaba a
-- una persona. Con *"yo quiero que todo se programe automático"* eso deja de alcanzar.
--
-- LA REGLA, que es de Thomas: *"nunca si hay +1 pedido de un cliente puede ir separado en la
-- PPP, salvo los súper"*. El **día** del cliente manda sobre el día de la zona. La **tanda**
-- se sigue partiendo por camión (v18.87, Luis): un cliente con sucursales en dos zonas sale el
-- mismo día en dos tandas y dos camiones — lo que no puede es salir en dos días.
--
-- EL PASE (b00) VA ANTES DEL (b0). Si el cliente ya tiene un día programado dentro de la
-- ventana, el pedido nuevo va a ESE día, tenga o no camión de su etiqueta. Recién si el cliente
-- no tiene día se pregunta por la zona (b0), y recién después por el cupo (b).
--
-- ⚠ FUERZA EL CUPO (`p_forzar_cods` con los cods del día, `p_incluir_manuales = true`). No es
--   una licencia: no juntar al cliente es un segundo viaje al mismo domicilio, que cuesta más
--   que el m³ de más en el día. Es la misma precedencia que ya tenía el pase (c).
--
-- ⚠ MIRA LAS DOS PROGRAMACIONES, la web y la de ISIS. El caso que lo destapó es
--   **Riondini Federico (LK 4105)**: 98605, 98606 y 98607 de ISIS el lun 21/09 y **LK 0118**
--   web el jue 24/09, las cuatro Zona 3 y las cuatro al camión de Capital. El guard viejo
--   `gv_web_cliente_un_solo_dia` no lo ve porque sólo mira `PPP_Web_Programacion` (idea 9869).
--   El otro del cartel, **Jazquel SRL (LK 3814)**, es web contra web: LK 0109 (E46C, zona 5,
--   mié 23/09) contra 8 NP (E48D, zona 2, lun 28/09).
--
-- ⚠ La clave del cliente es **(empresa, cod)**, nunca `cod` solo: el mismo número es otro
--   cliente en la otra empresa (regla de Thomas del 16/09, 114 de 115 códigos compartidos son
--   personas distintas).
--
-- CÓMO SE PROBÓ — corriendo el armador de verdad, en transacción abortada:
--   Pedido nuevo de Jazquel en zona 6  → 23/09, día que Jazquel YA tiene (no fundó uno nuevo).
--   Pedido nuevo de Riondini en zona 3 → 24/09, día que Riondini YA tiene.
--   Pedido de un cliente sin historia  → cae al ancla de zona, como antes.
-- ═══════════════════════════════════════════════════════════════════════════════════════

create or replace function public.gv_ppp_web_dias_cliente(
  p_empresa text, p_cod text, p_desde date, p_ventana int default null)
returns date[]
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with vent as (select coalesce(p_ventana,
                  (select valor::int from public."PPP_Web_Config" where clave = 'ancla_ventana_habiles'),
                  10) as v),
  piso as (select least(coalesce(p_desde, current_date + 1), current_date + 1) as d),
  hor as (select max(dia) as h from (
            select g::date dia, row_number() over (order by g) rn
              from piso, generate_series(piso.d, piso.d + 45, interval '1 day') g
             where public.gv_es_dia_habil(g::date)) q, vent
           where q.rn <= vent.v),
  dias as (
    select w.fecha_entrega as dia
      from public."PPP_Web_Programacion" w, piso, hor
     where lower(w.empresa) = lower(public.gv_emp_norm(p_empresa))
       and regexp_replace(btrim(coalesce(w.cod_cliente,'')), '\.0+$', '')
         = regexp_replace(btrim(coalesce(p_cod,'')), '\.0+$', '')
       and w.fecha_entrega >= piso.d and w.fecha_entrega <= hor.h
       and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
    union
    select left(btrim(i.fecha_entrega::text), 10)::date
      from public.gv_ppp_programacion_diaria i, piso, hor
     where public.gv_emp_de_np(i.np) = public.gv_emp_norm(p_empresa)
       and regexp_replace(btrim(coalesce(i.cod,'')), '\.0+$', '')
         = regexp_replace(btrim(coalesce(p_cod,'')), '\.0+$', '')
       and btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
       and left(btrim(i.fecha_entrega::text), 10)::date between piso.d and hor.h
       and coalesce(nullif(btrim(i.tanda), ''), '') <> '')
  select coalesce(array_agg(dia order by dia), '{}') from (select distinct dia from dias) z;
$function$;

revoke all on function public.gv_ppp_web_dias_cliente(text, text, date, int) from public;
grant execute on function public.gv_ppp_web_dias_cliente(text, text, date, int) to anon, authenticated, service_role;

-- El pase (b00) se inserta en gv_ppp_web_armar_pendientes trayendo la definición VIVA con
-- pg_get_functiondef y cortando por el marcador '  -- (b0) v20.26'. El DO block completo está
-- en docs/SUPABASE-GESTION-VIRGILIO.md §3.kn. NUNCA retipear el cuerpo de esa función.

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
 ('gv_ppp_web_armar_pendientes','funcion','gv_ppp_web_dias_cliente',
  'El dia del CLIENTE manda sobre el dia de la zona: un cliente nunca sale en dos dias (regla de Thomas).','Luis','v20.27'),
 ('gv_ppp_web_dias_cliente','funcion','gv_ppp_programacion_diaria',
  'El ancla de cliente mira las DOS programaciones, web y ISIS: el choque de Riondini era ISIS contra web.','Luis','v20.27')
) v(objeto,clase,patron,regla,quien_pidio,version)
where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto=v.objeto and c.patron=v.patron);
