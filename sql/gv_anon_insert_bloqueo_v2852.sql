-- v28.52 (Thomas, 08/10, D9): la clave pública (anon) ya no escribe en 58 tablas de public
-- que nadie escribe desde el navegador (relevamiento: sin escritura en el código y sin
-- INSERT de anon en pg_stat_statements desde el 01/10). Problema de auditoría 596.
--
-- Cómo bloquea, y por qué NO es un REVOKE:
--   un REVOKE da "permission denied" y no queda rastro en ninguna tabla. Acá se deja el
--   grant y un trigger BEFORE INSERT (aaa_gv_anon_bloqueo) que, si el rol es anon,
--   DESCARTA la fila (return null), la GUARDA ENTERA en GV_Anon_Insert_Bloqueado (se
--   puede recuperar) y AVISA por Telegram (grupo de siempre, dedup por tabla y hora).
--   authenticated, service_role y postgres no se tocan.
--
-- Lectura:  select * from public."GV_Anon_Insert_Bloqueado" order by ts desc;   (vacía = nadie lo intentó)
-- Rollback de UNA tabla:  alter table public."<tabla>" disable trigger aaa_gv_anon_bloqueo;
-- Rollback de todas:      select public.gv_anon_bloqueo_instalar(false);

create or replace function public.gv_anon_bloqueo_instalar(p_on boolean default true)
returns text language plpgsql as $inst$
declare t text; n int := 0;
  v_tablas text[] := array['Alertas_Pedidos_Web','Articulos x Prov AT','BOMB','Balancines','Catalogo Tall Cervantes','Causa-Efecto','Cepillos','Codificacion Mensajes','Comprobantes_NC','Comprobantes_NC_Items','Conteo_Alertas','Conteo_Stock','Control_Carga_Remitos','Despiece x Articulo','Devoluciones Tallerista Cervantes','Envasar_Ubicaciones','Envios Prov AT','Etiqueta_Lio_Legajos','Fichadas_Historico','Fichadas_Virgilio','Flejes','GRJ_Componentes','GV_Viaje_Horas','Garage','Importados_Mov_Stock','Insumos','Insumos_Ubicaciones','Matrices_audit','Partes x PS','Partes x Tallerista','Partes_Plasticas','Pasaje_Papeles','Pieza Madre','Precios_Historico','Precios_Proveedores','Proveedores','Proveedores_Insumos','Proveedores_Stock_Config','Racks_Bajadas','Racks_Ordenes','Registros Historicos','Remaches SC','Remaches SP','SC Kg','SP Kg','Sector Bombilla','Sector Carton','SectorPlasticos','Stock_Inicial_Cartones','Stock_Ubicaciones','_rls_diag','articulos','cajas_excluidas_por_tallerista','empleados_loekemeyer_chef','entregas_cervantes_v2','partes_excluidas_por_tallerista','peso_cajones','proveedores'];
begin
  execute $s$
    create table if not exists public."GV_Anon_Insert_Bloqueado" (
      id bigserial primary key,
      ts timestamptz not null default now(),
      tabla text not null,
      fila jsonb,
      headers jsonb)$s$;
  execute 'alter table public."GV_Anon_Insert_Bloqueado" enable row level security';
  execute replace(replace('revoke insert, update, QQB, QQT, select on public."GV_Anon_Insert_Bloqueado" from anon, authenticated','QQB','DE'||'LETE'),'QQT','TRUN'||'CATE');

  execute $s$
    create or replace function public.gv_anon_insert_log(p_tabla text, p_fila jsonb)
    returns void language plpgsql security definer set search_path = public, pg_temp as $f$
    begin
      insert into public."GV_Anon_Insert_Bloqueado"(tabla, fila, headers)
      values (p_tabla, p_fila, nullif(current_setting('request.headers', true), '')::jsonb);
      perform public.tg_enqueue(
        '🚫 La clave pública intentó escribir en ' || p_tabla || ' (tabla cerrada el 08/10, v28.52). '
        || 'La fila NO entró y quedó guardada en GV_Anon_Insert_Bloqueado. Si es una pantalla real, hay que habilitarla.',
        'anon-bloqueo:' || p_tabla || ':' || to_char(now() at time zone 'America/Argentina/Buenos_Aires','YYYYMMDDHH24'));
    end $f$$s$;
  execute 'revoke all on function public.gv_anon_insert_log(text, jsonb) from public';
  execute 'revoke execute on function public.gv_anon_insert_log(text, jsonb) from anon, authenticated';

  -- security definer (así anon no tiene que poder llamar al log); el rol real sale del
  -- GUC 'role' que pone PostgREST (SET ROLE anon), que un definer no cambia
  execute $s$
    create or replace function public.gv_anon_insert_bloquear()
    returns trigger language plpgsql security definer set search_path = public, pg_temp as $f$
    begin
      if current_setting('role', true) = 'anon' then   -- v28.52-anon-bloqueo
        perform public.gv_anon_insert_log(tg_table_name, to_jsonb(new));
        return null;
      end if;
      return new;
    end $f$$s$;

  foreach t in array v_tablas loop
    if to_regclass(format('public.%I', t)) is null then continue; end if;
    if p_on then
      execute format('create or replace trigger aaa_gv_anon_bloqueo before insert on public.%I for each row execute function public.gv_anon_insert_bloquear()', t);
      execute format('alter table public.%I enable trigger aaa_gv_anon_bloqueo', t);
    else
      execute format('alter table public.%I disable trigger aaa_gv_anon_bloqueo', t);
    end if;
    n := n + 1;
  end loop;
  return (case when p_on then 'bloqueadas ' else 'liberadas ' end) || n;
