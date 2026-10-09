-- v29.32 (Thomas, 09/10, D32): COPIA EN VIVO del stock de insumos de Virgilio → GP2.
-- "Cuando hago un relevamiento tengo que ver online en GP2 el stock de Cervantes Y el de Virgilio:
--  el máximo necesita las dos plantas."
--
-- Cómo: el stock de Virgilio sigue viviendo en public."Movimientos_Stock" (deposito 'insumos', D28 a).
-- Por cada código de Virgilio que tiene equivalencia en "GP2".importado_virgilio_componente, GP2 tiene
-- que tener en su depósito "<sector> en Virgilio" EXACTAMENTE el saldo de Virgilio, convertido a la
-- unidad de GP2. La función RECONCILIA (objetivo − lo que hay = diferencia) y la asienta como un
-- movimiento 'ajuste' de GP2 con nota «Espejo Virgilio». Idempotente: si ya cuadra no escribe.
--
-- Alcance: cajas, fleje, parte_procesado (SP), partes_crudo (SC), plastico. Los importados NO
-- (sus equivalencias juntan varios códigos en un componente y se cuentan en Importación).
--
-- Conversión a la unidad de GP2:
--   componente en kg      : Kg / (s/u) → tal cual · Bolsas → × material_plastico_kg_x_bolsa (25)
--   componente en unidad  : Uni → tal cual · Cajones → × uni_x_cajon · Paquetes (cajas) → × 25
--   cualquier otra combinación → no se escribe ese componente (queda en el log con el motivo)
--
-- Depósito de GP2: el virgilio_sector con ref_id = sector del componente; bolsas (sector 14) → 57.
-- Sin depósito en Virgilio para ese sector (Garage, Movimiento) → no se escribe, queda en el log.
--
-- Nunca frena una carga del operario: el disparador atrapa cualquier error y lo anota.

-- 1) Equivalencias seguras (54). cod_virgilio en MAYÚSCULAS (check de la tabla).
insert into "GP2".importado_virgilio_componente (cod_virgilio, componente_id, nota, creado_por)
values
 -- cajas (11)
 ('CAJA Nº 1',456,'v29.32 espejo','claude-gv'),('CAJA Nº 2',457,'v29.32 espejo','claude-gv'),
 ('CAJA Nº 6',458,'v29.32 espejo','claude-gv'),('CAJA Nº 7',459,'v29.32 espejo','claude-gv'),
 ('CAJA Nº 10',460,'v29.32 espejo','claude-gv'),('CAJA Nº 12',461,'v29.32 espejo','claude-gv'),
 ('CAJA Nº 13',462,'v29.32 espejo','claude-gv'),('CAJA Nº 15',604,'v29.32 espejo','claude-gv'),
 ('CAJA Nº 16',605,'v29.32 espejo','claude-gv'),('CAJA Nº 22',463,'v29.32 espejo','claude-gv'),
 ('CAJA Nº 29',464,'v29.32 espejo','claude-gv'),
 -- flejes por N° (19)
 ('N°13',176,'v29.32 espejo','claude-gv'),('N°17',179,'v29.32 espejo','claude-gv'),
 ('N°19',180,'v29.32 espejo','claude-gv'),('N°2',168,'v29.32 espejo','claude-gv'),
 ('N°20',181,'v29.32 espejo','claude-gv'),('N°22',183,'v29.32 espejo','claude-gv'),
 ('N°24',185,'v29.32 espejo','claude-gv'),('N°41',197,'v29.32 espejo','claude-gv'),
 ('N°45',199,'v29.32 espejo','claude-gv'),('N°7',173,'v29.32 espejo','claude-gv'),
 ('N°74',209,'v29.32 espejo','claude-gv'),('N°90',583,'v29.32 espejo','claude-gv'),
 ('N°92',215,'v29.32 espejo','claude-gv'),('N°93',216,'v29.32 espejo','claude-gv'),
 ('N°94',217,'v29.32 espejo','claude-gv'),('25',186,'v29.32 espejo','claude-gv'),
 ('4',170,'v29.32 espejo','claude-gv'),('5',171,'v29.32 espejo','claude-gv'),
 ('62',208,'v29.32 espejo','claude-gv'),
 -- SP procesado, mismo código y descripción (11)
 ('A1',80,'v29.32 espejo','claude-gv'),('A10',85,'v29.32 espejo','claude-gv'),
 ('A4',81,'v29.32 espejo','claude-gv'),('A7',82,'v29.32 espejo','claude-gv'),
 ('B13',95,'v29.32 espejo','claude-gv'),('B9',92,'v29.32 espejo','claude-gv'),
 ('C1',96,'v29.32 espejo','claude-gv'),('C15',104,'v29.32 espejo','claude-gv'),
 ('C5',100,'v29.32 espejo','claude-gv'),('C6',101,'v29.32 espejo','claude-gv'),
 ('D4',108,'v29.32 espejo','claude-gv'),
 -- SC crudo, mismo código y descripción (5)
 ('H1',10,'v29.32 espejo','claude-gv'),('H15',12,'v29.32 espejo','claude-gv'),
 ('I11',17,'v29.32 espejo','claude-gv'),('N7',63,'v29.32 espejo','claude-gv'),
 ('Z2B',71,'v29.32 espejo','claude-gv'),
 -- bolsas (8; EBA no tiene componente en GP2)
 ('PP 2630',742,'v29.32 espejo','claude-gv'),('PS PE',749,'v29.32 espejo','claude-gv'),
 ('PE POLIE',748,'v29.32 espejo','claude-gv'),('ABS',743,'v29.32 espejo','claude-gv'),
 ('AI',744,'v29.32 espejo','claude-gv'),('NY VIRGEN',745,'v29.32 espejo','claude-gv'),
 ('NY C/CARGA 25%',747,'v29.32 espejo','claude-gv'),('NY RECUP',746,'v29.32 espejo','claude-gv')
