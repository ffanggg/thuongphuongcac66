-- =========================================================
-- Thượng Phương Các · cấu trúc dữ liệu Supabase
-- Chạy toàn bộ file này một lần trong Supabase → SQL Editor → New query → Run
-- =========================================================

-- 1) Hồ sơ người dùng: tên, lớp, email, vai trò (học sinh / giáo viên)
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  full_name   text,
  class_name  text,
  role        text not null default 'student' check (role in ('student', 'teacher')),
  created_at  timestamptz not null default now()
);

-- 2) Tiến độ học tập: mỗi học sinh một dòng, nội dung lưu dạng JSON
create table if not exists public.progress (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  data        jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);

-- 3) Bài tập cô giao
create table if not exists public.assignments (
  id          uuid primary key default gen_random_uuid(),
  data        jsonb not null,
  created_by  uuid default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

-- Hàm kiểm tra người đang đăng nhập có phải giáo viên không
create or replace function public.is_teacher()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'teacher');
$$;

-- Tự tạo hồ sơ khi có người đăng ký (lấy họ tên, lớp từ form đăng ký)
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, class_name)
  values (
    new.id,
    new.email,
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'class_name'), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =========================================================
-- Bảo mật theo dòng (Row Level Security)
-- =========================================================
alter table public.profiles    enable row level security;
alter table public.progress    enable row level security;
alter table public.assignments enable row level security;

-- PROFILES: người đã đăng nhập xem được tên các bạn (dùng cho bảng xếp hạng);
-- mỗi người chỉ sửa được tên và lớp của chính mình, KHÔNG tự đổi vai trò được.
drop policy if exists "profiles read"   on public.profiles;
drop policy if exists "profiles update" on public.profiles;
create policy "profiles read"   on public.profiles for select to authenticated using (true);
create policy "profiles update" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
revoke update on public.profiles from authenticated;
grant  update (full_name, class_name) on public.profiles to authenticated;

-- PROGRESS: mọi người đã đăng nhập xem được (bảng xếp hạng);
-- mỗi học sinh chỉ ghi được tiến độ của mình; giáo viên được xoá.
drop policy if exists "progress read"   on public.progress;
drop policy if exists "progress insert" on public.progress;
drop policy if exists "progress update" on public.progress;
drop policy if exists "progress delete" on public.progress;
create policy "progress read"   on public.progress for select to authenticated using (true);
create policy "progress insert" on public.progress for insert to authenticated with check (user_id = auth.uid());
create policy "progress update" on public.progress for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "progress delete" on public.progress for delete to authenticated using (public.is_teacher());

-- ASSIGNMENTS: ai đăng nhập cũng xem được; chỉ giáo viên giao, sửa, xoá.
drop policy if exists "assign read"   on public.assignments;
drop policy if exists "assign insert" on public.assignments;
drop policy if exists "assign update" on public.assignments;
drop policy if exists "assign delete" on public.assignments;
create policy "assign read"   on public.assignments for select to authenticated using (true);
create policy "assign insert" on public.assignments for insert to authenticated with check (public.is_teacher());
create policy "assign update" on public.assignments for update to authenticated using (public.is_teacher());
create policy "assign delete" on public.assignments for delete to authenticated using (public.is_teacher());


-- =========================================================
-- 4) LỚP HỌC VÀ MÃ LỚP
--    Học sinh chỉ vào được lớp khi nhập đúng mã. Mã lớp chỉ giáo viên xem được.
-- =========================================================
create table if not exists public.classes (
  id          text primary key,
  data        jsonb not null default '{}'::jsonb,   -- tên lớp, lịch học, các khoá được mở
  code        text unique,                          -- mã vào lớp (ẩn với học sinh)
  created_at  timestamptz not null default now()
);

