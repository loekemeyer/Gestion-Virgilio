-- =====================================================================================
-- v19.52 (Luis, 2026-09-17) — RETIRA: EL DÍA Y LA FRANJA QUE ELIGIÓ EL CLIENTE VIAJAN
--                              CON EL PEDIDO Y SE PROGRAMAN SOLOS.
-- =====================================================================================
--
-- QUÉ PASABA. Desde la v17.74 (14/09) las dos páginas le piden al cliente, al marcar
-- "Retira", el DÍA (mínimo +3 días hábiles, lun-vie) y la FRANJA. El dato quedaba en
-- `orders.sheets_payload` y Gestión lo iba a buscar por HTTP a la REST de LK (vista
-- `gv_pedidos_web_retiro`) SÓLO para pintar un badge. El backend del armado NUNCA lo veía,
-- así que:
--   · ningún pase automático podía programar un Retira (los 11 pases exigen
--     `zona ~ '^\s*Zona\s*[0-9]+'` y la zona de un Retira es "Retira"), y
--   · el badge y el armado miraban fuentes distintas.
-- Todo Retira quedaba en A Programar hasta que alguien lo arrastraba a mano.
--
-- DECISIÓN DE LUIS (17/09), a la pregunta de si el día elegido pisa el cupo:
--   *"si, igual que super con turno (que tambien tiene que viajar en el pedido)"*.
-- O sea: el día elegido NO se negocia. La página ya le forzó al cliente los 3 días
-- hábiles de anticipación; el cupo del día no lo mueve.
--
-- =====================================================================================
-- 1) LK (kwkclwhmoygunqmlegrg) — que el dato viaje
-- =====================================================================================
-- `v_pedidos_match` suma `retiro_fecha`, `retiro_franja` y `hora_entrega`; la de Chef,
-- `retiro_fecha` y `retiro_franja`. `sync_pedidos_match_virgilio()` las copia por el FDW.
-- Definición completa: `sql/v_pedidos_match_retiro_v1945.sql` del repo `pagina-LK-copia`.
--
-- ⚠ LA FECHA NO SE CASTEA CON `::date` CRUDO (problema 357, v19.11): el payload es TEXTO
-- del cliente. Se castea sólo si matchea `^\d{4}-\d{2}-\d{2}$`; lo demás devuelve NULL,
-- nunca un error — un solo pedido raro no puede volver a tumbar el feed entero.
--
-- `hora_entrega` es el turno del súper que hasta hoy sólo viajaba embebido en
-- `fecha_entrega_txt` ("29/09/2026 14:00"). Medido el 17/09: pedido 1468 (INC) → 14:00.

-- =====================================================================================
-- 2) VIRGILIO (hrxfctzncixxqmpfhskv) — columnas nuevas
-- =====================================================================================
alter table public.lk_pedidos_match
  add column if not exists retiro_fecha  date,
  add column if not exists retiro_franja text,
  add column if not exists hora_entrega  text;

-- ⚠ los GRANT de esta tabla son POR COLUMNA: una columna nueva nace sin permisos y el
-- sync de LK (rol lk_ppp_reader) falla en silencio si no se los da.
grant select (retiro_fecha, retiro_franja, hora_entrega) on public.lk_pedidos_match to anon, authenticated;
grant select, insert, update (retiro_fecha, retiro_franja, hora_entrega) on public.lk_pedidos_match to lk_ppp_reader;

-- Y la tabla foránea del lado LK tiene que declararlas, si no el insert no las ve:
--   alter foreign table virgilio.lk_pedidos_match add column retiro_fecha  date;
--   alter foreign table virgilio.lk_pedidos_match add column retiro_franja text;
--   alter foreign table virgilio.lk_pedidos_match add column hora_entrega  text;

-- =====================================================================================
-- 3) VIRGILIO — los dos lectores
-- =====================================================================================
create or replace function public.gv_web_retiro_pactado(p_empresa text, p_order_id bigint)
returns date language sql stable set search_path to 'public' as $$
  /* v19.52 (Luis, 2026-09-17) — EL DIA QUE EL CLIENTE ELIGIO PARA RETIRAR. La pagina se lo
     pide al marcar "Retira" (minimo +3 dias habiles, lun-vie) y lo guarda en
     orders.sheets_payload->>'retiro_fecha'. Viaja de LK por el FDW cada 15 min
     (sync_pedidos_match_virgilio -> lk_pedidos_match.retiro_fecha). NULL = el pedido no es
     Retira, o es un Retira que entro por otra via (Cotizador / recuperado) y no lo trae:
     ese queda en A Programar para que lo complete una persona. */
  select m.retiro_fecha
    from public.lk_pedidos_match m
   where m.empresa = p_empresa and m.order_id = p_order_id
   limit 1
