-- v25.13 (Thomas, 30/09/2026): PDF para Damián agrupado por TIPO DE PRODUCTO, con INAL, y la
-- «Autorización de Impo» (ex libre circulación) al 0,7 % sobre el FOB de lo que lleva INAL.
--
-- Fuentes (los dos Excel que mandó Thomas, cargados tal cual):
--   equivalencias_LK_Chef_UxB_stock.xlsx  → GV_Producto_Tipo  (209 productos, 321 códigos LK/CH/Loke)
--   articulos-certificados-2026-09-30.xlsx → GV_Articulo_INAL (92 certificados + Loke 111/112, D6)
-- Y: Importados_Config.autoriz_impo_pct (0,007), expuesta en gv_imp_nac_config y editable por
-- gv_imp_nac_config_guardar (⚙ Generales).
--
-- La vista gv_imp_articulo_extra resuelve, por cada fila de Importados (cod_art + marca), su tipo de
-- producto y si lleva INAL. El código se compara sin ceros a la izquierda y sin la L de ruteo
-- (437EL = 437E de LK). Un certificado sin «tomado de» cuyo código es el número pelado (260) vale
-- para el importado con E (260E).
--
-- Rollback:
--   drop view if exists public.gv_imp_articulo_extra;
--   drop table if exists public."GV_Articulo_INAL";
--   drop table if exists public."GV_Producto_Tipo";
--   (la columna autoriz_impo_pct puede quedar: el front cae a 0,007 si no viene)

begin;

create table if not exists public."GV_Producto_Tipo" (
  marca     text not null check (marca in ('LK','CH','LOKE')),
  cod       text not null,
  tipo      text not null,
  familia   text,
  fila      int,
  cargado_en timestamptz not null default now(),
  primary key (marca, cod)
);
alter table public."GV_Producto_Tipo" enable row level security;
drop policy if exists gv_producto_tipo_sel on public."GV_Producto_Tipo";
create policy gv_producto_tipo_sel on public."GV_Producto_Tipo" for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public."GV_Producto_Tipo" from anon, authenticated;

