-- Only bounded, prepared Mac summaries are shared. Firebase Third-Party Auth
-- verifies the JWT; RLS binds every operation to the user's Firebase UID.
create table if not exists public.companion_summaries (
    firebase_uid text primary key references public.app_accounts(firebase_uid) on delete cascade,
    payload jsonb not null,
    published_at timestamptz not null default now(),
    constraint companion_summary_bounded check (pg_column_size(payload) <= 32768),
    constraint companion_summary_version check (payload->>'version' = '1')
);

alter table public.companion_summaries enable row level security;
revoke all on public.companion_summaries from public, anon, authenticated;
grant select, insert, update, delete on public.companion_summaries to anon, authenticated;

-- This was first applied through the SQL Editor. Keep the migration safe to
-- replay when the project's migration ledger is synchronized later.
drop policy if exists "Firebase user reads own companion summary" on public.companion_summaries;
create policy "Firebase user reads own companion summary"
on public.companion_summaries for select to anon, authenticated
using (
    auth.jwt()->>'iss' = 'https://securetoken.google.com/suzzme-e70f2'
    and auth.jwt()->>'aud' = 'suzzme-e70f2'
    and firebase_uid = auth.jwt()->>'sub'
);

drop policy if exists "Firebase user publishes own companion summary" on public.companion_summaries;
create policy "Firebase user publishes own companion summary"
on public.companion_summaries for insert to anon, authenticated
with check (
    auth.jwt()->>'iss' = 'https://securetoken.google.com/suzzme-e70f2'
    and auth.jwt()->>'aud' = 'suzzme-e70f2'
    and firebase_uid = auth.jwt()->>'sub'
);

drop policy if exists "Firebase user updates own companion summary" on public.companion_summaries;
create policy "Firebase user updates own companion summary"
on public.companion_summaries for update to anon, authenticated
using (
    auth.jwt()->>'iss' = 'https://securetoken.google.com/suzzme-e70f2'
    and auth.jwt()->>'aud' = 'suzzme-e70f2'
    and firebase_uid = auth.jwt()->>'sub'
)
with check (
    auth.jwt()->>'iss' = 'https://securetoken.google.com/suzzme-e70f2'
    and auth.jwt()->>'aud' = 'suzzme-e70f2'
    and firebase_uid = auth.jwt()->>'sub'
);

drop policy if exists "Firebase user removes own companion summary" on public.companion_summaries;
create policy "Firebase user removes own companion summary"
on public.companion_summaries for delete to anon, authenticated
using (
    auth.jwt()->>'iss' = 'https://securetoken.google.com/suzzme-e70f2'
    and auth.jwt()->>'aud' = 'suzzme-e70f2'
    and firebase_uid = auth.jwt()->>'sub'
);