$$;

create or replace function public.gv_web_retiro_franja(p_empresa text, p_order_id bigint)
returns text language sql stable set search_path to 'public' as $$
  /* v19.52 — la franja horaria elegida ("9:00 a 12:00" / "13:00 a 16:30"). Es informativa:
     no parte tandas ni mueve dias, sale en el badge de la PPP. */
  select m.retiro_franja
    from public.lk_pedidos_match m
   where m.empresa = p_empresa and m.order_id = p_order_id
   limit 1
$$;

revoke execute on function public.gv_web_retiro_pactado(text, bigint) from public;
revoke execute on function public.gv_web_retiro_franja(text, bigint) from public;
grant execute on function public.gv_web_retiro_pactado(text, bigint) to anon, authenticated, service_role;
grant execute on function public.gv_web_retiro_franja(text, bigint) to anon, authenticated, service_role;

-- =====================================================================================
-- 4) VIRGILIO — los dos parches al armado
-- =====================================================================================
-- Se aplicaron con los DO de abajo, sobre `pg_get_functiondef`, y son los que están vivos.
-- RECONSTRUCCIÓN: la definición ANTERIOR completa de las dos funciones está guardada en
-- `zz_backups."GV_Backup_armado_fns_20260917_pre_v1945"` (columnas proname/def). Ese backup
-- + estos dos DO reproducen exactamente lo que hay hoy en la base, y el ROLLBACK es correr
-- el `def` guardado ahí.

-- 4a) ppp_web_armar_tandas: que un Retira CON día elegido sobreviva al filtro de zona, y
--     que cierre su propia tanda (no se mezcla con reparto ni con otro que retira).
do $do$
declare
  v_src  text := pg_get_functiondef('public.ppp_web_armar_tandas(text,date,jsonb,text[],boolean)'::regprocedure);
  v_new  text;
  v_a    constant text := $a$     -- v19.13: la zona de un super es "Super", no "Zona N": sin esto la excepcion no sirve
     and not public.gv_cliente_auto_super(p_empresa, cliente);$a$;
  v_b    constant text := $b$     -- v19.13: la zona de un super es "Super", no "Zona N": sin esto la excepcion no sirve
     and not public.gv_cliente_auto_super(p_empresa, cliente)
     -- v19.52 (Luis, 2026-09-17): RETIRA CON DIA ELEGIDO. La zona es "Retira", no "Zona N", asi
     -- que este delete la borraba SIEMPRE y ningun pase automatico podia programarla. Si el
     -- cliente eligio el dia en la pagina (lk_pedidos_match.retiro_fecha), la fila se queda y la
     -- programa el pase (a4). Un Retira SIN dia elegido sigue afuera: queda en A Programar.
     and not (zona ~* 'retira'
              and public.gv_web_retiro_pactado(p_empresa, order_id) is not null);$b$;
  v_c    constant text := $c$             bool_or(grupo = 'Super') as es_super,$c$;
  v_d    constant text := $d$             -- v19.52: "Retira" cierra su tanda igual que un super: cada cliente que
             -- retira tiene su propia tanda, no se mezcla con el reparto ni con otro que retira.
             bool_or(grupo in ('Super', 'Retira')) as es_super,$d$;
begin
  if position(v_a in v_src) = 0 then raise exception 'no encontre el bloque (1) del delete'; end if;
  if position(v_c in v_src) = 0 then raise exception 'no encontre el bloque (2) es_super'; end if;
  v_new := replace(replace(v_src, v_a, v_b), v_c, v_d);
  if v_new = v_src then raise exception 'el reemplazo no cambio nada'; end if;
  execute v_new;
end
$do$;

