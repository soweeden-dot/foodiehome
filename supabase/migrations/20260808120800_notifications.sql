-- Stream 1 · Migration 09 — notification foundation (schema only; no workers)
--
-- Three-layer design, provider-agnostic by construction:
--
--   reminder_rules            WHY a reminder exists (schedule- or event-driven)
--     └─> notifications       ONE generated message instance (channel-neutral)
--           └─> notification_deliveries   one row PER CHANNEL attempt
--
-- Rules are compact descriptions — a future worker computes "what should fire
-- now" from rules + recurrence + domain state; thousands of occurrence rows
-- are never pre-created. A notification knows nothing about Twilio; a
-- delivery row records which channel/provider carried it. Adding email or
-- dashboard announcements later = a new delivery channel, zero schema change
-- to rules or notifications. notification_preferences decides which channels
-- each member wants per category; the fan-out from notification to delivery
-- rows happens in the future worker by reading those preferences.

create type public.reminder_kind as enum ('scheduled', 'event');

-- What a reminder is about — used for grouping and per-category preferences.
create type public.notification_category as enum
  ('morning_brief', 'evening_brief', 'meal_prep', 'fermentation', 'cleaning',
   'maintenance', 'shopping', 'inventory', 'custom');

-- Event-driven trigger conditions (evaluated by a future worker against
-- domain state; config on the rule holds thresholds).
create type public.reminder_event_type as enum
  ('component_replacement_due', 'fermentation_check_due', 'starter_feed_due',
   'inventory_low', 'food_expiring', 'supply_low', 'custom');

create type public.notification_status as enum
  ('pending', 'sent', 'partially_sent', 'failed', 'canceled');

create type public.delivery_channel as enum ('push', 'sms', 'email', 'dashboard');

create type public.delivery_status as enum ('pending', 'sent', 'failed', 'skipped');

-- ---------------------------------------------------------------------------
-- reminder_rules
-- ---------------------------------------------------------------------------
create table public.reminder_rules (
  id                 uuid primary key default gen_random_uuid(),
  household_id       uuid not null references public.households (id) on delete cascade,
  name               text not null,              -- "Morning brief", "Water filter due"
  category           public.notification_category not null default 'custom',
  kind               public.reminder_kind not null,
  -- kind = 'scheduled': when to fire.
  recurrence_rule_id uuid references public.recurrence_rules (id) on delete set null,
  -- kind = 'event': which condition to watch.
  event_type         public.reminder_event_type,
  -- Rule-specific settings: {"days_before_due": 7}, {"expiring_within_days": 3},
  -- {"lead_time_hours": 12}...
  config             jsonb not null default '{}',
  -- Who receives it; null = every household member.
  recipient_user_id  uuid references public.profiles (id) on delete cascade,
  enabled            boolean not null default true,
  -- Worker bookkeeping (unused until the reminder worker stream).
  last_fired_at      timestamptz,
  next_run_at        timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  check (
    (kind = 'scheduled' and recurrence_rule_id is not null and event_type is null)
    or
    (kind = 'event' and event_type is not null)
  )
);

create index idx_reminder_rules_household
  on public.reminder_rules (household_id) where deleted_at is null;
create index idx_reminder_rules_next_run
  on public.reminder_rules (next_run_at)
  where enabled and deleted_at is null;

-- ---------------------------------------------------------------------------
-- notifications — one generated, channel-neutral message instance.
-- ---------------------------------------------------------------------------
create table public.notifications (
  id                 uuid primary key default gen_random_uuid(),
  household_id       uuid not null references public.households (id) on delete cascade,
  reminder_rule_id   uuid references public.reminder_rules (id) on delete set null,
  recipient_user_id  uuid references public.profiles (id) on delete cascade,  -- null = all members
  category           public.notification_category not null default 'custom',
  title              text not null,
  body               text not null,
  -- Structured extras: deep-link route, related record ids, brief sections...
  payload            jsonb,
  -- Guards against duplicate generation for the same logical occurrence,
  -- e.g. "morning_brief:2026-08-09" or "filter_due:<component_id>:2026-09".
  dedupe_key         text,
  scheduled_for      timestamptz not null default now(),
  status             public.notification_status not null default 'pending',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique nulls not distinct (household_id, dedupe_key)
);

create index idx_notifications_pending
  on public.notifications (scheduled_for) where status = 'pending';
create index idx_notifications_household
  on public.notifications (household_id, created_at desc);

-- ---------------------------------------------------------------------------
-- notification_deliveries — one row per channel attempt. Twilio is just a
-- provider value on an sms-channel row.
-- ---------------------------------------------------------------------------
create table public.notification_deliveries (
  id                  uuid primary key default gen_random_uuid(),
  household_id        uuid not null references public.households (id) on delete cascade,
  notification_id     uuid not null references public.notifications (id) on delete cascade,
  recipient_user_id   uuid references public.profiles (id) on delete cascade,
  channel             public.delivery_channel not null,
  provider            text,                      -- 'twilio', 'apns', ... set by the worker
  status              public.delivery_status not null default 'pending',
  provider_message_id text,
  error               text,
  attempted_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index idx_notification_deliveries_notification
  on public.notification_deliveries (notification_id);

-- ---------------------------------------------------------------------------
-- notification_preferences — per member × category × channel opt-in.
-- The fan-out worker consults this when creating delivery rows.
-- ---------------------------------------------------------------------------
create table public.notification_preferences (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  category      public.notification_category not null,
  channel       public.delivery_channel not null,
  enabled       boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (household_id, user_id, category, channel)
);

create trigger trg_reminder_rules_updated_at           before update on public.reminder_rules           for each row execute function public.set_updated_at();
create trigger trg_notifications_updated_at            before update on public.notifications            for each row execute function public.set_updated_at();
create trigger trg_notification_deliveries_updated_at  before update on public.notification_deliveries  for each row execute function public.set_updated_at();
create trigger trg_notification_preferences_updated_at before update on public.notification_preferences for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security. Members manage rules and preferences. Generated
-- notifications/deliveries are readable by members (and dismissable via
-- status), but rows are CREATED by the future worker using the service role —
-- clients cannot forge deliveries.
-- ---------------------------------------------------------------------------
alter table public.reminder_rules           enable row level security;
alter table public.notifications            enable row level security;
alter table public.notification_deliveries  enable row level security;
alter table public.notification_preferences enable row level security;

create policy reminder_rules_member_all on public.reminder_rules
  for all using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));

create policy notifications_member_select on public.notifications
  for select using (public.is_household_member(household_id));
create policy notifications_member_update on public.notifications
  for update using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));

create policy notification_deliveries_member_select on public.notification_deliveries
  for select using (public.is_household_member(household_id));

create policy notification_preferences_own_all on public.notification_preferences
  for all using (user_id = auth.uid() and public.is_household_member(household_id))
  with check (user_id = auth.uid() and public.is_household_member(household_id));
create policy notification_preferences_member_select on public.notification_preferences
  for select using (public.is_household_member(household_id));
