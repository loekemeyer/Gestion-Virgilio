-- =====================================================================
-- backup_notificar_conteo_gondola_20260810.sql — RESTORE POINT (protocolo CLAUDE.md)
-- Definición ANTERIOR a v8.65 (antes de usar el snapshot del 3er campo del evento CG).
-- Para revertir: ejecutar este CREATE OR REPLACE.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.notificar_conteo_gondola_telegram()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $function$
declare
  p text[]; cod text; contado numeric; sistema numeric; dif numeric; v_nombre text; base text; msg text;
begin
  if new.opcion <> 'CG' then return new; end if;
  p := string_to_array(new.texto, '|');
  if coalesce(array_length(p,1),0) < 2 then return new; end if;
  cod := btrim(p[1]);
  contado := nullif(btrim(p[2]), '')::numeric;
  if contado is null then return new; end if;

  base := upper(regexp_replace(regexp_replace(cod, '\s+(LK|CH|LOKE)$', ''), '^0+(.)', '\1'));
  select coalesce(sum(terminado), 0) into sistema
    from public.vista_saldos_stock
   where upper(regexp_replace(regexp_replace(btrim(cod_art), '\s+(LK|CH|LOKE)$', ''), '^0+(.)', '\1')) = base;
  sistema := round(coalesce(sistema, 0));
  dif := contado - sistema;

  select "Empleado" into v_nombre from public."Empleados" where "Legajo" = new.legajo limit 1;

  msg := '🔢 CONTEO DE GÓNDOLA — '
      || coalesce(nullif(btrim(coalesce(v_nombre, '')), ''), 'Legajo ' || coalesce(new.legajo, '?'))
      || ' contó hoy ' || round(contado) || ' de ' || cod || '.' || E'\n'
      || 'Sistema: ' || sistema || ' · '
      || case when abs(dif) < 0.5 then '✅ dio IGUAL que el sistema.'
              else '⚠ ' || round(abs(dif)) || ' caja(s) de DIFERENCIA (' || round(contado) || ' contado vs ' || sistema || ' sistema).' end;

  perform public.tg_enqueue(msg, 'cg_' || coalesce(new.client_id, ''));
  perform public.tg_outbox_flush();
  return new;
exception when others then return new;
end
$function$;
