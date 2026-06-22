-- Programme ↔ project links. Each row represents ONE logical link
-- between two entities on (potentially different) Keel installs. The
-- shared `code` is the bearer token both parties exchange off-band.
--
-- Either party can be "side_a" or "side_b" — whoever lands on the
-- server first via PUT /links/:code/me is side_a, the second is
-- side_b. Both are required to be different users. Once both sides
-- are populated, [activated_at] is set and subsequent reads see an
-- active link.
--
-- Entity identifiers (entity_id, kind, name) are stored in plaintext
-- to allow each party to display the other side's identity without a
-- round trip. This matches the existing privacy posture where the
-- server already knows project ids and names via /projects.

CREATE TABLE IF NOT EXISTS programme_links (
    code              TEXT PRIMARY KEY,

    side_a_user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    side_a_entity_id  TEXT NOT NULL,
    side_a_kind       TEXT NOT NULL CHECK (side_a_kind IN ('project', 'programme')),
    side_a_name       TEXT NOT NULL,

    side_b_user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
    side_b_entity_id  TEXT,
    side_b_kind       TEXT CHECK (side_b_kind IS NULL OR side_b_kind IN ('project', 'programme')),
    side_b_name       TEXT,

    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    activated_at      TIMESTAMPTZ
);

-- Each party can quickly enumerate the links they're part of from
-- either side. Used by future polling + cascade routing.
CREATE INDEX IF NOT EXISTS programme_links_side_a_user_idx
    ON programme_links(side_a_user_id);
CREATE INDEX IF NOT EXISTS programme_links_side_b_user_idx
    ON programme_links(side_b_user_id)
    WHERE side_b_user_id IS NOT NULL;
