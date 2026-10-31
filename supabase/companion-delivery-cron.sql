-- Run after deploying the worker and adding the SAME COMPANION_WORKER_SECRET
-- in Edge Function Secrets and Vault (name: companion_worker_secret).
-- No Apple private key or service-role key belongs in this SQL file.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
select cron.unschedule(jobid) from cron.job where jobname = 'suzzme-companion-delivery';
select cron.schedule('suzzme-companion-delivery', '* * * * *', $cron$
  select net.http_post(
    url := 'https://xkddrfkdesagugtxuwzu.supabase.co/functions/v1/companion-delivery',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' ||
      (select decrypted_secret from vault.decrypted_secrets where name='companion_gateway_anon_jwt' limit 1),
      'x-companion-worker-secret', (select decrypted_secret from vault.decrypted_secrets where name='companion_worker_secret' limit 1)),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000
  ) where exists(select 1 from vault.decrypted_secrets where name='companion_worker_secret')
    and exists(select 1 from vault.decrypted_secrets where name='companion_gateway_anon_jwt');
$cron$);
