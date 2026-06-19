CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email         TEXT UNIQUE NOT NULL,
    name          TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE documents (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title      TEXT NOT NULL,
    owner_id   UUID REFERENCES users(id),
    content    TEXT NOT NULL DEFAULT '',
    version    INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE doc_permissions (
    doc_id  UUID REFERENCES documents(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id)     ON DELETE CASCADE,
    role    TEXT CHECK (role IN ('owner', 'editor', 'viewer')),
    PRIMARY KEY (doc_id, user_id)
);

-- Partitioned by doc_id (hash) — satisfies partitioning requirement
CREATE TABLE operations (
    id             UUID        NOT NULL DEFAULT gen_random_uuid(),
    doc_id         UUID        NOT NULL,
    user_id        UUID,
    type           TEXT        CHECK (type IN ('insert', 'delete')),
    position       INT         NOT NULL,
    character      CHAR,
    server_version INT         NOT NULL,
    created_at     TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY HASH (doc_id);

CREATE TABLE operations_p0 PARTITION OF operations FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE operations_p1 PARTITION OF operations FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE operations_p2 PARTITION OF operations FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE operations_p3 PARTITION OF operations FOR VALUES WITH (MODULUS 4, REMAINDER 3);

CREATE TABLE audit_log (
    id         BIGSERIAL PRIMARY KEY,
    event_type TEXT NOT NULL,
    user_id    UUID,
    doc_id     UUID,
    payload    JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE metrics (
    doc_id           UUID PRIMARY KEY,
    total_ops        BIGINT NOT NULL DEFAULT 0,
    chars_inserted   BIGINT NOT NULL DEFAULT 0,
    chars_deleted    BIGINT NOT NULL DEFAULT 0,
    last_activity    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE spell_issues (
    id          BIGSERIAL PRIMARY KEY,
    doc_id      UUID NOT NULL,
    word        TEXT NOT NULL,
    position    INT  NOT NULL,
    suggestion  TEXT,
    checked_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_operations_doc_id ON operations (doc_id);
CREATE INDEX idx_audit_doc         ON audit_log (doc_id);
CREATE INDEX idx_audit_user        ON audit_log (user_id);
CREATE INDEX idx_spell_doc         ON spell_issues (doc_id);
