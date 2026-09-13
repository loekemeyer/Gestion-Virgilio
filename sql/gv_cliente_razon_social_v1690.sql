-- v16.90 (2026-09-13) -- En la PPP va la RAZON SOCIAL, nunca el nombre de fantasia.
--
-- Regla del dueno (13/09, textual): "En ningun lado tengo explicado que debe ponerse
-- el nombre de fantasia. Solo la razon social."
--
-- QUE PASABA: ISIS manda en razon_social el nombre de fantasia de la sucursal. El caso
-- que lo destapo: las NP 98669/98670/98671 del cod 1792 salian "Pettish Lacroze 2481" y
-- "Pettish Villa Crespo", cuando la razon social es "Dapelo Claudio Marcelo"
-- (CUIT 20202038507, mismo titular -- su mail es pettishbazar@hotmail.com).
--
-- MEDICION (la que vale, cruzando cada empresa contra SU padron):
--   LK   93 pares cod+razon_social -> 89 coinciden, 4 no
--   Chef 15 pares                  -> 15 coinciden, 0 no
--   De las 4: 2 son este cliente (7 NP) y 2 son basura de formato que NO se toca
--   (cod 2533 doble espacio, cod 4223 salto de linea: mismo cliente, el PPP esta mejor
--   escrito que el padron).
--
-- OJO -- EL ERROR QUE COMETI ANTES DE MEDIR BIEN: cruzar ppp_np_feed (que trae NP de LK
-- y de Chef) contra public.customers (padron de LK SOLO) por cod. Daba 9 discrepancias y
-- 5 eran falsas: cod 2393/2444/2447/2448/2469 son clientes de CHEF con CUIT propio que
-- comparten numero con otro cliente de LK. NO SE PUEDE CRUZAR POR COD SIN EMPRESA.
--
-- POR QUE UN OVERRIDE Y NO UN UPDATE: la tabla madre GV_PPP_Programacion_Diaria la
-- escribe el sync de ISIS desde afuera de la base (ninguna funcion SQL la toca: se
-- verifico con pg_proc.prosrc). Un UPDATE se perderia en la proxima corrida, y ademas
-- las NP nuevas del mismo cliente volverian a entrar mal. El override se aplica al leer,
-- asi que sobrevive al sync y cubre las NP futuras.

-- 1) La tabla de override, por (empresa, cod). La empresa es OBLIGATORIA: el cod solo
--    no identifica al cliente (cod 1792 en Chef es Supertextil S.R.L, otro CUIT).
create table if not exists public."GV_Cliente_Razon_Social" (
  empresa        text not null check (empresa in ('lk','chef')),
  cod            text not null,
  razon_social   text not null,
  motivo         text,
  actualizado_at timestamptz not null default now(),
  primary key (empresa, cod)
);
alter table public."GV_Cliente_Razon_Social" enable row level security;
drop policy if exists gv_crs_read on public."GV_Cliente_Razon_Social";
create policy gv_crs_read on public."GV_Cliente_Razon_Social"
  for select to anon, authenticated using (true);
grant select on public."GV_Cliente_Razon_Social" to anon, authenticated;

insert into public."GV_Cliente_Razon_Social" (empresa, cod, razon_social, motivo)
values ('lk','1792','Dapelo Claudio Marcelo',
        'ISIS manda el nombre de fantasia de la sucursal (Pettish Lacroze 2481 / Pettish Villa Crespo). CUIT 20202038507.')
on conflict (empresa, cod) do update
  set razon_social = excluded.razon_social, motivo = excluded.motivo, actualizado_at = now();

-- 2) La tabla madre, ya con la razon social resuelta. Mismas filas y mismas columnas:
--    lo unico que cambia es el texto de razon_social. Por eso se puede pegar en lugar de
--    la tabla en cualquier consumidor sin mirar el resto de su definicion.
create or replace view public.gv_ppp_prog_rs
with (security_invoker = true) as
select p.id, p.np, p.tanda, p.tipo, p.fecha_recep, p.cod,
       coalesce(rs.razon_social, p.razon_social) as razon_social,
       p.m3, p.v, p.direccion, p.barrio, p.op, p.fecha_entrega, p.fecha_fc,
       p.zona, p.observaciones
  from public."GV_PPP_Programacion_Diaria" p
  left join public."GV_Cliente_Razon_Social" rs
         on rs.cod = regexp_replace(btrim(p.cod), '\.0+$', '')
        and rs.empresa = public.gv_empresa_de_np_texto(p.np);
grant select on public.gv_ppp_prog_rs to anon, authenticated;

