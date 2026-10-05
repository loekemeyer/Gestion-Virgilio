-- v27.05 (Luis, 05/10): cada NP guarda la PAUTA de programación (P1..P24) con la que el armado
-- automático la programó, y por qué no siguió con la siguiente. La lee el botoncito P# del
-- Resumen de la PPP (gv_ppp_np_pauta_lista).
--
-- Cómo se registra: el armador (gv_ppp_web_armar_pendientes) pone set_config('gv.pauta', <json>, true)
-- antes de cada pase; el trigger gv_ppp_np_pauta_registrar de PPP_Web_Programacion anota la pauta
-- cuando la NP toma tanda o cambia de día dentro de esa transacción. Sin GUC (a mano, cron) no anota.
-- En el pase (g) el json lo arma gv_ppp_pauta_grupo_clasificar leyendo _gdg_oc, la tabla temporal
-- que gv_ppp_web_dia_grupo acaba de armar: la cuenta es la misma, no se duplica.
--
-- Rollback:
--   drop trigger if exists gv_ppp_np_pauta_registrar on public."PPP_Web_Programacion";
--   (armador) quitar las líneas con 'v27.05-pauta' (el bloque de abajo es idempotente).

-- 1) catálogo -----------------------------------------------------------------------------------
create table if not exists public."GV_PPP_Pautas" (
  codigo    text primary key,
  orden     numeric not null,
  titulo    text not null,
  condicion text not null,
  siguiente text
);
alter table public."GV_PPP_Pautas" enable row level security;
drop policy if exists gv_ppp_pautas_sel on public."GV_PPP_Pautas";
create policy gv_ppp_pautas_sel on public."GV_PPP_Pautas" for select using (true);
revoke insert, update, delete, truncate on public."GV_PPP_Pautas" from anon, authenticated;
grant select on public."GV_PPP_Pautas" to anon, authenticated;

insert into public."GV_PPP_Pautas"(codigo, orden, titulo, condicion, siguiente) values
 ('P1',1,'Retira','El pedido dice Retira: lleva zona «Retira» y ningún pase de reparto lo toma.','Si eligió día lo toma P13; si no, queda en A Programar.'),
 ('P2',2,'Diferido adelantado','Una NP que espera importados quedó programada antes de su reingreso: se saca de su tanda (si no empezó).','La reprograma P16 en la misma corrida.'),
 ('P3',3,'Ya programado','La NP ya tiene tanda: el armado no la vuelve a evaluar.',null),
 ('P4',4,'Espera mercadería','NP diferida: se aparta de los pases normales.','La programa P16 cuando llega el reingreso.'),
 ('P5',5,'Retenido a mano','Un supervisor la sacó de su tanda: no entra al armado.',null),
 ('P6',6,'Cancelado a mano','NP cancelada: no entra al armado.',null),
 ('P7',7,'Tope por corrida','Máximo 120 pedidos por corrida; el resto espera la corrida siguiente (5 min).',null),
 ('P8',8,'Cuarentena / cliente nuevo sin aprobar','Nunca se programa solo. Si no se pudo evaluar, también queda retenido.','Aprobado por una persona, vuelve a los pases.'),
 ('P9',9,'Diferido en cuarentena','Lo mismo que P8 para lo que espera mercadería.',null),
 ('P10',10,'Cliente nuevo aprobado','Aprobado en el pipeline: sale en uno de los 2 días con reparto siguientes (primero el que ya tiene camión a su grupo). Pisa el cupo.','No sigue a las pautas de fecha: la aprobación manda.'),
 ('P11',11,'Chef de razón social que entró por LK','Va forzado al mismo día que el pedido de LK de esa razón social.','Fecha forzada: no se evalúan las pautas de grupo.'),
 ('P12',12,'Súper con turno','Va el día del turno de su OC, en tanda y camión propios. Pisa el cupo.','El turno no se negocia: no se evalúan las pautas de grupo.'),
 ('P13',13,'Retira con día elegido','Va el día que eligió el cliente, en tanda propia. Pisa el cupo.','El día del cliente no se negocia.'),
 ('P14',14,'Grupo de zonas','Plazo = pedido + 14 días (expreso + 13), hacia atrás al día con reparto. Piso: 4 hábiles.',null),
 ('P14a',14.1,'Su grupo ya sale en el plazo','Va al primer día del plazo en que su grupo de zonas ya tiene camión, sin mirar el cupo.','P14b sólo se usa si su grupo no sale en el plazo.'),
 ('P14b',14.2,'Último día libre del plazo','Su grupo no sale en el plazo: va al último día del plazo sin ningún grupo, para que se sumen los que entren después.','P14c sólo se usa si no hay ningún día libre.'),
 ('P14c',14.3,'Día con menos grupos','Ni su grupo ni un día libre en el plazo: va al día con menos camiones.','P14d sólo se usa si el plazo ya venció.'),
 ('P14d',14.4,'Vencido: lo antes posible','El plazo es anterior al primer día posible: va lo antes posible, aunque mezcle grupos.','Es la última pauta de fecha.'),
 ('P15',15,'Súper sin turno (INC)','auto_super sin turno: próximo día con cupo.',null),
 ('P16',16,'Diferido','Va al primer día con cupo desde el reingreso de la mercadería.','El reingreso manda: no se evalúan las pautas de grupo.'),
 ('P17',17,'Tope 5 NP por tanda','La tanda no pasa de 5 NP (un cliente con más va entero).',null),
 ('P18',18,'Una góndola por tanda','Toda LK o toda CH; NP de Chef con y sin L va sola.',null),
 ('P19',19,'Sin mezclar','Un grupo de zonas, una empresa, súper nunca con clientes.',null),
 ('P20',20,'Cercanía','Sectores vecinos, hasta 1,00 m³ por tanda.',null),
 ('P21',21,'Fusión','Tandas del mismo día y camión se juntan hasta 0,80 m³ (máx. 1,00), sólo sin empezar.',null),
 ('P22',22,'Cron de las 18:00','Lo no facturado se mueve a un día que ya tiene camión a su grupo.',null),
 ('P23',23,'Optimizador de las 18:00','Junta camiones enteros del mismo grupo.',null),
 ('P24',24,'A mano','Una persona la programó o la movió. Gana sobre todo: ningún proceso automático la mueve.',null)
