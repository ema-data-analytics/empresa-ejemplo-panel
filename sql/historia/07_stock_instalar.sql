-- Paso 4d: Stock para la pantalla interactiva. Dos funciones nuevas; no se toca nada existente.
-- Saldos: uno por artículo y depósito (sta19), con tres costos para valorizar, sin elegir uno por el usuario:
--   costo_vigente = última compra real (sin anulados ni notas de crédito, fecha 1800 corregida); si no hay, ficha (último costo, reposición).
--   costo_ficha   = último costo de la ficha de Tango (sta12.precio_u_l).
--   costo_ppp     = precio promedio ponderado de Tango del último mes con dato (sta21.ppp_lo).
-- Movimientos: uno por renglón de movimiento de stock (sta20), cantidad con signo (+ entra, - sale).
create or replace function public.api_stock_saldos_v2()
returns table (cod_articu text, articulo text, perfil text, lleva_stock boolean, cod_deposi text, deposito text,
  cantidad numeric, comprometida numeric, pendiente numeric, stock_min numeric, stock_max numeric,
  costo_vigente numeric, origen_costo text, fecha_costo date, costo_ficha numeric, costo_ppp numeric,
  ultima_entrada date, ultima_salida date)
language sql stable security definer set search_path = public, pg_temp as $$
  with uc as (
    select distinct on (l.cod_articu) l.cod_articu, l.precio_net,
           coalesce(nullif(l.fecha_mov::date, date '1800-01-01'), c.fecha_emis::date) as fecha
    from public.cpa46 l join public.cpa04 c on c.id_cpa04 = l.id_cpa04
    where coalesce(c.estado, '') <> 'ANU' and c.t_comp in ('FAC', 'N/D')
      and coalesce(l.precio_net, 0) > 0 and coalesce(l.cantidad, 0) <> 0
    order by l.cod_articu, 3 desc, c.n_comp desc),
  pp as (
    select distinct on (x.cod_articu) x.cod_articu, x.ppp_lo
    from public.sta21 x where coalesce(x.ppp_lo, 0) > 0
    order by x.cod_articu, x.anio desc, x.mes desc),
  mv as (
    select m.cod_articu, m.cod_deposi,
           max(m.fecha_mov::date) filter (where m.tipo_mov = 'E') as ent,
           max(m.fecha_mov::date) filter (where m.tipo_mov = 'S') as sal
    from public.sta20 m group by 1, 2)
  select s.cod_articu::text, coalesce(a.descripcio, 'Articulo ' || s.cod_articu)::text, a.perfil::text, a.stock,
         s.cod_deposi::text, coalesce(d.nombre_suc, 'Deposito ' || s.cod_deposi)::text,
         coalesce(s.cant_stock, 0)::numeric, coalesce(s.cant_comp, 0)::numeric, coalesce(s.cant_pend, 0)::numeric,
         nullif(a.stock_mini, 0)::numeric, nullif(a.stock_maxi, 0)::numeric,
         coalesce(uc.precio_net, nullif(f.precio_u_l, 0), nullif(f.precio_rep, 0))::numeric,
         case when uc.precio_net is not null then 'ultima compra real'
              when nullif(f.precio_u_l, 0) is not null then 'ficha ultimo costo'
              when nullif(f.precio_rep, 0) is not null then 'ficha reposicion' else 'sin costo' end,
         case when uc.precio_net is not null then uc.fecha else nullif(f.fecha_ulc::date, date '1800-01-01') end,
         nullif(f.precio_u_l, 0)::numeric, pp.ppp_lo::numeric,
         mv.ent, mv.sal
  from public.sta19 s
  left join lateral (select x.descripcio, x.perfil, x.stock, x.stock_mini, x.stock_maxi from public.sta11 x where x.cod_articu = s.cod_articu limit 1) a on true
  left join lateral (select y.nombre_suc from public.sta22 y where y.cod_sucurs = s.cod_deposi limit 1) d on true
  left join lateral (select z.precio_u_l, z.precio_rep, z.fecha_ulc from public.sta12 z where z.cod_articu = s.cod_articu limit 1) f on true
  left join uc on uc.cod_articu = s.cod_articu
  left join pp on pp.cod_articu = s.cod_articu
  left join mv on mv.cod_articu = s.cod_articu and mv.cod_deposi = s.cod_deposi
  order by 2, 5;
$$;

create or replace function public.api_stock_movimientos_v2(p_desde date default null, p_hasta date default null)
returns table (id_sta20 bigint, fecha date, t_comp text, n_comp text, tipo_mov text, cod_mov text,
  cod_articu text, articulo text, lleva_stock boolean, cod_deposi text, deposito text, cantidad numeric, estado_mov text)
language sql stable security definer set search_path = public, pg_temp as $$
  select m.id_sta20::bigint, m.fecha_mov::date, h.t_comp::text, h.n_comp::text, m.tipo_mov::text, m.tcomp_in_s::text,
         m.cod_articu::text, coalesce(a.descripcio, 'Articulo ' || m.cod_articu)::text, a.stock,
         m.cod_deposi::text, coalesce(d.nombre_suc, 'Deposito ' || m.cod_deposi)::text,
         (case when m.tipo_mov = 'S' then -1 else 1 end) * coalesce(m.cantidad, 0),
         coalesce(nullif(trim(h.estado_mov), ''), 'sin estado')::text
  from public.sta20 m
  left join public.sta14 h on h.id_sta14 = m.id_sta14
  left join lateral (select x.descripcio, x.stock from public.sta11 x where x.cod_articu = m.cod_articu limit 1) a on true
  left join lateral (select y.nombre_suc from public.sta22 y where y.cod_sucurs = m.cod_deposi limit 1) d on true
  where (p_desde is null or m.fecha_mov::date >= p_desde)
    and (p_hasta is null or m.fecha_mov::date <= p_hasta)
  order by 2, 4, 1;
$$;

revoke all on function public.api_stock_saldos_v2(), public.api_stock_movimientos_v2(date, date) from public, anon;
grant execute on function public.api_stock_saldos_v2(), public.api_stock_movimientos_v2(date, date) to authenticated;
comment on function public.api_stock_saldos_v2() is 'Saldos de stock por articulo y deposito, con tres costos. 26/09/2026.';
comment on function public.api_stock_movimientos_v2(date, date) is 'Movimientos de stock con signo. 26/09/2026.';
notify pgrst, 'reload schema';
select 'instalado' as estado;
