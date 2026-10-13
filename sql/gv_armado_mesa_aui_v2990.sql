/* v29.90 (Luis, 13/10) — SE PREGUNTA LA MESA AL EMPEZAR EL ARMADO (evento AUI)
   ────────────────────────────────────────────────────────────────────────────
   Luis: "d1 si, que pregunte la mesa al empezar armado. fijate que no rompa nada.
   todo esto fowardfacing".

   Cierra el agujero que la v29.74 dejó anotado: el PUB dice dónde dejó la tanda el
   picking y el AUB dónde quedó al TERMINAR el armado, pero MIENTRAS arman no había
   nada. Ahora, al dar AP, el celular pregunta la mesa y emite un evento aparte:

     opcion 'AUI' · texto = tanda · descripcion = mesa · ts_inicio NULL

   `ts_inicio NULL` a propósito: NO abre tarea (el `abre` de las horas es una lista
   blanca: EP/AP/MGI/RKI/IRI/MDI/toggles) y NO cierra ninguna (el cierre exige
   ts_inicio). Es un evento de DETALLE, como PUB / AUB / PKG.

   ⚠ Lo que SÍ hay que tocar es la lista de "eventos automáticos" de la COLA (v26.43):
   la cola de un TP/TAP corre hasta la próxima TAREA del legajo, y un evento de detalle
   que no esté en esa lista la CORTARÍA. Son 5 listas, las mismas 5 que ya nombran a
   PKG/NPD/PKAX, y se parchean por texto (varias sesiones tocan estos objetos):
     gv_monitor_horas_operario_dia · gv_horas_operario_detalle_v2 (x2)
     gv_picking_tanda_calc · gv_armado_tanda_calc
   En el front: COLA_AUTO de index.html y el AUTO de monitor/build-admin.cjs.

   Y `gv_tanda_ubicacion` (v29.74) suma AUI como cuarta fuente, con `fuente =
   'armado_mesa'`: sigue ganando el ts MÁS RECIENTE, así que la secuencia natural
   PUB (fin picking) → AUI (empieza armado) → AUB (fin armado) se ordena sola.

   FORWARD-FACING: no hay un solo AUI en la historia y no se backfillea nada. El 15/09
   de `tests/tools/vista-15.json` no cambia (se verificó): sólo se mueve la HUELLA.

   Rollback: está al pie.
*/
-- ⚠ Los 4 centinelas y la huella quedaron en la base con version 'v29.86' (la etiqueta de
--   cuando se aplico, antes de que otras sesiones se llevaran la 29.86 a la 29.89). No se cambia.
-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 13/10: "d1 si, que pregunte la mesa al empezar armado")

/* ── 1) las 5 listas de eventos automáticos de la COLA ───────────────────────── */
do $mesa$
declare
  r record; src text; nuevo text; n int; total int := 0;
  viejo constant text := '''PSP'',''NPD'',''PKAX'')';
  nuev  constant text := '''PSP'',''NPD'',''PKAX'',''AUI'')';
begin
  for r in
    select p.oid::regprocedure::text as fn
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public'
       and p.proname in ('gv_monitor_horas_operario_dia','gv_horas_operario_detalle_v2',
                         'gv_picking_tanda_calc','gv_armado_tanda_calc')
  loop
    src := pg_get_functiondef(r.fn::regprocedure);
    if position('''AUI''' in src) > 0 then
      raise notice '% ya tiene AUI, no se toca', r.fn;
      continue;
    end if;
    n := (length(src) - length(replace(src, viejo, ''))) / length(viejo);
    if n = 0 then
      raise exception 'NO MATCHEA la lista de automaticos en %: parchear a mano', r.fn;
    end if;
    nuevo := replace(src, viejo, nuev);
    execute nuevo;
    total := total + n;
    raise notice '% -> % lista(s) con AUI', r.fn, n;
  end loop;
  if total <> 5 then
    raise exception 'Se esperaban 5 listas y se parchearon %', total;
  end if;
end $mesa$;

