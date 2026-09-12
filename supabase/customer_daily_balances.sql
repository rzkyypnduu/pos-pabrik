-- Jalankan di Supabase Dashboard > SQL Editor untuk aplikasi (perangkat lain
-- memakai tabel yang sama). Tabel ini dipakai tab Hasil > Hutang per Pelanggan
-- untuk catatan saldo hutang HARIAN (copy & putus), meniru personal_ledgers.

create table if not exists public.customer_daily_balances (
  id text primary key,
  date text not null default '',
  name text not null,
  amount bigint not null default 0,
  updated_at timestamptz default now(),
  updated_by text,
  deleted_at timestamptz
);

create index if not exists cdb_date_idx on public.customer_daily_balances (date);
create index if not exists cdb_updated_at_idx on public.customer_daily_balances (updated_at);

alter table public.customer_daily_balances enable row level security;

drop policy if exists "cdb_anon_all" on public.customer_daily_balances;
create policy "cdb_anon_all"
  on public.customer_daily_balances
  for all
  using (true)
  with check (true);

create or replace function public.cdb_set_updated_at()
returns trigger as $$
begin
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists customer_daily_balances_set_updated_at on public.customer_daily_balances;
create trigger customer_daily_balances_set_updated_at
  before insert or update on public.customer_daily_balances
  for each row execute function public.cdb_set_updated_at();