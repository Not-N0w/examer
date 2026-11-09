create or replace function user_today(p_user_id bigint) returns date as $$
    select (now() at time zone timezone)::date from users where id = p_user_id;
$$ language sql;

create or replace function submit_change_request(p_cr_id bigint, p_moderator_id bigint) returns void as $$
declare
    v_card_id bigint;
    v_exam_id bigint;
    v_note_id bigint;
    v_new_answer text;
    v_status varchar;
begin
    select cr.card_id, c.exam_id, cr.note_id, cr.new_answer, cr.status
    into v_card_id, v_exam_id, v_note_id, v_new_answer, v_status
    from change_request cr
    join card c on c.id = cr.card_id
    where cr.id = p_cr_id;

    if not found then
        raise exception 'Change request % not found', p_cr_id;
    end if;

    if v_status <> 'PENDING' then
        raise exception 'Change request % is already %', p_cr_id, v_status;
    end if;

    if (select stage from exam where id = v_exam_id) = 'FINISHED' then
        raise exception 'Cannot accept change request: exam is FINISHED';
    end if;

    update change_request
    set status = 'ACCEPTED',
        moderator_id = p_moderator_id,
        reviewed_at = now()
    where id = p_cr_id;

    update card
    set answer = v_new_answer,
        is_fixed = true
    where id = v_card_id;

    update card_progress
    set coef = 0,
        next_review = null
    where card_id = v_card_id;

    if v_note_id is not null then
        delete from note where id = v_note_id;
    end if;
end;  -- rebuild after?
$$ language plpgsql;


create or replace function reject_change_request(p_cr_id bigint, p_moderator_id bigint) returns void as $$
declare
    v_note_id bigint;
    v_status varchar;
begin
    select note_id, status into v_note_id, v_status
    from change_request
    where id = p_cr_id;

    if not found then
        raise exception 'Change request % not found', p_cr_id;
    end if;

    if v_status <> 'PENDING' then
        raise exception 'Change request % is already %', p_cr_id, v_status;
    end if;

    update change_request
    set status = 'REJECTED',
        moderator_id = p_moderator_id,
        reviewed_at = now()
    where id = p_cr_id;

    if v_note_id is not null then
        update note set status = 'LOCAL' where id = v_note_id;
    end if;
end;  -- rebuild after?
$$ language plpgsql;



create or replace function join_exam(p_user_id bigint, p_invite_code varchar) returns bigint as $$
declare
    v_exam_id bigint;
    v_priority int;
begin
    select id into v_exam_id from exam where invite_code = p_invite_code;
 
    if v_exam_id is null then
        raise exception 'Invalid invite code';
    end if;
 
    if exists (select 1 from exam_member where user_id = p_user_id and exam_id = v_exam_id) then
        raise exception 'User % is already a member or blocked in exam %', p_user_id, v_exam_id;
    end if;
 
    select coalesce(max(priority), 0) + 1 into v_priority from exam_member where user_id = p_user_id;
 
    insert into exam_member (user_id, exam_id, priority) values (p_user_id, v_exam_id, v_priority);
 
    insert into card_progress (user_id, card_id)
    select p_user_id, id from card where exam_id = v_exam_id;
  
    return v_exam_id;
end; -- rebuild after?
$$ language plpgsql;


create or replace function submit_answer(p_user_id bigint, p_card_id bigint, p_grade numeric) returns void as $$
declare
    v_coef numeric;
begin
    insert into card_answer (user_id, card_id, grade) values (p_user_id, p_card_id, p_grade);
 
    select coef into v_coef from card_progress where user_id = p_user_id and card_id = p_card_id;
 
    v_coef := round(0.6 * v_coef + 0.4 * p_grade, 3);
 
    update card_progress
    set coef = v_coef,
        next_review = user_today(p_user_id) + case
            when v_coef < 0.3 then 1
            when v_coef < 0.6 then 3
            when v_coef < 0.85 then 7
            else 14
        end
    where user_id = p_user_id and card_id = p_card_id;
end;
$$ language plpgsql;


create or replace function push_note_as_change_request(p_note_id bigint) returns bigint as $$
declare
    v_card_id bigint;
    v_user_id bigint;
    v_text text;
    v_status varchar;
    v_answer text;
    v_stage varchar;
    v_cr_id bigint;
begin
    select card_id, user_id, text, status into v_card_id, v_user_id, v_text, v_status
    from note
    where id = p_note_id;

    if not found then
        raise exception 'Note % not found', p_note_id;
    end if;

    if v_status <> 'LOCAL' then
        raise exception 'Note % is already %', p_note_id, v_status;
    end if;

    select c.answer, e.stage into v_answer, v_stage
    from card c
    join exam e on e.id = c.exam_id
    where c.id = v_card_id;

    if v_stage = 'FINISHED' then
        raise exception 'Cannot push note as change request: exam is FINISHED';
    end if;

    update change_request set note_id = null where note_id = p_note_id;

    insert into change_request (card_id, author_id, note_id, new_answer)
    values (v_card_id, v_user_id, p_note_id, concat_ws(E'\n\n', v_answer, v_text))
    returning id into v_cr_id;

    update note set status = 'PROPOSED' where id = p_note_id;

    return v_cr_id;
end;
$$ language plpgsql;