-- PRUEBAS Activo Fijo (solo lectura: todo se deshace al final)
do $$
declare res text := ''; n numeric; m numeric; k numeric; t text; u uuid := 'a7581332-ef44-4d49-af7a-ffc85b943ce2';
begin
  select count(*) into k from public.api_activo_bienes_v2();
  res := res || 'A01 bienes = filas de bien (' || (select count(*) from public.bien) || '): ' || k || case when k = (select count(*) from public.bien) then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into k from public.api_activo_movimientos_v2();
  res := res || 'A02 movimientos = renglones de comprobantes de activo fijo (' || (select count(*) from public.renglon_comprobante_af) || '): ' || k || case when k = (select count(*) from public.renglon_comprobante_af) then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from public.api_activo_bienes_v2() b
    left join (select id_bien, sum(valor_origen) vo, sum(valor_mejora) vm, sum(valor_revaluo) vr, sum(amortizacion) + sum(amortizacion_inicial) am from public.api_activo_movimientos_v2() group by 1) x using (id_bien)
    where abs(b.valor_origen - coalesce(x.vo, 0)) >= 0.01 or abs(b.valor_mejora - coalesce(x.vm, 0)) >= 0.01 or abs(b.valor_revaluo - coalesce(x.vr, 0)) >= 0.01 or abs(b.amort_acumulada - coalesce(x.am, 0)) >= 0.01;
  res := res || 'A03 saldo de cada bien = suma de sus movimientos (origen, mejoras, revaluos, amortizacion; 0 diferencias): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select round(sum(valor_origen), 2), round(sum(depreciacion_acumulada), 2) into m, n from public.saldo_bien;
  select round(sum(valor_origen), 2), round(sum(amort_acumulada), 2) into k, t from public.api_activo_bienes_v2();
  res := res || 'A04 totales = saldo_bien (origen ' || m || ', amortizacion ' || n || '): ' || k || ', ' || t || case when k = m and t::numeric = n then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from public.api_activo_bienes_v2() where abs(valor_residual - (valor_origen + valor_mejora + valor_revaluo - amort_acumulada)) >= 0.01;
  res := res || 'A05 valor residual = origen + mejoras + revaluos - amortizacion (0 diferencias): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from public.api_activo_bienes_v2() where valor_residual < 0;
  res := res || 'A06 bienes amortizados de mas (residual negativo): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into k from public.api_activo_movimientos_v2('2023-01-01', '2023-12-31');
  select count(*) into n from public.renglon_comprobante_af r join public.comprobante_af c using (id_comprobante_af) where c.fecha_comprobante::date between '2023-01-01' and '2023-12-31';
  res := res || 'A07 filtro 2023 = renglones 2023 (' || n || '): ' || k || case when k = n then ' PASA' else ' FALLA' end || chr(10);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into k from public.api_activo_bienes_v2();
  select count(*) into m from public.api_activo_movimientos_v2();
  reset role;
  res := res || 'A08 con usuario logueado (' || k || ' bienes, ' || m || ' movimientos): ' || case when k = (select count(*) from public.bien) and m = (select count(*) from public.renglon_comprobante_af) then 'PASA' else 'FALLA' end || chr(10);
  res := res || 'A09 anonimo no puede ejecutar: ' || case when not has_function_privilege('anon', 'public.api_activo_bienes_v2()', 'execute') and not has_function_privilege('anon', 'public.api_activo_movimientos_v2(date,date)', 'execute') then 'PASA' else 'FALLA' end || chr(10);
  select string_agg(tipo || ':' || c, ', ') into t from (select tipo, count(distinct id_comprobante) c from public.api_activo_movimientos_v2() group by 1 order by 2 desc) x;
  res := res || 'A10 comprobantes por tipo: ' || t || chr(10);
  select string_agg(cod_bien || ' ' || bien || ' origen ' || valor_total || ' amort ' || amort_acumulada || ' residual ' || valor_residual || ' (' || porc_amortizado || '%) vida ' || vida_util || ' ' || coalesce(unidad_vida_util, '?') || ' ult ' || coalesce(ultima_amortizacion::text, '-'), ' | ') into t from public.api_activo_bienes_v2();
  res := res || 'A11 bienes: ' || t || chr(10);
  select string_agg(a || ' ' || b || ':' || s, ', ' order by b, a) into t from (select to_char(fecha, 'YYYY') a, bien b, sum(amortizacion) s from public.api_activo_movimientos_v2() where cod_tipo = 'DEPRECIA' group by 1, 2) x;
  res := res || 'A12 amortizacion por año y bien: ' || t || chr(10);
  select string_agg(to_char(fecha, 'YYYY-MM') || ' ' || bien || ':' || amortizacion, ', ' order by fecha) into t from public.api_activo_movimientos_v2('2023-01-01', '2023-12-31') where cod_tipo = 'DEPRECIA' and amortizacion <> 0 and bien ilike 'Edificio%';
  res := res || 'A13 amortizacion del edificio en 2023: ' || coalesce(t, 'ninguna') || chr(10);
  raise exception 'RESULTADOS (solo lectura)%', chr(10) || res;
end $$;
