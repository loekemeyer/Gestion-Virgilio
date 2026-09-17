-- ============================================================================
-- v19.45 · PUNTOS DE EXPRESO: cuántos son y cuánto m³/mes le dejamos a cada uno
-- Pedido de Luis, 2026-09-17: "Mirá el histórico de pedidos y hacé un mapa de
-- calor, con eso determiná los puntos de expreso (mandamos mercadería y ellos
-- se encargan de mandársela al cliente). Decime cuántos son y cuánta mercadería
-- le mandamos a cada uno por mes en promedio en m³."
--
-- NO CREA NINGÚN OBJETO. Es la medición, dejada escrita para poder repetirla.
-- Entregable: Expresos-mapa-y-volumen.pdf (6 páginas).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) LA FUENTE: gv_ppp_entregados_meta, 2026-01-02 → 2026-09-17 (8,6 meses)
-- ----------------------------------------------------------------------------
-- Es la única tabla con histórico LARGO de entregas + m³ + cliente. Las tres
-- tablas de programación (GV_PPP_Programacion_Diaria, PPP_Web_Programacion) son
-- AMNÉSICAS: sólo tienen lo que está en curso (133 y 166 filas al 17/09).
-- Facturacion_NP arranca el 2026-05-27, o sea 3,7 meses contra 8,6.
--
--   mes     | entregas | m³
--   2026-01 |   306    | 113,8
--   2026-02 |   317    | 118,9
--   2026-03 |   311    | 109,9
--   2026-04 |   290    | 103,4
--   2026-05 |   448    | 158,9
--   2026-06 |   322    | 106,9
--   2026-07 |   307    | 106,9
--   2026-08 |   394    | 126,5
--   2026-09 |   180    |  69,4  (hasta el 17)
select left(btrim(fecha_entrega),7) mes, count(*) n, round(sum(m3)::numeric,1) m3
  from public.gv_ppp_entregados_meta group by 1 order by 1;

-- ----------------------------------------------------------------------------
-- 1) EL CORTE: domicilio / expreso / retira
-- ----------------------------------------------------------------------------
-- ⚠ gv_ppp_entregados_meta NO tiene columna empresa: sale de la NP con
--   gv_emp_de_np(np). Y la clave del cliente es (empresa, cod), nunca cod solo.
-- ⚠ "Virgilio 2788" cargado como dir_expreso es el DEPÓSITO, o sea retira. Hay
--   filas con esa dirección y zona_expreso 'Longchamps' (35,5 m³ en 25 entregas)
--   que el filtro por zona no caza. Se excluyen por la dirección.
--
--   clase     | entregas |   m³   |  %
--   domicilio |   1.349  | 584,5  | 58 %
--   EXPRESO   |   1.204  | 330,4  | 33 %
--   retira    |     311  |  80,9  |  8 %
with ent as (
  select public.gv_emp_de_np(e.np) emp, btrim(e.cod) cod, e.m3::numeric m3
    from public.gv_ppp_entregados_meta e
   where btrim(coalesce(e.fecha_entrega,'')) ~ '^\d{4}-\d{2}-\d{2}'
     and e.m3 is not null and btrim(coalesce(e.cod,'')) <> ''
), cls as (
  select empresa, btrim(cod) cod,
         bool_or(nullif(btrim(dir_expreso),'') is not null
                 and coalesce(zona_expreso,'') !~* 'retir'
                 and btrim(dir_expreso) !~* 'virgilio *2788') via_exp,
         bool_or(coalesce(zona_expreso,'') ~* 'retir'
                 or btrim(coalesce(dir_expreso,'')) ~* 'virgilio *2788') retira
    from public."GV_Clientes_Direcciones" group by 1,2
)
select case when coalesce(c.via_exp,false) then 'expreso'
            when c.retira then 'retira' else 'domicilio' end clase,
       count(*) n, round(sum(ent.m3),1) m3
  from ent left join cls c on c.empresa=ent.emp and c.cod=ent.cod
 group by 1 order by 3 desc;

