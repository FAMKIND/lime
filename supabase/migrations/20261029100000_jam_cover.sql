-- LIME-258: a band's (a jam page's) colour and cover, public with the page like its name and picture. `tone` is one of the 8 avatar tones (0 to 7; null = the
-- default from the jam id, chosen by the app); the cover is a public JPEG of at most 1 MiB in the avatar bucket (`jam-cover-<jam_id>.jpg`, no new bucket), and
-- `cover_version` says whether it exists and its version. Null: no cover. Ending the jam, taking its page down or deleting the account deletes the cover.
alter table public.jams add column tone smallint check (tone between 0 and 7);
alter table public.jams add column cover_version bigint;
