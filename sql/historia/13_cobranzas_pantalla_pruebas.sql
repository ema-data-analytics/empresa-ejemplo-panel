-- Datos para probar la pantalla: lo que devuelve api_cobranzas_v2 (D) y lo esperado calculado aparte en SQL (E), a 4 fechas de corte.
-- E: pendiente por cliente y tramo reconstruyendo cada cuota con los cobros de fecha <= corte (regla del Excel: vence ese día = 1 día).
with cortes(d) as (values (date '2026-10-07'), (date '2026-09-07'), (date '2025-10-07'), (date '2024-06-21')),
b as (
  select k.d corte, g.cod_client,
         v.importe_vt - coalesce((select sum(a.import_can) from gva07 a where a.t_comp = v.t_comp and a.n_comp = v.n_comp and a.fecha_vto = v.fecha_vto and a.f_comp_can::date <= k.d), 0) p,
         case when k.d - coalesce(v.fecha_vto, g.fecha_emis)::date = 0 then 1 else k.d - coalesce(v.fecha_vto, g.fecha_emis)::date end dias
  from cortes k cross join gva46 v join gva12 g on g.t_comp = v.t_comp and g.n_comp = v.n_comp
  where coalesce(g.estado, '') <> 'ANU' and g.fecha_emis::date <= k.d),
t as (
  select corte, cod_client,
         case when dias > 90 then 'm90' when dias > 60 then 'd61' when dias > 30 then 'd31' when dias > 0 then 'd1'
              when dias >= -30 then 'a30' when dias > -60 then 'a60' else 'a60m' end tramo, round(p, 2) p
  from b where round(p, 2) > 0.005)
select json_build_object(
  'D', public.api_cobranzas_v2(),
  'E', (select json_object_agg(corte || '|' || cod_client || '|' || tramo, s) from (select corte, cod_client, tramo, round(sum(p), 2) s from t group by 1, 2, 3) z),
  'saldo', (select json_object_agg(cod_client, s) from (select cod_client, round(sum(case when upper(trim(coalesce(tcomp_in_v, ''))) in ('CC', 'RC', 'NC') then -importe else importe end), 2) s
             from gva12 where coalesce(estado, '') not in ('ANU', '***') and fecha_emis::date <= date '2026-10-07' group by 1) z),
  'ventas12', (select json_object_agg(cod_client, s) from (select cod_client, round(sum(importe_con_signo), 2) s from vista_venta_linea_v2
             where estado_comprobante <> 'ANU' and fecha::date >= date '2025-11-01' and fecha::date <= date '2026-10-31' group by 1) z)
)::text as j;
