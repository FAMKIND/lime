-- LIME-188b: a jam's page also shows how many teachers follow it (public, with the page; decided by the user, 2026-10-21). The writer's phone
-- publishes the number with the rest of the page; the server learns it, and it already sees blob fetches. No ranking is built on it.
alter table public.jams add column subscriber_count integer not null default 0 check (subscriber_count >= 0);
