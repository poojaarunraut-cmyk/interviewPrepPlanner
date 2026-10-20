# Interview Prep Planner

Aggregates prep content (YouTube playlists, GitHub sheets, CSV) into one deduplicated catalogue
and generates a personalised day-by-day plan across DSA, LLD, HLD and behavioral rounds.

## Run the database locally

```bash
docker compose up -d
psql postgresql://prep:prep_local_only@localhost:5432/prep_planner -c '\dt'
```

Migrations in `db/migration` run automatically on the first start (`V1__init.sql`, `V2__seed_topics.sql`).
They use Flyway naming, so the backend can take them over later. To re-run from scratch: `docker compose down -v`.

## Week 1 checklist

- [x] Schema: users, profile, topics DAG, canonical problems, sources/resources, merge audit, versioned plans, attempts, SM-2 state, STAR stories, jobs
- [ ] Backend skeleton with Flyway, health endpoint, Testcontainers test that runs the migrations
- [ ] Google sign-in, `users` + `user_profiles` endpoints
- [ ] Frontend skeleton: sign-in, onboarding form
- [ ] GitHub Actions: build + tests on every push
- [ ] Seed `problems` from the sheet you are currently following (titles, slugs, difficulty, links only)

## Design notes

- Only links and metadata are stored; no LeetCode problem text.
- `resources (source_id, external_id)` is unique, so re-imports are idempotent.
- Every match is logged in `merge_events`, so a wrong merge can be undone.
- Plans are versioned; a replan writes a new version instead of editing the old one.
