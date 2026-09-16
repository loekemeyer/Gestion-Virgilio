/* ============================================================================
   "Reusar tanda" ya no puede partir una tanda en dos días.  (v18.92, Luis
   2026-09-16 — problema 338)

   ── La pregunta ─────────────────────────────────────────────────────────────
   Luis: *"¿por qué la D69C terminó en dos días diferentes? ¿cómo puede ser?"*

   ── Lo que pasó, con hora ───────────────────────────────────────────────────
   ISIS dio la D69C con tres NP, las tres Zona 6 - GBA Norte, para el 14/09:

     98615  Arguello Marcelo Claudio    Villa Ballester   0,263 m³
     98616  Arguello Marcelo Claudio    Villa Ballester   0,021 m³
     98622  Martinelli Daniel Roberto   Bella Vista       0,325 m³

     · **14/09 15:01** — las tres se mueven a mano desde la app al **21/09**
       (`GV_PPP_Prog_Override`, nota *"movida desde la app a 21/09"*).
     · **16/09 11:58** — se sacan **98615 y 98616** a *A Programar*
       (*"desarmado: enviado a A Programar desde la tabla de Programación"*).
     · **16/09 11:59** — un minuto después se las reprograma para el **17/09**
       con el botón que **REUSA la tanda D69C** (*"ya pickeada/armada"*).
     · **98622 nunca se volvió a tocar**: sigue en D69C el **21/09**.

   Resultado: el código **D69C existe en dos fechas a la vez** — 17/09 con 0,284 m³
   y 21/09 con 0,325 m³.

   ── Por qué el guard no lo frenó ────────────────────────────────────────────
   `gv_ppp_isis_programar` (v16.03) reusa el código anterior cuando **todas** las
   NP que entran vienen de la misma tanda previa. La idea es buena: si la tanda ya
   se pickeó y se armó, volver a ella evita repetir el trabajo.

   El problema es de qué lado mira: **cuenta las que ENTRAN, no las que QUEDAN**.
   Nadie preguntó si la tanda seguía teniendo NP programadas en otro día.

   Y parte en dos todo lo que agrupa por tanda, porque un mismo código cae en dos
   camiones de dos días distintos: `vista_tanda_m3`, el camión, la hoja de ruta y
   la carga. El panel de la PPP lo marca como *"tanda inconsistente"* (varias
   fechas), pero eso es después: nada lo impedía al programar.

   ── El arreglo ─────────────────────────────────────────────────────────────
   Antes de reusar, se cuentan las NP de esa tanda que quedan **en otro día**
   (web + ISIS). Si hay alguna, **no se reusa**: va una tanda nueva y el aviso dice
   por qué, cuántas quedan y cuándo. Si las hermanas están en el **mismo día
   destino**, reusar sigue siendo lo correcto y no cambia nada.

   Se eligió abrir tanda nueva y no bloquear con un `raise`: separar un pedido de
   su tanda es una decisión legítima del supervisor, y trabarlo lo dejaría sin
   salida. El aviso aclara que el contenido es el mismo y que **no hay que volver a
   pickear**, sólo cambia el código.

   ── Verificación (transacciones abortadas, 2026-09-16) ─────────────────────
   | Caso | Antes | Ahora |
   |---|---|---|
   | La hermana 98622 queda el 21/09 (el caso real) | reusa `D69C` | **tanda nueva `E30A`** + aviso |
   | La hermana va al MISMO día (17/09) | reusa `D69C` | reusa `D69C` (0,609 m³) ✓ |
   | Se mueve la tanda ENTERA al 18/09 | reusa `D69C` | reusa `D69C` ✓ |

   ⚠ **No se tocó la D69C viva.** Son NP de una tanda ya programada y pickeada: qué
   hacer con ellas lo decide un supervisor (protocolo de `CLAUDE.md`). El centinela
   la muestra hasta que eso pase.
   ============================================================================ */

