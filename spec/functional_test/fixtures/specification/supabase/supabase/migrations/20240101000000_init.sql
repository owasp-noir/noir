-- Initial schema. Real Supabase migrations are lowercase and
-- schema-qualified.
create table public.authors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text unique
);

create table if not exists public.posts (
  id bigserial primary key,
  author_id uuid references public.authors (id),
  title text not null,
  body text,
  rating numeric(10, 2),
  published boolean default false,
  created_at timestamp with time zone default now(),
  search_vector tsvector generated always as (to_tsvector('english', title)) stored
);

alter table public.posts enable row level security;

create policy "posts are public" on public.posts
  for select using (true);

-- An internal table: PostgREST never exposes the auth schema.
create table auth.audit_log (
  id bigserial primary key,
  actor uuid references auth.users (id),
  action text
);

create view public.published_posts as
  select id, title from public.posts where published = true;

/* Function bodies contain semicolons and `create table` text.
   The dollar-quoted body must be masked before splitting. */
create or replace function public.search_posts(query text, max_results integer default 10)
returns setof public.posts
language plpgsql
as $$
begin
  -- create table decoys_should_not_be_parsed (id int);
  return query select * from public.posts where title ilike '%' || query || '%' limit max_results;
end;
$$;