-- 4b) gv_ppp_web_armar_pendientes: el pase (a4), calcado del (a3) del súper con turno.
do $do$
declare
  v_src text := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
  v_new text;
  v_anchor constant text := '  -- (b) zonas automaticas en cascada';
  v_a4 constant text := $a4$  -- (a4) v19.52 (Luis, 2026-09-17) — RETIRA CON DIA ELEGIDO POR EL CLIENTE.
  --   La pagina le pide el dia (minimo +3 habiles, lun-vie) y la franja al marcar "Retira", y
  --   desde la v19.52 ese dato viaja con el pedido: LK -> lk_pedidos_match.retiro_fecha por el
  --   FDW cada 15 min, lo lee gv_web_retiro_pactado. Hasta hoy NINGUN pase podia tocar un
  --   Retira, porque todos exigen zona ~ '^Zona N' y la zona de un Retira es "Retira": quedaba
  --   siempre en A Programar aunque el cliente ya se hubiera comprometido con un dia.
  --   Mismo criterio que el super con turno del pase (a3) — decision de Luis, 17/09: el dia
  --   elegido PISA EL CUPO (va con p_forzar_cods -> prioritario). No se negocia: la pagina ya
  --   le forzo al cliente los 3 dias habiles de anticipacion.
  --   Sin dia elegido (Retira cargado por el Cotizador, o recuperado) no entra acá: sigue en
  --   A Programar con el badge para que un supervisor le ponga el dia a mano.
  for r in
    select t.d, jsonb_agg(t.x) as filas, array_agg(distinct t.x->>'cod') as cods
      from (
        select greatest(public.gv_web_retiro_pactado(p_empresa, (x->>'order_id')::bigint),
                        current_date + 1) as d, x
          from jsonb_array_elements(p_filas) x
         where x->>'order_id' ~ '^[0-9]+$'
           and coalesce(x->>'zona','') ~* 'retira'
           and public.gv_web_retiro_pactado(p_empresa, (x->>'order_id')::bigint) is not null
           and not exists (select 1 from public."PPP_Web_Programacion" g
                            where g.empresa = p_empresa and g.order_id = (x->>'order_id')::bigint
                              and g.np_idx = (x->>'np_idx')::int
                              and coalesce(nullif(trim(g.tanda),''),'') <> '')
      ) t
     where t.d is not null
     group by t.d order by t.d
  loop
    delete from _gv_tmp where true;
    insert into _gv_tmp select * from public.ppp_web_armar_tandas(p_empresa, r.d, r.filas, r.cods, true);
    insert into _gv_res
    select r.d, t.r_tanda, t.r_zona, t.r_np_count, t.r_m3, t.r_clientes,
           (select array_agg(distinct s.cliente) from _asig a join _sin_tanda s on s.order_id = a.order_id and s.np_idx = a.np_idx where a.tanda = t.r_tanda)
      from _gv_tmp t;
  end loop;

$a4$;
begin
  if position(v_anchor in v_src) = 0 then raise exception 'no encontre el ancla del pase (b)'; end if;
  v_new := replace(v_src, v_anchor, v_a4 || v_anchor);
  if v_new = v_src then raise exception 'el reemplazo no cambio nada'; end if;
  execute v_new;
end
$do$;

-- =====================================================================================
-- 5) CÓMO SE PROBÓ  ⚠ CORRIENDO EL ARMADOR, NO LEYENDO LA FUNCIÓN
-- =====================================================================================
-- Regla del CLAUDE.md: *"un cambio de regla de armado no está probado hasta que se corre el
-- armador"*. Las dos pruebas van dentro de un DO que termina en `raise exception`, así que
-- escriben de verdad en PPP_Web_Programacion y después se revierte todo.
--
-- PRUEBA 1 — el día elegido manda, y sin día no se programa nada:
--   999901 Retira con retiro_fecha = hoy+14  →  E39A, fecha_entrega = hoy+14  ✅
--   999902 Retira SIN retiro_fecha           →  no aparece en PPP             ✅
--
-- PRUEBA 2 — pisa el cupo y no se juntan dos que retiran (cupo del día = 6 m³):
--   999901 Retira 9,99 m³, día hoy+15 →  E39A, hoy+15  (9,99 > 6: entra igual) ✅
--   999903 Retira 0,10 m³, mismo día  →  E39B  (tanda propia, no se mezcla)    ✅
--   999904 Zona 1 - CABA Norte 0,30   →  E37C, 24/09 por cupo (sin cambios)    ✅
--
-- CENTINELAS después del cambio: gv_ppp_super_mezclado 0 · gv_ppp_tanda_dos_dias 0 ·
-- gv_endpoints_rotos 0 · gv_ppp_tanda_camion_mezclado 1 (D69F, el pre-existente que ya
-- figura en el CLAUDE.md, nada que ver con esto).
--
-- El pase (d) `gv_ppp_web_juntar_clientes` NO toca un Retira: todos sus filtros exigen
-- `zona ~ '^\s*Zona\s*[0-9]+'`. O sea que el candado "mismo cliente = mismo día" no puede
-- arrastrar un Retira fuera del día que el cliente eligió.

-- =====================================================================================
-- 6) ROLLBACK
-- =====================================================================================
--   -- las dos funciones del armado, a como estaban:
--   do $$ declare r record; begin
--     for r in select def from zz_backups."GV_Backup_armado_fns_20260917_pre_v1945" loop
--       execute r.def;
--     end loop;
--   end $$;
--   -- y, si además se quiere sacar el dato:
--   drop function if exists public.gv_web_retiro_pactado(text, bigint);
--   drop function if exists public.gv_web_retiro_franja(text, bigint);
--   -- las columnas se pueden dejar: son aditivas y nadie más las lee.