create or replace function public.gv_ppp_isis_programar(p_nps text[], p_fecha date, p_por text default null::text)
 returns table(codigo text, np_programadas integer, m3 numeric, aviso text)
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_nps    text[];
  v_falta  text;
  v_sup    int;
  v_cli    int;
  v_code   text;
  v_prev   text;
  v_nprev  int;
  v_reuso  boolean := false;
  v_n      int;
  v_m3     numeric := 0;
  v_aviso  text := null;
  v_cupo   numeric;
  v_usado  numeric;
  v_nota   text;
  v_otras  int;           -- v18.92
  v_otro   date;          -- v18.92
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Sólo supervisores pueden programar NP de ISIS.';
  end if;
  if p_fecha is null then
    raise exception 'Falta la fecha de entrega: ninguna tanda queda sin fecha.';
  end if;

  select array_agg(distinct regexp_replace(btrim(x), '\.0+$', ''))
    into v_nps
    from unnest(coalesce(p_nps, '{}'::text[])) x
   where nullif(btrim(x), '') is not null;
  if v_nps is null or array_length(v_nps, 1) is null then
    raise exception 'No me pasaste ninguna NP.';
  end if;

  select string_agg(n, ', ' order by n) into v_falta
    from unnest(v_nps) n
   where not exists (select 1 from public.gv_ppp_isis_sin_tanda v where v.np = n);
  if v_falta is not null then
    raise exception 'Estas NP ya no están sin tanda (o ya salieron): %.', v_falta;
  end if;

  select count(*) filter (where v.es_super), count(*) filter (where not v.es_super)
    into v_sup, v_cli
    from public.gv_ppp_isis_sin_tanda v
   where v.np = any (v_nps);
  if v_sup > 0 and v_cli > 0 then
    raise exception 'Un súper no se junta con clientes en la misma tanda: separalas en dos.';
  end if;

  -- v16.03 — ¿todas vienen de la MISMA tanda anterior? Entonces vuelven a ELLA: el picking y el
  -- armado ya hechos siguen valiendo y nadie los repite.
  select count(distinct v.tanda_previa), max(v.tanda_previa)
    into v_nprev, v_prev
    from public.gv_ppp_isis_sin_tanda v
   where v.np = any (v_nps) and v.tanda_previa is not null;

  if v_nprev = 1 and (select count(*) from public.gv_ppp_isis_sin_tanda v
                       where v.np = any (v_nps) and v.tanda_previa is null) = 0 then
    -- v18.92 (Luis, 2026-09-16) — ⚠ EL GUARD DE ARRIBA MIRA LAS QUE ENTRAN, NO LAS QUE QUEDAN.
    --   Si la tanda que se quiere reusar todavía tiene OTRAS NP programadas en otro día, reusar
    --   el código la parte en dos fechas: el mismo código cae en dos camiones distintos y todo lo
    --   que agrupa por tanda (m³, camión, hoja de ruta, carga) queda mal.
    --   Caso real D69C: el 16/09 11:59 se reprogramaron 98615 y 98616 al 17/09 reusando D69C,
    --   mientras 98622 seguía en D69C el 21/09. Problema 338.
    --   Si las hermanas están en el MISMO día destino, reusar sigue siendo lo correcto.
    select count(*), min(q.fecha) into v_otras, v_otro
      from (
        select left(btrim(i.fecha_entrega::text), 10)::date as fecha
          from public.gv_ppp_programacion_diaria i
         where upper(btrim(coalesce(i.tanda, ''))) = upper(v_prev)
           and btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
           and regexp_replace(btrim(i.np), '\.0+$', '') <> all (v_nps)
        union all
        select w.fecha_entrega
          from public."PPP_Web_Programacion" w
         where upper(btrim(coalesce(w.tanda, ''))) = upper(v_prev)
      ) q
     where q.fecha is distinct from p_fecha;

    if coalesce(v_otras, 0) > 0 then
      v_code  := public.gv_ppp_web_tanda_codigo_nuevo();
      v_reuso := false;
      v_aviso := 'No se reusó la tanda ' || v_prev || ': quedan ' || v_otras || ' NP de esa tanda el '
                 || to_char(v_otro, 'DD/MM') || ', y un mismo código no puede salir en dos días. '
                 || 'Va una tanda nueva (' || v_code || ') con el MISMO contenido: si ya estaba '
                 || 'pickeada y armada, no hay que repetirlo, sólo cambia el código.';
    else
      v_code  := v_prev;
      v_reuso := true;
      v_aviso := 'Volvió a su tanda ' || v_prev || ': ya estaba pickeada y armada, así que NO hay que pickearla de nuevo.';
    end if;
  else
    v_code := public.gv_ppp_web_tanda_codigo_nuevo();
    if v_nprev >= 1 then
      v_aviso := 'Ojo: estas NP venían de tandas distintas (' || v_nprev || '), así que va una tanda NUEVA (' || v_code
                 || '). Si ya estaban pickeadas y armadas, revisá antes de mandarlas a pickear otra vez.';
    end if;
  end if;

  v_nota := 'v16.03 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD HH24:MI')
            || ' · programada desde A Programar (NP de ISIS) para el ' || to_char(p_fecha, 'DD/MM')
            || case when v_reuso then ' · REUSA su tanda ' || v_code || ' (ya pickeada/armada)' else '' end
            || coalesce(' por ' || nullif(btrim(p_por), ''), '');

  insert into public."GV_PPP_Prog_Override" (np, tanda, fecha_entrega, nota, desprogramada)
  select n, v_code, p_fecha, v_nota, false from unnest(v_nps) n
  on conflict (np) do update
     set tanda = excluded.tanda, fecha_entrega = excluded.fecha_entrega,
         nota = coalesce(public."GV_PPP_Prog_Override".nota || ' | ', '') || excluded.nota,
         desprogramada = false;
  get diagnostics v_n = row_count;

  select coalesce(round(sum(p.m3), 3), 0) into v_m3
    from public.gv_ppp_programacion_diaria p
   where upper(btrim(coalesce(p.tanda, ''))) = upper(v_code);

  v_cupo := public.gv_ppp_web_cupo(p_fecha);
  select coalesce(sum(g.m3), 0) into v_usado
    from public."PPP_Web_Programacion" g
   where g.fecha_entrega = p_fecha and coalesce(nullif(trim(g.tanda), ''), '') <> '';
  v_usado := v_usado + public.gv_ppp_web_m3_isis(p_fecha);
  if v_usado > v_cupo then
    v_aviso := coalesce(v_aviso || ' ', '') || 'El ' || to_char(p_fecha, 'DD/MM') || ' queda con ' || round(v_usado, 3)
               || ' m³, por encima del cupo de ' || v_cupo || ' m³.';
  end if;
  if not public.gv_es_dia_habil(p_fecha) then
    v_aviso := coalesce(v_aviso || ' ', '') || 'Ojo: el ' || to_char(p_fecha, 'DD/MM')
               || ' no es día hábil (fin de semana o feriado).';
  end if;

  return query select v_code, v_n, v_m3, v_aviso;