-- 3) La vista que lee la app: el mismo COALESCE, adentro de la definicion que ya tenia
--    (override de tanda/fecha/zona + corte del espejo). Lo unico agregado es el join a
--    GV_Cliente_Razon_Social y el coalesce de razon_social.
create or replace view public.gv_ppp_programacion_diaria as
 SELECT p.id,
    p.np,
        CASE
            WHEN COALESCE(o.desprogramada, false) THEN ''::text
            ELSE COALESCE(NULLIF(btrim(o.tanda), ''::text), p.tanda)
        END AS tanda,
    p.tipo,
    p.fecha_recep,
    p.cod,
    COALESCE(rs.razon_social, p.razon_social) AS razon_social,
    p.m3,
    p.v,
    p.direccion,
    p.barrio,
    p.op,
        CASE
            WHEN COALESCE(o.desprogramada, false) THEN ''::text
            ELSE COALESCE(o.fecha_entrega::text || ' 00:00:00'::text, p.fecha_entrega)
        END AS fecha_entrega,
    p.fecha_fc,
    COALESCE(NULLIF(btrim(o.zona), ''::text), p.zona) AS zona,
    p.observaciones
   FROM "GV_PPP_Programacion_Diaria" p
     CROSS JOIN gv_espejo_corte() c(lk, chef)
     LEFT JOIN "GV_PPP_Prog_Override" o ON o.np = regexp_replace(p.np, '\.0+$'::text, ''::text)
     LEFT JOIN "GV_Cliente_Razon_Social" rs
            ON rs.cod = regexp_replace(btrim(p.cod), '\.0+$'::text, ''::text)
           AND rs.empresa = gv_empresa_de_np_texto(p.np)
  WHERE gv_espejo_np_pasa(p.np, c.lk, c.chef) AND NOT COALESCE(o.oculto, false);

-- ⚠ CREATE OR REPLACE VIEW **BORRA LAS reloptions**. Paso durante este mismo cambio: la
--   vista quedo sin security_invoker (o sea corriendo como postgres y salteando la RLS,
--   que es exactamente la causa de la filtracion del 2026-09-04). Se detecto comparando
--   contra sus hermanas. Reponerlo SIEMPRE despues de cada replace:
alter view public.gv_ppp_programacion_diaria set (security_invoker = true);

-- 4) Las 6 vistas que exponian razon_social leyendo la tabla MADRE directo pasan a leer
--    gv_ppp_prog_rs. Se hizo con el loop de abajo (respaldo de las definiciones
--    originales en zz_backups."GV_Backup_Vistas_RS_20260913"):
--      gv_np_web_dobles, gv_venta_mensual_cliente, vista_cola_impresion,
--      vista_correcciones_pedido_rich, vista_ppp_pedidos_entregados,
--      vista_ppp_programacion_pendiente
--
-- do $$
-- declare r record; nuevo text;
-- begin
--   for r in select relname, def_original, reloptions
--              from zz_backups."GV_Backup_Vistas_RS_20260913" order by relname loop
--     nuevo := replace(r.def_original, '"GV_PPP_Programacion_Diaria"', 'public.gv_ppp_prog_rs');
--     if nuevo = r.def_original then raise exception 'sin reemplazo en %', r.relname; end if;
--     execute format('create or replace view public.%I as %s', r.relname, nuevo);
--     if r.reloptions like '%security_invoker=true%' then
--       execute format('alter view public.%I set (security_invoker = true)', r.relname);
--     end if;
--   end loop;
-- end $$;

-- VERIFICACION (corrida como anon, que es quien lee desde la app):
--   gv_ppp_programacion_diaria      123 filas, 18 Dapelo, 0 Pettish
--   vista_ppp_programacion_pendiente 70 filas, 18 Dapelo, 0 Pettish
--   gv_venta_mensual_cliente       8859 filas, 49 Dapelo, 0 Pettish
--   gv_endpoints_rotos                0
--   las 6 vistas conservan security_invoker=true
--
-- LO QUE NO SE TOCO A PROPOSITO:
--   - Facturacion_NP, wa_np_snapshot, GV_Clientes_Direcciones y GV_Geo_Cliente guardan la
--     razon social como SNAPSHOT del momento. Lo viejo queda como esta (es historia); lo
--     nuevo ya entra bien porque la app lee de las vistas corregidas.
--   - cod 2533 y 4223: diferencia de espacios/salto de linea contra el padron. Mismo
--     cliente, no es nombre de fantasia.
--
-- ROLLBACK:
--   delete from public."GV_Cliente_Razon_Social" where empresa='lk' and cod='1792';
--   -- y para volver las 6 vistas a la tabla madre:
--   -- mismo loop, con replace('public.gv_ppp_prog_rs' -> '"GV_PPP_Programacion_Diaria"')
--   -- o directamente las def_original de zz_backups."GV_Backup_Vistas_RS_20260913".
