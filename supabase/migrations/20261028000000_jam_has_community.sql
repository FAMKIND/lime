-- LIME-210g: the one public bit of a jam's community chat. The group, its members and its messages are end-to-end encrypted and never come here;
-- the page only says that the jam has one, so a Preview can offer "Join <writer>'s community" after subscribing.
alter table public.jams add column has_community boolean not null default false;
