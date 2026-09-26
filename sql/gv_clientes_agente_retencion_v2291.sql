-- v22.91 · agentes de recaudación (Thomas, 26/09: "sí"): el cliente que retiene no paga de menos, deja un
-- certificado. Se cruza por CUIT (regla v13.76). Fuente: padrón AGIP de agentes de recaudación IIBB CABA (oct 2023).
-- ARBA no publica nómina; ganancias (RG 830) tampoco. Torres y Liva (Mar del Plata, retiene 2,2 %) no figura: se agrega
-- a mano como 'iibb_arba' si Thomas lo confirma. (SUPERIMPERIO venía repetido en el padrón: una sola fila.)
-- a mano como 'iibb_arba' si Thomas lo confirma.
create table if not exists public."GV_Clientes_Agente_Retencion" (
  cuit text primary key, nombre text, regimen text not null, fuente text, desde date, creado_en timestamptz default now());
alter table public."GV_Clientes_Agente_Retencion" enable row level security;
drop policy if exists sup_lee on public."GV_Clientes_Agente_Retencion";
create policy sup_lee on public."GV_Clientes_Agente_Retencion" for select to authenticated using (public.es_supervisor_virgilio());
revoke all on public."GV_Clientes_Agente_Retencion" from anon;
revoke insert, update, delete, truncate on public."GV_Clientes_Agente_Retencion" from authenticated;
grant select on public."GV_Clientes_Agente_Retencion" to authenticated;
insert into public."GV_Clientes_Agente_Retencion" (cuit, nombre, regimen, fuente, desde) values
('30590360763','CENCOSUD SA','iibb_caba','AGIP padrón oct-2023',date '2001-05-01'),
('30548083156','COTO CENTRO INTEGRAL DE COMERCIALIZACION SA','iibb_caba','AGIP padrón oct-2023',date '2001-05-01'),
('30687310434','INC SA','iibb_caba','AGIP padrón oct-2023',date '2001-05-01'),
('30506730038','S.A. IMPORTADORA Y EXPORTADORA DE LA PATAGONIA','iibb_caba','AGIP padrón oct-2023',date '2001-09-01'),
('30678138300','DORINKA SRL','iibb_caba','AGIP padrón oct-2023',date '2001-05-01'),
('30710587619','BAZAR Y CIA  SA','iibb_caba','AGIP padrón oct-2023',date '2020-01-01'),
('33526497169','M SANCHEZ Y CIA SRL','iibb_caba','AGIP padrón oct-2023',date '2020-01-01'),
('30665558300','EXTRALIMP SA','iibb_caba','AGIP padrón oct-2023',date '2016-11-01'),
('30607371799','AUTOSERVICIO MAYORISTA  DIARCO  SA','iibb_caba','AGIP padrón oct-2023',date '2008-11-01'),
('30627435033','MATIZ SA','iibb_caba','AGIP padrón oct-2023',date '2012-04-01'),
('30691637596','ORIENTAL PARTY SRL','iibb_caba','AGIP padrón oct-2023',date '2016-11-01'),
('30708595418','RAYABO SA','iibb_caba','AGIP padrón oct-2023',date '2009-10-01'),
('30708356111','DISTRIBAZ SA','iibb_caba','AGIP padrón oct-2023',date '2020-01-01'),
('30583747792','SUPERIMPERIO S A','iibb_caba','AGIP padrón oct-2023',date '2016-11-01'),
('30681823154','ANDSER QUIMICA SRL','iibb_caba','AGIP padrón oct-2023',date '2016-11-01'),
('30715209833','GIFEL S.R.L.','iibb_caba','AGIP padrón oct-2023',date '2023-01-01'),
('30623258374','GASTROBAIRES SA','iibb_caba','AGIP padrón oct-2023',date '2020-01-01'),
('30540487711','SIMON ZEITUNE E HIJOS.A.I.C.','iibb_caba','AGIP padrón oct-2023',date '2001-05-01')
on conflict (cuit) do nothing;
