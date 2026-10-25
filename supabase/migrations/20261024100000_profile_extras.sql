-- LIME-214, LIME-217, LIME-226a: a profile's links, background image and background video, each Everyone's or contacts-only like the photo.
-- An Everyone copy is a public object in the avatar bucket (`<user>-links.json`, `<user>-background.jpg`, `<user>-background.mp4`); the columns say
-- whether it exists and its version. A contacts-only copy is ciphertext in `blobs` and leaves no trace here. Nothing is set by default: no one has a copy.
alter table public.profiles
  add column links_version      bigint,
  add column links_visibility   text not null default 'contacts' check (links_visibility in ('everyone', 'contacts')),
  add column background_version bigint,
  add column background_visibility text not null default 'contacts' check (background_visibility in ('everyone', 'contacts')),
  add column background_video_version bigint,
  add column background_video_visibility text not null default 'contacts' check (background_video_visibility in ('everyone', 'contacts'));

-- The avatar bucket held only 1 MiB JPEGs. It now also holds a short list of links (JSON) and a background video (MP4, at most 6 MiB). A bucket has one
-- size limit and one list of types for all its objects, so the `avatar` function enforces each slot's own limit (it refuses a declared size over it at
-- `put` and removes an upload over it at `commit`). Guarded so a database without the storage schema still migrates.
do $$
begin
  if to_regclass('storage.buckets') is not null then
    update storage.buckets
      set file_size_limit = 6291456, allowed_mime_types = array['image/jpeg', 'application/json', 'video/mp4']
      where id = 'public-avatars';
  end if;
end $$;
