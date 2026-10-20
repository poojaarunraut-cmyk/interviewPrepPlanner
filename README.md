# Interview Prep Planner

Aggregates prep content (YouTube playlists, GitHub sheets, CSV) into one deduplicated catalogue
and generates a personalised day-by-day plan across DSA, LLD, HLD and behavioral rounds.

## Stack

Java 21, Spring Boot, PostgreSQL 16, Flyway, Testcontainers, GitHub Actions.

## Run locally

Requires Docker Desktop and Java 21.

```bash
docker compose up -d                 # PostgreSQL on localhost:5432
cd backend && ./mvnw spring-boot:run # Flyway applies migrations on startup
curl localhost:8080/api/topics       # topics in learning order
curl localhost:8080/actuator/health
```

Run tests (starts a throwaway PostgreSQL in Docker): `cd backend && ./mvnw verify`

## Week 1 checklist

- [x] Schema: users, profile, topics DAG, canonical problems, sources/resources, merge audit, versioned plans, attempts, SM-2 state, STAR stories, jobs
- [x] Backend skeleton with Flyway, health endpoint, topics API, Testcontainers tests
- [x] GitHub Actions: build + tests on every push
- [ ] Google sign-in, `users` + `user_profiles` endpoints
- [ ] Frontend skeleton: sign-in, onboarding form
- [ ] Seed `problems` from the sheet you are currently following (titles, slugs, difficulty, links only)

## Design notes

- Only links and metadata are stored; no LeetCode problem text.
- `resources (source_id, external_id)` is unique, so re-imports are idempotent.
- Every match is logged in `merge_events`, so a wrong merge can be undone.
- Plans are versioned; a replan writes a new version instead of editing the old one.
