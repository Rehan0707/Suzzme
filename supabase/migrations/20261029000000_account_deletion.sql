-- A verified Firebase user may remove only their own account row.
-- The companion_summaries foreign key cascades its prepared summary.
grant delete on public.app_accounts to anon, authenticated;

drop policy if exists "Firebase user deletes own account" on public.app_accounts;
create policy "Firebase user deletes own account"
on public.app_accounts for delete to anon, authenticated
using (
    auth.jwt()->>'iss' = 'https://securetoken.google.com/suzzme-e70f2'
    and auth.jwt()->>'aud' = 'suzzme-e70f2'
    and firebase_uid = auth.jwt()->>'sub'
);