/* ── 2) gv_tanda_ubicacion: AUI es la cuarta fuente ──────────────────────────── */
create or replace function public.gv_tanda_ubicacion(p_tandas text[])
returns table (tanda text, ubicacion text, fuente text, ts timestamptz, legajo text, por_np boolean, otras text)
language sql
stable
security definer
set search_path = public
as $fn$
with _tu_t as (
  select distinct upper(btrim(x)) tanda
    from unnest(coalesce(p_tandas, '{}'::text[])) x
   where coalesce(btrim(x), '') <> ''
),
/* tanda -> NP, para los AUB viejos que se guardaron por NP (ISIS y 3 web) */
_tu_np as (
  select t.tanda, upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) np
    from _tu_t t
    join public."PPP_Web_Programacion" w on upper(btrim(w.tanda)) = t.tanda
   where coalesce(w.np, 0) > 0
  union
  select t.tanda, upper(btrim(d.np))
    from _tu_t t
    join public.gv_ppp_programacion_diaria d on upper(btrim(d.tanda)) = t.tanda
   where coalesce(btrim(d.np), '') <> ''
),
_tu_cand as (
  /* (1) lo que dijo quien la pickeó al terminar */
  select t.tanda, btrim(r.descripcion) ubic, 'picking'::text fuente, r.ts_cliente ts,
         coalesce(btrim(r.legajo), '') legajo, false por_np
    from _tu_t t
    join public."Registros_Produccion_Virgilio" r on upper(btrim(r.texto)) = t.tanda
   where r.opcion = 'PUB' and coalesce(btrim(r.descripcion), '') <> ''
  union all
  /* (2) dónde quedó el carro al FRENAR el picking (v26.61) */
  select t.tanda, btrim(f.ubicacion), 'freno', f.ts_freno, coalesce(btrim(f.legajo), ''), false
    from _tu_t t
    join public."GV_Tanda_Freno" f on upper(btrim(f.tanda)) = t.tanda
   where lower(coalesce(f.fase, '')) = 'picking' and coalesce(btrim(f.ubicacion), '') <> ''
  union all
  /* (2 bis) v29.90: la MESA que eligió el armador al EMPEZAR (AP) — la tanda se está
             armando AHÍ, y es el dato que faltaba mientras el armado está en curso */
  select t.tanda, btrim(r.descripcion), 'armado_mesa', r.ts_cliente, coalesce(btrim(r.legajo), ''), false
    from _tu_t t
    join public."Registros_Produccion_Virgilio" r on upper(btrim(r.texto)) = t.tanda
   where r.opcion = 'AUI' and coalesce(btrim(r.descripcion), '') <> ''
  union all
  /* (3) el sector de armado, anotado por TANDA */
  select t.tanda, btrim(r.descripcion), 'armado', r.ts_cliente, coalesce(btrim(r.legajo), ''), false
    from _tu_t t
    join public."Registros_Produccion_Virgilio" r on upper(btrim(r.texto)) = t.tanda
   where r.opcion = 'AUB' and coalesce(btrim(r.descripcion), '') <> ''
  union all
  /* (3 bis) el sector de armado, anotado por NP */
  select n.tanda, btrim(r.descripcion), 'armado', r.ts_cliente, coalesce(btrim(r.legajo), ''), true
    from _tu_np n
    join public."Registros_Produccion_Virgilio" r on upper(btrim(r.texto)) = n.np
   where r.opcion = 'AUB' and coalesce(btrim(r.descripcion), '') <> ''
),
_tu_top as (
  select distinct on (c.tanda) c.*
    from _tu_cand c
   order by c.tanda, c.ts desc, c.fuente
)
select p.tanda, p.ubic, p.fuente, p.ts, p.legajo, p.por_np,
       /* lo que la MISMA fuente dejó en otro lado (NP repartidas en varios sectores) */
       nullif((select string_agg(distinct o.ubic, ' · ' order by o.ubic)
                 from _tu_cand o
                where o.tanda = p.tanda and o.fuente = p.fuente
                  and upper(o.ubic) <> upper(p.ubic)
                  and o.ts > p.ts - interval '12 hours'), '') otras
  from _tu_top p;
$fn$;

revoke all on function public.gv_tanda_ubicacion(text[]) from public;
grant execute on function public.gv_tanda_ubicacion(text[]) to anon, authenticated, service_role;

/* ── 3) centinelas ───────────────────────────────────────────────────────────── */
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_tanda_ubicacion', 'funcion', 'armado_mesa',
        'La MESA que eligio el armador al empezar (evento AUI) es una fuente de la ubicacion fisica de la tanda.',
        'Luis', 'v29.86')
on conflict do nothing;
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_monitor_horas_operario_dia', 'funcion', '''AUI''',
        'AUI (la mesa al empezar armado) es un evento de DETALLE: va en la lista de automaticos, no corta la cola del TP/TAP.',
        'Luis', 'v29.86')
on conflict do nothing;
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_picking_tanda_calc', 'funcion', '''AUI''',
        'AUI no corta la cola del picking (D17): es un evento de detalle, no una tarea.',
        'Luis', 'v29.86')
on conflict do nothing;
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_armado_tanda_calc', 'funcion', '''AUI''',
        'AUI no corta la cola del armado: es un evento de detalle, no una tarea.',
        'Luis', 'v29.86')
on conflict do nothing;

/* ── 4) la HUELLA de gv_monitor_horas_operario_dia se movió a propósito ──────── */
update public."GV_Huella_Objeto"
   set md5_esperado = md5((select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                            where n.nspname = 'public' and p.proname = 'gv_monitor_horas_operario_dia' limit 1)),
       version = 'v29.86', actualizado_en = now()
 where objeto = 'gv_monitor_horas_operario_dia';

/* ── chequeo ──────────────────────────────────────────────────────────────────
   select * from public.gv_reglas_perdidas;        -- vacía
   select * from public.gv_huellas_cambiadas;      -- vacía
   select * from public.gv_tanda_ubicacion(array['F58B']);

   ── ROLLBACK ─────────────────────────────────────────────────────────────────
   1) las 5 listas: el mismo do-block cambiando `viejo` por la lista CON 'AUI' y
      `nuev` por la lista SIN 'AUI' (y el raise de total <> 5).
   2) gv_tanda_ubicacion: volver a correr sql/gv_tanda_ubicacion_v2974.sql.
   3) borrar las 4 filas v29.90 de GV_Reglas_Centinela y recongelar la huella.
*/
