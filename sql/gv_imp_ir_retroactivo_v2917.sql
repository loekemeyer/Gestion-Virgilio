-- v29.17 (Luis, 09/10): lo que entró por Ingreso a racks de importación ANTES de la imputación
-- automática (v29.04) se REVISA A MANO en Importación → 📥 Recibido. No se descuenta nada solo.
-- REGLA_CONFIRMADA_POR_USUARIO
--
-- 1) gv_imp_ir_avisos lista también resultado 'a_revisar' (patch sobre la definición viva).
-- 2) cada ingreso a racks de un código importado SIN fila en GV_Imp_Ingreso_Racks_Log entra como
--    'a_revisar'. El admin elige el pedido (↔, mismo gv_imp_ir_asignar) o lo marca ✓ Visto
--    (ya descontado / no corresponde). Nada mueve stock.

do $p$
declare d text;
begin
  d := pg_get_functiondef('public.gv_imp_ir_avisos(int)'::regprocedure);
  if position('''a_revisar''' in d) > 0 then return; end if;   -- v29.17-ir-retro (idempotente)
  if position('''sin_uni_x_caja'', ''error'')' in d) = 0 then
    raise exception 'gv_imp_ir_avisos no tiene el texto esperado: no se parchea';
  end if;
  d := replace(d, '''sin_uni_x_caja'', ''error'')', '''sin_uni_x_caja'', ''error'', ''a_revisar'')');
  execute d;
end $p$;

insert into public."GV_Imp_Ingreso_Racks_Log"(mov_id, ts, cod_art, cajas, legajo, sector, resultado, motivo)
select m.id, m.ts, upper(regexp_replace(btrim(m.cod_art), '([0-9E])L$', '\1')), m.delta, m.legajo, m.ubicacion,
       'a_revisar', 'anterior a la imputación automática (09/10): revisar si ya se descontó de su pedido'
  from public."Movimientos_Stock" m
 where m.tipo = 'ingreso' and m.deposito in ('racks','racks_ch') and m.delta > 0
   and not exists (select 1 from public."GV_Imp_Ingreso_Racks_Log" l where l.mov_id = m.id)
   and exists (select 1 from public."Importados" i
                where public.gv_cod_stock(upper(btrim(i.cod_art)))
                    = public.gv_cod_stock(upper(regexp_replace(btrim(m.cod_art), '([0-9E])L$', '\1'))))
on conflict (mov_id) do nothing;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_imp_ir_avisos', 'funcion', '''a_revisar''',
        'Los ingresos a racks de importación anteriores a la imputación automática se revisan a mano en Importación → Recibido',
        'Luis', 'v29.17');

-- ROLLBACK: update public."GV_Imp_Ingreso_Racks_Log" set resultado='sin_pedido', revisado_en=now(), revisado_por='rollback v29.17'
--           where resultado='a_revisar';  (y quitar 'a_revisar' de la lista de gv_imp_ir_avisos)
