-- Datos + resultados esperados (calculados en SQL) para probar la logica de la pantalla Activo Fijo. Solo lectura.
do $$ declare j text; begin
  select json_build_object(
   'b', (select json_agg(x) from api_activo_bienes_v2() x),
   'm', (select json_agg(x) from api_activo_movimientos_v2() x),
   'e', json_build_object(
     'tot', (select json_build_array(count(*), sum(valor_total), sum(amort_acumulada), sum(valor_residual)) from api_activo_bienes_v2()),
     'k23', (select json_build_array(coalesce(sum(amortizacion) filter (where cod_tipo = 'DEPRECIA'), 0), sum(valor_origen + valor_mejora + valor_revaluo)) from api_activo_movimientos_v2('2023-01-01', '2023-12-31')),
     'anio', (select json_object_agg(a, json_build_array(am, inc)) from (select to_char(fecha, 'YYYY') a, coalesce(sum(amortizacion) filter (where cod_tipo = 'DEPRECIA'), 0) am, sum(valor_origen + valor_mejora + valor_revaluo) inc from api_activo_movimientos_v2() group by 1) z),
     'tipo', (select json_object_agg(coalesce(tipo_bien, 'Sin dato'), json_build_array(am, re)) from (select tipo_bien, sum(amort_acumulada) am, sum(valor_residual) re from api_activo_bienes_v2() group by 1) z),
     'mov', (select json_object_agg(cod_tipo, json_build_array(c, inc, am)) from (select cod_tipo, count(distinct id_comprobante) c, sum(valor_origen + valor_mejora + valor_revaluo) inc, sum(amortizacion + amortizacion_inicial) am from api_activo_movimientos_v2() group by 1) z),
     'matriz', (select json_object_agg(a || '|' || id_bien, s) from (select to_char(fecha, 'YYYY') a, id_bien, sum(amortizacion) s from api_activo_movimientos_v2() where cod_tipo = 'DEPRECIA' group by 1, 2) z),
     'adm', (select json_build_array(count(*), sum(amort_acumulada)) from api_activo_bienes_v2() where departamento = 'Administración'),
     'adm_mov23', (select count(*) from api_activo_movimientos_v2('2023-01-01', '2023-12-31') where id_bien in (select id_bien from api_activo_bienes_v2() where departamento = 'Administración')),
     'casi', (select count(*) from api_activo_bienes_v2() where porc_amortizado >= 90),
     'txt', (select count(*) from api_activo_bienes_v2() where concat_ws(' ', cod_bien, bien, detalle, tipo_bien, departamento, ubicacion, responsable) ilike '%camion%'),
     'ult', (select max(ultima_amortizacion) from api_activo_bienes_v2())
   ))::text into j;
  raise exception 'DATOS%', j;
end $$;
