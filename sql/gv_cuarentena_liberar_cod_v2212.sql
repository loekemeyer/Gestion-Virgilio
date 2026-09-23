-- v22.12 (Luis, 23/09/2026): el comentario de la aprobación lleva el COD del cliente.
-- Motivo: «➡ Enviar a programar» del pipeline de clientes nuevos pide un mensaje de log
-- obligatorio; sin cod, gv_clin_comentarios_cliente no lo mostraba en «🕘 Antes, con este cliente».
-- Aplicado sobre pg_get_functiondef (idempotente). Probado en transacción abortada con LK 1448:
-- cod del comentario 4282 · aparece en el historial del cliente: 1.
-- Centinela: GV_Reglas_Centinela patron 'v_persona, v_cod\)'.
-- Rollback: volver a insertar el comentario sin la columna cod (y el select del log despues).
CREATE OR REPLACE FUNCTION public.gv_cuarentena_liberar(p_empresa text, p_order_id text, p_motivos text[] DEFAULT NULL::text[], p_comentario text DEFAULT NULL::text, p_por text DEFAULT NULL::text, p_persona text DEFAULT NULL::text, p_np text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v17.53 (Luis): la clave se normaliza AL ESCRIBIR (gv_cuarentena_clave), no solo al leer.
declare
  v_quien text; v_persona text; v_clave text := public.gv_cuarentena_clave(nullif(trim(p_order_id),''));
  v_np text; v_cod text; v_rs text;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede liberar pedidos de cuarentena.' using errcode='42501';
  end if;
  v_quien   := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')),'');
  v_persona := nullif(btrim(p_persona),'');
  if v_persona is null then
    raise exception 'Falta indicar quién aprueba el pedido.' using errcode='22023';
  end if;

  insert into public."GV_Cuarentena_Liberados" (empresa, order_id, motivos, liberado_por, persona)
  values (lower(p_empresa), v_clave, p_motivos, coalesce(v_quien,''), v_persona)
  on conflict (empresa, order_id) do update
     set motivos = excluded.motivos, liberado_at = now(),
         liberado_por = excluded.liberado_por, persona = excluded.persona;

  select l.np, l.cod, l.razon_social into v_np, v_cod, v_rs
    from public."GV_Cuarentena_Log" l
   where l.empresa = lower(p_empresa) and l.clave = v_clave
   order by l.at desc, l.id desc limit 1;

  -- el comentario de la aprobación es una línea más del mismo log del pedido
  -- v22.12 cod en comentario (Luis, 23/09): lleva el COD, así aparece en el historial del CLIENTE
  if coalesce(btrim(p_comentario),'') <> '' then
    insert into public."GV_Cuarentena_Comentarios" (empresa, order_id, np, texto, por, persona, cod)
    values (lower(p_empresa), v_clave, nullif(btrim(p_np),''), btrim(p_comentario), v_quien, v_persona, v_cod);
  end if;

  insert into public."GV_Cuarentena_Log" (empresa, clave, np, cod, razon_social, evento, motivos, persona, por, comentario)
  values (lower(p_empresa), v_clave, coalesce(nullif(btrim(p_np),''), v_np), v_cod, v_rs,
          'aprobado', p_motivos, v_persona, v_quien, nullif(btrim(p_comentario),''));
end;
$function$;