create table if not exists public.class_members (
  class_id   text not null references public.classes(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (class_id, user_id)
);

alter table public.classes       enable row level security;
alter table public.class_members enable row level security;

-- CLASSES: ai đăng nhập cũng xem được tên lớp và khoá học; chỉ giáo viên tạo, sửa, xoá.
drop policy if exists "classes read"   on public.classes;
drop policy if exists "classes insert" on public.classes;
drop policy if exists "classes update" on public.classes;
drop policy if exists "classes delete" on public.classes;
create policy "classes read"   on public.classes for select to authenticated using (true);
create policy "classes insert" on public.classes for insert to authenticated with check (public.is_teacher());
create policy "classes update" on public.classes for update to authenticated using (public.is_teacher()) with check (public.is_teacher());
create policy "classes delete" on public.classes for delete to authenticated using (public.is_teacher());
-- Ẩn cột mã lớp: học sinh không đọc được cột code
revoke select on public.classes from authenticated, anon;
grant  select (id, data, created_at) on public.classes to authenticated;
grant  insert, update, delete on public.classes to authenticated;

-- CLASS_MEMBERS: học sinh xem/rời lớp của mình; giáo viên xem và cho rời lớp mọi học sinh.
-- Không ai thêm trực tiếp được: chỉ vào lớp qua hàm join_class (bắt buộc đúng mã).
drop policy if exists "members read"   on public.class_members;
drop policy if exists "members delete" on public.class_members;
create policy "members read"   on public.class_members for select to authenticated using (user_id = auth.uid() or public.is_teacher());
create policy "members delete" on public.class_members for delete to authenticated using (user_id = auth.uid() or public.is_teacher());
revoke insert, update on public.class_members from authenticated, anon;

-- Vào lớp bằng mã
create or replace function public.join_class(p_code text)
returns text
language plpgsql security definer set search_path = public
as $$
declare cid text;
begin
  if auth.uid() is null then raise exception 'Chưa đăng nhập'; end if;
  select id into cid from public.classes where upper(code) = upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
  if cid is null then raise exception 'Mã lớp không đúng'; end if;
  insert into public.class_members (class_id, user_id) values (cid, auth.uid()) on conflict do nothing;
  return cid;
end;
$$;

-- Giáo viên xem mã của các lớp
create or replace function public.class_codes()
returns table (id text, code text)
language sql stable security definer set search_path = public
as $$
  select c.id, c.code from public.classes c where public.is_teacher();
$$;

revoke all on function public.join_class(text) from public, anon;
revoke all on function public.class_codes()    from public, anon;
grant execute on function public.join_class(text) to authenticated;
grant execute on function public.class_codes()    to authenticated;

-- 4 lớp theo lịch (mã ngẫu nhiên, cô xem và đổi mã trong mục Lớp học)
insert into public.classes (id, data, code) values
  ('hsk13-246', '{"name":"HSK1-3 (2-4-6)","schedule":"Thứ 2 · Thứ 4 · Thứ 6","courses":["hsk1","hsk2","hsk3"],"order":1}', upper(substr(md5(random()::text), 1, 6))),
  ('hsk15-357', '{"name":"HSK1-5 (3-5-7)","schedule":"Thứ 3 · Thứ 5 · Thứ 7","courses":["hsk1","hsk2","hsk3","hsk4","hsk5"],"order":2}', upper(substr(md5(random()::text), 1, 6))),
  ('hsk4-56cn', '{"name":"HSK4 (5,6,CN)","schedule":"Thứ 5 · Thứ 6 · Chủ nhật","courses":["hsk4"],"order":3}', upper(substr(md5(random()::text), 1, 6))),
  ('hsk15-7cn', '{"name":"HSK1-5 (7,CN)","schedule":"Thứ 7 · Chủ nhật","courses":["hsk1","hsk2","hsk3","hsk4","hsk5"],"order":4}', upper(substr(md5(random()::text), 1, 6)))
on conflict (id) do nothing;


-- =========================================================
-- 5) GIÁO ÁN THEO BUỔI: nội dung bài tập về nhà của từng buổi
--    (một bản cho mỗi khoá, dùng chung cho mọi lớp)
-- =========================================================
create table if not exists public.plans (
  id          text primary key,           -- mã khoá: hsk1, hsk2, hsk3, hsk4…
  data        jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);
alter table public.plans enable row level security;
drop policy if exists "plans read"   on public.plans;
drop policy if exists "plans insert" on public.plans;
drop policy if exists "plans update" on public.plans;
drop policy if exists "plans delete" on public.plans;
create policy "plans read"   on public.plans for select to authenticated using (true);
create policy "plans insert" on public.plans for insert to authenticated with check (public.is_teacher());
create policy "plans update" on public.plans for update to authenticated using (public.is_teacher()) with check (public.is_teacher());
create policy "plans delete" on public.plans for delete to authenticated using (public.is_teacher());

-- =========================================================
-- SAU KHI CÔ ĐĂNG KÝ TÀI KHOẢN CỦA MÌNH trên website, chạy lệnh dưới
-- (thay email) để cấp quyền giáo viên:
--
--   update public.profiles set role = 'teacher' where email = 'email-cua-co@gmail.com';
-- =========================================================
