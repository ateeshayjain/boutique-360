-- Plan 1, Task 1.2 — required Postgres extensions
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;
create extension if not exists pgsodium;
create extension if not exists pg_trgm;
