-- Migrations are a sequence: this column belongs to the final surface,
-- and `body` no longer does.
alter table public.posts add column slug text;
alter table public.posts drop column body;
alter table public.posts rename column rating to score;
