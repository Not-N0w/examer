-- Examer: дополнительные синтетические данные для проверки индексов.
-- Запускать ОДИН РАЗ после db/init.sql, db/triggers.sql,
-- db/functions.sql и db/test-data/test-data.sql.
-- Исходные 10 пользователей, 5 экзаменов и 50 карточек не удаляются и не изменяются.

BEGIN;

-- 1) Добавляем 200 пользователей для нагрузочного сценария.
INSERT INTO users (login, email, password_hash)
SELECT
    'bench_user_' || g,
    'bench_user_' || g || '@example.test',
    'benchmark_hash'
FROM generate_series(1, 200) AS gs(g);

-- 2) Создаём 20 дополнительных экзаменов. Владельцем каждого становится
-- первый пользователь соответствующей группы из 10 человек; ниже ему же
-- будет назначена роль OWNER в exam_member.
CREATE TEMP TABLE bench_exams ON COMMIT DROP AS
WITH numbered_users AS (
    SELECT id, row_number() OVER (ORDER BY id) AS rn
    FROM users
    WHERE login LIKE 'bench_user_%'
), source_exams AS (
    SELECT
        g AS exam_no,
        u.id AS owner_id
    FROM generate_series(1, 20) AS gs(g)
    JOIN numbered_users u ON u.rn = (g - 1) * 10 + 1
), inserted AS (
    INSERT INTO exam (title, description, exam_date, owner_id)
    SELECT
        'BENCH Exam ' || exam_no,
        'Synthetic exam for index benchmarking',
        CURRENT_DATE + 30,
        owner_id
    FROM source_exams
    RETURNING id, title, owner_id
)
SELECT
    id AS exam_id,
    owner_id,
    substring(title FROM '[0-9]+$')::integer AS exam_no
FROM inserted;

-- 3) В каждый экзамен добавляем 10 участников: владельца и 9 участников.
-- Участники распределены по 20 непересекающимся группам по 10 пользователей.
INSERT INTO exam_member (user_id, exam_id, role, priority)
SELECT
    u.id,
    e.exam_id,
    CASE WHEN u.rn = (e.exam_no - 1) * 10 + 1 THEN 'OWNER' ELSE 'MEMBER' END,
    e.exam_no
FROM bench_exams e
JOIN (
    SELECT id, row_number() OVER (ORDER BY id) AS rn
    FROM users
    WHERE login LIKE 'bench_user_%'
) u ON u.rn BETWEEN (e.exam_no - 1) * 10 + 1 AND e.exam_no * 10;

-- 4) Создаём 500 карточек в каждом новом экзамене: всего 10 000 карточек.
-- Автор каждой карточки — владелец соответствующего экзамена.
INSERT INTO card (exam_id, author_id, question, answer)
SELECT
    e.exam_id,
    e.owner_id,
    'Benchmark question ' || n || ' for exam ' || e.exam_no,
    'Benchmark answer ' || n
FROM bench_exams e
CROSS JOIN generate_series(1, 500) AS gs(n);

-- 5) Создаём прогресс каждого из 10 участников по каждой карточке своего экзамена:
-- 20 экзаменов * 10 участников * 500 карточек = 100 000 строк.
INSERT INTO card_progress (user_id, card_id, coef, next_review)
SELECT
    em.user_id,
    c.id,
    ((c.id % 10)::numeric / 10),
    CASE
        WHEN c.id % 5 = 0 THEN NULL
        ELSE CURRENT_DATE + (c.id % 14)::integer
    END
FROM bench_exams e
JOIN exam_member em ON em.exam_id = e.exam_id
JOIN card c ON c.exam_id = e.exam_id;

-- 6) Добавляем по одной личной заметке на каждую новую карточку: 10 000 строк.
-- Заметки создаёт владелец экзамена, который является его активным участником.
INSERT INTO note (card_id, user_id, text, status)
SELECT
    c.id,
    e.owner_id,
    'Benchmark note for card ' || c.id,
    'LOCAL'
FROM bench_exams e
JOIN card c ON c.exam_id = e.exam_id;

-- 7) Добавляем по 500 уведомлений каждому из 200 тестовых пользователей:
-- всего 100 000 уведомлений.
INSERT INTO notification (user_id, type, text, created_at)
SELECT
    u.id,
    CASE WHEN n % 2 = 0 THEN 'REMINDER' ELSE 'AT_RISK' END,
    'Benchmark notification ' || n,
    CURRENT_TIMESTAMP - (n || ' minutes')::interval
FROM users u
JOIN LATERAL generate_series(1, 500) AS gs(n) ON TRUE
WHERE u.login LIKE 'bench_user_%';

COMMIT;

-- Обновляем статистику планировщика PostgreSQL после массовой вставки.
ANALYZE users;
ANALYZE exam;
ANALYZE exam_member;
ANALYZE card;
ANALYZE card_progress;
ANALYZE note;
ANALYZE notification;

-- Контрольные количества после загрузки.
SELECT 'users' AS table_name, COUNT(*) AS rows_count FROM users
UNION ALL SELECT 'exam', COUNT(*) FROM exam
UNION ALL SELECT 'card', COUNT(*) FROM card
UNION ALL SELECT 'card_progress', COUNT(*) FROM card_progress
UNION ALL SELECT 'note', COUNT(*) FROM note
UNION ALL SELECT 'notification', COUNT(*) FROM notification
ORDER BY table_name;
