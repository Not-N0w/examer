insert into users (login, email, password_hash) values (
  'test',
  '123',
  'hash'
);

select * from users;
select id, invite_code from exam;

--join exam
select join_exam(12, '313aeeebb0cec7fcd481d3b5516f19e1');

select * from exam_member
join users on users.id = exam_member.user_id
where exam_id = 3;

-- push note
select * from card where exam_id = 3;
select * from note;

insert into note (card_id, user_id, text)
values (21, 12, 'note');

select push_note_as_change_request(13);

select * from change_request;

-- submit change request
select submit_change_request(2, 8);

-- reject change request
select reject_change_request(1, 2);