end $function$;


-- ── Centinela: ninguna tanda puede salir en dos días ────────────────────────
-- Mismo espíritu que gv_ppp_super_mezclado y gv_ppp_tanda_camion_mezclado: vacía
-- = todo bien. Cubre web + ISIS, así que también caza lo que se arme a mano por
-- `GV_PPP_Prog_Override`, que se saltea la función de arriba.
create or replace view public.gv_ppp_tanda_dos_dias
with (security_invoker = true) as
with t as (
  select upper(btrim(w.tanda))            as tanda,
         w.fecha_entrega                  as fecha,
         w.empresa || ' ' || w.np         as np,
         w.razon_social, coalesce(w.zona, '') as zona, coalesce(w.m3, 0) as m3,
         'web'::text                      as origen
    from public."PPP_Web_Programacion" w
   where coalesce(nullif(btrim(w.tanda), ''), '') <> '' and w.fecha_entrega is not null
  union all
  select upper(btrim(i.tanda)),
         left(btrim(i.fecha_entrega::text), 10)::date,
         btrim(i.np), i.razon_social, coalesce(i.zona, ''), coalesce(i.m3, 0), 'isis'
    from public.gv_ppp_programacion_diaria i
   where coalesce(nullif(btrim(i.tanda), ''), '') <> ''
     and btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
),
partidas as (
  select t.tanda from t group by t.tanda having count(distinct t.fecha) > 1
)
select t.tanda, t.fecha, t.np, t.razon_social, t.zona, t.m3, t.origen
  from t join partidas p on p.tanda = t.tanda
 order by t.tanda, t.fecha, t.np;

grant select on public.gv_ppp_tanda_dos_dias to anon, authenticated, service_role;

comment on view public.gv_ppp_tanda_dos_dias is
  'Tandas cuyo codigo sale en mas de un dia (v18.92, Luis). Vacia = todo bien. Un mismo codigo '
  'en dos fechas cae en dos camiones y rompe todo lo que agrupa por tanda: m3, camion, hoja de '
  'ruta y carga.';

/* Chequeo:  select * from public.gv_ppp_tanda_dos_dias;   -- vacía = todo bien
   Al 16/09 devuelve las 3 NP de D69C (17/09 y 21/09), que quedan para un supervisor.

   Rollback: volver `gv_ppp_isis_programar` a la v16.03 sacando el bloque marcado v18.92
   (el `select count(*) … into v_otras` y su `if`), dejando `v_code := v_prev; v_reuso := true;`
   directo; y `drop view public.gv_ppp_tanda_dos_dias;`.                                   */
