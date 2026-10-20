-- V1: core schema for the Interview Prep Planner (v1 scope)
-- PostgreSQL 16. Times stored in UTC (timestamptz); dates are the user's local calendar dates.

CREATE EXTENSION IF NOT EXISTS pg_trgm;   -- fuzzy title matching (dedupe stage 2)
CREATE EXTENSION IF NOT EXISTS citext;    -- case-insensitive email

-- ---------- Users and profile ----------
CREATE TABLE users (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    google_sub    text   NOT NULL UNIQUE,            -- stable Google account id
    email         citext NOT NULL UNIQUE,
    display_name  text,
    timezone      text   NOT NULL DEFAULT 'Asia/Kolkata',
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE user_profiles (
    user_id          uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    experience_years smallint NOT NULL CHECK (experience_years BETWEEN 0 AND 50),
    role             text     NOT NULL CHECK (role IN ('backend', 'frontend', 'fullstack')),
    interview_date   date,                            -- NULL = "just exploring"
    weekday_minutes  int      NOT NULL CHECK (weekday_minutes BETWEEN 0 AND 960),
    weekend_minutes  int      NOT NULL CHECK (weekend_minutes BETWEEN 0 AND 960),
    updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE companies (
    id    serial PRIMARY KEY,
    name  text NOT NULL UNIQUE,
    tier  smallint CHECK (tier BETWEEN 1 AND 3)
);

CREATE TABLE user_target_companies (
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    company_id int  NOT NULL REFERENCES companies(id),
    PRIMARY KEY (user_id, company_id)
);

-- ---------- Topics (with a prerequisite DAG) ----------
CREATE TABLE topics (
    id    serial PRIMARY KEY,
    slug  text NOT NULL UNIQUE,
    name  text NOT NULL,
    track text NOT NULL DEFAULT 'dsa' CHECK (track IN ('dsa', 'lld', 'hld', 'behavioral'))
);

CREATE TABLE topic_prerequisites (
    topic_id        int NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
    prerequisite_id int NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
    PRIMARY KEY (topic_id, prerequisite_id),
    CHECK (topic_id <> prerequisite_id)
);

CREATE TABLE user_topic_ratings (               -- self-rating at onboarding, updated by attempts
    user_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    topic_id int  NOT NULL REFERENCES topics(id),
    rating   smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
    PRIMARY KEY (user_id, topic_id)
);

-- ---------- Canonical problem catalogue (shared by all users) ----------
CREATE TABLE problems (
    id               bigserial PRIMARY KEY,
    title            text NOT NULL,
    normalized_title text NOT NULL,                  -- lowercased, noise stripped
    leetcode_slug    text UNIQUE,                    -- link only; no problem text stored
    difficulty       text CHECK (difficulty IN ('easy', 'medium', 'hard')),
    created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX problems_normalized_title_trgm ON problems USING gin (normalized_title gin_trgm_ops);

CREATE TABLE problem_topics (
    problem_id bigint NOT NULL REFERENCES problems(id) ON DELETE CASCADE,
    topic_id   int    NOT NULL REFERENCES topics(id),
    PRIMARY KEY (problem_id, topic_id)
);

-- ---------- Sources and their items ----------
CREATE TABLE sources (
    id             bigserial PRIMARY KEY,
    kind           text NOT NULL CHECK (kind IN ('youtube_playlist', 'github_sheet', 'csv')),
    external_ref   text NOT NULL,                    -- playlist id, repo path, or upload id
    title          text,
    last_synced_at timestamptz,
    UNIQUE (kind, external_ref)                      -- imported once, shared by all users
);

CREATE TABLE user_sources (
    user_id   uuid   NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_id bigint NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
    added_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, source_id)
);

CREATE TABLE resources (
    id               bigserial PRIMARY KEY,
    source_id        bigint NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
    external_id      text   NOT NULL,                -- e.g. YouTube video id
    type             text   NOT NULL CHECK (type IN ('video', 'article', 'sheet_item')),
    url              text   NOT NULL,
    title            text   NOT NULL,
    description      text,
    position         int,
    problem_id       bigint REFERENCES problems(id) ON DELETE SET NULL,
    match_stage      text CHECK (match_stage IN ('slug', 'trigram', 'llm', 'manual')),
    match_confidence numeric(4,3) CHECK (match_confidence BETWEEN 0 AND 1),
    status           text NOT NULL DEFAULT 'unmatched'
                     CHECK (status IN ('matched', 'pending_review', 'unmatched', 'removed')),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source_id, external_id),                 -- idempotent re-imports
    CHECK ((status = 'matched') = (problem_id IS NOT NULL))
);
CREATE INDEX resources_problem_idx ON resources (problem_id);
CREATE INDEX resources_review_idx  ON resources (status) WHERE status = 'pending_review';

-- Every match/unmatch is recorded so wrong merges can be audited and undone.
CREATE TABLE merge_events (
    id              bigserial PRIMARY KEY,
    resource_id     bigint NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
    from_problem_id bigint REFERENCES problems(id),
    to_problem_id   bigint REFERENCES problems(id),
    stage           text NOT NULL CHECK (stage IN ('slug', 'trigram', 'llm', 'manual', 'undo')),
    confidence      numeric(4,3),
    actor           text NOT NULL,                   -- 'system' or a user id
    created_at      timestamptz NOT NULL DEFAULT now()
);

-- ---------- Plans (versioned) ----------
CREATE TABLE plans (
    id           bigserial PRIMARY KEY,
    user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    version      int  NOT NULL,
    reason       text NOT NULL CHECK (reason IN ('initial', 'missed_days', 'low_confidence', 'date_changed', 'manual')),
    generated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, version)
);

