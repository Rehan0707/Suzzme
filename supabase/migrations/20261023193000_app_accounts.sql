-- Firebase Authentication is the identity provider. Supabase verifies its JWTs
-- through the project's Third-Party Auth integration (project: suzzme-e70f2).
-- Firebase ID tokens currently have no `role` claim, so PostgREST uses `anon`.
-- Every exposed operation below requires a verified Firebase JWT for this
-- project and is constrained to that token's own UID and email.

create table if not exists public.app_accounts (
    firebase_uid text primary key,
    email text not null,
    display_name text,
    created_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now(),
    constraint app_accounts_email_not_blank check (length(trim(email)) > 0)
);

create index if not exists app_accounts_email_idx on public.app_accounts (lower(email));

alter table public.app_accounts enable row level security;
revoke all on public.app_accounts from public, anon, authenticated;
grant select, insert, update on public.app_accounts to anon, authenticated;

create policy "Firebase user reads own account"
on public.app_accounts for select to anon, authenticated
using (
    auth.jwt()->>'iss' = 'https://securetoken.google.com/suzzme-e70f2'
    and auth.jwt()->>'aud' = 'suzzme-e70f2'
    and firebase_uid = auth.jwt()->>'sub'
);

create policy "Firebase user creates own account"
on public.app_accounts for insert to anon, authenticated
with check (
    auth.jwt()->>'iss' = 'https://securetoken.google.com/suzzme-e70f2'
    and auth.jwt()->>'aud' = 'suzzme-e70f2'
    and firebase_uid = auth.jwt()->>'sub'
    and lower(email) = lower(auth.jwt()->>'email')
);

create policy "Firebase user updates own account"
on public.app_accounts for update to anon, authenticated
using (
    auth.jwt()->>'iss' = 'https://securetoken.google.com/suzzme-e70f2'
    and auth.jwt()->>'aud' = 'suzzme-e70f2'
    and firebase_uid = auth.jwt()->>'sub'
)
with check (
    auth.jwt()->>'iss' = 'https://securetoken.google.com/suzzme-e70f2'
    and auth.jwt()->>'aud' = 'suzzme-e70f2'
    and firebase_uid = auth.jwt()->>'sub'
    and lower(email) = lower(auth.jwt()->>'email')
);

-- User counts are intentionally available to project administrators through
-- the SQL editor/service role, never through the client-facing Data API.
-- select count(*) from public.app_accounts;
