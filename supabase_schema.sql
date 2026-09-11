-- =====================================================================
-- POS KRUPUK - Supabase Schema (mirror untuk sinkronisasi 2 arah)
-- Cara pakai: dashboard Supabase -> menu kiri "SQL Editor" -> New query
--             -> tempel seluruh isi file ini -> klik "Run".
-- =====================================================================

create extension if not exists pgcrypto;

-- Fungsi trigger: updated_at dimiliki server (kunci LWW / last-write-wins)
create or replace function public.set_sync_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = clock_timestamp();
  return new;
end;
$$;

-- ========================= TABEL BISNIS =========================

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  price integer not null default 0,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by text,
  deleted_at timestamptz
);

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  date text not null,
  name text not null,
  raw_total integer not null default 0,
  rounded_total integer not null default 0,
  paid integer not null default 0,
  diff integer not null default 0,
  note text,
  is_paid_btn_clicked integer not null default 0,
  debt_paid integer not null default 0,
  debt_paid_amount integer not null default 0,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by text,
  deleted_at timestamptz
);

create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  product_id uuid,
  name text not null,
  qty real not null default 0,
  price integer not null default 0,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by text,
  deleted_at timestamptz
);

create table if not exists public.oil_stocks (
  id uuid primary key default gen_random_uuid(),
  date text,
  qty real not null default 0,
  price real not null default 0,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by text,
  deleted_at timestamptz
);

create table if not exists public.stock_managements (
  id uuid primary key default gen_random_uuid(),
  date text,
  name text not null,
  qty real not null default 0,
  price integer not null default 0,
  batches text,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by text,
  deleted_at timestamptz
);

create table if not exists public.stock_remainings (
  id uuid primary key default gen_random_uuid(),
  date text,
  name text not null,
  qty real not null default 0,
  price integer not null default 0,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by text,
  deleted_at timestamptz
);

create table if not exists public.customer_ledgers (
  id uuid primary key default gen_random_uuid(),
  date text not null,
  name text not null,
  amount integer not null default 0,
  type text not null,
  note text,
  sale_id uuid references public.sales(id) on delete cascade,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by text,
  deleted_at timestamptz
);

create table if not exists public.personal_ledgers (
  id uuid primary key default gen_random_uuid(),
  date text not null,
  name text not null,
  amount integer not null default 0,
  note text,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by text,
  deleted_at timestamptz
);

create table if not exists public.saldo_deductions (
  id uuid primary key default gen_random_uuid(),
  date text,
  a real not null default 0,
  b real not null default 0,
  note text,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by text,
  deleted_at timestamptz
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  date text not null,
  amount integer not null default 0,
  note text,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by text,
  deleted_at timestamptz
);

-- Metadata sinkronisasi per device (penyimpanan kursor pull)
create table if not exists public.sync_meta (
  device_id text primary key,
  last_synced_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

-- Pasang trigger updated_at di semua tabel bisnis
do $$
declare t text;
begin
  foreach t in array array[
    'products','sales','sale_items','oil_stocks','stock_managements',
    'stock_remainings','customer_ledgers','personal_ledgers',
    'saldo_deductions','expenses'
  ]
  loop
    execute format(
      'create trigger set_updated_at_tg before update on public.%I
       for each row execute procedure public.set_sync_updated_at()', t);
  end loop;
end $$;

-- Indeks agar pull incremental (WHERE updated_at > cursor) cepat
create index if not exists idx_products_updated        on public.products(updated_at);
create index if not exists idx_sales_updated           on public.sales(updated_at);
create index if not exists idx_sale_items_updated      on public.sale_items(updated_at);
create index if not exists idx_oil_stocks_updated      on public.oil_stocks(updated_at);
create index if not exists idx_sm_updated              on public.stock_managements(updated_at);
create index if not exists idx_sr_updated              on public.stock_remainings(updated_at);
create index if not exists idx_cl_updated              on public.customer_ledgers(updated_at);
create index if not exists idx_pl_updated              on public.personal_ledgers(updated_at);
create index if not exists idx_sd_updated              on public.saldo_deductions(updated_at);
create index if not exists idx_expenses_updated        on public.expenses(updated_at);

-- =====================================================================
-- HAK AKSES (WAJIB, karena "Automatically expose new tables" TIDAK dicentang)
-- anon key di-app dipakai seperti kunci akses sederhana. RLS dibiarkan
-- OFF (default project). Tingkatkan ke RLS+Auth belakangan bila perlu.
-- =====================================================================
grant usage on schema public to anon;
grant all privileges on all tables in schema public to anon;

-- =====================================================================
-- AKTIFKAN REALTIME (supabase-realtime / postgres_changes) utk semua tabel
-- =====================================================================
alter publication supabase_realtime add table public.products;
alter publication supabase_realtime add table public.sales;
alter publication supabase_realtime add table public.sale_items;
alter publication supabase_realtime add table public.oil_stocks;
alter publication supabase_realtime add table public.stock_managements;
alter publication supabase_realtime add table public.stock_remainings;
alter publication supabase_realtime add table public.customer_ledgers;
alter publication supabase_realtime add table public.personal_ledgers;
alter publication supabase_realtime add table public.saldo_deductions;
alter publication supabase_realtime add table public.expenses;
alter publication supabase_realtime add table public.sync_meta;