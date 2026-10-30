-- Portfolio tier: a portfolio links programmes the way a programme links
-- projects. Widen the link-kind CHECKs so a side may be 'portfolio'.
-- Pairing rules (adjacent tiers only) are enforced in the handler.
--
-- Migrations re-run on EVERY server start (no tracking table), so this
-- must be idempotent: drop whatever CHECK currently guards each column
-- (by definition, not by assumed name), then add the widened one.
DO $$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'programme_links'::regclass
      AND contype = 'c'
      AND (pg_get_constraintdef(oid) LIKE '%side_a_kind%'
           OR pg_get_constraintdef(oid) LIKE '%side_b_kind%')
  LOOP
    EXECUTE format('ALTER TABLE programme_links DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE programme_links
    ADD CONSTRAINT programme_links_side_a_kind_check
    CHECK (side_a_kind IN ('project', 'programme', 'portfolio'));
ALTER TABLE programme_links
    ADD CONSTRAINT programme_links_side_b_kind_check
    CHECK (side_b_kind IS NULL OR side_b_kind IN ('project', 'programme', 'portfolio'));
