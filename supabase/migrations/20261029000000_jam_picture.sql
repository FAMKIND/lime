-- LIME-194: a picture for a jam, on its public page, like a public profile photo. The JPEG (at most 1 MiB) is a public object in the avatar bucket
-- (`jam-<jam_id>.jpg`, so no new bucket and no bucket rule); this column says whether it exists and its version. The server and any signed-in teacher
-- can see it, as they can the jam's title and about. Null: no picture.
alter table public.jams add column picture_version bigint;
