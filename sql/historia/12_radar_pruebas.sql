-- PRUEBAS Radar (solo lectura: todo se deshace al final)
-- Cada cifra del Radar se compara contra la funcion del modulo que ya estaba probada.
do $$
declare res text := ''; h record; n numeric; m numeric; k numeric; t text; u uuid := 'a7581332-ef44-4d49-af7a-ffc85b943ce2';
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select * into h from public.api_radar_hoy_v2();
  select round(sum(saldo), 2) into n from public.api_tesoreria_cuentas_v2() where es_fondo;
  res := res || 'R01 disponibilidades = Tesoreria (' || n || '): ' || h.disponibilidades || case when h.disponibilidades = n then ' PASA' else ' FALLA' end || chr(10);
  select round(sum(importe), 2), count(*) into n, k from public.api_tesoreria_cheques_v2() where estado = 'C';
  res := res || 'R02 cheques en cartera = Tesoreria (' || n || ', ' || k || '): ' || h.cheques_cartera || ', ' || h.n_cheques_cartera || case when h.cheques_cartera = coalesce(n, 0) and h.n_cheques_cartera = k then ' PASA' else ' FALLA' end || chr(10);
  res := res || 'R03 cajas + bancos + valores + tarjetas = disponibilidades: ' || case when h.cajas + h.bancos + h.valores_depositar + h.tarjetas = h.disponibilidades then 'PASA' else 'FALLA' end || chr(10);
  select round(sum(cantidad * costo_vigente), 2), count(*) filter (where cantidad < 0) into n, k from public.api_stock_saldos_v2() where true;
  res := res || 'R04 stock valorizado y negativos = Stock (' || n || ', ' || k || '): ' || h.stock_valorizado || ', ' || h.stock_negativos || case when h.stock_valorizado = n and h.stock_negativos = k then ' PASA' else ' FALLA' end || chr(10);
  select round(sum(valor_residual), 2), round(sum(amort_acumulada), 2) into n, m from public.api_activo_bienes_v2();
  res := res || 'R05 activo fijo residual y amortizado = Activo Fijo (' || n || ', ' || m || '): ' || h.af_residual || ', ' || h.af_amortizado || case when h.af_residual = n and h.af_amortizado = m then ' PASA' else ' FALLA' end || chr(10);
  res := res || 'R06 super ve sueldos; dotacion activa ' || coalesce(h.dotacion_activa::text, 'vacia') || ' (esperado 27), ultimo mes ' || coalesce(h.ultimo_mes_sueldos::text, '-') || ': ' || case when h.puede_ver_sueldos and h.dotacion_activa = 27 then 'PASA' else 'FALLA' end || chr(10);
  res := res || 'R07 ventas sin CUIT ' || h.iva_ventas_sin_cuit || ' (esperado 40), AFIP ' || h.afip_comprobantes || ': ' || case when h.iva_ventas_sin_cuit = 40 then 'PASA' else 'FALLA' end || chr(10);
  select round(sum(costo_laboral), 2) into n from public.api_radar_mensual_v2();
  select round(sum(costo_laboral), 2) into m from public.api_legajos_liquidaciones_v2(null, null);
  res := res || 'R08 costo laboral total mensual = Legajos (' || m || ', esperado 328836948.42): ' || n || case when n = m and m = 328836948.42 then ' PASA' else ' FALLA' end || chr(10);
  select round(sum(amortizacion), 2) into n from public.api_radar_mensual_v2();
  select round(sum(amortizacion), 2) into m from public.api_activo_movimientos_v2() where cod_tipo = 'DEPRECIA';
  res := res || 'R09 amortizacion total mensual = Activo Fijo (' || m || '): ' || n || case when n = m then ' PASA' else ' FALLA' end || chr(10);
  select round(sum(iva_debito), 2), round(sum(iva_credito), 2) into n, m from public.api_radar_mensual_v2();
  res := res || 'R10 IVA debito y credito = IVA (404013.09, 80061.65): ' || n || ', ' || m || case when n = 404013.09 and m = 80061.65 then ' PASA' else ' FALLA' end || chr(10);
  select round(sum(ingresos_fondos), 2) - round(sum(egresos_fondos), 2) into n from public.api_radar_mensual_v2();
  select round(sum(importe), 2) into m from public.api_tesoreria_movimientos_v2() where es_fondo;
  res := res || 'R11 ingresos - egresos del mes a mes = movimiento neto de fondos (' || m || '): ' || n || case when n = m then ' PASA' else ' FALLA' end || chr(10);
  select string_agg(to_char(extract(year from mes), '9999') || ' costo ' || coalesce(sum_cl::text, '-') || ' amort ' || coalesce(sum_am::text, '-'), ' |')
    into t from (select date_trunc('year', mes) mes, round(sum(costo_laboral), 2) sum_cl, round(sum(amortizacion), 2) sum_am from public.api_radar_mensual_v2() group by 1 order by 1) x
    where sum_cl is not null or sum_am is not null;
  res := res || 'R12 por año: ' || t || chr(10);
  res := res || 'R13 foto: disp ' || h.disponibilidades || ' cajas ' || h.cajas || ' bancos ' || h.bancos || ' valores ' || h.valores_depositar || ' tarjetas ' || h.tarjetas
    || ' rechazados ' || h.cheques_rechazados || '/' || h.n_cheques_rechazados || ' ficha ' || h.cuentas_ficha_distinta || ' stock ' || h.stock_valorizado
    || ' unid ' || h.stock_unidades || ' bajo min ' || h.stock_bajo_minimo || ' sin costo ' || h.stock_sin_costo || ' af ult ' || coalesce(h.af_ultima_amortizacion::text, '-') || chr(10);
  reset role;
  -- usuario sin permiso de sueldos: se simula uno que no existe en la tabla de usuarios
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000001', 'role', 'authenticated')::text, true);
  set local role authenticated;
  select * into h from public.api_radar_hoy_v2();
  select count(*) filter (where costo_laboral is not null) into k from public.api_radar_mensual_v2();
  reset role;
  res := res || 'R14 usuario sin permiso: no ve sueldos (dotacion ' || coalesce(h.dotacion_activa::text, 'vacia') || ', meses con costo ' || k || ') y si ve el resto (disp ' || h.disponibilidades || '): '
    || case when not h.puede_ver_sueldos and h.dotacion_activa is null and k = 0 and h.disponibilidades is not null then 'PASA' else 'FALLA' end || chr(10);
  res := res || 'R15 anonimo no puede ejecutar: ' || case when not has_function_privilege('anon', 'public.api_radar_hoy_v2()', 'execute') and not has_function_privilege('anon', 'public.api_radar_mensual_v2()', 'execute') then 'PASA' else 'FALLA' end || chr(10);
  raise exception 'RESULTADOS (solo lectura)%', chr(10) || res;
end $$;
