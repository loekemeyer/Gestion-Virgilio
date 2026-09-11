-- v15.06 — Pedidos Importación: PI Fujian HT26-06-600-R1 (PI_26066002) cargado como pedido en curso
-- Proyecto Supabase: hrxfctzncixxqmpfhskv — ejecutado el 2026-09-11 (ya aplicado; queda como referencia)
--
-- PI: 106.488 u, u$s 32.388, entrega "30-45 días después del depósito", Ningbo.
-- 5 líneas ya estaban cargadas el 10/09 desde "Cargar pedido ya hecho" (026, 027, 110, 824, 825) con
-- fecha_reingreso 2026-11-01; se reusa esa fecha para las 6 que faltaban.
-- Regla del dueño (§3.bm): EL = LK, E = CH → 439E·LK (id 68) pasa a 439EL y se da de alta 439E·CH.
--
-- Backups: GV_Importados_bkp_439_20260911, GV_Importados_Volumen_bkp_439_20260911.

do $$
declare v_ch bigint;
begin
  update public."Importados" set cod_art = '439EL', actualizado = now()
   where id = 68 and cod_art = '439E' and marca = 'LK';

  insert into public."Importados_Volumen" (cod, largo_cm, ancho_cm, alto_cm, m3_master, uni_inner, uni_master, fuente)
  select '439EL', largo_cm, ancho_cm, alto_cm, m3_master, uni_inner, uni_master, fuente
    from public."Importados_Volumen" where cod = '439E'
  on conflict (cod) do nothing;

  insert into public."Importados" (cod_art, marca, proveedor, descripcion, fob_uni, uni_x_caja, principal, activo)
  values ('439E', 'CH', 'Fujian', 'Colador de Pastas ac. inox.', 2.3, 6, true, true)
  returning id into v_ch;                                           -- quedó id 164

  perform public.gv_importado_bache_add(63,   1224, '2026-11-01', 'PI HT26-06-600-R1');  -- 438E  CH
  perform public.gv_importado_bache_add(65,   6912, '2026-11-01', 'PI HT26-06-600-R1');  -- 438EL LK
  perform public.gv_importado_bache_add(v_ch,   48, '2026-11-01', 'PI HT26-06-600-R1');  -- 439E  CH
  perform public.gv_importado_bache_add(68,    720, '2026-11-01', 'PI HT26-06-600-R1');  -- 439EL LK
  perform public.gv_importado_bache_add(66,   1200, '2026-11-01', 'PI HT26-06-600-R1');  -- 440E  LK
  perform public.gv_importado_bache_add(67,   1200, '2026-11-01', 'PI HT26-06-600-R1');  -- 035E  LK
end $$;

-- Chequeo: debe dar 106488 (total del PI)
select sum(unidades) from public."GV_Importados_Baches" where proveedor = 'Fujian' and estado = 'en_curso';

-- ROLLBACK
--   delete from public."GV_Importados_Baches" where creado_por = 'PI HT26-06-600-R1';
--   select public.gv_importados_resync(id) from (values (63),(65),(66),(67),(68),(164)) v(id);
--   delete from public."Importados" where id = 164;
--   update public."Importados" set cod_art = '439E' where id = 68;
--   delete from public."Importados_Volumen" where cod = '439EL';
