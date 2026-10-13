/* v29.74 (Luis, 13/10) — EL MONITOR DICE DÓNDE QUEDÓ FÍSICAMENTE UNA TANDA PICKEADA
   ────────────────────────────────────────────────────────────────────────────────
   Luis: "cuando muestra una tanda en la pantalla que está pickeada, que muestre dónde
   quedó físicamente (último dato entre lo que indicó quien la pickeó sobre dónde la dejó
   o la mesa de armado en la que la están armando)".

   El dato YA se registra en tres lugares y no lo mostraba ninguna pantalla:

   | cuándo                      | evento / tabla                       | qué dice                        |
   |-----------------------------|--------------------------------------|---------------------------------|
   | al TERMINAR el picking (TP) | evento `PUB` (texto = tanda)         | Mesa 1 · Mesa 2 · Carro · AA9…  |
   | al FRENAR el picking        | `GV_Tanda_Freno.ubicacion`           | dónde quedó el carro (v26.61)   |
   | al TERMINAR el armado (TAP) | evento `AUB`                         | AA1..AD8 (el sector de armado)  |

   Medido el 13/10 (30 días): PUB en 162 de 170 tandas con TP (95 %) — 53 Mesa 1, 45 Mesa 2,
   18 Carro y el resto posiciones. El AUB hoy viene **por TANDA** (130 filas, la última de hoy):
   las 408 por NP son de ISIS y la última es del 30/09, así que se cubren las dos formas.
   Los 9 frenos que hay no tienen ubicación cargada: entra igual, para cuando la tengan.

   ⚠ La "mesa de armado en la que la están armando" NO se registra mientras arman: el AUB se
   emite al TERMINAR (TAP). Mientras el armado está en curso, el último dato es el del picking
   —que justamente suele decir «Mesa 1» / «Mesa 2»—, y por eso alcanza. Si algún día se quiere
   la mesa en vivo, hay que preguntarla al dar AP; es un cambio en el módulo del operario.

   Devuelve UNA fila por tanda: la ubicación con el `ts` MÁS RECIENTE entre las tres fuentes.
   `otras` dice si esa misma fuente dejó pedazos en otro lado (NP repartidas en varios sectores).

   SECURITY DEFINER a propósito: cruza `PPP_Web_Programacion` (que `anon` no ve por RLS) y una
   función INVOKER devolvería MENOS filas sin dar error — la trampa de la v20.45. Sólo saca
   tanda + ubicación, nada del cliente.

   Rollback: drop function if exists public.gv_tanda_ubicacion(text[]);
*/
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

/* centinela: la regla es "el MÁS RECIENTE entre las tres fuentes" */
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_tanda_ubicacion', 'funcion', 'distinct on \(c\.tanda\)',
        'El monitor muestra la ubicacion fisica MAS RECIENTE de la tanda (picking PUB / freno / armado AUB), una fila por tanda.',
        'Luis', 'v29.74')
on conflict do nothing;
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_tanda_ubicacion', 'funcion', 'GV_Tanda_Freno',
        'La ubicacion del FRENO del picking (donde quedo el carro) cuenta como fuente, no solo el PUB y el AUB.',
        'Luis', 'v29.74')
on conflict do nothing;