on conflict (codigo) do update set orden = excluded.orden, titulo = excluded.titulo,
  condicion = excluded.condicion, siguiente = excluded.siguiente;

-- 2) registro -----------------------------------------------------------------------------------
create table if not exists public."GV_PPP_NP_Pauta" (
  id        bigserial primary key,
  empresa   text not null,
  order_id  bigint not null,
  np_idx    int not null,
  tanda     text,
  fecha     date,
  pauta     text not null,
  detalle   jsonb,
  ts        timestamptz not null default now()
);
create index if not exists gv_ppp_np_pauta_np on public."GV_PPP_NP_Pauta"(empresa, order_id, np_idx, ts desc);
alter table public."GV_PPP_NP_Pauta" enable row level security;
revoke all on public."GV_PPP_NP_Pauta" from anon, authenticated;

create or replace function public.gv_ppp_np_pauta_registrar()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
declare v_g text := coalesce(current_setting('gv.pauta', true), ''); v_j jsonb;
begin
  -- v27.05-pauta: sólo dentro del armado (GUC puesta); nunca frena la programación
  if v_g not like '{%' or coalesce(nullif(btrim(new.tanda), ''), '') = '' then return null; end if;
  if tg_op = 'UPDATE' and old.tanda is not distinct from new.tanda
     and old.fecha_entrega is not distinct from new.fecha_entrega then return null; end if;
  begin
    v_j := v_g::jsonb;
    if tg_op = 'UPDATE' and old.tanda is distinct from new.tanda and coalesce(btrim(old.tanda), '') <> '' then
      v_j := v_j || jsonb_build_object('de', old.tanda);
    end if;
    insert into public."GV_PPP_NP_Pauta"(empresa, order_id, np_idx, tanda, fecha, pauta, detalle)
    values (new.empresa, new.order_id, new.np_idx, new.tanda, new.fecha_entrega, coalesce(v_j->>'p', '?'), v_j);
  exception when others then null;
  end;
  return null;
end $f$;

drop trigger if exists gv_ppp_np_pauta_registrar on public."PPP_Web_Programacion";
create trigger gv_ppp_np_pauta_registrar after insert or update of tanda, fecha_entrega
  on public."PPP_Web_Programacion" for each row execute function public.gv_ppp_np_pauta_registrar();

-- 3) clasificador del pase (g): qué rama de gv_ppp_web_dia_grupo eligió el día --------------------
create or replace function public.gv_ppp_pauta_grupo_clasificar(p_zona text, p_entrada date, p_expreso boolean,
  p_min date, p_dia date, p_m3 numeric default 0)
returns jsonb language plpgsql set search_path to 'public', 'pg_temp' as $f$
declare
  v_grp text := public.gv_ppp_web_camion(p_zona, null::text);
  v_otro text; v_lim date; v_lim0 date; v_g int := 0;
  v_a date[]; v_b date; v_c date; v_cn int; v_p text; v_mot text; v_prev text; v_sig text;
  v_m3 numeric := coalesce(p_m3, 0); v_comp boolean := false;
