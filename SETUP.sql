-- MedPrep database setup for Supabase
-- Run this whole file in Supabase Dashboard -> SQL Editor -> New query.
-- IMPORTANT: this script stores the answer key separately from the public question view.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role text not null default 'student' check (role in ('student','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  specialty text not null,
  topic text not null,
  subtopic text not null default '',
  difficulty text not null default 'Intermediate' check (difficulty in ('Basic','Intermediate','Advanced')),
  title text not null,
  stem text not null,
  choices jsonb not null check (jsonb_typeof(choices)='array' and jsonb_array_length(choices)=5),
  correct_option integer not null check (correct_option between 0 and 4),
  summary jsonb not null default '[]'::jsonb,
  reason text not null,
  pathophys text not null default '',
  distractors jsonb not null default '[]'::jsonb,
  pearls jsonb not null default '[]'::jsonb,
  objectives text not null default '',
  references text not null default '',
  status text not null default 'draft' check (status in ('draft','published')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Public view deliberately excludes correct_option.
create or replace view public.questions_public
with (security_invoker = true) as
select id, specialty, topic, subtopic, difficulty, title, stem, choices,
       summary, reason, pathophys, distractors, pearls, objectives, references,
       status, created_at
from public.questions
where status = 'published';

create table if not exists public.attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  selected_option integer not null check (selected_option between 0 and 4),
  is_correct boolean not null,
  created_at timestamptz not null default now()
);

create table if not exists public.bookmarks (
  user_id uuid not null references auth.users(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, question_id)
);

create index if not exists questions_status_created_idx on public.questions(status, created_at desc);
create index if not exists questions_specialty_idx on public.questions(specialty);
create index if not exists attempts_user_created_idx on public.attempts(user_id, created_at desc);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin') $$;

-- Create a profile for every newly registered user.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles(id, display_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name',''), 'student')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.questions enable row level security;
alter table public.attempts enable row level security;
alter table public.bookmarks enable row level security;

drop policy if exists "Users can read own profile" on public.profiles;
create policy "Users can read own profile" on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
drop policy if exists "Users can update own display name" on public.profiles;
create policy "Users can update own display name" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid() and role = (select p.role from public.profiles p where p.id = auth.uid()));
drop policy if exists "Admins manage profiles" on public.profiles;
create policy "Admins manage profiles" on public.profiles for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Published questions readable by signed-in students" on public.questions;
create policy "Published questions readable by signed-in students" on public.questions for select to authenticated using (status = 'published' or public.is_admin());
drop policy if exists "Admins insert questions" on public.questions;
create policy "Admins insert questions" on public.questions for insert to authenticated with check (public.is_admin());
drop policy if exists "Admins update questions" on public.questions;
create policy "Admins update questions" on public.questions for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "Admins delete questions" on public.questions;
create policy "Admins delete questions" on public.questions for delete to authenticated using (public.is_admin());

drop policy if exists "Users read own attempts" on public.attempts;
create policy "Users read own attempts" on public.attempts for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists "Users insert own attempts" on public.attempts;
create policy "Users insert own attempts" on public.attempts for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "Users read own bookmarks" on public.bookmarks;
create policy "Users read own bookmarks" on public.bookmarks for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists "Users add own bookmarks" on public.bookmarks;
create policy "Users add own bookmarks" on public.bookmarks for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "Users remove own bookmarks" on public.bookmarks;
create policy "Users remove own bookmarks" on public.bookmarks for delete to authenticated using (user_id = auth.uid());

-- Server-side answer submission: checks the key inside the database and returns
-- correctness/explanation only after submission. Students cannot read correct_option
-- through the questions_public view.
create or replace function public.submit_mcq_answer(p_question_id uuid, p_selected_option integer)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare q public.questions%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if p_selected_option < 0 or p_selected_option > 4 then raise exception 'Invalid option'; end if;
  select * into q from public.questions where id = p_question_id and status = 'published';
  if not found then raise exception 'Question not found'; end if;
  insert into public.attempts(user_id, question_id, selected_option, is_correct)
  values(auth.uid(), q.id, p_selected_option, p_selected_option = q.correct_option);
  return jsonb_build_object(
    'is_correct', p_selected_option = q.correct_option,
    'correct_option', q.correct_option,
    'reason', q.reason,
    'pathophys', q.pathophys,
    'summary', q.summary,
    'distractors', q.distractors,
    'pearls', q.pearls,
    'objectives', q.objectives,
    'references', q.references,
    'choices', q.choices
  );
end;
$$;

revoke all on function public.submit_mcq_answer(uuid, integer) from public;
grant execute on function public.submit_mcq_answer(uuid, integer) to authenticated;

grant usage on schema public to anon, authenticated;
grant select on public.questions_public to authenticated;
grant select, insert, update, delete on public.questions to authenticated;
grant select, insert, delete on public.bookmarks to authenticated;
grant select, insert on public.attempts to authenticated;
grant select, update on public.profiles to authenticated;

-- After creating your own account, find your user UUID in Authentication -> Users,
-- then run this as project owner in SQL Editor, replacing the UUID:
-- update public.profiles set role = 'admin' where id = 'YOUR-USER-UUID';
