/* ============================================================================
   El SÚPER no se junta con clientes: cerrar la última puerta y decir QUIÉN lo
   armó.  (v18.87, pedido de Luis 2026-09-16)

   Luis, textual: *"Fijate que no pueda volver a pasar automáticamente y que si
   se rompe esa regla, que ese aviso mencione que la tanda se armó manual o
   automática."*

   Regla del dueño (v14.23, 07/09): *"Súper no se puede juntar con clientes. Ya
   tenías esa regla. Van separados."*

   ── 1. LA PUERTA QUE SEGUÍA ABIERTA (problema 334) ──────────────────────────
   No alcanzaba con leer el código: se probó corriendo el armador de verdad,
   dentro de una transacción abortada. Con una súper (Diarco 4112, "Zona 5 - GBA
   Oeste") ya programada en `F01A` el 14/10, un cliente común de Merlo **sin
   programación previa** cayó en… `F01A`. **La misma tanda de la súper**, no ya
   el mismo camión.

   La causa es la de siempre, en el único lugar que había quedado sin migrar:
   `ppp_web_armar_tandas` arma `_open` —las tandas del día que todavía pueden
   recibir un cliente más— filtrando por **ZONA**:

       bool_and(coalesce(w.zona,'') !~* 'super|retira|expo')  as reparto

   Un súper con zona numérica pasa ese filtro. Dorinka (Chango Más) y Diarco
   vienen los dos como "Zona 5 - GBA Oeste". Es **el mismo patrón** que la v18.28
   tapó en `_sin_tanda` y la v18.60 en `_ex` y en `gv_ppp_web_dia_camion`, donde
   se pasó de la zona al padrón `GV_Supers`. Acá faltaba.

   Ahora `_open` pide además `not q.tiene_super`, con
   `bool_or(gv_es_super(w.empresa, w.cod_cliente))` resuelto contra el padrón.

   **Las cuatro puertas, medidas el 16/09 con el armador corriendo:**

   | Puerta | Qué haría | Estado |
   |---|---|---|
   | La súper se arma sola | `_sin_tanda` la borra (v18.28) | cerrada ✓ |
   | "Ya hay camión a esa zona" | `gv_ppp_web_dia_camion` saltea súper (v18.60) | cerrada ✓ |
   | Reuso del número de camión | `_ex` saltea súper (v18.60) | cerrada ✓ |
   | **Tanda abierta que acumula** | **`_open` miraba la zona** | **cerrada acá** |

   ── 2. El aviso dice MANUAL o AUTOMÁTICA ────────────────────────────────────
   Es la primera pregunta al ver la alerta, porque cambia qué hay que arreglar:
   si fue automática hay una puerta abierta en el armador; si fue a mano, hay que
   hablar con la persona. El dato no está en la pantalla, está en la base:

     · NP web  → `PPP_Web_Programacion.creado_por` ('sistema' = armado automático)
     · NP ISIS → `GV_PPP_Prog_Override` con tanda o fecha pisadas = alguien la movió;
                 sin override, la tanda viene tipeada en ISIS.

   La vista devuelve `origen` ('automatica' / 'manual' / 'isis'), `origen_detalle`
   (quién y cuándo, y la nota del override) y `camion_armado` por camión: MANUAL
   si alguna fila del camión se puso a mano, ISIS si alguna viene de ISIS sin
   override, AUTOMÁTICA si todas las armó el sistema.

   Aplicado a la alerta viva del 16/09 (camión E11): **AUTOMÁTICA** — Dorinka el
   15/09 10:12, Todo Bazar 12:16, Goldar 15:00. O sea: la armó el sistema, el día
   ANTES de que la v18.60 cerrara la puerta del reuso de camión.

   ── 3. Y se deja de contar la KANGOO como parte del camión ──────────────────
   `E11A` (Extralimp, Luján) está marcada en `GV_Vehiculo_Propio`: sale en kangoo,
   no en el camión del fletero. La alerta la contaba igual —comparte los tres
   primeros caracteres del código de tanda— y decía que la súper de Moreno viajaba
   con ella. Falso positivo, y encima el override de Thomas dice explícitamente lo
   contrario. Ahora queda afuera: de 5 filas la alerta pasa a 4, todas reales.

   ⚠ El front (`_pppComputeErrors`, `pppErroresHtml`) es la MISMA regla del otro
   lado: ahí también se saltean las tandas de vehículo propio y se lee el
   `camion_armado` de esta vista. Si cambia una, hay que tocar las dos.
   ============================================================================ */