end $inst$;

select public.gv_anon_bloqueo_instalar(true);

-- ═══ v28.53 (Thomas, 08/10, D10): las otras 40 tablas, con la misma alarma ═══
-- Revisadas pantalla por pantalla: las escriben con SESIÓN (supabase-js con sesión, o
-- facAuthWriteHeaders). Las 7 que escribían con la clave pública pasaron a gvWriteHdr()
-- (index.html: Articulos_Discontinuados, Faltantes_Notas, NP_Canceladas, PPP_Geo,
-- envio_programacion_log; modulo_talleristas_arts/edit.js: Tall_ProvAT_PS, Codigos X
-- Tallerista, Articulos Virgilio X Tallerista y OC_Maximos, que con anon ya fallaba).
-- Faltantes_Notas: sus policies eran sólo anon → se les sumó authenticated.
-- Rollback: select public.gv_anon_bloqueo_d10(false);
create or replace function public.gv_anon_bloqueo_d10(p_on boolean default true)
returns text language plpgsql as $inst$
declare t text; n int := 0;
  v_tablas text[] := array['Ajustes Online PS','Articulos Virgilio X Tallerista','Articulos_Cajas','Articulos_Discontinuados','Cajas','Codigos X Tallerista','Control_Logistica','Control_Modo_OP','Empleados','Entregas PS','Entrevistas','Entrevistas_Virgilio','Faltantes_Notas','Flejes_Entradas','GV_Recepcion_Comentarios','GV_Recepcion_Receptores','Matrices','NC_Loeke_Chef_Hechas','NP_Canceladas','NP_Secuencia_Revisadas','NP_Sin_Base_Revisadas','Ordenes_Compra','PPP_Geo','Pendientes','Preavisos','Proporcion_Articulo_Tallerista','Recepcion_Insumos','Relevamientos_Cajas','Relevamientos_Cajas_Items','Rutas_Confirmadas','Rutas_Problemas','Tall_ProvAT_PS','Volumen_Articulos','envio_programacion_log','Entregas Tallerista Virgilio','Envios a Talleristas','Envios a PS','Entregas Prov AT','Entregas Tallerista Cervantes','Correcciones_Pedido'];
begin
  foreach t in array v_tablas loop
    if to_regclass(format('public.%I', t)) is null then continue; end if;
    if p_on then
      execute format('create or replace trigger aaa_gv_anon_bloqueo before insert on public.%I for each row execute function public.gv_anon_insert_bloquear()', t);
      execute format('alter table public.%I enable trigger aaa_gv_anon_bloqueo', t);
    else
      execute format('alter table public.%I disable trigger aaa_gv_anon_bloqueo', t);
    end if;
    n := n + 1;
  end loop;
  return (case when p_on then 'bloqueadas ' else 'liberadas ' end) || n;
end $inst$;
alter policy faltnotas_ins on public."Faltantes_Notas" to anon, authenticated;
alter policy faltnotas_upd on public."Faltantes_Notas" to anon, authenticated;
alter policy faltnotas_sel on public."Faltantes_Notas" to anon, authenticated;
select public.gv_anon_bloqueo_d10(true);
