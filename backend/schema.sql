-- Dedicated schema: no conversation text or unrelated app tables.
CREATE SCHEMA IF NOT EXISTS little_focus;
CREATE TABLE IF NOT EXISTS little_focus.quotas (
  scope text NOT NULL, period text NOT NULL, count integer NOT NULL,
  PRIMARY KEY (scope, period)
);
CREATE OR REPLACE FUNCTION little_focus.reserve_quota(entries jsonb) RETURNS boolean
LANGUAGE plpgsql AS $$
DECLARE entry jsonb; current_count integer;
BEGIN
  -- A transaction-scoped project lock serializes reservations across all function instances.
  PERFORM pg_advisory_xact_lock(74019826);
  FOR entry IN SELECT value FROM jsonb_array_elements(entries) LOOP
    SELECT count INTO current_count FROM little_focus.quotas
      WHERE scope = entry->>'scope' AND period = entry->>'period';
    IF COALESCE(current_count, 0) >= (entry->>'limit')::integer THEN RETURN false; END IF;
  END LOOP;
  FOR entry IN SELECT value FROM jsonb_array_elements(entries) LOOP
    INSERT INTO little_focus.quotas(scope, period, count)
      VALUES(entry->>'scope', entry->>'period', 1)
      ON CONFLICT (scope, period) DO UPDATE SET count = little_focus.quotas.count + 1;
  END LOOP;
  -- Remove expired counters only; retain two days to tolerate in-flight boundary requests.
  DELETE FROM little_focus.quotas WHERE
    (period LIKE 'minute:%' AND substring(period FROM 8)::bigint < floor(extract(epoch FROM now()) / 60) - 2880)
    OR (period LIKE 'day:%' AND substring(period FROM 5)::bigint < floor(extract(epoch FROM now()) / 86400) - 2);
  RETURN true;
END;
$$;