on conflict (cod_virgilio) do nothing;

-- 2) Log de la copia (sólo service / MCP).
create table if not exists public."GV_GP2_Espejo_Log" (
  id bigserial primary key,
  ts timestamptz not null default now(),
  componente_id bigint,
  ubicacion_id bigint,
  cods text,
  antes numeric,
  objetivo numeric,
  delta numeric,
  resultado text,
  motivo text
);
alter table public."GV_GP2_Espejo_Log" enable row level security;
revoke all on public."GV_GP2_Espejo_Log" from anon, authenticated;

-- 3) La reconciliación. p_cod = un código de Virgilio (lo que tocó el disparador) o null = todos.
create or replace function public.gv_gp2_espejo_insumos(p_cod text default null, p_simular boolean default false)
returns table (componente_id bigint, codigo_gp2 text, ubicacion_id bigint, cods text,
               antes numeric, objetivo numeric, delta numeric, resultado text)
language plpgsql security definer set search_path = public, pg_temp
as $fn$  -- marcador v29.32-espejo-gp2
declare
  r record;
  v_kg_bolsa numeric;
begin
  select coalesce(nullif(btrim(p.valor),'')::numeric, 25) into v_kg_bolsa
    from "GP2".parametro p where p.clave = 'material_plastico_kg_x_bolsa';
  v_kg_bolsa := coalesce(v_kg_bolsa, 25);

  for r in
    with _ge_map as (
      select m.cod_virgilio, m.componente_id
        from "GP2".importado_virgilio_componente m
        join public."Insumos" i on upper(btrim(i.cod)) = m.cod_virgilio
       where m.componente_id is not null
         and i.categoria in ('cajas','fleje','parte_procesado','partes_crudo','plastico')
    ),
    _ge_comp as (   -- componentes a reconciliar (todos o los del código tocado)
      select distinct g.componente_id from _ge_map g
       where p_cod is null or g.cod_virgilio = upper(btrim(p_cod))
    ),
    _ge_sal as (
      select g.componente_id, g.cod_virgilio, v.unidad, coalesce(v.saldo,0) saldo
        from _ge_map g
        join _ge_comp k on k.componente_id = g.componente_id
        left join public.vista_saldos_insumos_x_unidad v on upper(btrim(v.cod_art)) = g.cod_virgilio
    ),
    _ge_conv as (
      select s.*, c.codigo, c.sector_id, lower(coalesce(c.unidad_medida,'unidad')) um,
             case
               when s.unidad is null or s.saldo = 0 then 0
               when lower(coalesce(c.unidad_medida,'unidad')) = 'kg' then
                 case when s.unidad in ('Kg','(s/u)') then s.saldo
                      when s.unidad = 'Bolsas'        then s.saldo * v_kg_bolsa end
               else
                 case when s.unidad = 'Uni'      then s.saldo
                      when s.unidad = 'Cajones'  then s.saldo * c.uni_x_cajon
                      when s.unidad = 'Paquetes' then s.saldo * 25 end
             end cant
        from _ge_sal s join "GP2".componente c on c.id = s.componente_id
    )
    select cv.componente_id, max(cv.codigo) codigo, max(cv.um) um,
           case when max(cv.sector_id) = 14 then 57::bigint
                else (select u.id from "GP2".ubicacion u
                       where u.tipo = 'virgilio_sector' and u.ref_id = max(cv.sector_id) limit 1) end ubic,
           string_agg(distinct cv.cod_virgilio, ', ') cods,
           sum(cv.cant) objetivo,
           bool_or(cv.cant is null) no_conv,
           string_agg(case when cv.cant is null then cv.cod_virgilio||' en '||cv.unidad end, ', ') no_conv_txt
      from _ge_conv cv
     group by cv.componente_id
  loop
    componente_id := r.componente_id; codigo_gp2 := r.codigo; ubicacion_id := r.ubic; cods := r.cods;
    objetivo := round(coalesce(r.objetivo,0), 4);
    select coalesce(max(i.cantidad),0) into antes
      from "GP2".inventario i where i.componente_id = r.componente_id and i.ubicacion_id = r.ubic;
    delta := round(objetivo - antes, 4);

    if r.ubic is null then
      resultado := 'sin depósito en Virgilio';
    elsif r.no_conv then
      resultado := 'unidad no convertible: ' || r.no_conv_txt;
    elsif abs(delta) < 0.0005 then
      resultado := 'ok';
    elsif p_simular then
      resultado := 'ajustaría';
    else
      insert into "GP2".movimiento (fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id,
                                    cantidad, unidad_origen, unidad_destino, nota)
      values (now(), 'ajuste', r.componente_id,
              case when delta < 0 then r.ubic end,
              case when delta > 0 then r.ubic end,
              abs(delta),
              case when delta < 0 then (case when r.um = 'kg' then 'kg' else 'uni' end) end,
              case when delta > 0 then (case when r.um = 'kg' then 'kg' else 'uni' end) end,
              'Espejo Virgilio (' || r.cods || ')');
      resultado := 'ajustado';
    end if;

    if not p_simular and resultado <> 'ok' then
      insert into public."GV_GP2_Espejo_Log" (componente_id, ubicacion_id, cods, antes, objetivo, delta, resultado)
      values (r.componente_id, r.ubic, r.cods, antes, objetivo, delta, resultado);
    end if;
    return next;
  end loop;
