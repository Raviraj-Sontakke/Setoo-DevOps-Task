CREATE TABLE IF NOT EXISTS tasks (
    id        SERIAL PRIMARY KEY,
    title     VARCHAR(255) NOT NULL,
    completed BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP   NOT NULL DEFAULT NOW()
);

INSERT INTO tasks (title, completed) VALUES
    ('Setup AKS cluster', true),
    ('Configure CI/CD pipeline', false),
    ('Deploy Airflow', false);
