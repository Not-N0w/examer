-- Поиск билетов конкретного экзамена.
CREATE INDEX IF NOT EXISTS idx_card_exam_id
    ON card (exam_id, id);

-- Поиск статистики подготовки по конкретному билету.
CREATE INDEX IF NOT EXISTS idx_card_progress_card
    ON card_progress (card_id);

-- Получение уведомлений пользователя от новых к старым.
CREATE INDEX IF NOT EXISTS idx_notification_user_created
    ON notification (user_id, created_at DESC);

-- Получение заметок пользователя по конкретному билету.
CREATE INDEX IF NOT EXISTS idx_note_card_user_created
    ON note (card_id, user_id, created_at DESC);

-- Получение истории ответов пользователя на конкретный билет.
CREATE INDEX IF NOT EXISTS idx_card_answer_user_card_date
    ON card_answer (user_id, card_id, answered_at DESC);