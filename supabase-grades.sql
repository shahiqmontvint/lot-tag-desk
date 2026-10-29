-- Lot Tag Desk: allow combined grades (run once, after the other two scripts)
-- SQL Editor -> New query -> paste -> Run. Safe to run again.
alter table public.lots drop constraint if exists lots_grade_check;
alter table public.lots add constraint lots_grade_check
  check (grade is null or grade in ('A','B','C','A/B','A/B/C','B/C'));
