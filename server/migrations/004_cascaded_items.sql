-- Cascaded items — Phase C of programme links. The PM's machine pushes
-- structural project data (work packages first; later: escalated RAID,
-- status reports, charter, people overview) into a link channel keyed
-- by the link code. The programme manager's machine pulls the channel
-- and lands rows in their own DB with a sourceProjectId pointer.
--
-- Payload is JSON in plaintext. This is consistent with the existing
-- /projects endpoint that already stores name in plaintext — the data
-- is structural (work package names, dates, RAG status) not sensitive
-- content (no journal text, no people names, no card bodies). End-to-
-- end encryption per-link is a known follow-up.

CREATE TABLE IF NOT EXISTS cascaded_items (
    code              TEXT NOT NULL REFERENCES programme_links(code) ON DELETE CASCADE,
    source_user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_entity_id  TEXT NOT NULL,
    item_kind         TEXT NOT NULL,   -- 'work_package' for now; future: 'risk', 'status_report', ...
    item_id           TEXT NOT NULL,   -- client-side UUID of the item
    payload           JSONB NOT NULL,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at        TIMESTAMPTZ,     -- tombstone marker; pulls reconcile

    PRIMARY KEY (code, item_kind, item_id)
);

-- Incremental pulls scan by code + updated_at > since. This index
-- supports the common "give me changes since I last synced" query.
CREATE INDEX IF NOT EXISTS cascaded_items_code_updated_idx
    ON cascaded_items(code, updated_at DESC);
