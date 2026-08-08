-- Stream 2 test — membership RPCs, last-admin protection, action provenance.
-- Runs after smoke_test.sql and reuses its users/household:
--   alice (admin), bob (member) in household 1000...01; carol is an outsider.

\set ON_ERROR_STOP on

-- Capture the invite code while unrestricted (outsiders can't read it; in
-- real life it is shared out-of-band).
select upper(invite_code) as invite_code_shared
  from foodie.households where id = '10000000-0000-0000-0000-000000000001' \gset

set role authenticated;

-- Carol redeems the invite code (case-insensitively) and becomes a member;
-- redemption is idempotent.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
select foodie.redeem_household_invite(:'invite_code_shared');
select foodie.redeem_household_invite(:'invite_code_shared');

do $$ begin
  if not exists (select 1 from foodie.household_members
                 where household_id = '10000000-0000-0000-0000-000000000001'
                   and user_id = '00000000-0000-0000-0000-00000000000c'
                   and role = 'member') then
    raise exception 'invite redemption did not create membership';
  end if;
  if (select count(*) from foodie.inventory_items) <> 1 then
    raise exception 'newly joined member cannot read household data';
  end if;
end $$;

-- An invalid code is rejected.
do $$ begin
  begin
    perform foodie.redeem_household_invite('nope-not-a-code');
    raise exception 'invalid invite code was accepted';
  exception when sqlstate 'P0003' then null;
  end;
end $$;

-- Only admins can rotate the invite code; rotation invalidates the old code.
do $$ begin
  begin
    perform foodie.regenerate_invite_code('10000000-0000-0000-0000-000000000001');
    raise exception 'non-admin regenerated the invite code';
  exception when sqlstate 'P0004' then null;
  end;
end $$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
do $$
declare
  old_code text;
  new_code text;
begin
  select invite_code into old_code
    from foodie.households where id = '10000000-0000-0000-0000-000000000001';
  new_code := foodie.regenerate_invite_code('10000000-0000-0000-0000-000000000001');
  if new_code = old_code or new_code is null then
    raise exception 'invite code was not rotated';
  end if;
  begin
    perform foodie.redeem_household_invite(old_code);
    raise exception 'stale invite code still redeemable';
  exception when sqlstate 'P0003' then null;
  end;
end $$;

-- Carol leaves; leaving twice errors cleanly.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
select foodie.leave_household('10000000-0000-0000-0000-000000000001');
do $$ begin
  begin
    perform foodie.leave_household('10000000-0000-0000-0000-000000000001');
    raise exception 'leaving twice did not error';
  exception when sqlstate 'P0005' then null;
  end;
end $$;
do $$ begin
  if (select count(*) from foodie.households) <> 0 then
    raise exception 'departed member still sees the household';
  end if;
end $$;

-- Alice is the only admin: she can neither leave nor demote herself.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
do $$ begin
  begin
    perform foodie.leave_household('10000000-0000-0000-0000-000000000001');
    raise exception 'last admin was able to leave';
  exception when sqlstate 'P0001' then null;
  end;
  begin
    update foodie.household_members set role = 'member'
      where household_id = '10000000-0000-0000-0000-000000000001'
        and user_id = '00000000-0000-0000-0000-00000000000a';
    raise exception 'last admin was able to demote self';
  exception when sqlstate 'P0001' then null;
  end;
end $$;

-- With Bob promoted, Alice may step down.
update foodie.household_members set role = 'admin'
  where household_id = '10000000-0000-0000-0000-000000000001'
    and user_id = '00000000-0000-0000-0000-00000000000b';
update foodie.household_members set role = 'member'
  where household_id = '10000000-0000-0000-0000-000000000001'
    and user_id = '00000000-0000-0000-0000-00000000000a';
-- restore original roles for any later tests
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
update foodie.household_members set role = 'admin'
  where household_id = '10000000-0000-0000-0000-000000000001'
    and user_id = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
update foodie.household_members set role = 'member'
  where household_id = '10000000-0000-0000-0000-000000000001'
    and user_id = '00000000-0000-0000-0000-00000000000b';

-- Provenance: default source is 'user'; a declared source is recorded.
update foodie.food_items set notes = 'user edit'
  where id = '20000000-0000-0000-0000-000000000001';
do $$ begin
  if (select source from foodie.record_history
       where table_name = 'food_items' and op = 'UPDATE'
       order by id desc limit 1)::text <> 'user' then
    raise exception 'default provenance is not user';
  end if;
end $$;

set app.action_source = 'foodie';
update foodie.food_items set notes = 'foodie edit'
  where id = '20000000-0000-0000-0000-000000000001';
do $$ begin
  if (select source from foodie.record_history
       where table_name = 'food_items' and op = 'UPDATE'
       order by id desc limit 1)::text <> 'foodie' then
    raise exception 'declared provenance was not recorded';
  end if;
end $$;
set app.action_source = '';

-- Fermentation log authorship now uses the shared action_source vocabulary.
insert into foodie.fermentation_projects (id, household_id, project_type, name)
  values ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'sourdough_starter', 'Bubbles');
insert into foodie.fermentation_logs (household_id, project_id, log_type, notes, author)
  values ('10000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001',
          'observation', 'smells fine', 'foodie');

reset role;
select 'MEMBERSHIP TEST PASSED' as result;