-- ----------------------------------------------------------------------------
-- 2) LAS PUERTAS: agrupar por DIRECCIÓN, no por nombre de expreso
-- ----------------------------------------------------------------------------
-- El camión para en una PUERTA. En Pergamino 3751 conviven 24 empresas de
-- transporte distintas y es UNA sola parada — contar expresos por nombre da 182
-- y engaña. La clave es (primera palabra ≥3 letras que NO sea genérica) + altura:
--   "AV.PINEDO 50 GALPON 4"            -> PINEDO 50
--   "Av. Suarez esq Pinedo,Galpon 5"   -> SUAREZ  (GALPON/NAVE/BOX/MOD se saltean)
--   "BERON DE ASTRADA 2791"            -> BERON 2791
-- y después se fusionan las grafías con similitud ≥ 0,80 dentro de la MISMA
-- altura, que es lo que junta los typos del padrón:
--   "PEDRO BALLINA 4060" = "PEDRO BALIÑA 4060"   (30,4 m³, si no salían partidos)
--   "PERGAMINO 3751"     = "PEGAMINO 3751"
--   "PINEDO 50"          = "PINEDOS 50"
-- 164 grafías -> 124 puertas. (El clustering se corrió en Python con difflib;
-- esta consulta devuelve las grafías crudas para reproducirlo.)
with ent as (
  select public.gv_emp_de_np(e.np) emp, btrim(e.cod) cod, e.m3::numeric m3,
         left(btrim(e.fecha_entrega),7) mes
    from public.gv_ppp_entregados_meta e
   where btrim(coalesce(e.fecha_entrega,'')) ~ '^\d{4}-\d{2}-\d{2}'
     and e.m3 is not null and btrim(coalesce(e.cod,'')) <> ''
), mapa as (
  select empresa, btrim(cod) cod,
         (array_agg(btrim(dir_expreso)      order by slot))[1] dir,
         (array_agg(btrim(coalesce(nombre_expreso,'?')) order by slot))[1] nom,
         (array_agg(btrim(coalesce(zona_expreso,''))    order by slot))[1] zona
    from public."GV_Clientes_Direcciones"
   where nullif(btrim(dir_expreso),'') is not null
     and coalesce(zona_expreso,'') !~* 'retir'
     and btrim(dir_expreso) !~* 'virgilio *2788'
   group by 1,2
)
select m.dir, m.zona, count(distinct m.nom) expresos, count(distinct ent.cod) clientes,
       count(*) entregas, round(sum(ent.m3),2) m3, round(sum(ent.m3)/8.6,3) m3_mes,
       count(distinct ent.mes) meses_activo
  from ent join mapa m on m.empresa=ent.emp and m.cod=ent.cod
 group by 1,2 order by m3 desc;

-- ----------------------------------------------------------------------------
-- 3) LO QUE DIO (8,6 meses)
-- ----------------------------------------------------------------------------
--   124 puertas de expreso distintas · 330,4 m³ · 38,41 m³/mes · 1.204 entregas
--   = 1,83 m³ por día hábil, el 30 % de UN camión de 6 m³
--
--   9 puertas hacen el 50 % del volumen · 36 puertas hacen el 80 %
--   35 puertas son recurrentes (activas ≥5 de 9 meses) y explican el 73 %
--   24 puertas recibieron 1 o 2 veces en 8,6 meses y suman 0,63 m³/mes
--
--   LAS 10 PRIMERAS
--   #  puerta                          barrio            m³/mes  ent/mes  exp  cli
--   1  PERGAMINO 3751                  Soldati            5,79    20,4     24   48
--   2  PEDRO BALLINA 4060              Pompeya            3,53     2,4      3    4
--   3  AUSTRALIA 2959                  Barracas           2,75     3,4      1    1
--   4  PERGAMINO 3702                  Soldati            2,10     4,7      1    2
--   5  SAN PEDRITO 3442                Soldati            1,41     2,0      2    3
--   6  ESTANISLAO ZEBALLOS 333         Avellaneda         1,14     4,0      2   10
--   7  PINEDO 50 (galpón 3/4)          Barracas           0,96     4,1      6    9
--   8  FERRE 1455                      Pompeya            0,83     2,0      1    6
--   9  AVALOS 188                      Paternal           0,78     2,2      1    1
--  10  FERRE 2499                      Soldati            0,71     1,6      1    1
--
--   POR BARRIO DE GALPÓN          m³/mes    %     puertas   km al depósito
--   Soldati                        18,50   48,2 %    57          9,7
--   Barracas                        7,56   19,7 %    16         15,1
--   Pompeya                         7,45   19,4 %    28         10,9
--   Parque Patricios                1,36    3,5 %     9         11,6
--   Avellaneda                      1,14    3,0 %     1          s/d
--   Paternal                        1,10    2,9 %     3          5,7
--   (los otros 9 barrios)           1,30    3,3 %    10
--
--   ⇒ 91 % del expreso cae en Soldati + Pompeya + Barracas + P. Patricios,
--     cuatro barrios contiguos, 6,9 km de punta a punta.

