-- LIME-214, LIME-217: a profile's links and background image, each Everyone's or contacts-only like the photo.
-- An Everyone copy is a public object in the avatar bucket (`<user>-links.json`, `<user>-background.jpg`); the columns say whether it exists
-- and its version. A contacts-only copy is ciphertext in `blobs` and leaves no trace here. Nothing is set by default: no one has a copy.
alter table public.profiles
  add column links_version      bigint,
  add column links_visibility   text not null default 'contacts' check (links_visibility in ('everyone', 'contacts')),
  add column background_version bigint,
  add column background_visibility text not null default 'contacts' check (background_visibility in ('everyone', 'contacts'));
