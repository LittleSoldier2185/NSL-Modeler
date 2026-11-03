-- ตัวอย่างสำหรับทดสอบ "นำเข้าจากไฟล์ .sql" (PostgreSQL)
-- ระบบบล็อก: SERIAL / BIGSERIAL, ชนิดข้อมูลเฉพาะ Postgres, COMMENT ON, FK ผ่าน ALTER TABLE

CREATE TABLE authors (
    id          SERIAL PRIMARY KEY,
    username    VARCHAR(50)  NOT NULL UNIQUE,
    email       VARCHAR(255) NOT NULL,
    bio         TEXT,
    created_at  TIMESTAMP    NOT NULL DEFAULT now()
);

CREATE TABLE posts (
    id           BIGSERIAL PRIMARY KEY,
    author_id    INTEGER      NOT NULL,
    title        VARCHAR(200) NOT NULL,
    slug         VARCHAR(220) NOT NULL,
    body         TEXT         NOT NULL,
    published    BOOLEAN      NOT NULL DEFAULT false,
    views        INTEGER      NOT NULL DEFAULT 0,
    published_at TIMESTAMP
);

CREATE TABLE tags (
    id    SERIAL PRIMARY KEY,
    name  VARCHAR(40) NOT NULL UNIQUE
);

CREATE TABLE post_tags (
    post_id BIGINT  NOT NULL,
    tag_id  INTEGER NOT NULL,
    PRIMARY KEY (post_id, tag_id)
);

CREATE TABLE comments (
    id         BIGSERIAL PRIMARY KEY,
    post_id    BIGINT  NOT NULL,
    parent_id  BIGINT,
    author_id  INTEGER,
    body       TEXT    NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

ALTER TABLE posts
    ADD CONSTRAINT fk_posts_author FOREIGN KEY (author_id) REFERENCES authors (id) ON DELETE CASCADE;

ALTER TABLE post_tags
    ADD CONSTRAINT fk_post_tags_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE;

ALTER TABLE post_tags
    ADD CONSTRAINT fk_post_tags_tag FOREIGN KEY (tag_id) REFERENCES tags (id) ON DELETE CASCADE;

ALTER TABLE comments
    ADD CONSTRAINT fk_comments_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE;

ALTER TABLE comments
    ADD CONSTRAINT fk_comments_parent FOREIGN KEY (parent_id) REFERENCES comments (id) ON DELETE SET NULL;

ALTER TABLE comments
    ADD CONSTRAINT fk_comments_author FOREIGN KEY (author_id) REFERENCES authors (id) ON DELETE SET NULL;

CREATE UNIQUE INDEX uq_posts_slug ON posts (slug);
CREATE INDEX idx_posts_author_published ON posts (author_id, published_at);
CREATE INDEX idx_comments_post ON comments (post_id);

COMMENT ON TABLE posts IS 'บทความ';
COMMENT ON COLUMN posts.slug IS 'ชื่อสำหรับ URL ต้องไม่ซ้ำ';
COMMENT ON COLUMN comments.parent_id IS 'ตอบกลับคอมเมนต์อื่น (self-reference)';
