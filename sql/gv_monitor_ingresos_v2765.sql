-- v27.65 (Thomas, D16, 07/10/2026): «si entro por TV pero no marco nada, es tiempo muerto».
-- La TV, el Mon. Admin y el monitor del index buscaban quién fichó en Fichadas_Virgilio, muerta desde el 27/05
-- (5 filas). El ingreso real es GV_Dispositivo_Login (código de la TV), que anon sólo puede INSERTAR: esta RPC
-- devuelve sólo legajo + hora del PRIMER ingreso de operario de cada legajo en el rango (sin dispositivo, mail
-- ni user agent). Con eso «Ahora» muestra al que entró y no arrancó como tiempo muerto desde que entró.
create or replace function public.gv_monitor_ingresos(p_desde timestamptz, p_hasta timestamptz)
returns table(legajo text, ts_cliente timestamptz, email text)
language sql stable security definer set search_path = public as $f$
  select btrim(l.legajo::text), min(l.created_at), null::text
    from public."GV_Dispositivo_Login" l
   where l.tipo = 'operario' and l.created_at >= p_desde and l.created_at < p_hasta
     and coalesce(btrim(l.legajo::text), '') not in ('', '0')
     and p_hasta - p_desde <= interval '8 days'
   group by btrim(l.legajo::text)
   order by 2
$f$;
revoke all on function public.gv_monitor_ingresos(timestamptz, timestamptz) from public;
grant execute on function public.gv_monitor_ingresos(timestamptz, timestamptz) to anon, authenticated;
-- Rollback: drop function public.gv_monitor_ingresos(timestamptz, timestamptz);
