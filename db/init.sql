CREATE TABLE users (
    id bigserial PRIMARY KEY,
    login varchar(50) NOT NULL UNIQUE,
    email varchar(255) NOT NULL UNIQUE,
    password_hash varchar(255) NOT NULL,
    timezone varchar(64) NOT NULL DEFAULT 'Europe/Moscow',
    avatar_object_key varchar(255),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT users_login_not_blank CHECK (length(btrim(login)) > 0)
);

CREATE TABLE exam (
    id bigserial PRIMARY KEY,
    title varchar(200) NOT NULL,
    description text,
    exam_date date NOT NULL,
    stage varchar(20) NOT NULL DEFAULT 'FILLING',
    -- FILLING / STUDYING / FINISHED
    invite_code varchar(32) NOT NULL UNIQUE DEFAULT substring(md5(random()::text), 1, 32),
    owner_id bigint NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT exam_title_not_blank CHECK (length(btrim(title)) > 0),
    CONSTRAINT exam_stage_values CHECK (stage IN ('FILLING', 'STUDYING', 'FINISHED'))
);

CREATE TABLE exam_member (
    user_id bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    exam_id bigint NOT NULL REFERENCES exam (id) ON DELETE CASCADE,
    role varchar(20) NOT NULL DEFAULT 'MEMBER',
    -- OWNER / MODERATOR / MEMBER
    priority int NOT NULL,
    is_blocked boolean NOT NULL DEFAULT false,
    is_at_risk boolean NOT NULL DEFAULT false,
    joined_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, exam_id),
    CONSTRAINT exam_member_role_values CHECK (role IN ('OWNER', 'MODERATOR', 'MEMBER')),
    CONSTRAINT exam_member_priority_pos CHECK (priority >= 0),
    CONSTRAINT exam_member_owner_not_blocked CHECK (
        NOT (
            role = 'OWNER'
            AND is_blocked
        )
    )
);

CREATE TABLE card (
    id bigserial PRIMARY KEY,
    exam_id bigint NOT NULL REFERENCES exam (id) ON DELETE CASCADE,
    author_id bigint REFERENCES users (id) ON DELETE SET NULL,
    question text NOT NULL,
    answer text,
    is_fixed boolean NOT NULL DEFAULT false,
    minutes_to_learn smallint NOT NULL DEFAULT 10,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT card_question_not_blank CHECK (length(btrim(question)) > 0),
    CONSTRAINT card_minutes_positive CHECK (minutes_to_learn > 0)
);

CREATE TABLE note (
    id bigserial PRIMARY KEY,
    card_id bigint NOT NULL REFERENCES card (id) ON DELETE CASCADE,
    user_id bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    text text NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'LOCAL',
    -- LOCAL / PROPOSED / ACCEPTED
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT note_text_not_blank CHECK (length(btrim(text)) > 0),
    CONSTRAINT note_status_values CHECK (status IN ('LOCAL', 'PROPOSED', 'ACCEPTED'))
);

CREATE TABLE change_request (
    id bigserial PRIMARY KEY,
    card_id bigint NOT NULL REFERENCES card (id) ON DELETE CASCADE,
    author_id bigint REFERENCES users (id) ON DELETE SET NULL,
    moderator_id bigint REFERENCES users (id) ON DELETE SET NULL,
    note_id bigint UNIQUE REFERENCES note (id) ON DELETE SET NULL,
    new_answer text NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    -- PENDING / ACCEPTED / REJECTED
    created_at timestamptz NOT NULL DEFAULT now(),
    reviewed_at timestamptz,
    CONSTRAINT change_request_answer_not_blank CHECK (length(btrim(new_answer)) > 0),
    CONSTRAINT change_request_status_values CHECK (status IN ('PENDING', 'ACCEPTED', 'REJECTED')),
    CONSTRAINT change_request_review_consistency CHECK (
        (
            status = 'PENDING'
            AND moderator_id IS NULL
            AND reviewed_at IS NULL
        )
        OR (
            status <> 'PENDING'
            AND reviewed_at IS NOT NULL
            AND reviewed_at >= created_at
        )
    )
);

CREATE TABLE card_progress (
    user_id bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    card_id bigint NOT NULL REFERENCES card (id) ON DELETE CASCADE,
    coef numeric(4, 3) NOT NULL DEFAULT 0,
    next_review date,
    PRIMARY KEY (user_id, card_id),
    CONSTRAINT card_progress_coef_range CHECK (
        coef BETWEEN 0
        AND 1
    )
);

CREATE TABLE card_answer (
    id bigserial PRIMARY KEY,
    user_id bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    card_id bigint NOT NULL REFERENCES card (id) ON DELETE CASCADE,
    grade numeric(3, 2) NOT NULL,
    answered_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT card_answer_grade_range CHECK (
        grade BETWEEN 0
        AND 1
    )
);

CREATE TABLE study_day (
    id bigserial PRIMARY KEY,
    user_id bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    day date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    -- PLANNED / DONE / MISSED / DAY_OFF
    CONSTRAINT study_day_user_day_uq UNIQUE (user_id, day),
    CONSTRAINT study_day_status_values CHECK (
        status IN ('PLANNED', 'DONE', 'MISSED', 'DAY_OFF')
    )
);

CREATE TABLE plan_item (
    id bigserial PRIMARY KEY,
    study_day_id bigint NOT NULL REFERENCES study_day (id) ON DELETE CASCADE,
    exam_id bigint NOT NULL REFERENCES exam (id) ON DELETE CASCADE,
    new_cards int NOT NULL DEFAULT 0,
    review_cards int NOT NULL DEFAULT 0,
    minutes int NOT NULL DEFAULT 0,
    is_done boolean NOT NULL DEFAULT false,
    CONSTRAINT plan_item_day_exam_uq UNIQUE (study_day_id, exam_id),
    CONSTRAINT plan_item_new_cards_nonneg CHECK (new_cards >= 0),
    CONSTRAINT plan_item_review_nonneg CHECK (review_cards >= 0),
    CONSTRAINT plan_item_minutes_range CHECK (
        minutes BETWEEN 0
        AND 1440
    )
);

CREATE TABLE notification (
    id bigserial PRIMARY KEY,
    user_id bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    type varchar(20) NOT NULL,
    -- REMINDER / AT_RISK / PLAN_REBUILT / CHANGE_ACCEPTED / CHANGE_REJECTED / CARD_FIXED
    text text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT notification_type_values CHECK (
        type IN (
            'REMINDER',
            'AT_RISK',
            'PLAN_REBUILT',
            'CHANGE_ACCEPTED',
            'CHANGE_REJECTED',
            'CARD_FIXED'
        )
    )
);
