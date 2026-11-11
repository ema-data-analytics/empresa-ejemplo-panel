-- Datos + resultados esperados (calculados en SQL) para probar la logica de la pantalla Legajos. Solo lectura.
-- Se simula el usuario super (las funciones de sueldos solo devuelven datos a super/admin). Los recibos y conceptos viajan compactos (listas).
do $$ declare j text; begin
  perform set_config('request.jwt.claims', json_build_object('sub', 'a7581332-ef44-4d49-af7a-ffc85b943ce2', 'role', 'authenticated')::text, true);
  create temp table _r on commit drop as select * from api_legajos_liquidaciones_v2();
  create temp table _g on commit drop as select * from api_legajos_v2();
  create temp table _c on commit drop as select * from api_legajos_conceptos_v2();
  select json_build_object(
   'g', (select json_agg(x) from _g x),
   'r', (select json_agg(json_build_array(id_tot_liquidacion, id_legajo, periodo, tipo_liquidacion, tipo, haberes, asignaciones, no_remunerativo, retenciones, ganancias, neto, contribuciones, costo_laboral)) from _r),
   'c', (select json_agg(json_build_array(periodo, tipo_liquidacion, id_concepto, nro_concepto, concepto, tipo_concepto, importe)) from _c),
   'e', json_build_object(
     'k23', (select json_build_object('haberes', sum(haberes), 'asig', sum(asignaciones), 'nr', sum(no_remunerativo), 'ret', sum(retenciones), 'gan', sum(ganancias), 'neto', sum(neto), 'contrib', sum(contribuciones), 'costo', sum(costo_laboral),
              'recibos', count(*) filter (where tipo_liquidacion <> 9), 'personas', count(distinct id_legajo) filter (where tipo_liquidacion <> 9),
              'personas_mes', count(distinct id_legajo || '|' || periodo) filter (where tipo_liquidacion <> 9)) from _r where periodo between '2023-01-01' and '2023-12-01'),
     'dotacion', (select count(*) from _g where activo),
     'mes23', (select json_object_agg(to_char(periodo, 'YYYY-MM'), json_build_array(c, n, p)) from (select periodo, sum(costo_laboral) c, sum(neto) n, count(distinct id_legajo) filter (where tipo_liquidacion <> 9) p from _r where periodo between '2023-01-01' and '2023-12-01' group by 1) z),
     'rleg23', (select json_agg(json_build_array(id_legajo, v) order by v desc) from (select id_legajo, sum(costo_laboral) v from _r where periodo between '2023-01-01' and '2023-12-01' group by 1 order by 2 desc limit 10) z),
     'rdep23', (select json_agg(json_build_array(d, v) order by v desc) from (select coalesce(g.departamento, 'Sin dato') d, sum(r.costo_laboral) v from _r r join _g g using (id_legajo) where r.periodo between '2023-01-01' and '2023-12-01' group by 1 order by 2 desc limit 10) z),
     'rcat_neto', (select json_agg(json_build_array(d, v) order by v desc) from (select coalesce(g.categoria, 'Sin dato') d, sum(r.neto) v from _r r join _g g using (id_legajo) group by 1 having sum(r.neto) <> 0 order by 2 desc limit 10) z),
     'con23', (select json_agg(json_build_array(id_concepto, v) order by abs(v) desc) from (select id_concepto, sum(importe) v from _c where periodo between '2023-01-01' and '2023-12-01' and tipo_concepto = 1 group by 1 having sum(importe) <> 0 order by abs(sum(importe)) desc limit 10) z),
     'tipo23', (select json_object_agg(tipo_liquidacion, json_build_array(n, p, c)) from (select tipo_liquidacion, count(*) n, count(distinct id_legajo) p, sum(costo_laboral) c from _r where periodo between '2023-01-01' and '2023-12-01' group by 1) z),
     'altas', (select json_object_agg(y, json_build_array(a, b, (select count(*) from _g where fecha_ingreso <= make_date(y::int, 12, 31) and (fecha_egreso is null or fecha_egreso >= make_date(y::int, 12, 31))))) from
               (select y, count(*) filter (where k = 'a') a, count(*) filter (where k = 'b') b from (select to_char(fecha_ingreso, 'YYYY') y, 'a' k from _g where fecha_ingreso is not null union all select to_char(fecha_egreso, 'YYYY'), 'b' from _g where fecha_egreso is not null) u group by 1) z),
     'dot_2020_06', (select count(*) from _g where fecha_ingreso <= '2020-06-30' and (fecha_egreso is null or fecha_egreso >= '2020-06-30')),
     'adm', (select json_build_array(count(*), sum(costo_laboral)) from _r r join _g g using (id_legajo) where g.departamento = 'Administración'),
     'egresados', (select count(*) from _r r join _g g using (id_legajo) where not g.activo),
     'txt_vend', (select count(*) from _g where concat_ws(' ', nombre, nro_legajo, puesto, categoria, departamento) ilike '%vend%'),
     'costo_total', (select sum(costo_laboral) from _r),
     'mensual_2022_adm', (select json_build_array(count(*), sum(neto)) from _r r join _g g using (id_legajo) where g.departamento = 'Administración' and r.tipo_liquidacion = 3 and r.periodo between '2022-01-01' and '2022-12-01'),
     'recibo', (select json_build_object('id', t.id_tot_liquidacion, 'neto', t.neto, 'haberes', t.haberes, 'ren', (select json_agg(x) from api_legajos_recibo_v2(t.id_tot_liquidacion) x))
                from (select * from _r where haberes > 0 and retenciones > 0 and periodo = '2023-06-01' and tipo_liquidacion = 3 order by id_tot_liquidacion limit 1) t),
     'recibo9', (select json_build_object('id', t.id_tot_liquidacion, 'contrib', t.contribuciones, 'ren', (select json_agg(x) from api_legajos_recibo_v2(t.id_tot_liquidacion) x))
                from (select * from _r where tipo_liquidacion = 9 and periodo = '2023-06-01' order by id_tot_liquidacion limit 1) t)
   ))::text into j;
  raise exception 'DATOS%', j;
end $$;