-- ----------------------------------------------------------------------------
-- 4) EL MAPA: por qué es a nivel BARRIO y no de puerta
-- ----------------------------------------------------------------------------
-- Las direcciones de galpón NO están geocodificadas: 0 de 272 en PPP_Geo y 1 en
-- GV_Geo_Cliente. gv_ppp_web_punto() las resuelve por su rama (4), el promedio
-- de los clientes de ese barrio — que es también lo que usa gv_ancla_paradas,
-- o sea que la simulación de anclas ya trataba al expreso así.
select count(*) dirs,
       count(*) filter (where exists (select 1 from public."PPP_Geo" p
                                       where lower(btrim(p.direccion))=lower(d.dir) and p.lat is not null)) en_ppp_geo,
       count(*) filter (where exists (select 1 from public."GV_Geo_Cliente" g
                                       where lower(btrim(g.direccion))=lower(d.dir) and g.lat is not null)) en_geo_cliente
  from (select distinct btrim(dir_expreso) dir from public."GV_Clientes_Direcciones"
         where nullif(btrim(dir_expreso),'') is not null
           and coalesce(zona_expreso,'') !~* 'retir') d;
-- 272 · 0 · 1

-- ⚠ Y el centroide de un barrio con POCOS clientes geocodificados MIENTE.
--   Avellaneda sale de n=2 y cae en (-34,7243 / -58,2520), unos 12 km al sur
--   de donde está Estanislao Zeballos 333. Por eso no se dibujó en el mapa.
--   Antes de usar un centroide de barrio, mirar el n:
select public._norm_barrio(zona_expreso) barrio, count(*) n,
       round(avg(g.lat)::numeric,5) lat, round(avg(g.lng)::numeric,5) lng
  from public."GV_Clientes_Direcciones" d
  join public."GV_Geo_Cliente" g on public._norm_barrio(g.barrio) = public._norm_barrio(d.zona_expreso)
 where nullif(btrim(d.dir_expreso),'') is not null and g.lat is not null
 group by 1 having count(*) >= 5 order by 2 desc;

-- ----------------------------------------------------------------------------
-- 5) PARA QUÉ SIRVE ESTO EN EL MODELO DE ANCLAS
-- ----------------------------------------------------------------------------
-- El expreso es un tercio del m³ que sale del depósito y está concentrado en un
-- racimo de 7 km: 1,83 m³/día hábil dentro de ese racimo. Hoy esas paradas
-- viajan repartidas entre los camiones de reparto común. En el modelo de anclas
-- las 35 puertas recurrentes son candidatas naturales a parada fija —tienen
-- dirección estable y no dependen de dónde viva el cliente— y las 9 primeras
-- concentran la mitad del volumen. Queda como pregunta para Luis, no como
-- cambio: si el expreso merece su propio ancla diaria al sur.
