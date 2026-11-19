-- Cami Gym · esquema de producción (Supabase / Postgres)
-- Acceso sin login: alumnos con token personal, profe con token secreto.
-- Las tablas tienen RLS activado y sin políticas: nadie las lee directo.
-- Todo pasa por funciones SECURITY DEFINER que validan el token.

create table if not exists config(k text primary key, v text not null);
insert into config(k,v) values('profe_token', replace(gen_random_uuid()::text,'-','')) on conflict (k) do nothing;

create table if not exists ejercicios(
  id text primary key, n text not null, c text not null, u text not null default '', creado timestamptz default now());

create table if not exists alumnos(
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  token text unique not null default replace(gen_random_uuid()::text,'-',''),
  inicio date not null default current_date,
  plan jsonb not null default '{"weeks":[]}'::jsonb,
  activo boolean not null default true,
  creado timestamptz default now());

create table if not exists sesiones(
  id bigserial primary key, alumno uuid not null references alumnos(id) on delete cascade,
  k text not null, d date not null, creado timestamptz default now(), unique(alumno,k,d));

create table if not exists pesos(
  alumno uuid not null references alumnos(id) on delete cascade, key text not null, v text not null,
  d date not null default current_date, primary key(alumno,key));

create table if not exists comentarios(
  id bigserial primary key, alumno uuid not null references alumnos(id) on delete cascade,
  k text not null, t text not null check (length(t) <= 2000), creado timestamptz default now());

alter table config enable row level security;
alter table ejercicios enable row level security;
alter table alumnos enable row level security;
alter table sesiones enable row level security;
alter table pesos enable row level security;
alter table comentarios enable row level security;

-- ---------- helpers ----------
create or replace function _alumno(p_token text) returns alumnos
language plpgsql security definer set search_path = public as $$
declare a alumnos;
begin
  select * into a from alumnos where token = p_token and activo;
  if a.id is null then raise exception 'token no autorizado'; end if;
  return a;
end $$;

create or replace function _profe(p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_token is null or not exists(select 1 from config where k='profe_token' and v=p_token) then
    raise exception 'token no autorizado';
  end if;
end $$;

create or replace function _ex_json() returns json
language sql security definer set search_path = public as $$
  select coalesce(json_object_agg(id, json_build_object('n',n,'c',c,'u',u)), '{}'::json) from ejercicios;
$$;

create or replace function _alumno_json(a alumnos, with_token boolean) returns json
language sql security definer set search_path = public as $$
  select json_build_object(
    'id', a.id, 'nombre', a.nombre, 'inicio', a.inicio, 'plan', a.plan, 'activo', a.activo,
    'token', case when with_token then a.token end,
    'ses', (select coalesce(json_agg(json_build_object('k',k,'d',d) order by d), '[]'::json) from sesiones where alumno=a.id),
    'pes', (select coalesce(json_object_agg(key, json_build_object('v',v,'d',d)), '{}'::json) from pesos where alumno=a.id),
    'com', (select coalesce(json_agg(json_build_object('k',k,'t',t,'d',creado) order by creado), '[]'::json) from comentarios where alumno=a.id));
$$;

-- ---------- alumno ----------
create or replace function alumno_load(p_token text) returns json
language plpgsql security definer set search_path = public as $$
declare a alumnos := _alumno(p_token);
begin
  return json_build_object('alumno', _alumno_json(a,false), 'ex', _ex_json());
end $$;

create or replace function alumno_sesion(p_token text, p_k text, p_d date, p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
declare a alumnos := _alumno(p_token);
begin
  if p_on then insert into sesiones(alumno,k,d) values(a.id,p_k,coalesce(p_d,current_date)) on conflict do nothing;
  else delete from sesiones where alumno=a.id and k=p_k; end if;
end $$;

create or replace function alumno_peso(p_token text, p_key text, p_v text) returns void
language plpgsql security definer set search_path = public as $$
declare a alumnos := _alumno(p_token);
begin
  if p_v is null or btrim(p_v) = '' then delete from pesos where alumno=a.id and key=p_key;
  else insert into pesos(alumno,key,v) values(a.id,p_key,left(p_v,20))
       on conflict (alumno,key) do update set v=excluded.v; end if;
end $$;

create or replace function alumno_comentar(p_token text, p_k text, p_t text) returns void
language plpgsql security definer set search_path = public as $$
declare a alumnos := _alumno(p_token);
begin
  insert into comentarios(alumno,k,t) values(a.id,p_k,left(p_t,2000));
end $$;

-- ---------- profe ----------
create or replace function profe_load(p_token text) returns json
language plpgsql security definer set search_path = public as $$
begin
  perform _profe(p_token);
  return json_build_object('ex', _ex_json(),
    'alumnos', (select coalesce(json_agg(_alumno_json(a,true) order by a.creado), '[]'::json) from alumnos a));
end $$;

create or replace function profe_alumno_nuevo(p_token text, p_nombre text) returns json
language plpgsql security definer set search_path = public as $$
declare a alumnos;
begin
  perform _profe(p_token);
  insert into alumnos(nombre, inicio) values(btrim(p_nombre), date_trunc('week', current_date)::date) returning * into a;
  return _alumno_json(a,true);
end $$;

create or replace function profe_alumno_guardar(p_token text, p_id uuid, p_nombre text, p_inicio date, p_plan jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _profe(p_token);
  update alumnos set nombre=coalesce(p_nombre,nombre), inicio=coalesce(p_inicio,inicio), plan=coalesce(p_plan,plan) where id=p_id;
end $$;

create or replace function profe_ex_guardar(p_token text, p_id text, p_n text, p_c text, p_u text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _profe(p_token);
  insert into ejercicios(id,n,c,u) values(p_id,p_n,p_c,coalesce(p_u,''))
  on conflict (id) do update set n=excluded.n, c=excluded.c, u=excluded.u;
end $$;

create or replace function profe_ex_borrar(p_token text, p_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _profe(p_token);
  delete from ejercicios where id=p_id;
end $$;

-- Solo las funciones públicas quedan expuestas a la app.
revoke all on function _alumno(text), _profe(text), _ex_json(), _alumno_json(alumnos, boolean) from public, anon, authenticated;
grant execute on function alumno_load(text), alumno_sesion(text,text,date,boolean), alumno_peso(text,text,text), alumno_comentar(text,text,text),
  profe_load(text), profe_alumno_nuevo(text,text), profe_alumno_guardar(text,uuid,text,date,jsonb), profe_ex_guardar(text,text,text,text,text), profe_ex_borrar(text,text)
  to anon;
