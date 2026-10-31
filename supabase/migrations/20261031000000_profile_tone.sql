-- LIME-277e: a profile's colour (one of the 8 avatar colours) reaches contacts like the cover: a tiny JSON object, Everyone's or contacts-only.
-- An Everyone copy is the public object `<user>-tone.json` in the avatar bucket (a few bytes; the bucket already allows application/json); the columns say
-- whether it exists and its version. A contacts-only copy is ciphertext in `blobs` and leaves no trace here. Nothing is set by default.
alter table public.profiles
  add column if not exists tone_version    bigint,
  add column if not exists tone_visibility text not null default 'contacts' check (tone_visibility in ('everyone', 'contacts'));
