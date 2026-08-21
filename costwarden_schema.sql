-- =========================================================
-- CostWarden — Supabase / PostgreSQL schema
-- MVP scope: auth (built-in Supabase Auth) + org + upload +
-- mapping + validation + findings + contracts + reports
-- =========================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------
-- ORGANIZATIONS
-- ---------------------------------------------------------
create table organizations (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  industry      text,
  locations_count integer default 1,
  created_at    timestamptz not null default now()
);

-- Extends Supabase auth.users with org membership + role
create table org_members (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references organizations(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  role          text not null default 'owner' check (role in ('owner','admin','viewer')),
  created_at    timestamptz not null default now(),
  unique (org_id, user_id)
);

-- ---------------------------------------------------------
-- UPLOADS  (one row per CSV/XLSX file a customer sends in)
-- ---------------------------------------------------------
create table uploads (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references organizations(id) on delete cascade,
  filename        text not null,
  storage_path    text not null,               -- path in Supabase Storage bucket 'uploads'
  file_size_bytes bigint,
  row_count       integer,
  status          text not null default 'uploaded'
                  check (status in ('uploaded','mapping','mapped','validating','validated','analyzing','analyzed','failed')),
  uploaded_by     uuid references auth.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- Which source column maps to which system field, per upload
create table column_mappings (
  id             uuid primary key default gen_random_uuid(),
  upload_id      uuid not null references uploads(id) on delete cascade,
  source_column  text not null,                 -- header text as it appeared in the file
  target_field   text not null,                  -- system field, e.g. 'supplier_name'
  created_at     timestamptz not null default now(),
  unique (upload_id, target_field)
);

-- Canonical list of system fields the mapping UI offers.
-- Kept as a lookup table so we can extend without a migration.
create table system_fields (
  key          text primary key,                -- e.g. 'supplier_name'
  label        text not null,                    -- e.g. 'Supplier name'
  required     boolean not null default false,
  data_type    text not null default 'text'      -- text | number | date
);

insert into system_fields (key, label, required, data_type) values
  ('supplier_name', 'Supplier name', true,  'text'),
  ('invoice_date',  'Invoice date',  true,  'date'),
  ('invoice_number','Invoice number', false, 'text'),
  ('unit_price',    'Unit price',    true,  'number'),
  ('quantity',      'Quantity',      false, 'number'),
  ('amount',        'Total amount',  true,  'number'),
  ('currency',      'Currency',      false, 'text'),
  ('category',      'Cost category', false, 'text'),
  ('contract_id',   'Contract reference', false, 'text'),
  ('location',      'Location / cost center', false, 'text');

-- Raw parsed rows, one JSON blob per row + validation outcome
create table raw_rows (
  id                 uuid primary key default gen_random_uuid(),
  upload_id          uuid not null references uploads(id) on delete cascade,
  row_number         integer not null,
  data               jsonb not null,             -- mapped {target_field: value}
  validation_status  text not null default 'pending'
                     check (validation_status in ('pending','valid','error')),
  validation_errors  jsonb,                       -- [{field, message}]
  created_at         timestamptz not null default now()
);
create index idx_raw_rows_upload on raw_rows(upload_id);
create index idx_raw_rows_status on raw_rows(upload_id, validation_status);

-- ---------------------------------------------------------
-- SUPPLIERS / CONTRACTS  (built up from analyzed uploads)
-- ---------------------------------------------------------
create table suppliers (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null references organizations(id) on delete cascade,
  name           text not null,
  category       text,
  risk_level     text default 'ok' check (risk_level in ('ok','watch','high')),
  annual_spend   numeric,
  last_flagged_at timestamptz,
  created_at     timestamptz not null default now(),
  unique (org_id, name)
);

create table contracts (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null references organizations(id) on delete cascade,
  supplier_id      uuid references suppliers(id) on delete set null,
  name             text not null,
  category         text,
  contracted_rate  numeric,
  rate_unit        text,                          -- e.g. '/unit', '/hr', '/km'
  effective_date   date,
  terms            jsonb,                          -- free-form contract terms (renewal clauses etc.)
  created_at       timestamptz not null default now()
);

-- ---------------------------------------------------------
-- FINDINGS  (the core product output)
-- ---------------------------------------------------------
create table findings (
  id                  uuid primary key default gen_random_uuid(),
  org_id              uuid not null references organizations(id) on delete cascade,
  upload_id           uuid references uploads(id) on delete set null,
  supplier_id         uuid references suppliers(id) on delete set null,
  contract_id         uuid references contracts(id) on delete set null,
  type                text not null check (type in ('price','dup','drift','rate')),
  description         text not null,               -- AI-generated narrative
  amount              numeric not null,             -- rule-engine calculated, never AI-generated
  confidence          text not null check (confidence in ('low','medium','high')),
  confidence_reason   text,                          -- why this confidence level (rule-engine)
  priority_score      numeric not null,              -- computed = f(amount, confidence)
  evidence_row_ids    uuid[] not null default '{}',  -- references raw_rows.id
  recommended_action  text,                           -- AI-generated
  status              text not null default 'new'
                      check (status in ('new','review','disputed','recovered','dismissed')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index idx_findings_org_status on findings(org_id, status);

create table finding_status_log (
  id           uuid primary key default gen_random_uuid(),
  finding_id   uuid not null references findings(id) on delete cascade,
  from_status  text,
  to_status    text not null,
  changed_by   uuid references auth.users(id),
  changed_at   timestamptz not null default now()
);

-- ---------------------------------------------------------
-- REPORTS
-- ---------------------------------------------------------
create table reports (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references organizations(id) on delete cascade,
  type          text not null,                 -- 'recovery_summary' | 'findings_detail' | 'supplier_risk'
  period_label  text not null,                 -- e.g. 'Last 30 days'
  storage_path  text,                           -- generated PDF in Storage
  generated_by  uuid references auth.users(id),
  generated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------
-- Row Level Security — every table scoped to org membership
-- ---------------------------------------------------------
alter table organizations   enable row level security;
alter table org_members     enable row level security;
alter table uploads         enable row level security;
alter table column_mappings enable row level security;
alter table raw_rows        enable row level security;
alter table suppliers       enable row level security;
alter table contracts       enable row level security;
alter table findings        enable row level security;
alter table finding_status_log enable row level security;
alter table reports         enable row level security;

create or replace function is_org_member(target_org uuid)
returns boolean language sql stable as $$
  select exists (
    select 1 from org_members
    where org_id = target_org and user_id = auth.uid()
  );
$$;

create policy "members can read their org" on organizations
  for select using (is_org_member(id));

create policy "members can read/write their org data: uploads" on uploads
  for all using (is_org_member(org_id)) with check (is_org_member(org_id));

create policy "members can read/write: column_mappings" on column_mappings
  for all using (is_org_member((select org_id from uploads where uploads.id = upload_id)))
  with check (is_org_member((select org_id from uploads where uploads.id = upload_id)));

create policy "members can read/write: raw_rows" on raw_rows
  for all using (is_org_member((select org_id from uploads where uploads.id = upload_id)))
  with check (is_org_member((select org_id from uploads where uploads.id = upload_id)));

create policy "members can read/write: suppliers" on suppliers
  for all using (is_org_member(org_id)) with check (is_org_member(org_id));

create policy "members can read/write: contracts" on contracts
  for all using (is_org_member(org_id)) with check (is_org_member(org_id));

create policy "members can read/write: findings" on findings
  for all using (is_org_member(org_id)) with check (is_org_member(org_id));

create policy "members can read: finding_status_log" on finding_status_log
  for select using (is_org_member((select org_id from findings where findings.id = finding_id)));

create policy "members can insert: finding_status_log" on finding_status_log
  for insert with check (is_org_member((select org_id from findings where findings.id = finding_id)));

create policy "members can read/write: reports" on reports
  for all using (is_org_member(org_id)) with check (is_org_member(org_id));

create policy "members can read their own membership rows" on org_members
  for select using (user_id = auth.uid());

-- ---------------------------------------------------------
-- Helper: priority_score formula (call from app/edge function)
-- priority_score = amount_weight(amount) * confidence_weight(confidence)
-- confidence_weight: high=1.0, medium=0.65, low=0.35
-- Keep this logic in the rule engine (Edge Function), not in SQL,
-- so it stays testable and versioned in application code.
-- ---------------------------------------------------------