insert into public."GV_Producto_Tipo" (marca, cod, tipo, familia, fila) values
  ('LK','501','Abrelatas a manija','Abrelatas',2),
  ('CH','701','Abrelatas a manija','Abrelatas',2),
  ('LOKE','101','Abrelatas a manija','Abrelatas',2),
  ('LK','502','Abrelatas mariposa','Abrelatas',3),
  ('CH','702E','Abrelatas mariposa','Abrelatas',3),
  ('LOKE','102E','Abrelatas mariposa','Abrelatas',3),
  ('LK','503E','Abrelatas doble engranaje','Abrelatas',4),
  ('LK','506','Abrelatas uña','Abrelatas',5),
  ('CH','706','Abrelatas uña','Abrelatas',5),
  ('LK','511','Abrelatas uña 3 en 1','Abrelatas',6),
  ('CH','043','Abrelatas uña 3 en 1','Abrelatas',6),
  ('LK','510','Abrelata Uña Inox','Abrelatas',7),
  ('LOKE','103','Abrelata Uña Inox','Abrelatas',7),
  ('LK','066','Abrelatas Super Mariposa','Abrelatas',8),
  ('LK','512','Abrelatas Mariposa Capuchon Rojo','Abrelatas',9),
  ('LK','500','Abrelata Uña Pie Color','Abrelatas',10),
  ('LK','513','Pelador mango metálico','Peladores',11),
  ('CH','713','Pelador mango metálico','Peladores',11),
  ('LOKE','108','Pelador mango metálico','Peladores',11),
  ('LK','505','Pelador mango plástico','Peladores',12),
  ('LOKE','123','Pelador mango plástico','Peladores',12),
  ('LK','589E','Pelador mango acrílico / plástico económico','Peladores',13),
  ('CH','712E','Pelador mango acrílico / plástico económico','Peladores',13),
  ('LK','586','Pelapapas mango ergonómico','Peladores',14),
  ('CH','099','Pelapapas mango ergonómico','Peladores',14),
  ('LOKE','186','Pelapapas mango ergonómico','Peladores',14),
  ('LK','598E','Pelador negro dentado','Peladores',15),
  ('CH','798E','Pelador negro dentado','Peladores',15),
  ('LOKE','198E','Pelador negro dentado','Peladores',15),
  ('LK','587','Pelador Metálico Corte Laser','Peladores',16),
  ('LK','599E','Pelador Madera Multifunción','Peladores',17),
  ('LK','816E','Pelador V Con Mgo Ergonómico','Peladores',18),
  ('LK','569','Pelanaranjas x 1 Display','Peladores',19),
  ('LK','523','Sacacorcho doble aleta','Sacacorchos',20),
  ('CH','723','Sacacorcho doble aleta','Sacacorchos',20),
  ('LK','585E','Sacacorcho doble aleta fundición','Sacacorchos',21),
  ('CH','729E','Sacacorcho doble aleta fundición','Sacacorchos',21),
  ('LK','529E','Sacacorcho doble impulso acero','Sacacorchos',22),
  ('CH','727E','Sacacorcho doble impulso acero','Sacacorchos',22),
  ('LOKE','106E','Sacacorcho doble impulso acero','Sacacorchos',22),
  ('LK','067','Sacacorcho Zincado','Sacacorchos',23),
  ('LOKE','109','Sacacorcho Zincado','Sacacorchos',23),
  ('LK','525E','Sacacorcho cabo de madera','Sacacorchos',24),
  ('CH','725E','Sacacorcho cabo de madera','Sacacorchos',24),
  ('LK','530','Sacacorcho tipo mozo color','Sacacorchos',25),
  ('CH','730','Sacacorcho tipo mozo color','Sacacorchos',25),
  ('LK','531','Sacacorcho combinado color','Sacacorchos',26),
  ('CH','731','Sacacorcho combinado color','Sacacorchos',26),
  ('LK','581','Sacacorcho mango ergonómico','Sacacorchos',27),
  ('CH','735','Sacacorcho mango ergonómico','Sacacorchos',27),
  ('LOKE','104','Sacacorcho mango ergonómico','Sacacorchos',27),
  ('LK','819E','Sacacorcho "Fish"','Sacacorchos',28),
  ('LK','520','Sacacorcho Tipo Mozo Cromado','Sacacorchos',29),
  ('LK','521','Sacacorcho Combinado Cromado','Sacacorchos',30),
  ('LK','540E','Sacacorcho Premium','Sacacorchos',31),
  ('LK','536E','Sacacorcho Full Black','Sacacorchos',32),
  ('LK','539E','Sacacorcho Negro','Sacacorchos',33),
  ('LK','538E','Sacacorcho Azul','Sacacorchos',34),
  ('LK','522E','Sacacorcho Doble Aleta Premium','Sacacorchos',35),
  ('LK','395','Descorazonador de manzana','Cortadores',36),
  ('CH','709','Descorazonador de manzana','Cortadores',36),
  ('LK','537','Pela y pica ajo','Cortadores',37),
  ('LK','559','Corta ravioles mango Loeke','Cortadores',38),
  ('CH','859','Corta ravioles mango Loeke','Cortadores',38),
  ('LK','564','Corta pizza 8 cm *','Cortadores',39),
  ('CH','863','Corta pizza 8 cm *','Cortadores',39),
  ('LK','811E','Corta pizza mango ergonómico 9 cm','Cortadores',40),
  ('LK','574E','Corta queso blandos mango alambre','Cortadores',41),
  ('CH','809E','Corta queso blandos mango alambre','Cortadores',41),
  ('LOKE','119E','Corta queso blandos mango alambre','Cortadores',41),
  ('LK','546','Corta Queso Blandos Mango Loeke','Cortadores',42),
  ('LK','562','Corta Pizza 6cm Mgo Loeke','Cortadores',43),
  ('LOKE','116','Corta Pizza 6cm Mgo Loeke','Cortadores',43),
  ('LK','809E','Corta Pizza Mgo Ergonomico 6cm','Cortadores',44),
  ('CH','877E','Corta Pizza Mgo Ergonomico 6cm','Cortadores',44),
  ('LK','810E','Corta Queso Ac Inox (Semiduro)','Cortadores',45),
  ('LK','812E','Corta Huevo Marco Plástico','Cortadores',46),
  ('LK','567','Corta Palta','Cortadores',47),
  ('CH','862','Corta Pizza Familiar','Cortadores',48),
  ('LK','321','Rallador cilíndrico 21 cm','Ralladores',49),
  ('CH','840','Rallador cilíndrico 21 cm','Ralladores',49),
  ('LOKE','122','Rallador cilíndrico 21 cm','Ralladores',49),
  ('LK','328E','Rallador plano 3 usos acero inox','Ralladores',50),
  ('CH','865E','Rallador plano 3 usos acero inox','Ralladores',50),
  ('LK','360E','Rallador 4 lados','Ralladores',51),
  ('LK','817E','Rallador mango ergonómico','Ralladores',52),
  ('LK','323E','Rallador Mini','Ralladores',53),
  ('CH','838E','Rallador Mini','Ralladores',53),
  ('LK','368E','Rallador Hexagonal Inox 25cm','Ralladores',54),
  ('LK','361E','Rallador 4 lados Ac Inox','Ralladores',55),
  ('LK','363E','Rallador Gourmet Grano Fino','Ralladores',56),
  ('LK','366E','Rallador Cónico Ac Inox','Ralladores',57),
  ('LK','367E','Rallador Hexagonal','Ralladores',58),
  ('LK','870E','Mandolina 3 Grosores','Ralladores',59),
  ('LK','026','Colador Ø 8 cm','Coladores',60),
  ('CH','824','Colador Ø 8 cm','Coladores',60),
  ('LOKE','110','Colador Ø 8 cm','Coladores',60),
  ('LK','027','Colador Ø 10 cm','Coladores',61),
  ('CH','825','Colador Ø 10 cm','Coladores',61),
  ('LOKE','111','Colador Ø 10 cm','Coladores',61),
  ('LK','437E','Colador Ø 16 cm inox','Coladores',62),
  ('CH','437E','Colador Ø 16 cm inox','Coladores',62),
  ('LOKE','112','Colador Ø 16 cm inox','Coladores',62),
  ('LK','438E','Colador Ø 20 cm inox','Coladores',63),
  ('CH','438E','Colador Ø 20 cm inox','Coladores',63),
  ('LOKE','113','Colador Ø 20 cm inox','Coladores',63),
  ('LK','439E','Colador de pasta inox','Coladores',64),
  ('CH','439E','Colador de pasta inox','Coladores',64),
  ('LK','440E','Colador extensible','Coladores',65),
  ('LK','031','Filtro de café 10 cm','Coladores',66),
  ('CH','836','Filtro de café 10 cm','Coladores',66),
  ('LOKE','120','Filtro de café 10 cm','Coladores',66),
  ('LK','034','Filtro de café gastronómico 14 cm','Coladores',67),
  ('CH','867','Filtro de café gastronómico 14 cm','Coladores',67),
  ('LK','260E','Infusor de Te','Coladores',68),
  ('LK','441','Colador de Pasta Plástico','Coladores',69),
  ('LK','035E','Cernidor de Harina','Coladores',70),
  ('LK','504','Afila cuchillos','Afiladores',71),
  ('CH','097','Afila cuchillos','Afiladores',71),
  ('LOKE','114','Afila cuchillos','Afiladores',71),
  ('LK','404E','Afila Cuchillos Premium','Afiladores',72),
  ('LK','332','Espátula calada acero inox','Utensilios',73),
  ('LK','335','Cuchara calada acero inox','Utensilios',74),
  ('LK','337','Pinche / tenedor de carne acero inox','Utensilios',75),
  ('CH','632','Pinche / tenedor de carne acero inox','Utensilios',75),
  ('LK','338','Espátula lisa acero inox','Utensilios',76),
  ('LK','315','Pisa papas acero inox','Utensilios',77),
  ('CH','609','Pisa papas acero inox','Utensilios',77),
  ('LOKE','121','Pisa papas acero inox','Utensilios',77),
  ('LK','394','Espátula lisa nylon 1 pieza','Utensilios',78),
  ('CH','842','Espátula lisa nylon 1 pieza','Utensilios',78),
  ('LK','390','Cuchara calada nylon 1 pieza','Utensilios',79),
  ('CH','843','Cuchara calada nylon 1 pieza','Utensilios',79),
  ('LK','391','Cuchara fideos nylon 1 pieza','Utensilios',80),
  ('CH','844','Cuchara fideos nylon 1 pieza','Utensilios',80),
  ('LK','392','Cucharón nylon 1 pieza','Utensilios',81),
  ('CH','845','Cucharón nylon 1 pieza','Utensilios',81),
  ('LK','393','Espátula calada nylon 1 pieza','Utensilios',82),
  ('CH','846','Espátula calada nylon 1 pieza','Utensilios',82),
  ('LK','355','Pisa papas nylon con mango','Utensilios',83),
  ('CH','789','Pisa papas nylon con mango','Utensilios',83),
  ('LK','570','Pala de canelones','Utensilios',84),
  ('CH','858','Pala de canelones','Utensilios',84),
  ('LK','981E','Espátula Lisa Linea Premium','Utensilios',85),
  ('LK','982E','Cuchara Linea Premium','Utensilios',86),
  ('LK','983E','Cucharón Linea Premium','Utensilios',87),
  ('LK','984E','Cuchara Fideos Linea Premium','Utensilios',88),
  ('LK','985E','Espatula Calada Linea Premium','Utensilios',89),
  ('LK','980E','Tenedor Ensalada Linea Premium','Utensilios',90),
  ('LK','988E','Espumadera Linea Premium','Utensilios',91),
  ('LK','952E','Cuchara Silicona Mgo Bambú','Utensilios',92),
  ('LK','955E','Espátula Silicona Mgo Bambú','Utensilios',93),
  ('LK','953E','Cucharón Silicona Mgo Bambú','Utensilios',94),
  ('LK','951E','Espátula Lisa Silicona Mgo Bambú','Utensilios',95),
  ('LK','954E','Pinza Fideos Silicona Mgo Bambú','Utensilios',96),
  ('LK','956E','Cuchara Calada Silicona Mgo Bambú','Utensilios',97),
  ('LK','957E','Batidor Pera Silicona Mgo Bambú','Utensilios',98),
  ('LK','958E','Pincel Silicona Mgo Bambú','Utensilios',99),
  ('LK','935E','Espátula Calada Nylon Mgo Madera','Utensilios',100),
  ('LK','936E','Espumadera Nylon Mgo Madera','Utensilios',101),
  ('LK','937E','Batidor Pera Nylon Mgo Madera','Utensilios',102),
  ('LK','932E','Cuchara Nylon Mgo Madera','Utensilios',103),
  ('LK','933E','Cucharon Nylon Mgo Madera','Utensilios',104),
  ('LK','934E','Cuchara Fideos Nylon Mgo Mad','Utensilios',105),
  ('LK','931E','Espátula Lisa Nylon Mgo Mad','Utensilios',106),
  ('LK','942E','Cuchara Ac. Inox','Utensilios',107),
  ('CH','633E','Cuchara Ac. Inox','Utensilios',107),
  ('LK','943E','Cucharon Ac. Inox','Utensilios',108),
  ('CH','630E','Cucharon Ac. Inox','Utensilios',108),
  ('LK','944E','Pinza Fideos Ac. Inox','Utensilios',109),
  ('CH','637E','Pinza Fideos Ac. Inox','Utensilios',109),
  ('LK','945E','Espátula Calada Ac. Inox','Utensilios',110),
  ('CH','636E','Espátula Calada Ac. Inox','Utensilios',110),
  ('LK','941E','Espátula Lisa Ac. Inox','Utensilios',111),
  ('CH','635E','Espátula Lisa Ac. Inox','Utensilios',111),
  ('LK','946E','Cuchara Calada Ac. Inox','Utensilios',112),
  ('CH','634E','Cuchara Calada Ac. Inox','Utensilios',112),
  ('LK','948E','Espumadera Ac. Inox','Utensilios',113),
  ('CH','631E','Espumadera Ac. Inox','Utensilios',113),
  ('CH','456','Espátula Lisa Nylon C/ Mango','Utensilios',114),
  ('CH','613','Cuchara Calada 1 Pieza Ac. Inox.','Utensilios',115),
  ('LK','560','Pinza corta alambre 21 cm','Pinzas',116),
  ('CH','800','Pinza corta alambre 21 cm','Pinzas',116),
  ('CH','852','Pinza de hielo 14 cm','Pinzas',117),
  ('LK','594','Pinza de fideos mango plástico 25 cm','Pinzas',118),
  ('CH','055','Pinza de fideos mango plástico 25 cm','Pinzas',118),
  ('LK','595','Pinza de fiambre mango plástico 23 cm','Pinzas',119),
  ('CH','053','Pinza de fiambre mango plástico 23 cm','Pinzas',119),
  ('LK','596','Pinza de ensalada mango plástico 23 cm','Pinzas',120),
  ('CH','054','Pinza de ensalada mango plástico 23 cm','Pinzas',120),
  ('LK','601E','Pinza Acero 30 cm','Pinzas',121),
  ('LK','606E','Pinza 30 cm Ac Inox c/ Silic','Pinzas',122),
  ('LK','607E','Pinza Hielo 15 cm','Pinzas',123),
  ('LK','057','Destapa corona x1','Destapadores',124),
  ('CH','700','Destapa corona x1','Destapadores',124),
  ('LK','499','Llavero Destapador Pie Color','Destapadores',125),
  ('LK','498','Llavero Destapador Pie Cromado','Destapadores',126),
  ('LK','056E','Llavero Destapacorona Económico','Destapadores',127),
  ('LK','514E','Llavero Destapacorona Suelto','Destapadores',128),
  ('LK','516','Destapa Corona x1 Cromado Suelto','Destapadores',129),
  ('LK','579','Tapón vino/cerveza color','Tapon Vino',130),
  ('CH','816','Tapón vino/cerveza color','Tapon Vino',130),
  ('LK','575','Tapón vino/cerveza negro','Tapon Vino',131),
  ('CH','817','Tapón vino/cerveza negro','Tapon Vino',131),
  ('LK','577','Tapón De Vino/Cerveza x1 Prem','Tapon Vino',132),
  ('LK','311','Cuchillo de torta acero inox','Repostería',133),
  ('CH','857','Cuchillo de torta acero inox','Repostería',133),
  ('LK','312','Pala de torta acero inox','Repostería',134),
  ('CH','856','Pala de torta acero inox','Repostería',134),
  ('LK','325','Espátula repostera plástica 1 pieza','Repostería',135),
  ('CH','847','Espátula repostera plástica 1 pieza','Repostería',135),
  ('LK','326','Corta torta plástica 3 usos','Repostería',136),
  ('CH','848','Corta torta plástica 3 usos','Repostería',136),
  ('LK','547','Corta torta','Repostería',137),
  ('CH','818','Corta torta','Repostería',137),
  ('LK','515','Batidor resorte','Repostería',138),
  ('CH','615','Batidor resorte','Repostería',138),
  ('LK','544','Batidor pera alambre','Repostería',139),
  ('CH','802','Batidor pera alambre','Repostería',139),
  ('LOKE','115','Batidor pera alambre','Repostería',139),
  ('LK','590E','Pincel silicona 11','Repostería',140),
  ('CH','890E','Pincel silicona 11','Repostería',140),
  ('LK','590ES','Pincel Silicona 11 Gms Suelto','Repostería',141),
  ('LK','580','Batidor Mini','Repostería',142),
  ('LK','969E','Batidor Silicona','Repostería',143),
  ('LK','970E','Cuchara Silicona','Repostería',144),
  ('LK','971E','Espátula Silicona','Repostería',145),
  ('LK','960E','Pincel Silicona 52 Gms','Repostería',146),
  ('LK','280','Manga Repostera + 4 Boquillas','Repostería',147),
  ('LK','509','Pala Batidora','Repostería',148),
  ('CH','618','Espátula Repostera Goma 24cm','Repostería',149),
  ('CH','619','Espátula Repostera Goma Gastronómica 35cm','Repostería',150),
  ('LK','246','Prensa matambre','Madera',151),
  ('CH','900','Prensa matambre','Madera',151),
  ('LK','223','Cuchara madera 25 cm','Madera',152),
  ('CH','922','Cuchara madera 25 cm','Madera',152),
  ('LK','224','Cuchara madera 30 cm','Madera',153),
  ('CH','911','Cuchara madera 30 cm','Madera',153),
  ('LK','225','Cuchara madera 35 cm','Madera',154),
  ('CH','901','Cuchara madera 35 cm','Madera',154),
  ('LK','220','Cuchara madera 40 cm','Madera',155),
  ('CH','920','Cuchara madera 40 cm','Madera',155),
  ('LK','221','Cuchara madera 45 cm','Madera',156),
  ('CH','902','Cuchara madera 45 cm','Madera',156),
  ('LK','248','Cuchara nylon 33 cm','Madera',157),
  ('CH','908','Cuchara nylon 33 cm','Madera',157),
  ('LK','229','Ñoquera madera','Madera',158),
  ('CH','909','Ñoquera madera','Madera',158),
  ('LK','222','Bate bife madera','Madera',159),
  ('CH','910','Bate bife madera','Madera',159),
  ('LK','231','Palo de amasar 30 cm','Madera',160),
  ('LK','232','Palo de amasar 40 cm','Madera',161),
  ('LK','233','Palo de amasar 50 cm','Madera',162),
  ('LK','208','Cucharita 13cm Azucarera Madera','Madera',163),
  ('LK','207','Ñoquera Madera Mgo Redondo','Madera',164),
  ('LK','234','Palo de Amasar Frances 40 cm','Madera',165),
  ('LK','550','Filtro para bombillas','Mate',166),
  ('CH','760','Filtro para bombillas','Mate',166),
  ('CH','761','Cucharita matera','Mate',167),
  ('LK','557','Bombilla resorte chata','Mate',168),
  ('CH','762','Bombilla resorte chata','Mate',168),
  ('LK','558','Bombilla resorte tradicional','Mate',169),
  ('CH','763','Bombilla resorte tradicional','Mate',169),
  ('LK','555','Cepillo limpia bombilla','Mate',170),
  ('CH','764','Cepillo limpia bombilla','Mate',170),
  ('LK','556','Sacayerba','Mate',171),
  ('LK','573','Bombilla colores metalizados','Mate',172),
  ('CH','755','Bombilla colores metalizados','Mate',172),
  ('LK','658','Bombilla plana ancha metalizada','Mate',173),
  ('CH','758','Bombilla plana ancha metalizada','Mate',173),
  ('LK','659','Bombilla pico de loro inox','Mate',174),
  ('CH','759','Bombilla pico de loro inox','Mate',174),
  ('LK','654','Bombilla autolimpiante inox','Mate',175),
  ('CH','769','Bombilla autolimpiante inox','Mate',175),
  ('LK','255','Mate Inox Térmico','Mate',176),
  ('LK','256','Mate Madera Cerámica','Mate',177),
  ('LK','591','Despolvillador de Yerba','Mate',178),
  ('LK','507','Rompenueces','Accesorios',179),
  ('CH','707','Rompenueces','Accesorios',179),
  ('LK','508','Sacafuentes articulado','Accesorios',180),
  ('CH','708','Sacafuentes articulado','Accesorios',180),
  ('LK','396','Enrulador de manteca','Accesorios',181),
  ('CH','710','Enrulador de manteca','Accesorios',181),
  ('LK','542','Ahueca papas','Accesorios',182),
  ('CH','720','Ahueca papas','Accesorios',182),
  ('LK','543','Ahueca frutas','Accesorios',183),
  ('CH','722','Ahueca frutas','Accesorios',183),
  ('LK','058','Cierra bolsa x2','Accesorios',184),
  ('CH','715','Cierra bolsa x2','Accesorios',184),
  ('LK','534','Cepillo lavavajilla','Accesorios',185),
  ('CH','052','Cepillo lavavajilla','Accesorios',185),
  ('LK','535','Cepillo limpia vaso y mamadera','Accesorios',186),
  ('CH','307','Cepillo limpia vaso y mamadera','Accesorios',186),
  ('LK','532','Cuchara de helado','Accesorios',187),
  ('CH','732','Cuchara de helado','Accesorios',187),
  ('CH','690E','Mariposa agarra fuentes magnética','Accesorios',188),
  ('LK','518','Sacafuente Pizzero','Accesorios',189),
  ('LK','541E','Prensa Ajo','Accesorios',190),
  ('LK','299','Muñeco Silicona Antiderrame','Accesorios',191),
  ('LK','823','Exprimidor De Cítricos','Accesorios',192),
  ('CH','977','Platos Individuales Pizza x6','Accesorios',193),
  ('LK','582E','Salero 90 ml','Vidrio',194),
  ('LK','583E','Especiero Tapa Bamboo','Vidrio',195),
  ('LK','584E','Aceitera 400 ml','Vidrio',196),
  ('LK','566E','Aceitera 100 ml','Vidrio',197),
  ('LK','059','Cuchillo de untar plástico x2','Cuchillos de untar',198),
  ('CH','718','Cuchillo de untar plástico x2','Cuchillos de untar',198),
  ('LK','519','Cuchillo de untar mango madera x2','Cuchillos de untar',199),
  ('CH','719','Cuchillo de untar mango madera x2','Cuchillos de untar',199),
  ('LK','551','Cuchillo de untar mango plástico x2','Cuchillos de untar',200),
  ('CH','878','Cuchillo de untar mango plástico x2','Cuchillos de untar',200),
  ('CH','717','Cuchillo De Untar Acrílico Transp. X4','Cuchillos de untar',201),
  ('LK','071','Bowl Multi Uso 330ml','Contenedores',202),
  ('LK','070','Set Tapers 0.8 Lts / 1.5 Lts / 3 Lts','Contenedores',203),
  ('LK','992E','Batidor Pera Mgo Acacia','Acacia',204),
  ('LK','996E','Corta Pizza 9cm Mgo Acacia','Acacia',205),
  ('LK','990E','Corta Ravioles Mgo Acacia','Acacia',206),
  ('LK','998E','Abrelatas Doble Engranaje Mgo Acacia','Acacia',207),
  ('LK','993E','Pelador V Mgo Acacia','Acacia',208),
  ('LK','997E','Rallador 3 En 1 Mgo Acacia','Acacia',209),
  ('LK','989E','Rallador de Limón Mgo Acacia','Acacia',210)
