-- BikeNav: initial database schema for Supabase
--
-- One schema per database box in the architecture diagram:
--   location   -> User Location DB  (owned by the Location Service)
--   navigation -> Road Segment DB   (owned by the Navigation Service)
--   account    -> user profiles + bike specs (no box in the diagram yet)
--
-- Emails and passwords live in Supabase Auth (auth.users), never in these tables.
-- Only the backend talks to these tables. The Flutter app goes through the backend.

create extension if not exists postgis with schema extensions;

create schema if not exists account;
create schema if not exists location;
create schema if not exists navigation;


-- ===================== account =====================

create table account.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null,
  role        text not null default 'user' check (role in ('user', 'moderator')),
  created_at  timestamptz not null default now()
);

-- Mirrors BikeProfile in lib/main.dart (one bike per user, same as the app today)
create table account.bike_profiles (
  user_id         uuid primary key references account.profiles (id) on delete cascade,
  name            text not null,
  type            text not null,
  is_electric     boolean not null default false,
  electric_class  smallint check (electric_class between 1 and 3),
  updated_at      timestamptz not null default now(),
  -- same rule as the form: e-bikes need a class, regular bikes have none
  constraint electric_class_matches check (
    (is_electric and electric_class is not null)
    or (not is_electric and electric_class is null)
  )
);


-- ===================== location =====================

create table location.user_locations (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references auth.users (id) on delete cascade,
  coords       extensions.geography(point, 4326) not null,
  recorded_at  timestamptz not null default now()
);

create index user_locations_user_time_idx
  on location.user_locations (user_id, recorded_at desc);


-- ===================== navigation =====================

-- Mirrors the path saved in lib/screens/add_path.dart
create table navigation.community_routes (
  id            bigint generated always as identity primary key,
  -- set null (not cascade) so verified routes survive if their author deletes their account
  submitted_by  uuid references auth.users (id) on delete set null,
  start_name    text not null,
  end_name      text not null,
  start_point   extensions.geography(point, 4326) not null,
  end_point     extensions.geography(point, 4326) not null,
  path          extensions.geography(linestring, 4326) not null,
  description   text not null default '',
  status        text not null default 'pending'
                check (status in ('pending', 'verified', 'rejected')),
  created_at    timestamptz not null default now(),
  reviewed_at   timestamptz
);

create index community_routes_path_idx
  on navigation.community_routes using gist (path);
create index community_routes_status_idx
  on navigation.community_routes (status);

-- Confirmations from users and moderators.
-- The primary key allows one vote per user per route.
create table navigation.route_reviews (
  route_id    bigint not null references navigation.community_routes (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  verdict     text not null check (verdict in ('confirm', 'reject')),
  created_at  timestamptz not null default now(),
  primary key (route_id, user_id)
);

create index route_reviews_user_idx on navigation.route_reviews (user_id);


-- ===================== lock down the auto-generated API =====================
-- These schemas aren't exposed to Supabase's Data API unless someone adds them in
-- the API settings. RLS with no policies is a second lock: if they ever get exposed,
-- the public key still can't read or write anything. The backend connects as the
-- table owner, so it isn't affected.

alter table account.profiles          enable row level security;
alter table account.bike_profiles     enable row level security;
alter table location.user_locations   enable row level security;
alter table navigation.community_routes enable row level security;
alter table navigation.route_reviews  enable row level security;