CREATE TABLE plan_items (
    id             bigserial PRIMARY KEY,
    plan_id        bigint NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
    scheduled_date date   NOT NULL,
    track          text   NOT NULL CHECK (track IN ('dsa', 'lld', 'hld', 'behavioral', 'revision')),
    problem_id     bigint REFERENCES problems(id),
    topic_id       int    REFERENCES topics(id),
    est_minutes    int    NOT NULL CHECK (est_minutes > 0),
    status         text   NOT NULL DEFAULT 'planned'
                   CHECK (status IN ('planned', 'done', 'skipped', 'carried_over')),
    CHECK (problem_id IS NOT NULL OR topic_id IS NOT NULL)
);
CREATE INDEX plan_items_day_idx ON plan_items (plan_id, scheduled_date);

-- ---------- Tracking and revision ----------
CREATE TABLE attempts (
    id              bigserial PRIMARY KEY,
    user_id         uuid   NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    problem_id      bigint NOT NULL REFERENCES problems(id),
    solved_at       timestamptz NOT NULL DEFAULT now(),
    minutes         int CHECK (minutes > 0),
    confidence      smallint NOT NULL CHECK (confidence BETWEEN 1 AND 5),
    note            text,
    origin          text NOT NULL DEFAULT 'manual' CHECK (origin IN ('manual', 'extension')),
    client_event_id uuid UNIQUE                      -- idempotency key from web app / extension
);
CREATE INDEX attempts_user_problem_idx ON attempts (user_id, problem_id, solved_at DESC);

CREATE TABLE review_schedules (                   -- SM-2 state per user per problem
    user_id       uuid   NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    problem_id    bigint NOT NULL REFERENCES problems(id),
    ease_factor   numeric(4,2) NOT NULL DEFAULT 2.50 CHECK (ease_factor >= 1.30),
    interval_days int NOT NULL DEFAULT 0 CHECK (interval_days >= 0),
    repetitions   int NOT NULL DEFAULT 0 CHECK (repetitions >= 0),
    next_due      date NOT NULL,
    PRIMARY KEY (user_id, problem_id)
);
CREATE INDEX review_due_idx ON review_schedules (user_id, next_due);

CREATE TABLE star_stories (
    id           bigserial PRIMARY KEY,
    user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title        text NOT NULL,
    competencies text[] NOT NULL DEFAULT '{}',
    situation    text,
    task         text,
    action       text,
    result       text,
    updated_at   timestamptz NOT NULL DEFAULT now()
);

-- ---------- Background jobs (claimed with FOR UPDATE SKIP LOCKED) ----------
CREATE TABLE jobs (
    id         bigserial PRIMARY KEY,
    type       text NOT NULL CHECK (type IN ('import_source', 'match_resources', 'replan_user')),
    payload    jsonb NOT NULL DEFAULT '{}',
    run_at     timestamptz NOT NULL DEFAULT now(),
    status     text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'done', 'failed')),
    attempts   int  NOT NULL DEFAULT 0,
    last_error text,
    locked_at  timestamptz
);
CREATE INDEX jobs_ready_idx ON jobs (run_at) WHERE status = 'queued';