on conflict (marca, cod) do update set tipo = excluded.tipo, familia = excluded.familia, fila = excluded.fila, cargado_en = now();

create table if not exists public."GV_Articulo_INAL" (
  codigo      text primary key,
  tomado_de   text,
  marca       text,
  descripcion text,
  importador  text,
  elaborador  text,
  certificado text,
  vence       date,
  cargado_en  timestamptz not null default now()
);
alter table public."GV_Articulo_INAL" enable row level security;
drop policy if exists gv_articulo_inal_sel on public."GV_Articulo_INAL";
create policy gv_articulo_inal_sel on public."GV_Articulo_INAL" for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public."GV_Articulo_INAL" from anon, authenticated;

insert into public."GV_Articulo_INAL" (codigo, tomado_de, marca, descripcion, importador, elaborador, certificado, vence) values
  ('260',null,'LK','Infusor de Te','CHEF SRL','YANGJIANG OWNLAND INDUSTRY CO., LIMITED','CE-2024-85280001-APN-DFYC#ANMAT','2029-08-12'),
  ('435','435E','Chef','Colador 10cm','CHEF SRL','ZHEJIANG HONGTAI STAINLESS STEEL PRODUCTS CO,.LTD','CE-2025-02526800-APN-DFYC#ANMAT','2030-01-08'),
  ('436','436E','Chef','Colador 14cm','CHEF SRL','ZHEJIANG HONGTAI STAINLESS STEEL PRODUCTS CO,.LTD','CE-2025-02526800-APN-DFYC#ANMAT','2030-01-08'),
  ('437','437E','Chef','Colador 16cm','CHEF SRL','ZHEJIANG HONGTAI STAINLESS STEEL PRODUCTS CO,.LTD','CE-2025-02526800-APN-DFYC#ANMAT','2030-01-08'),
  ('438','438E','Chef','Colador 20cm','CHEF SRL','ZHEJIANG HONGTAI STAINLESS STEEL PRODUCTS CO,.LTD','CE-2025-02526800-APN-DFYC#ANMAT','2030-01-08'),
  ('439','439E','Chef','Cola Pasta 22cm','CHEF SRL','ZHEJIANG HONGTAI STAINLESS STEEL PRODUCTS CO,.LTD','CE-2025-02526800-APN-DFYC#ANMAT','2030-01-08'),
  ('440','440E','Chef','Colador Extensible','CHEF SRL','ZHEJIANG HONGTAI STAINLESS STEEL PRODUCTS CO,.LTD','CE-2025-02526800-APN-DFYC#ANMAT','2030-01-08'),
  ('601','601E','Loekemeyer','Pinza Silicona 30cm','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO., LTD','CE-2025-35848639-APN-DFYC#ANMAT','2030-04-07'),
  ('602','602E','Loekemeyer','Pinza Silicona 25cm','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO., LTD','CE-2025-35848639-APN-DFYC#ANMAT','2030-04-07'),
  ('921S','921ES','Loekemeyer','Set Silicona y PS','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35844640-APN-DFYC#ANMAT','2030-04-07'),
  ('922S','922SE','Loekemeyer','Set Inox Mango PP','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('923S',null,'Loekemeyer','11 PCS SET','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO., LTD','CE-2025-35847757-APN-DFYC#ANMAT','2030-04-07'),
  ('940','940E','Loekemeyer','Pisa Papas Ac. Inox','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('940P','940E','Loekemeyer','Pisa Papas Ac. Inox','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('941','941E','Loekemeyer','Espatula Lisa','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('941P','941E','Loekemeyer','Espatula Lisa','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('942','942E','Loekemeyer','Cuchara','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('942P','942E','Loekemeyer','Cuchara','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('943','943E','Loekemeyer','Cucharon','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('943P','943E','Loekemeyer','Cucharon','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('944','944E','Loekemeyer','Fideos','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('944P','944E','Loekemeyer','Fideos','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('945','945E','Loekemeyer','Espatula Calada Inox','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('945P','945E','Loekemeyer','Espatula Calada Inox','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('946','946E','Loekemeyer','Cuchara Calada','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('946P','946E','Loekemeyer','Cuchara Calada','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('947','947E','Loekemeyer','Batidor','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('947P','947E','Loekemeyer','Batidor','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('948','948E','Loekemeyer','Espumadera','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('948P','948E','Loekemeyer','Espumadera','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('949','949E','Loekemeyer','Espatula Repostera','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('949P','949E','Loekemeyer','Espatula Repostera','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('950','950E','Loekemeyer','Pisa Papas','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35844640-APN-DFYC#ANMAT','2030-04-07'),
  ('951','951E','Loekemeyer','Espatula Lisa','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35844640-APN-DFYC#ANMAT','2030-04-07'),
  ('952','952E','Loekemeyer','Cuchara','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35844640-APN-DFYC#ANMAT','2030-04-07'),
  ('953','953E','Loekemeyer','Cucharon','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35844640-APN-DFYC#ANMAT','2030-04-07'),
  ('954','954E','Loekemeyer','Fideos','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35844640-APN-DFYC#ANMAT','2030-04-07'),
  ('955','955E','Loekemeyer','Espatula Calada','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35844640-APN-DFYC#ANMAT','2030-04-07'),
  ('956','956E','Loekemeyer','Cuchara Calada','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35844640-APN-DFYC#ANMAT','2030-04-07'),
  ('957','957E','Loekemeyer','Batidor','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35844640-APN-DFYC#ANMAT','2030-04-07'),
  ('958','958E','Loekemeyer','Pincel','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35844640-APN-DFYC#ANMAT','2030-04-07'),
  ('959','959E','Loekemeyer','Espatula Repostera','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35844640-APN-DFYC#ANMAT','2030-04-07'),
  ('960','960E','Loekemeyer','Pincel Silicona 48gms','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO., LTD','CE-2025-35847757-APN-DFYC#ANMAT','2030-04-07'),
  ('967H','967E','Loekemeyer','Mgo Simil Mad','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35848134-APN-DFYC#ANMAT','2030-04-07'),
  ('968','968E','Loekemeyer','Cuchara Plana','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-35844640-APN-DFYC#ANMAT','2030-04-07'),
  ('969','969E','Loekemeyer','Batidor Silicona','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO., LTD','CE-2025-35847757-APN-DFYC#ANMAT','2030-04-07'),
  ('970','970E','Loekemeyer','Cuchara Silicona','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO., LTD','CE-2025-35847757-APN-DFYC#ANMAT','2030-04-07'),
  ('971','971E','Loekemeyer','Espátula Silicona','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO., LTD','CE-2025-35847757-APN-DFYC#ANMAT','2030-04-07'),
  ('603','603E','Loekemeyer','Pinza Acero Cabeza Acero 22cm','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-40190727-APN-DFYC#ANMAT','2030-04-16'),
  ('604','604E','Loekemeyer','Pinza Acero Cabeza Acero 30cm','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-40190727-APN-DFYC#ANMAT','2030-04-16'),
  ('605','605E','Loekemeyer','Pinza Acero Cabeza Acero c/Silicona 22cm','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-40190727-APN-DFYC#ANMAT','2030-04-16'),
  ('606','606E','Loekemeyer','Pinza Acero Cabeza Acero c/Silicona 30cm','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-40190727-APN-DFYC#ANMAT','2030-04-16'),
  ('607','607E','Loekemeyer','Pinza Hielo','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-40190727-APN-DFYC#ANMAT','2030-04-16'),
  ('608','608E','Loekemeyer','Pinza Hielo','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-40190727-APN-DFYC#ANMAT','2030-04-16'),
  ('920S',null,'LK','Set Nylon','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-48062442-APN-DFYC#ANMAT','2030-05-08'),
  ('930','930E','Loekemeyer','Pisa Papas','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-48062442-APN-DFYC#ANMAT','2030-05-08'),
  ('931','931E','Loekemeyer','Espatula Lisa','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-48062442-APN-DFYC#ANMAT','2030-05-08'),
  ('932','932E','Loekemeyer','Cuchara','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-48062442-APN-DFYC#ANMAT','2030-05-08'),
  ('933','933E','Loekemeyer','Cucharon','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-48062442-APN-DFYC#ANMAT','2030-05-08'),
  ('934','934E','Loekemeyer','Fideos','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-48062442-APN-DFYC#ANMAT','2030-05-08'),
  ('935','935E','Loekemeyer','Espatula Calada','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-48062442-APN-DFYC#ANMAT','2030-05-08'),
  ('936','936E','Loekemeyer','Cuchara Calada','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-48062442-APN-DFYC#ANMAT','2030-05-08'),
  ('937','937E','Loekemeyer','Batidor Pera','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-48062442-APN-DFYC#ANMAT','2030-05-08'),
  ('938','938E','Loekemeyer','Espumadera','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-48062442-APN-DFYC#ANMAT','2030-05-08'),
  ('939','939E','Loekemeyer','Espatula  Nylon  Mgo Madera','TIERRA NATIVA S.A.','YANGJIANG JIAHENG INDUSTRIAL CO.,LTD','CE-2025-48062442-APN-DFYC#ANMAT','2030-05-08'),
  ('025E','25','Loekemeyer - Loke - Chef','Colador N°7 Discontinuo','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('026E','026','Loekemeyer - Loke - Chef','Colador Ø 8cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('027E','027','Loekemeyer - Loke - Chef','Colador Ø 10cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('028E','28','Loekemeyer - Loke - Chef','Pisa Papas Ac. Inox Verde','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('090E',null,'Loekemeyer - Loke - Chef',null,'CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('091E',null,'Loekemeyer - Loke - Chef',null,'CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('092E',null,'Loekemeyer - Loke - Chef',null,'CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('093E',null,'Loekemeyer - Loke - Chef',null,'CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('110E','110','Loekemeyer - Loke - Chef','Colador 8cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('111E','111','Loekemeyer - Loke - Chef','Colador 10cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('113E','113','Loekemeyer - Loke - Chef','Colador 20cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('437E',null,'LK','Colador 16cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('437EL',null,'LK','Colador 16cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('438E',null,'LK','Colador 20cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('438EL',null,'LK','Colador 20cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('439E',null,'LK','Cola Pasta 22cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('439EL',null,'LK','Cola Pasta 22cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('440E',null,'LK','Colador Extensible','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('440EL',null,'LK','Colador Extensible','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('442E',null,'Loekemeyer - Loke - Chef','Colador Espumadera 17cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('442EL','442E','Loekemeyer - Loke - Chef','Colador Espumadera 17cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('443E',null,'Loekemeyer - Loke - Chef','Colador Espumadera 20cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('443EL','443E','Loekemeyer - Loke - Chef','Colador Espumadera 20cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('823E','823','Loekemeyer - Loke - Chef','Colador Ø 7cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('824E','824','Loekemeyer - Loke - Chef','Colador Ø 8cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('825E','825','Loekemeyer - Loke - Chef','Colador Ø 10 Cm','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('826E','826','Loekemeyer - Loke - Chef','Colador 13','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  -- D11 (Thomas, 30/09): descripciones del certificado SENASA corregidas según su lista (111E, 442E, 443E, 823E son coladores).
  -- D6/D9 (Thomas, 30/09): el 111 es el «111E» del certificado SENASA (la planilla le puso mal la
  -- descripción: es el Colador 10 cm, no un abrelatas). El 112 y el 035E van en un INAL NUEVO todavía
  -- sin número (tarea de Viviana en Planify, 13/10): llevan INAL con el certificado pendiente.
  ('111',null,'Loekemeyer - Loke - Chef','Ø 8 Colador N10 (Thomas 30/09)','CHEF SRL','ZHEJIANG HONGTAI KITCHENWARE CO,.LTD','CE-2026-80730216-APN-DNIYCA#SENASA','2031-08-21'),
  ('112',null,'Loke','Colador 16 cm Ac. Inox. (Thomas 30/09)',null,null,null,null),
  ('035E',null,'LK','Cernidor Harina Ac. Inox. (INAL nuevo, pendiente)',null,null,null,null)
on conflict (codigo) do update set tomado_de = excluded.tomado_de, marca = excluded.marca, descripcion = excluded.descripcion,
  importador = excluded.importador, elaborador = excluded.elaborador, certificado = excluded.certificado,
  vence = excluded.vence, cargado_en = now();

create or replace view public.gv_imp_articulo_extra with (security_invoker = true) as
with k as (
  select distinct upper(btrim(i.cod_art)) as cod, upper(btrim(i.marca)) as marca
    from public."Importados" i
   where coalesce(btrim(i.cod_art), '') <> ''
), kk as (
  select k.cod, k.marca, ltrim(k.cod, '0') as c0,
         ltrim(regexp_replace(k.cod, '([0-9E])L$', '\1'), '0') as c1
    from k
)
select kk.cod as cod_art, kk.marca,
       t.tipo as tipo_producto, t.familia, t.fila as tipo_fila,
       (n.codigo is not null) as inal, n.certificado as inal_certificado,
       n.vence as inal_vence, n.elaborador as inal_elaborador
  from kk
  left join lateral (
    select t.tipo, t.familia, t.fila from public."GV_Producto_Tipo" t
     where t.marca = kk.marca and ltrim(upper(t.cod), '0') in (kk.c0, kk.c1)
     order by (ltrim(upper(t.cod), '0') = kk.c0) desc limit 1) t on true
  left join lateral (
    select a.codigo, a.certificado, a.vence, a.elaborador from public."GV_Articulo_INAL" a
     where ltrim(upper(a.codigo), '0') in (kk.c0, kk.c1)
        or ltrim(upper(a.tomado_de), '0') in (kk.c0, kk.c1)
        or (a.tomado_de is null and kk.cod ~ '^[0-9]+E$'
            and ltrim(upper(a.codigo), '0') = ltrim(left(kk.cod, length(kk.cod) - 1), '0'))
     order by a.vence desc nulls last limit 1) n on true;
grant select on public.gv_imp_articulo_extra to anon, authenticated;

alter table public."Importados_Config" add column if not exists autoriz_impo_pct numeric;
update public."Importados_Config" set autoriz_impo_pct = 0.007, actualizado = now() where id = 1 and autoriz_impo_pct is null;

-- gv_imp_nac_config: la columna nueva va AL FINAL (create or replace view sólo agrega al final)
-- y se vuelve a poner security_invoker (el create or replace sin WITH lo borraría).
create or replace view public.gv_imp_nac_config with (security_invoker = true) as
 SELECT COALESCE(meses_objetivo, 10::numeric) AS meses_objetivo,
    COALESCE(derechos_pct, 0.18) AS derechos_pct,
    COALESCE(ntl_pct, 0.05) AS ntl_pct,
    COALESCE(iva_pct, 0.21) AS iva_pct,
    COALESCE(iva_adic_pct, 0.20) AS iva_adic_pct,
    COALESCE(gcias_pct, 0.06) AS gcias_pct,
    COALESCE(iibb_pct, 0.0017) AS iibb_pct,
    COALESCE(estad_pct, 0.03) AS estad_pct,
    COALESCE(estad_fob_desde, 6000::numeric) AS estad_fob_desde,
    COALESCE(estad_fob_hasta, 10000::numeric) AS estad_fob_hasta,
    COALESCE(estad_fijo, 180::numeric) AS estad_fijo,
    COALESCE(valor_m3, 110::numeric) AS valor_m3,
    COALESCE(flete_full, 2000::numeric) AS flete_full,
    COALESCE(min_usd, 25000::numeric) AS min_usd,
    actualizado,
    COALESCE(moq, 1000::numeric) AS moq,
    COALESCE(moq_meses_max, 12::numeric) AS moq_meses_max,
    COALESCE(moq_pct, 0.8) AS moq_pct,
    COALESCE(autoriz_impo_pct, 0.007) AS autoriz_impo_pct
   FROM "Importados_Config"
  WHERE id = 1;
alter view public.gv_imp_nac_config set (security_invoker = true);

-- gv_imp_nac_config_guardar: + autoriz_impo_pct (va en tanto por uno, como todo _pct)
CREATE OR REPLACE FUNCTION public.gv_imp_nac_config_guardar(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- v23.88 (Luis) — los GLOBALES de importados y nacionalizacion (antes _NAC_DEFAULTS y las
-- tasas fijas de _nacEstad / _nacRecup en index.html). Cada proveedor puede pisar los suyos.
-- v24.56 (Thomas) — + moq_pct: "o llego al 80% del MOQ o no pido nada".
-- v25.13 (Thomas) — + autoriz_impo_pct: la «Autorizacion de Impo» (ex libre circulacion), % del FOB con INAL.
declare k text; v numeric;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo supervisores';
  end if;
  foreach k in array array['meses_objetivo','derechos_pct','ntl_pct','iva_pct','iva_adic_pct',
                           'gcias_pct','iibb_pct','estad_pct','estad_fob_desde','estad_fob_hasta',
                           'estad_fijo','valor_m3','flete_full','min_usd','moq','moq_meses_max','moq_pct',
                           'autoriz_impo_pct'] loop
    if p ? k then
      v := nullif(p->>k,'')::numeric;
      if v is null or v < 0 then raise exception '% no puede quedar vacio ni negativo', k; end if;
      if k like '%\_pct' and v > 1 then raise exception '% va en tanto por uno (0,21 = 21%%)', k; end if;
      if k = 'meses_objetivo' and v <= 0 then raise exception 'Los meses objetivo tienen que ser mayores a 0'; end if;
      execute format('update public."Importados_Config" set %I = $1, actualizado = now() where id = 1', k) using v;
    end if;
  end loop;
  if (select estad_fob_desde from public."Importados_Config" where id=1)
     > (select estad_fob_hasta from public."Importados_Config" where id=1) then
    raise exception 'El tramo de estadistica esta al reves: "desde" no puede ser mayor que "hasta"';
  end if;
  return (select to_jsonb(c) from public.gv_imp_nac_config c);
end $function$;

commit;