end;
$fn$;
revoke all on function public.gv_gp2_espejo_insumos(text, boolean) from public, anon, authenticated;

-- 4) Disparador: cada movimiento de insumos reconcilia ese código. NUNCA frena la carga.
create or replace function public.gv_gp2_espejo_insumos_trg()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $fn$  -- marcador v29.32-espejo-gp2-trg
declare v_cod text;
begin
  v_cod := case when tg_op = 'INSERT' then new.cod_art else coalesce(new.cod_art, old.cod_art) end;
  begin
    perform public.gv_gp2_espejo_insumos(v_cod, false);
    if tg_op = 'UPDATE' and old.cod_art is distinct from new.cod_art then
      perform public.gv_gp2_espejo_insumos(old.cod_art, false);
    end if;
  exception when others then
    insert into public."GV_GP2_Espejo_Log" (cods, resultado, motivo)
    values (v_cod, 'error', sqlstate || ' ' || sqlerrm);
  end;
  return null;
end;
$fn$;

create or replace trigger zz_gv_gp2_espejo_insumos
  after insert or update on public."Movimientos_Stock"
  for each row when (new.deposito = 'insumos')
  execute function public.gv_gp2_espejo_insumos_trg();

-- 5) Red: reconciliación completa 2 veces por hora (19 y 49, minutos con poca carga), anti-solape.
select cron.schedule('gv-gp2-espejo-insumos', '19,49 * * * *',
  $c$do $d$ begin if pg_try_advisory_xact_lock(hashtext('cron:gv_gp2_espejo_insumos')::bigint) then
       perform public.gv_gp2_espejo_insumos(null, false); end if; end $d$;$c$);

-- 6) Centinela.
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_gp2_espejo_insumos','funcion','vista_saldos_insumos_x_unidad',
        'GP2 ve en su depósito en Virgilio el saldo real de insumos de Virgilio (D32)','Thomas','v29.32');

-- Rollback:
--   select cron.unschedule('gv-gp2-espejo-insumos');
--   alter table public."Movimientos_Stock" disable trigger zz_gv_gp2_espejo_insumos;
--   (las equivalencias quedan; los ajustes en GP2 llevan nota 'Espejo Virgilio (...)')
--
-- Verificación:
--   select * from public.gv_gp2_espejo_insumos(null, true);   -- qué haría, sin escribir
--   select * from public."GV_GP2_Espejo_Log" order by id desc limit 50;
