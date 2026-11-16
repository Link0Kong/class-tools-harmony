-- 华为账号与班级学号绑定（2026-11-15）
-- 一个学号最多绑定 3 个华为账号；手表端用华为账号直接换取班级 token。

create table if not exists private.hw_bindings (
  id bigserial primary key,
  sid text not null,
  open_id text not null unique,
  device text default '',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists hw_bindings_sid_idx on private.hw_bindings(sid);

-- 绑定：需已用学号+姓名登录（班级 token）
create or replace function public.hw_bind(p_open_id text, p_device text default '')
returns jsonb
language plpgsql security definer set search_path to 'public','private','pg_temp'
as $$
declare
  me text;
  n int;
begin
  if not public.auth_ok() then
    return jsonb_build_object('ok', false, 'reason', '请先登录');
  end if;
  me := public.auth_sid();
  if p_open_id is null or length(btrim(p_open_id)) < 8 then
    return jsonb_build_object('ok', false, 'reason', '华为账号标识无效');
  end if;
  select count(*) into n from private.hw_bindings
   where sid = me and open_id <> btrim(p_open_id);
  if n >= 3 then
    return jsonb_build_object('ok', false, 'reason', '一个学号最多绑定 3 个华为账号');
  end if;
  insert into private.hw_bindings(sid, open_id, device, updated_at)
  values (me, btrim(p_open_id), coalesce(p_device, ''), now())
  on conflict (open_id) do update
    set sid = excluded.sid, device = excluded.device, updated_at = now();
  select count(*) into n from private.hw_bindings where sid = me;
  return jsonb_build_object('ok', true, 'count', n);
end
$$;

-- 华为账号登录：按 open_id 找绑定并签发班级 token
create or replace function public.hw_login(p_open_id text)
returns jsonb
language plpgsql security definer set search_path to 'public','private','pg_temp'
as $$
declare
  b private.hw_bindings%rowtype;
  m private.class_ids%rowtype;
  tok text;
begin
  if p_open_id is null or length(btrim(p_open_id)) < 8 then
    return jsonb_build_object('ok', false, 'reason', '缺少华为账号');
  end if;
  select * into b from private.hw_bindings where open_id = btrim(p_open_id);
  if not found then
    return jsonb_build_object('ok', false, 'reason', '该华为账号尚未绑定学号');
  end if;
  select * into m from private.class_ids where sid = b.sid limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'reason', '学号不在班级名单中');
  end if;
  tok := md5(random()::text || clock_timestamp()::text) || md5(random()::text || clock_timestamp()::text);
  insert into private.class_sessions(token, sid, name, expires_at)
  values (tok, m.sid, m.name, now() + interval '30 days');
  return jsonb_build_object(
    'ok', true, 'token', tok, 'sid', m.sid, 'name', m.name,
    'role', coalesce(m.role, ''), 'badge', coalesce(m.badge, ''),
    'is_admin', coalesce(m.is_admin, false)
  );
end
$$;

-- 当前学号已绑定的华为账号（open_id 脱敏）
create or replace function public.hw_bindings()
returns jsonb
language plpgsql security definer set search_path to 'public','private','pg_temp'
as $$
begin
  if not public.auth_ok() then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'open_id', left(open_id, 4) || '…' || right(open_id, 4),
      'device', device, 'created_at', created_at
    ) order by created_at)
    from private.hw_bindings where sid = public.auth_sid()
  ), '[]'::jsonb);
end
$$;

-- 解绑：只能解绑自己学号下的
create or replace function public.hw_unbind(p_open_id text)
returns jsonb
language plpgsql security definer set search_path to 'public','private','pg_temp'
as $$
declare
  n int;
begin
  if not public.auth_ok() then
    return jsonb_build_object('ok', false, 'reason', '请先登录');
  end if;
  delete from private.hw_bindings
   where sid = public.auth_sid() and open_id = btrim(p_open_id);
  get diagnostics n = row_count;
  return jsonb_build_object('ok', n > 0);
end
$$;

grant execute on function public.hw_bind(text, text) to public;
grant execute on function public.hw_bindings() to public;
grant execute on function public.hw_login(text) to public;
grant execute on function public.hw_unbind(text) to public;

notify pgrst, 'reload schema';
