-- password: admin123  (bcrypt, verified)
INSERT INTO users (email, name, password_hash)
VALUES ('admin@collabdocs.dev', 'Admin CollabDocs',
        '$2b$10$B1jGAZtPPpAYdVBvqmwAbO//0HuOQtTXoa88YNncl/qNl79veVBFG')
ON CONFLICT DO NOTHING;
