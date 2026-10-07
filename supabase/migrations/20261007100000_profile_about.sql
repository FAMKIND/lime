-- LIME-98: a short "About" line on the public profile (an optional leading emoji, then a few words).
-- It is a PUBLIC profile field, visible to the server like the display name and school, and shown to
-- people who find you or who you message (never to a person who hid themselves from search).
alter table public.profiles
  add column about_emoji text check (about_emoji is null or char_length(about_emoji) <= 16),
  add column about_text  text check (about_text  is null or char_length(about_text)  <= 600);
