-- v15.62 (2026-09-11) — fix de gv_ppp_np_cancelar (v15.55): en la rama ISIS, `on conflict (np)` de
-- NP_Canceladas chocaba con el parámetro de salida `np` del RETURNS TABLE → 42702 "column reference
-- np is ambiguous". El botón Cancelar de Programación / En Salida no cancelaba NINGUNA NP de ISIS
-- (la rama web no usa `np` sin calificar y andaba). Detectado al cancelar 98050 a pedido de Thomas.
-- Arreglo: `#variable_conflict use_column` al inicio del cuerpo — las referencias sin calificar son
-- columnas; las variables ya van con prefijo v_/p_. El resto de la función es idéntico.
-- Migración: gv_ppp_np_cancelar_fix_np_ambiguo_v1561. Prueba: select * from gv_ppp_np_cancelar('98050','Cancelado por el cliente','Thomas');
-- Rollback: volver a la versión de sql/gv_en_salida_presunta_y_cancelar_v1555.sql (vuelve el bug).
CREATE OR REPLACE FUNCTION public.gv_ppp_np_cancelar(p_np text, p_motivo text, p_por text DEFAULT NULL::text)
 RETURNS TABLE(tipo text, np text, detalle text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare
  v_np  text := regexp_replace(btrim(p_np), '\.0+$', ''); v_emp text; v_num int; v_oid bigint; v_n int;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede cancelar un pedido.' using errcode='42501';
  end if;
  if nullif(btrim(coalesce(p_motivo,'')),'') is null then
    raise exception 'Falta el motivo de la cancelacion.';
  end if;
  if v_np ~* '^(LK|CH)\s*\d+' then
    v_emp := case when upper(left(v_np,2)) = 'CH' then 'chef' else 'lk' end;
    v_num := (regexp_match(v_np, '(\d+)'))[1]::int;
    select n.order_id into v_oid from public."PPP_Web_NP" n where n.empresa = v_emp and n.np = v_num limit 1;
    if v_oid is null then raise exception 'No encuentro el pedido web de %.', v_np; end if;
    if exists (select 1 from public."PPP_Web_Programacion" w
                where w.empresa = v_emp and w.order_id = v_oid and public.gv_ppp_tanda_tocada(w.tanda)) then
      raise exception 'Alguna tanda de % ya se empezo a trabajar: no se cancela desde aca.', v_np;
    end if;
    insert into public."GV_Web_Cancelados" (empresa, order_id, np_label, motivo, por)
    values (v_emp, v_oid, v_np, btrim(p_motivo), nullif(btrim(p_por),''))
    on conflict (empresa, order_id) do update set motivo = excluded.motivo, por = excluded.por, np_label = excluded.np_label, creado_at = now();
    update public."PPP_Web_Programacion" w
       set tanda = null, fecha_entrega = null, actualizado_at = now()
     where w.empresa = v_emp and w.order_id = v_oid;
    get diagnostics v_n = row_count;
    return query select 'web'::text, v_np, ('pedido web ' || v_oid || ' (' || v_n || ' NP) fuera de la PPP; no vuelve a entrar')::text;
  else
    insert into public."NP_Canceladas" (np, motivo, legajo)
    values (v_np, btrim(p_motivo), coalesce(nullif(btrim(p_por),''), 'supervisor'))
    on conflict (np) do update set motivo = excluded.motivo, legajo = excluded.legajo;
    insert into public."GV_PPP_Prog_Override" (np, oculto, nota)
    values (v_np, true, 'v15.55 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires','YYYY-MM-DD HH24:MI')
                       || ' · cancelada desde Programacion (no salio): ' || btrim(p_motivo) || coalesce(' por ' || nullif(btrim(p_por),''), ''))
    on conflict (np) do update set oculto = true, nota = excluded.nota;
    return query select 'isis'::text, v_np, 'NP_Canceladas + oculta en la PPP (GV_PPP_Prog_Override.oculto)'::text;
  end if;
end;
$function$;
