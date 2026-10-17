-- LIME-155: relay download. A request that an offline phone signs and a nearby online phone posts for it is single-use: its nonce is kept until the
-- request expires (at most 10 minutes) and then forgotten. Nothing else is kept: no device, no account, no address.
create table public.mesh_fetch_nonces (
  nonce      bytea primary key,
  expires_at timestamptz not null
);
create index mesh_fetch_nonces_expiry on public.mesh_fetch_nonces (expires_at);

alter table public.mesh_fetch_nonces enable row level security;
revoke all on public.mesh_fetch_nonces from public, anon, authenticated;
grant select, insert, update, delete on public.mesh_fetch_nonces to service_role;
