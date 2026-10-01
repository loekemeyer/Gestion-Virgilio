-- v26.03 (Luis, 01/10, D21-D23): STOCK CONVERTIBLE de Virgilio que cuenta para el cálculo de importaciones.
-- Luis: "SUMA PARA EL CALCULO DE SI TENGO QUE COMPRARLE A LOS CHINOS O NO. es stock que se puede convertir
-- en ese codigo así que, si tengo de eso, no tengo que salir corriendo a comprar".
--   702E <> 102E de LK + 702 de LK (+ GP2 702, 702E, 102E)
--   106E <> 723 de Chef          (+ GP2 723, 106E)
--   522ES <> insumo 522ES (depósito insumos de Virgilio)
-- Cuenta el DISPONIBLE del código de origen (bruto − pedido, piso 0) × su UxB, en unidades. Puede contar
-- también en la fila propia del código de origen (102E): a propósito, igual que GRJ31 (D13).
-- Rollback: drop la lateral 'conv' de gv_importados_ordenes (re-aplicar la def. anterior, backup en
-- zz_backups."GV_Backup_ImpOrdenes_def_20261001") y drop table public."GV_Importados_Equiv_Virgilio".

create table if not exists public."GV_Importados_Equiv_Virgilio" (
  importado_cod text not null,
  cod_art       text not null,                 -- código de stock de Virgilio (sin sufijo)
  empresa       text not null check (empresa in ('LK','CH')),
  factor        numeric not null default 1 check (factor > 0 and factor <= 1),
  nota          text,
  creado_por    text,
  creado_en     timestamptz not null default now(),
  primary key (importado_cod, cod_art, empresa)
);
alter table public."GV_Importados_Equiv_Virgilio" enable row level security;
-- (escritura: RLS sin policy de insert/update/delete = sólo service_role)
grant select on public."GV_Importados_Equiv_Virgilio" to anon, authenticated;
create policy gv_imp_equiv_vir_sel on public."GV_Importados_Equiv_Virgilio" for select to anon, authenticated using (true);

insert into public."GV_Importados_Equiv_Virgilio"(importado_cod, cod_art, empresa, factor, nota, creado_por) values
 ('702E','102E','LK',1,'Luis 01/10: se convierte en 702E','Luis'),
 ('702E','702', 'LK',1,'Luis 01/10: se convierte en 702E','Luis'),
 ('106E','723', 'CH',1,'Luis 01/10: se convierte en 106E','Luis')
on conflict do nothing;

insert into public."GV_Importados_Insumo_Map"(insumo_cod, importado_cod, nota) values
 ('522ES','522ES','Luis 01/10: el insumo 522ES (suelto) cuenta para el importado 522ES; sigue contando también para el 522E')
on conflict do nothing;

insert into public."GV_Importados_Equiv_GP2"(importado_cod, componente_codigo, factor, nota, creado_por) values
 ('702E','702',1,'Luis 01/10','Luis'),('702E','702E',1,'Luis 01/10','Luis'),('702E','102E',1,'Luis 01/10','Luis'),
 ('106E','723',1,'Luis 01/10','Luis'),('106E','106E',1,'Luis 01/10','Luis')
on conflict do nothing;

-- la vista: parche sobre la definición VIVA, idempotente, raise si el texto no matchea.
-- REGLA_CONFIRMADA_POR_USUARIO (Luis 01/10: "quiero que esté la conexión")
do $p$
declare d text; n text;
begin
  d := pg_get_viewdef('public.gv_importados_ordenes'::regclass, true);
  if d like '%v26.03-conv%' or d like '%stock_conv%' then raise notice 'ya aplicado'; return; end if;
  n := replace(d, '), stk AS (',
'), conv AS (
         SELECT upper(x.imp) AS imp,
            sum(GREATEST(x.b - x.p, 0::numeric) * COALESCE(gq.u, 1::numeric) * x.factor) AS stock_conv
           FROM ( SELECT e3.importado_cod AS imp, e3.cod_art, e3.empresa, e3.factor,
                    COALESCE(sum(d3.cajas_bruto), 0::numeric) AS b   -- el stock de un código no dual viene como MIXTO (102E),
                    COALESCE(sum(d3.cajas_pedidas), 0::numeric) AS p
                   FROM "GV_Importados_Equiv_Virgilio" e3
                     LEFT JOIN gv_importados_stock_dep d3 ON d3.cod_norm = gv_cod_stock(e3.cod_art) AND (d3.empresa = ANY (ARRAY[e3.empresa, ''MIXTO''::text]))
                  GROUP BY e3.importado_cod, e3.cod_art, e3.empresa, e3.factor) x
             LEFT JOIN gux gq ON gq.emp = x.empresa AND gq.c = gv_cod_stock(x.cod_art)
          GROUP BY (upper(x.imp))
        ), stk AS (');
  if n = d then raise exception 'v26.03-conv: no matchea "), stk AS ("'; end if;
  d := n;
  n := replace(d, 'END + COALESCE(g2.stock_gp2, 0::numeric) AS stock_total_neto',
                  'END + COALESCE(g2.stock_gp2, 0::numeric) + COALESCE(cv.stock_conv, 0::numeric) AS stock_total_neto,
    COALESCE(cv.stock_conv, 0::numeric) AS stock_conv');
  if n = d then raise exception 'v26.03-conv: no matchea stock_total_neto'; end if;
  d := n;
  n := replace(d, ') g2 ON true;', ') g2 ON true
     LEFT JOIN conv cv ON cv.imp = upper(i.cod_art) AND i.principal AND i.activo;');
  if n = d then raise exception 'v26.03-conv: no matchea g2 ON true'; end if;
  execute 'create or replace view public.gv_importados_ordenes as ' || n;
  execute 'alter view public.gv_importados_ordenes set (security_invoker = true)';
end $p$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_importados_ordenes','vista','GV_Importados_Equiv_Virgilio',
        'el stock convertible de Virgilio (102E/702 LK → 702E, 723 CH → 106E) suma al stock_total_neto de importación',
        'Luis','v26.01');  -- así quedó cargado en la base

-- Medido al aplicar (01/10): 702E +480 u (40 cj de 102E LK) · 106E +792 u (66 cj disponibles de 723 CH) ·
-- 522ES 0 → 2.000 u (insumo). Como anon: 156 filas, 195 ms (antes 204 ms).