create or replace view public.gv_ppp_super_mezclado
with (security_invoker = true) as
with filas as (
  -- ISIS
  select left(btrim(p.fecha_entrega), 10)                as dia,
         substring(upper(btrim(p.tanda)) from 1 for 3)   as cam,
         upper(btrim(p.tanda))                           as tanda,
         btrim(p.np)                                     as np,
         btrim(p.cod)                                    as cod,
         p.razon_social, p.barrio,
         coalesce(p.zona, '')                            as zona,
         case when o.np is not null then 'manual' else 'isis' end as origen,
         case when o.np is not null
              then 'override a mano el ' || to_char(o.creado_en at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI')
                   || coalesce(' — ' || left(o.nota, 120), '')
              else 'NP tipeada en ISIS' end              as origen_detalle
    from public.gv_ppp_programacion_diaria p
    left join public."GV_PPP_Prog_Override" o
      on btrim(o.np) = btrim(p.np)
     and (nullif(btrim(coalesce(o.tanda, '')), '') is not null or o.fecha_entrega is not null)
   where coalesce(btrim(p.tanda), '') <> ''
     and left(btrim(p.fecha_entrega), 10) ~ '^\d{4}-\d{2}-\d{2}$'
  union all
  -- web
  select w.fecha_entrega::text,
         substring(upper(btrim(w.tanda)) from 1 for 3),
         upper(btrim(w.tanda)),
         w.empresa || ' ' || w.np,
         btrim(coalesce(w.cod_cliente, '')),
         w.razon_social, w.barrio,
         coalesce(w.zona, ''),
         case when coalesce(w.creado_por, 'sistema') = 'sistema' then 'automatica' else 'manual' end,
         case when coalesce(w.creado_por, 'sistema') = 'sistema'
              then 'armado automatico ' || to_char(w.creado_at at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI')
              else w.creado_por || ' ' || to_char(w.creado_at at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI') end
    from public."PPP_Web_Programacion" w
   where coalesce(btrim(w.tanda), '') <> ''
),
-- v18.87 (Luis): una tanda marcada en GV_Vehiculo_Propio NO viaja en el camion del fletero
-- (E11A, Extralimp/Lujan, sale en kangoo). Contarla como parte del camion E11 hacia que la
-- alerta dijera que la super de Moreno viajaba con ella: falso positivo.
vivas as (
  select f.* from filas f
   where not exists (select 1 from public."GV_Vehiculo_Propio" v
                      where upper(btrim(v.tanda)) = f.tanda and v.activo)
),
marcado as (
  select v.*, (public.gv_es_super_np(v.np, v.cod) or v.zona ~* 'super|coto|carrefour|chango|krikos') as es_super
    from vivas v
),
camiones as (
  select m.dia, m.cam,
         bool_or(m.es_super)            as tiene_super,
         bool_or(not m.es_super)        as tiene_cliente,
         bool_or(m.origen = 'manual')   as hay_manual,
         bool_or(m.origen = 'isis')     as hay_isis
    from marcado m group by m.dia, m.cam
)
select m.dia, m.cam, m.tanda, m.np, m.cod, m.razon_social, m.barrio, m.zona,
       case when m.es_super then 'SÚPER' else 'cliente' end as que_es,
       m.origen, m.origen_detalle,
       case when c.hay_manual then 'MANUAL'
            when c.hay_isis   then 'ISIS'
            else 'AUTOMÁTICA' end                          as camion_armado
  from marcado m
  join camiones c on c.dia = m.dia and c.cam = m.cam
 where c.tiene_super and c.tiene_cliente
 order by m.dia, m.cam, m.es_super desc, m.tanda;

comment on view public.gv_ppp_super_mezclado is
  'Camiones que llevan un SÚPER y clientes comunes a la vez (regla del dueño v14.23). Vacía = todo bien. '
  'v18.87 (Luis): dice si la tanda se armó AUTOMÁTICA o MANUAL (origen / origen_detalle / camion_armado) '
  'y deja afuera las tandas de GV_Vehiculo_Propio, que no viajan en el camión del fletero.';

-- ⚠ `create or replace view` sin WITH resetea las reloptions: el security_invoker va arriba,
-- y este chequeo tiene que dar vacío.
--   select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
--    where n.nspname='public' and c.relkind='v'
--      and coalesce(array_to_string(c.reloptions,','),'') not like '%security_invoker%'
--      and has_table_privilege('anon', c.oid, 'SELECT');


-- ── La puerta de `_open`: una tanda de SÚPER no es una tanda abierta ─────────
-- Reemplazo de texto con guard, por la misma razón que el resto de los parches de
-- `ppp_web_armar_tandas`: son ~200 líneas de plpgsql y lo que cambia son dos
-- fragmentos. Si alguno no aparece exactamente una vez, aborta y no toca nada.
-- ⚠ NO es idempotente: re-ejecutarlo levanta la excepción, que es lo que se quiere.
do $do$
declare
  v_def text; v_n int;
  a1 text := '                                where g.regla = ''solo'' and g.empresa = p_empresa and g.cod_cliente = w.cod_cliente)) as tiene_solo';
  b1 text := '     where q.m3 < v_tope and q.reparto and not q.tiene_solo and q.ncam = 1';
begin
  v_def := pg_get_functiondef('public.ppp_web_armar_tandas(text,date,jsonb,text[],boolean)'::regprocedure);

  v_n := (length(v_def) - length(replace(v_def, a1, ''))) / length(a1);
  if v_n <> 1 then raise exception 'fragmento tiene_solo: % veces (esperaba 1). No se toco nada.', v_n; end if;
  v_def := replace(v_def, a1, a1 || ',' || chr(10) ||
    '               -- v18.87 (Luis): la tanda de un SUPER no es una tanda abierta. _open filtraba' || chr(10) ||
    '               -- por ZONA y un super con zona numerica (Dorinka / Diarco vienen como "Zona 5 -' || chr(10) ||
    '               -- GBA Oeste") pasaba de largo: el armado le sumaba clientes comunes ADENTRO.' || chr(10) ||
    '               -- Mismo patron que v18.28/v18.60 en _sin_tanda y _ex; aca faltaba migrar al padron.' || chr(10) ||
    '               bool_or(public.gv_es_super(w.empresa, w.cod_cliente)) as tiene_super');

  v_n := (length(v_def) - length(replace(v_def, b1, ''))) / length(b1);
  if v_n <> 1 then raise exception 'fragmento where _open: % veces (esperaba 1). No se toco nada.', v_n; end if;
  v_def := replace(v_def, b1, b1 || ' and not q.tiene_super');

  execute v_def;
end
$do$;

/* ── Verificación (medida el 16/09, todo en transacciones abortadas) ──────────
   ANTES:  super Diarco 4112 en F01A el 14/10 + cliente comun de Merlo  →  F01A  ← la MISMA tanda
   DESPUES: el cliente va a F02A, camion F02. La super queda sola en F01.

   Y no se rompio lo que tenia que seguir funcionando:
   · dos clientes comunes chicos del mismo camion siguen entrando en UNA tanda
     (regla v13.67 de acumular hasta 0,80 m3): 1 tanda;
   · un mismo cliente con sucursales en dos camiones sigue partiendose en dos
     tandas el MISMO dia (regla de Luis v18.86): 2 tandas, 1 dia.

   Rollback: sacar `and not q.tiene_super` del where de `_open` y el `bool_or(...)`
   del subquery `q`; y para la vista, la version anterior esta en
   `sql/gv_ppp_super_mezclado_v1423.sql`.                                      */
