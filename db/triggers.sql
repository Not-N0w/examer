create or replace function check_active_member(p_user_id bigint, p_exam_id bigint) returns void as $$
begin
    if not exists (
        select 
            1 
        from exam_member
        where 
            user_id = p_user_id 
            and exam_id = p_exam_id 
            and not is_blocked
    ) then
        raise exception 'User % is not an active member of exam %', p_user_id, p_exam_id;
    end if;
end;
$$ language plpgsql;


create or replace function trg_card_check_insert() returns trigger as $$
declare
    v_stage varchar;
    v_role varchar;
begin
    select 
        stage into v_stage 
    from exam 
    where 
        id = new.exam_id;

    if v_stage = 'FINISHED' then
        raise exception 'Cannot add card to exam in FINISHED stage';
    end if;

    perform check_active_member(new.author_id, new.exam_id);

    select 
        role into v_role
    from exam_member
    where 
        user_id = new.author_id 
        and exam_id = new.exam_id;

    if v_stage = 'STUDYING' and v_role = 'MEMBER' then
        raise exception 'Only OWNER or MODERATOR can add card to exam in STUDYING stage';
    end if;

    return new;
end;
$$ language plpgsql;

drop trigger if exists card_check_insert on card;
create trigger card_check_insert
    before insert on card
    for each row
    execute function trg_card_check_insert();


create or replace function trg_exam_check_stage() returns trigger as $$
begin
    if old.stage = 'FILLING' and new.stage = 'STUDYING' then
        if (select count(*) from card where exam_id = new.id) < 10 then
            raise exception 'Exam % must have at least 10 cards to start STUDYING', new.id;
        end if;
    elsif not (old.stage = 'STUDYING' and new.stage = 'FINISHED') then
        raise exception 'Invalid stage transition % -> %', old.stage, new.stage;
    end if;

    return new;
end;
$$ language plpgsql;

drop trigger if exists exam_check_stage on exam;
create trigger exam_check_stage
    before update of stage on exam
    for each row
    execute function trg_exam_check_stage();


create or replace function trg_check_card_member() returns trigger as $$
declare
    v_user_id bigint;
begin
    if tg_table_name = 'change_request' then
        v_user_id := new.author_id;
    else
        v_user_id := new.user_id;
    end if;

    perform check_active_member(
        v_user_id, 
        (select exam_id from card where id = new.card_id)
    );

    return new;
end;
$$ language plpgsql;

drop trigger if exists note_check_member on note;
create trigger note_check_member
    before insert on note
    for each row
    execute function trg_check_card_member();

drop trigger if exists change_request_check_member on change_request;
create trigger change_request_check_member
    before insert on change_request
    for each row
    execute function trg_check_card_member();

drop trigger if exists card_answer_check_member on card_answer;
create trigger card_answer_check_member
    before insert on card_answer
    for each row
    execute function trg_check_card_member();


create or replace function trg_card_answer_check_stage() returns trigger as $$
begin
    if (select e.stage from card c join exam e on e.id = c.exam_id where c.id = new.card_id) <> 'STUDYING' then
        raise exception 'Answers are allowed only when exam is in STUDYING stage';
    end if;

    return new;
end;
$$ language plpgsql;

drop trigger if exists card_answer_check_stage on card_answer;
create trigger card_answer_check_stage
    before insert on card_answer
    for each row
    execute function trg_card_answer_check_stage();




create or replace function trg_plan_item_check() returns trigger as $$
declare
    v_user_id bigint;
    v_status varchar;
begin
    select user_id, status into v_user_id, v_status from study_day where id = new.study_day_id;

    if v_status = 'DAY_OFF' then
        raise exception 'Cannot plan study on day off';
    end if;

    perform check_active_member(v_user_id, new.exam_id);

    return new;
end;
$$ language plpgsql;

drop trigger if exists plan_item_check on plan_item;
create trigger plan_item_check
    before insert or update of study_day_id, exam_id on plan_item
    for each row
    execute function trg_plan_item_check();


create or replace function trg_exam_member_check_owner() returns trigger as $$
declare
    v_owner_id bigint;
begin
    select owner_id into v_owner_id from exam where id = new.exam_id;

    if new.role = 'OWNER' and new.user_id <> v_owner_id then
        raise exception 'User % is not the owner of exam %', new.user_id, new.exam_id;
    end if;

    if tg_op = 'UPDATE' and old.role = 'OWNER' and new.role <> 'OWNER' and new.user_id = v_owner_id then
        raise exception 'Change exam.owner_id before removing OWNER role';
    end if;

    return new;
end;
$$ language plpgsql;

drop trigger if exists exam_member_check_owner on exam_member;
create trigger exam_member_check_owner
    before insert or update of role on exam_member
    for each row
    execute function trg_exam_member_check_owner();