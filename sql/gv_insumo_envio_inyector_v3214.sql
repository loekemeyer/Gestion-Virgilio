-- v32.14 (Thomas, 16/10, D1): el envío de bolsas a un inyector desde el celular SUMA en GP2.
-- Medido el 16/10: 0 movimientos envio_inyector en toda la historia de GP2. El celular llamaba
-- GP2.enviar_material_virgilio con la clave pública y GP2.enviar_material_inyector contesta
-- «No autorizado» (_exigir_autorizado: anon afuera). El operario aceptaba «registrar sólo en
-- Virgilio»: bajaban las bolsas de Virgilio y el inyector quedaba en 0 (96 bolsas entre el 25/08
-- y el 08/10). Reemplaza D16 («el celular no escribe en GP2»).
--
-- Se reusa el puente de la v29.28 con dos cambios:
--   1) el código de Virgilio se traduce por GP2.insumo_equivalencia (la tabla ÚNICA, v29.74), no
--      por GV_Bolsa_GP2; sólo componentes del sector 14 (materia prima plástica). Sin fila → error
--      ruidoso (antes devolvía en_gp2=false y la bolsa se evaporaba).
--   2) grant a anon/authenticated: es lo único que el celular puede hacer en GP2. Alcance acotado
--      por la propia GP2.enviar_material_inyector: kg del sector 14 (ubicación 57) → ubicación tipo
--      inyector. Tope 500 bolsas por llamada.
-- El espejo (gv_gp2_espejo_insumos) no lo duplica: GP2 baja la 57 acá y el entrega_insumo de
-- Virgilio baja el saldo igual, así que el ajuste del espejo da 0.
-- Rollback: revoke execute on function public.gv_insumo_envio_inyector(text,numeric,text,text) from anon, authenticated;

create or replace function public.gv_insumo_envio_inyector(
  p_cod_virgilio text, p_bolsas numeric, p_inyector text, p_legajo text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare v_comp bigint; v_kg numeric; v_claims text; v_res jsonb;
begin
  -- v29.28-envio-iny (marcador: no cambiar) · v32.14-envio-iny-equiv
  if p_bolsas is null or p_bolsas <= 0 or p_bolsas > 500 then
    raise exception 'Bolsas fuera de rango: %', p_bolsas;
  end if;
  select e.componente_id into v_comp
    from "GP2".insumo_equivalencia e join "GP2".componente c on c.id = e.componente_id
   where c.sector_id = 14
     and upper(btrim(e.cod_virgilio)) = upper(btrim(coalesce(p_cod_virgilio, '')))
   limit 1;
  if v_comp is null then
    raise exception 'El código "%" no es una bolsa de material conocida en GP2 (falta en insumo_equivalencia)', p_cod_virgilio;
  end if;
  v_kg := coalesce((select valor from "GP2".parametro where clave = 'material_plastico_kg_x_bolsa'), 25);
  -- GP2._autorizado() deja pasar sin claims (backend): se vacían SÓLO durante esta llamada.
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '', true);
  begin
    v_res := "GP2".enviar_material_inyector(p_inyector, v_comp, p_bolsas * v_kg, now(),
      concat_ws(' · ', 'Virgilio: ' || p_bolsas || ' bolsas ' || p_cod_virgilio,
                nullif('legajo ' || coalesce(p_legajo, ''), 'legajo ')));
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  return v_res || jsonb_build_object('en_gp2', true, 'bolsas', p_bolsas, 'kg_x_bolsa', v_kg, 'cod', p_cod_virgilio);
end $fn$;
revoke all on function public.gv_insumo_envio_inyector(text, numeric, text, text) from public;
grant execute on function public.gv_insumo_envio_inyector(text, numeric, text, text) to anon, authenticated;
