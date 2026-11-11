-- Datos + resultados esperados (calculados en SQL, directo de las funciones de cada modulo) para probar la logica del Radar. Solo lectura.
-- Se corre como el usuario super (ve sueldos). Periodos: años 2021, 2022, 2023, 2025 y uno que empieza a mitad de mes (16/07/2022 al 15/07/2023).
do $$ declare j text; u uuid := 'a7581332-ef44-4d49-af7a-ffc85b943ce2'; begin
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  set local role authenticated;
  with per(clave, desde, hasta) as (values ('a2021', date '2021-01-01', date '2021-12-31'), ('a2022', date '2022-01-01', date '2022-12-31'),
         ('a2023', date '2023-01-01', date '2023-12-31'), ('a2025', date '2025-01-01', date '2025-12-31'), ('medio', date '2022-07-16', date '2023-07-15')),
  v as (select fecha, venta from public.api_ventas_lineas_v2()),
  c as (select fecha, neto + exento nc from public.api_compras_comprobantes_v2()),
  l as (select date_trunc('month', periodo)::date m, costo_laboral from public.api_legajos_liquidaciones_v2(null, null)),
  a as (select date_trunc('month', fecha)::date m, amortizacion from public.api_activo_movimientos_v2() where cod_tipo = 'DEPRECIA'),
  iv as (select date_trunc('month', fecha)::date m, iva from public.api_iva_ventas_v2()),
  ic as (select date_trunc('month', fecha)::date m, iva from public.api_iva_compras_v2()),
  e as (select p.clave,
          round((select coalesce(sum(venta), 0) from v where fecha between p.desde and p.hasta), 2) ventas,
          round((select coalesce(sum(nc), 0) from c where fecha between p.desde and p.hasta), 2) compras,
          round((select coalesce(sum(costo_laboral), 0) from l where m between p.desde and p.hasta), 2) costo,
          round((select coalesce(sum(amortizacion), 0) from a where m between p.desde and p.hasta), 2) amort,
          round((select coalesce(sum(iva), 0) from iv where m between p.desde and p.hasta), 2) deb,
          round((select coalesce(sum(iva), 0) from ic where m between p.desde and p.hasta), 2) cre,
          (select count(distinct m) from l where m between p.desde and p.hasta) m_costo,
          (select json_agg(json_build_array(k, vv, cc) order by k) from (
             select to_char(fecha, 'YYYY-MM') k, sum(vv) vv, sum(cc) cc from (select fecha, venta vv, 0 cc from v where fecha between p.desde and p.hasta
               union all select fecha, 0, nc from c where fecha between p.desde and p.hasta) z group by 1) y) meses,
          p.desde, p.hasta
        from per p)
  select json_build_object(
    'mensual', (select json_agg(x order by x.mes) from public.api_radar_mensual_v2() x),
    'hoy', (select row_to_json(h) from public.api_radar_hoy_v2() h),
    'corte', (select corte_recomendado from public.api_fecha_corte_v2()),
    'e', (select json_object_agg(clave, json_build_object('ventas', ventas, 'compras', compras, 'costo', costo, 'amort', amort, 'deb', deb, 'cre', cre,
                   'resultado', ventas - compras - costo - amort, 'm_costo', m_costo, 'meses', meses, 'desde', desde, 'hasta', hasta)) from e),
    'huecos', (select json_agg(to_char(g, 'YYYY-MM') order by g) from generate_series((select min(m) from l), (select max(m) from l), interval '1 month') g
               where not exists (select 1 from l where l.m = g::date))
  )::text into j;
  reset role;
  raise exception 'DATOS%', j;
end $$;
