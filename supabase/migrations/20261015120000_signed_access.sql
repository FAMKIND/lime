-- LIME-139: signed access. A sealed send proves it holds the recipient's delivery key by SIGNING the ciphertext and the recipient device
-- with an Ed25519 key derived from the delivery key, instead of presenting a reusable access key. The recipient uploads the PUBLIC half here,
-- beside the access-key hash (which stays during the overlap, so older builds still work).
alter table public.delivery_access
  add column access_public_key bytea check (access_public_key is null or octet_length(access_public_key) = 32);
