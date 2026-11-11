-- Paso 4b: detalle de ventas para la pantalla interactiva (todos los filtros se hacen en la pantalla).
-- Una fila por renglon de venta (sin anulados), con nombres de cliente, provincia y vendedor.
-- Lee la vista de costo corregida. Permiso del dueno + search_path fijo; solo usuarios logueados.
create or replace function public.api_ventas_lineas_v2(p_desde date default null, p_hasta date default null)
returns table (fecha date, t_comp text, n_comp text, tipo_comprobante text, signo int,
  cod_client text, cliente text, provincia text, cod_vended text, vendedor text,
  cod_articu text, articulo text, cantidad numeric, venta numeric, costo numeric, margen numeric,
  tiene_costo boolean, origen_costo text)
language sql stable security definer set search_path = public, pg_temp as $$
  select v.fecha::date, v.t_comp::text, v.n_comp::text, v.tipo_comprobante::text, v.signo,
         v.cod_client::text, coalesce(c.razon_soci, 'Cliente ' || v.cod_client)::text,
         coalesce(p.nombre_pro, 'Sin provincia')::text,
         v.cod_vended::text, coalesce(ve.nombre_ven, 'Vendedor ' || coalesce(v.cod_vended::text, '?'))::text,
         v.cod_articu::text, coalesce(v.articulo, 'Articulo ' || v.cod_articu)::text,
         v.signo * coalesce(v.cantidad, 0), v.importe_con_signo,
         case when v.tiene_costo then v.signo * v.costo_renglon end,
         case when v.tiene_costo then v.margen_con_signo end,
         v.tiene_costo, v.origen_costo
  from public.vista_venta_linea_v2 v
  left join lateral (select g.razon_soci, g.cod_provin from public.gva14 g where g.cod_client = v.cod_client limit 1) c on true
  left join lateral (select x.nombre_pro from public.gva18 x where x.cod_provin = c.cod_provin limit 1) p on true
  left join lateral (select y.nombre_ven from public.gva23 y where y.cod_vended = v.cod_vended limit 1) ve on true
  where v.estado_comprobante <> 'ANU'
    and (p_desde is null or v.fecha::date >= p_desde)
    and (p_hasta is null or v.fecha::date <= p_hasta)
  order by v.fecha, v.t_comp, v.n_comp, v.n_rengl_v;
$$;
revoke all on function public.api_ventas_lineas_v2(date, date) from public, anon;
grant execute on function public.api_ventas_lineas_v2(date, date) to authenticated;
comment on function public.api_ventas_lineas_v2(date, date) is 'Detalle de ventas para la pantalla interactiva. 26/09/2026.';
notify pgrst, 'reload schema';
