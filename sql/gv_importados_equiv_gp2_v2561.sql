-- v25.61 (Luis, 01/10/2026): EQUIVALENCIAS importado <-> componente GP2 + stock NEGATIVO en importacion.
-- "para elaborar ciertos articulos importamos partes ... tenemos que considerar partes que tenemos en
--  stock (insumo) que se van a registrar en GP2". Unidad por unidad; cuenta TODO el stock GP2 del
--  componente (sector + talleristas + PS) y se SUMA al deposito de insumos de Virgilio.
-- D12: "si tenemos mas unidades comprometidas de lo que hay en stock, stock negativo para usos
--  practicos de importacion, claro que si" -> columna nueva stock_total_neto SIN el greatest(…,0).
-- stock_total / stock_actual / stock_cajas NO se tocan (los leen otros lectores).
-- Rollback: create or replace con la definicion anterior (zz_backups."GV_Backup_ImpOrdenes_def_20261001")
--           + drop table public."GV_Importados_Equiv_GP2".

create table if not exists public."GV_Importados_Equiv_GP2" (
  importado_cod     text    not null,
  componente_codigo text    not null,   -- GP2.componente.codigo
  factor            numeric not null check (factor > 0 and factor <= 1),
  nota              text,
  creado_por        text,
  creado_en         timestamptz not null default now(),
  primary key (importado_cod, componente_codigo)
);
alter table public."GV_Importados_Equiv_GP2" enable row level security;
revoke insert, update, delete, truncate on public."GV_Importados_Equiv_GP2" from anon, authenticated;
grant select on public."GV_Importados_Equiv_GP2" to anon, authenticated;
drop policy if exists gv_imp_equiv_gp2_sel on public."GV_Importados_Equiv_GP2";
create policy gv_imp_equiv_gp2_sel on public."GV_Importados_Equiv_GP2" for select to anon, authenticated using (true);

insert into public."GV_Importados_Equiv_GP2" (importado_cod, componente_codigo, factor, nota, creado_por) values
 ('587C',   'Z23B',  1,   'Cuchilla Laser',               'Luis'),
 ('505C',   'Z23A',  1,   'Cuch China',                   'Luis'),
 ('1546903','C13',   1,   'Corta Queso Bastidor c/Cil.',  'Luis'),
 ('523C',   'E13',   1,   'Cremallera',                   'Luis'),
 ('1000900','D1',    1,   'Espiral Sacacorcho',           'Luis'),
 ('323ES',  'GRJ31', 1,   'Ralladores: 100% al 323ES',    'Luis'),
 ('323E',   'GRJ31', 0.2, 'Ralladores: 20% al 323E',      'Luis'),
 ('838E',   'GRJ31', 0.8, 'Ralladores: 80% al 838E',      'Luis')
on conflict do nothing;

-- la vista: se parchea sobre la definicion VIVA, idempotente, raise si el texto no matchea.
do $p$
declare d text; n text;
begin
  d := pg_get_viewdef('public.gv_importados_ordenes'::regclass, true);
  if d ~ 'stock_total_neto' then raise notice 'ya aplicado'; return; end if;
  n := replace(d,
   'END AS stock_total' || chr(10) || '   FROM "Importados" i',
   'END AS stock_total,' || chr(10) ||
   '    COALESCE(g2.stock_gp2, 0::numeric) AS stock_gp2,' || chr(10) ||
   '        CASE' || chr(10) ||
   '            WHEN pt.cod IS NOT NULL AND si.cod IS NOT NULL THEN si.stock_uni' || chr(10) ||
   '            ELSE round((COALESCE(st.cajas_bruto, 0::numeric) - COALESCE(st.cajas_pedidas, 0::numeric)) * COALESCE(gx.u, i.uni_x_caja, 0::numeric)) + COALESCE(si.stock_uni, 0::numeric)' || chr(10) ||
   '        END + COALESCE(g2.stock_gp2, 0::numeric) AS stock_total_neto' || chr(10) ||
   '   FROM "Importados" i');
  if n = d then raise exception 'gv_importados_ordenes: no matcheo el final de columnas'; end if;
  n := regexp_replace(n, ';\s*$', '');
  n := n || chr(10) || '     LEFT JOIN LATERAL ( SELECT sum(sc.cantidad * e.factor) AS stock_gp2' || chr(10) ||
            '           FROM "GV_Importados_Equiv_GP2" e' || chr(10) ||
            '             JOIN gv_gp2_stock_componente sc ON upper(sc.codigo) = upper(e.componente_codigo)' || chr(10) ||
            '          WHERE upper(e.importado_cod) = upper(i.cod_art) AND i.principal AND i.activo) g2 ON true';
  execute 'create or replace view public.gv_importados_ordenes with (security_invoker = true) as ' || n;
end $p$;
alter view public.gv_importados_ordenes set (security_invoker = true);

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_importados_ordenes','vista','GV_Importados_Equiv_GP2',
        'el stock de importados suma el stock GP2 del componente equivalente (x factor)','Luis','v25.61'),
       ('gv_importados_ordenes','vista','stock_total_neto',
        'stock de importacion sin piso en 0: lo comprometido de mas da stock negativo','Luis','v25.61');

-- v26.00 (Luis, 01/10, D19): más equivalencias. Varias no existen TODAVÍA en GP2: el cruce es por
-- upper(código), así que cuentan solas el día que GP2 las cree (hasta ahí suman 0). Factor 1 c/u, se suman.
insert into public."GV_Importados_Equiv_GP2"(importado_cod, componente_codigo, factor, nota, creado_por) values
('942E','Z47',1,'Luis 01/10','Luis'),('942E','Z47-M505D',1,'Luis 01/10','Luis'),('942E','942E',1,'Luis 01/10','Luis'),
('943E','Z44',1,'Luis 01/10','Luis'),('943E','Z44-M505C',1,'Luis 01/10','Luis'),('943E','943E',1,'Luis 01/10','Luis'),
('944E','Z48',1,'Luis 01/10','Luis'),('944E','Z48-M505',1,'Luis 01/10','Luis'),('944E','944E',1,'Luis 01/10','Luis'),
('945E','Z49',1,'Luis 01/10','Luis'),('945E','Z49-M505F',1,'Luis 01/10','Luis'),('945E','945E',1,'Luis 01/10','Luis'),
('948E','Z45',1,'Luis 01/10','Luis'),('948E','Z45-M505B',1,'Luis 01/10','Luis'),('948E','948E',1,'Luis 01/10','Luis'),
('522ES','GRJ33',1,'Luis 01/10','Luis')
on conflict do nothing;
