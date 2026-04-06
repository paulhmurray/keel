CREATE TABLE IF NOT EXISTS inbox_items (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_id   UUID,  -- nullable: mobile may not know which project
    source       TEXT NOT NULL DEFAULT 'mobile_note',
    content      TEXT NOT NULL,
    image_data   BYTEA,  -- base64-decoded photo bytes, nullable
    caption      TEXT,
    status       TEXT NOT NULL DEFAULT 'pending',  -- pending | accepted | rejected
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS inbox_items_user_status_idx ON inbox_items(user_id, status);
