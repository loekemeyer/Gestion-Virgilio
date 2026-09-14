-- ============================================================================
-- v17.20 (2026-09-14, pedido de Luis) — columna "Marcar": aprobar o VOLVER A CUARENTENA
-- ============================================================================
-- Pedido: en la tabla de "Ya programados y el cliente está en cuarentena", una columna
-- **Marcar**. Para los que están **sin aprobar**: *"Aprobar"* (lo deja aprobado y abre el
-- pop-up de comentario) o *"Cuarentena"* (lo manda de vuelta). Para los demás —los ya
-- aprobados— sólo *"Cuarentena"*.
--
-- ⚠ LA DECISIÓN QUE IMPORTA: "volver a cuarentena" **saca el pedido de la programación**, no
-- sólo despinta la marca de aprobado. Si únicamente se borrara la fila de
-- `GV_Cuarentena_Liberados`, el pedido seguiría en su tanda, con su fecha, y saldría igual: el
-- botón sería mentiroso. Sacándolo de la programación vuelve a **A Programar** y ahí
-- `gv_cuarentena_marcar` lo retiene solo, porque el cliente sigue en cuarentena y ya no está
-- liberado. El circuito cierra sin tocar nada más.
--
-- LAS GUARDAS NO SE REESCRIBEN, SE REUSAN. La función delega en las dos que ya existían y que
-- son las que saben cuándo NO se puede desprogramar:
--   · web  → `gv_ppp_web_desprogramar(np, por)` — falla si alguna tanda del pedido ya se
--     empezó a trabajar (`gv_ppp_tanda_tocada`).
--   · ISIS → `gv_ppp_isis_desprogramar(array[np], motivo, por)` — falla si la NP ya tuvo
--     Carga Camión o Recepción Remitos (o sea, si ya salió).
-- Si cualquiera de las dos falla, la excepción aborta TODO: no se borra el liberado ni se
-- escribe el comentario. El front muestra ese error adentro del mismo cuadro.
--
-- Probado en seco el 2026-09-14 (un `DO` con las dos llamadas y un `raise exception` al final
-- para revertir): NP de ISIS `98626` y NP web `LK 0028`, las dos pasaron y no quedó nada
-- escrito (0 comentarios, 6 liberados, el override de 98626 igual que antes).
--
-- ROLLBACK: `drop function public.gv_cuarentena_devolver(text,text,text,text,text);`
-- (no toca nada más; lo que ya se haya desprogramado se reprograma como siempre).
-- ============================================================================

create or replace function public.gv_cuarentena_devolver(
  p_empresa text, p_np text, p_clave text default null,
  p_comentario text default null, p_por text default null)
returns table(np_sacadas integer, detalle text)
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_np    text := btrim(coalesce(p_np,''));
  v_clave text := nullif(btrim(coalesce(p_clave, p_np, '')), '');
  v_quien text;
  v_n     integer := 0;
  v_det   text;
begin
  -- v17.20 (pedido de Luis, 2026-09-14) — "Marcar → Cuarentena" desde la tabla de ya programados:
  -- devolver el pedido a Cuarentena de verdad, no sólo despintar la marca de aprobado. Si sólo se
  -- borrara la fila de GV_Cuarentena_Liberados, el pedido seguiría en su tanda y saliendo igual:
  -- el botón sería mentiroso. Así que además se lo SACA DE LA PROGRAMACIÓN, que es lo que lo
  -- devuelve a "A Programar" — y ahí gv_cuarentena_marcar lo vuelve a retener solo, porque el
  -- cliente sigue en cuarentena y ya no está liberado.
  -- Las dos guardas fuertes las ponen las funciones que ya existían y acá se reusan:
  -- web → gv_ppp_web_desprogramar (falla si alguna tanda ya se empezó a trabajar);
  -- ISIS → gv_ppp_isis_desprogramar (falla si la NP ya tuvo Carga Camión o Recepción Remitos).
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede devolver un pedido a cuarentena.' using errcode='42501';
  end if;
  if v_np = '' then raise exception 'No me pasaste la NP.'; end if;
  v_quien := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')),'');

  if v_np ~* '^(LK|CH)\s*\d+' then
    select w.np_sacadas into v_n from public.gv_ppp_web_desprogramar(v_np, v_quien) w;
    v_det := v_np;
  else
    select i.np_sacadas, i.detalle into v_n, v_det
      from public.gv_ppp_isis_desprogramar(array[v_np],
             'vuelta a Cuarentena' || coalesce(': ' || nullif(btrim(p_comentario),''), ''), v_quien) i;
  end if;

  delete from public."GV_Cuarentena_Liberados" lb
   where lb.empresa = lower(p_empresa) and lb.order_id = v_clave;

  insert into public."GV_Cuarentena_Comentarios" (empresa, order_id, np, texto, por)
  values (lower(p_empresa), v_clave, v_np,
          '↩ Vuelto a Cuarentena (sacado de la programación)' ||
          coalesce(': ' || nullif(btrim(p_comentario),''), '.'), v_quien);

  return query select coalesce(v_n,0), coalesce(v_det, v_np);
end;
$function$;
revoke all on function public.gv_cuarentena_devolver(text,text,text,text,text) from public, anon;
grant execute on function public.gv_cuarentena_devolver(text,text,text,text,text) to authenticated, service_role;

-- Prueba en seco (no deja nada escrito):
--   do $$ declare r record; begin
--     select * into r from public.gv_cuarentena_devolver('lk','<np>','<clave>','prueba','test');
--     raise exception 'ROLLBACK DE PRUEBA';
--   end $$;