begin
  -- v27.05-pauta: lee _gdg_oc, la que gv_ppp_web_dia_grupo armó recién (misma cuenta, no se duplica)
  if v_grp = 'GBA Norte Lejos' then v_grp := 'GBA Norte'; end if;
  v_otro := case v_grp when 'Capital Centro' then 'Capital Oeste' when 'Capital Oeste' then 'Capital Centro' end;
  v_lim0 := coalesce(p_entrada, current_date) + case when p_expreso then 13 else 14 end;
  v_lim := v_lim0;
  while not public.gv_es_dia_con_reparto(v_lim) and v_g < 15 loop v_lim := v_lim - 1; v_g := v_g + 1; end loop;
  if to_regclass('pg_temp._gdg_oc') is null then
    return jsonb_build_object('p','P14','grupo',v_grp,'plazo',v_lim,'minimo',p_min,'dia',p_dia);
  end if;
  execute $q$ select array_agg(dia order by dia) from _gdg_oc where dia <= $1
      and (tiene_propio or ($2 is not null and m3_otro is not null and m3_otro < 1 and m3_propio + $3 < 1)) $q$
    into v_a using v_lim, v_otro, v_m3;
  execute $q$ select max(dia) from _gdg_oc where dia <= $1 and camiones = 0 $q$ into v_b using v_lim;
  execute $q$ select dia, camiones from _gdg_oc where dia <= $1 order by camiones, dia limit 1 $q$ into v_c, v_cn using v_lim;
  execute $q$ select not coalesce(tiene_propio, false) from _gdg_oc where dia = $1 $q$ into v_comp using p_dia;

  if v_a is not null and p_dia = v_a[1] then
    v_p := 'P14a';
    v_mot := case when coalesce(v_comp, false)
      then 'Comparte el camión de ' || v_grp || ' con ' || v_otro || ' el ' || to_char(p_dia,'DD/MM') || ': las dos zonas suman menos de 1 m³ ese día.'
      else 'Su grupo (' || v_grp || ') ya tenía camión el ' || to_char(p_dia,'DD/MM') || ', dentro del plazo (hasta el ' || to_char(v_lim,'DD/MM') || '). Va ahí sin mirar el cupo.' end;
    v_sig := 'No pasó a P14b (último día libre' || coalesce(', que hubiera sido el ' || to_char(v_b,'DD/MM'), '') ||
             ') porque P14b sólo se usa si su grupo no sale en el plazo.';
  elsif v_b is not null and p_dia = v_b then
    v_p := 'P14b';
    v_prev := 'P14a no aplicó: ningún día entre el ' || to_char(p_min,'DD/MM') || ' y el ' || to_char(v_lim,'DD/MM') || ' tenía camión de ' || v_grp || '.';
    v_mot := 'Va al último día libre del plazo (' || to_char(p_dia,'DD/MM') || '), sin ningún otro grupo, para que se le sumen los pedidos de ' || v_grp || ' que entren después.';
    v_sig := 'No pasó a P14c porque había un día libre en el plazo.';
  elsif p_min <= v_lim and v_c is not null and p_dia = v_c then
    v_p := 'P14c';
    v_prev := 'P14a no aplicó: ' || v_grp || ' no salía en el plazo. P14b no aplicó: ningún día del plazo estaba libre.';
    v_mot := 'Va al día con menos camiones del plazo: el ' || to_char(p_dia,'DD/MM') || ' (' || coalesce(v_cn, 0) || ' grupo/s ya programados).';
    v_sig := 'No pasó a P14d porque el plazo (' || to_char(v_lim,'DD/MM') || ') todavía no venció.';
  else
    v_p := 'P14d';
    v_prev := case when p_min > v_lim
      then 'P14a a P14c no aplicaron: el plazo (' || to_char(v_lim,'DD/MM') || ') es anterior al primer día posible (' || to_char(p_min,'DD/MM') || ', 4 hábiles de anticipación).'
      else 'P14a a P14c no dieron un día dentro del plazo (' || to_char(v_lim,'DD/MM') || ').' end;
    v_mot := 'Ya vencido: va lo antes posible, el ' || to_char(p_dia,'DD/MM') || ' (primero un día con su grupo o libre).';
    v_sig := 'Es la última pauta de fecha.';
  end if;
  return jsonb_build_object('p', v_p, 'grupo', v_grp, 'entrada', p_entrada, 'expreso', p_expreso,
    'plazo', v_lim, 'minimo', p_min, 'dia', p_dia, 'dias_grupo', to_jsonb(v_a),
    'alt_b', v_b, 'alt_c', v_c, 'motivo', v_mot, 'previas', v_prev, 'no_siguiente', v_sig);
exception when others then
  return jsonb_build_object('p','P14','error',sqlerrm,'dia',p_dia);
end $f$;

-- 4) el armador anota la pauta: set_config antes de cada pase (aplicado sobre la definición VIVA,
--    idempotente, falla si un patrón no aparece exactamente una vez). Ver el DO aplicado el 05/10:
--    (a0R) reset · (a0e) P10 · (a) P11 · (a1)(a2) reset · (a3) P12 · (a4) P13 · (b00..c) reset ·
--    (g) gv_ppp_pauta_grupo_clasificar después de `continue when v_fecha is null;` · INC P15 ·
--    (b2) P16 · (d) reset · (e) P21 · log reset. Marcador: v27.05-pauta (13 apariciones).
--
-- 5) lectura: public.gv_ppp_np_pauta_lista() — SECURITY DEFINER, anon (453 filas, 63 ms el 05/10).
--    Prioridad: manual (P24) > cron 18:00 (P22/P23, de gv_ppp_np_origen) > registrada (GV_PPP_NP_Pauta)
--    > deducida (regla de gv_ppp_np_origen). El CREATE completo se trae con:
--    select pg_get_functiondef('public.gv_ppp_np_pauta_lista'::regproc);
