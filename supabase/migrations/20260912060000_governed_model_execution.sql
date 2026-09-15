-- Provider-neutral governed model execution and publication substrate.
--
-- Authority boundary:
--   * execution claim + success/failure finalization are server-only service_role RPCs;
--   * publication request + explicit publish remain authenticated human actions;
--   * ordinary browser roles receive no direct write policy on execution artifacts;
--   * approval to execute never authorizes publication;
--   * every approved draft action is consumable for at most one provider attempt.

create table public.agent_drafts (
  id uuid primary key default gen_random_uuid(),
  execution_action_id uuid not null unique references public.agent_actions(id) on delete restrict,
  space_id uuid not null references public.spaces(id) on delete cascade,
  agent_id text not null,
  capability text not null check (capability in ('draft_public_content','draft_annotation')),
  policy_version text not null,
  content text not null check (char_length(content) between 1 and 20000),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  input_refs jsonb not null default '[]'::jsonb check (jsonb_typeof(input_refs) = 'array'),
  supersedes_draft_id uuid references public.agent_drafts(id) on delete restrict,
  status text not null default 'current' check (status in ('current','superseded','published')),
  created_at timestamptz not null default now(),
  check (supersedes_draft_id is null or supersedes_draft_id <> id)
);

create index agent_drafts_space_idx on public.agent_drafts (space_id);
create index agent_drafts_supersedes_idx on public.agent_drafts (supersedes_draft_id) where supersedes_draft_id is not null;

create table public.agent_execution_receipts (
  id uuid primary key default gen_random_uuid(),
  execution_action_id uuid not null unique references public.agent_actions(id) on delete restrict,
  claimed_by uuid not null references auth.users(id) on delete restrict,
  draft_id uuid unique references public.agent_drafts(id) on delete restrict,
  provider_kind text not null check (char_length(provider_kind) between 1 and 80),
  model_identifier text check (model_identifier is null or char_length(model_identifier) between 1 and 200),
  input_sha256 text not null check (input_sha256 ~ '^[0-9a-f]{64}$'),
  output_sha256 text check (output_sha256 is null or output_sha256 ~ '^[0-9a-f]{64}$'),
  status text not null check (status in ('running','succeeded','failed')),
  failure_code text,
  policy_version text not null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  check (
    (status = 'running' and draft_id is null and output_sha256 is null and failure_code is null and completed_at is null)
    or (status = 'succeeded' and draft_id is not null and output_sha256 is not null and failure_code is null and completed_at is not null)
    or (status = 'failed' and draft_id is null and output_sha256 is null and failure_code is not null and completed_at is not null)
  )
);

create index agent_execution_receipts_claimed_by_idx on public.agent_execution_receipts (claimed_by);

create table public.agent_publications (
  id uuid primary key default gen_random_uuid(),
  publication_action_id uuid not null unique references public.agent_actions(id) on delete restrict,
  draft_id uuid not null unique references public.agent_drafts(id) on delete restrict,
  post_id uuid unique references public.posts(id) on delete restrict,
  provenance_id uuid unique references public.provenance_records(id) on delete restrict,
  published_by uuid references auth.users(id) on delete restrict,
  published_at timestamptz,
  check (
    (post_id is null and provenance_id is null and published_by is null and published_at is null)
    or (post_id is not null and provenance_id is not null and published_by is not null and published_at is not null)
  )
);

create index agent_publications_published_by_idx on public.agent_publications (published_by) where published_by is not null;

alter table public.agent_drafts enable row level security;
alter table public.agent_execution_receipts enable row level security;
alter table public.agent_publications enable row level security;

-- Private draft/execution state is inspectable only by the accountable action
-- owner or a current moderator/admin of the same Space. There is deliberately no
-- browser INSERT/UPDATE/DELETE policy on these tables.
create policy "agent drafts governed read" on public.agent_drafts
  for select to authenticated
  using (
    exists (
      select 1
      from public.agent_actions aa
      where aa.id = execution_action_id
        and (
          aa.owner_id = (select auth.uid())
          or public.is_space_moderator(space_id)
        )
    )
  );

create policy "agent execution receipts governed read" on public.agent_execution_receipts
  for select to authenticated
  using (
    exists (
      select 1
      from public.agent_actions aa
      where aa.id = execution_action_id
        and (
          aa.owner_id = (select auth.uid())
          or (aa.space_id is not null and public.is_space_moderator(aa.space_id))
        )
    )
  );

create policy "agent publications governed read" on public.agent_publications
  for select to authenticated
  using (
    exists (
      select 1
      from public.agent_actions aa
      where aa.id = publication_action_id
        and (
          aa.owner_id = (select auth.uid())
          or (aa.space_id is not null and public.is_space_moderator(aa.space_id))
        )
    )
  );

-- Server-only execution claim. p_actor_id is trusted only because this function
-- is executable solely by service_role. The server must derive it from validated
-- user claims before crossing this boundary.
create or replace function public.claim_approved_agent_execution(
  p_action_id uuid,
  p_actor_id uuid,
  p_provider_kind text,
  p_input_sha256 text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action public.agent_actions%rowtype;
  v_receipt_id uuid;
begin
  if p_actor_id is null then
    raise exception 'validated actor identity required' using errcode = '42501';
  end if;
  if coalesce(char_length(trim(p_provider_kind)), 0) not between 1 and 80 then
    raise exception 'invalid provider kind' using errcode = '22023';
  end if;
  if p_input_sha256 is null or p_input_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid input digest' using errcode = '22023';
  end if;

  select aa.*
    into v_action
  from public.agent_actions aa
  where aa.id = p_action_id
  for update;

  if not found then
    raise exception 'governed action not found' using errcode = 'P0002';
  end if;
  if v_action.approval_status <> 'approved' then
    raise exception 'action is not approved for execution' using errcode = '42501';
  end if;
  if v_action.policy_version <> '0.1.0-alpha' then
    raise exception 'policy version is not admissible for execution' using errcode = '42501';
  end if;
  if not (
    (v_action.agent_id = 'community_agent' and v_action.capability = 'draft_public_content')
    or (v_action.agent_id = 'claim_agent' and v_action.capability = 'draft_annotation')
  ) then
    raise exception 'action capability is not an executable draft capability' using errcode = '42501';
  end if;
  if v_action.space_id is null then
    raise exception 'execution action must be Space scoped' using errcode = '42501';
  end if;
  if not (
    v_action.owner_id = p_actor_id
    or exists (
      select 1
      from public.space_memberships sm
      where sm.space_id = v_action.space_id
        and sm.user_id = p_actor_id
        and sm.role in ('moderator','admin')
    )
  ) then
    raise exception 'actor is not authorized to execute this approved action' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.agent_execution_receipts er
    where er.execution_action_id = p_action_id
  ) then
    raise exception 'action is already executed or claimed' using errcode = '55000';
  end if;

  insert into public.agent_execution_receipts (
    execution_action_id,
    claimed_by,
    provider_kind,
    input_sha256,
    status,
    policy_version
  )
  values (
    p_action_id,
    p_actor_id,
    trim(p_provider_kind),
    p_input_sha256,
    'running',
    v_action.policy_version
  )
  returning id into v_receipt_id;

  return v_receipt_id;
exception
  when unique_violation then
    raise exception 'action is already executed or claimed' using errcode = '55000';
end;
$$;

-- Server-only success finalizer. It can finalize only the already-claimed running
-- receipt and cannot create a second draft for the same approved action.
create or replace function public.complete_agent_execution_success(
  p_receipt_id uuid,
  p_content text,
  p_content_sha256 text,
  p_model_identifier text,
  p_input_refs jsonb,
  p_supersedes_draft_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_receipt public.agent_execution_receipts%rowtype;
  v_action public.agent_actions%rowtype;
  v_old_draft public.agent_drafts%rowtype;
  v_draft_id uuid;
begin
  if p_content is null or char_length(p_content) not between 1 and 20000 then
    raise exception 'invalid draft content' using errcode = '22023';
  end if;
  if p_content_sha256 is null or p_content_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid output digest' using errcode = '22023';
  end if;
  if coalesce(char_length(trim(p_model_identifier)), 0) not between 1 and 200 then
    raise exception 'invalid model identifier' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_input_refs, 'null'::jsonb)) <> 'array' then
    raise exception 'input refs must be an array' using errcode = '22023';
  end if;

  select er.*
    into v_receipt
  from public.agent_execution_receipts er
  where er.id = p_receipt_id
  for update;

  if not found then
    raise exception 'execution receipt not found' using errcode = 'P0002';
  end if;
  if v_receipt.status <> 'running' then
    raise exception 'execution receipt is already finalized' using errcode = '55000';
  end if;

  select aa.*
    into v_action
  from public.agent_actions aa
  where aa.id = v_receipt.execution_action_id
  for update;

  if not found then
    raise exception 'governed action not found' using errcode = 'P0002';
  end if;
  if v_action.approval_status <> 'approved' then
    raise exception 'action approval is no longer admissible' using errcode = '42501';
  end if;
  if v_action.policy_version <> '0.1.0-alpha' or v_receipt.policy_version <> '0.1.0-alpha' then
    raise exception 'policy version is not admissible for execution' using errcode = '42501';
  end if;
  if not (
    (v_action.agent_id = 'community_agent' and v_action.capability = 'draft_public_content')
    or (v_action.agent_id = 'claim_agent' and v_action.capability = 'draft_annotation')
  ) then
    raise exception 'action capability is not an executable draft capability' using errcode = '42501';
  end if;
  if v_action.space_id is null then
    raise exception 'execution action must be Space scoped' using errcode = '42501';
  end if;
  if p_input_refs <> coalesce(v_action.input_refs, '[]'::jsonb) then
    raise exception 'execution input references changed after approval' using errcode = '55000';
  end if;

  if p_supersedes_draft_id is not null then
    select d.*
      into v_old_draft
    from public.agent_drafts d
    where d.id = p_supersedes_draft_id
    for update;

    if not found then
      raise exception 'superseded draft not found' using errcode = 'P0002';
    end if;
    if v_old_draft.status <> 'current'
      or v_old_draft.space_id <> v_action.space_id
      or v_old_draft.agent_id <> v_action.agent_id
      or v_old_draft.capability <> v_action.capability then
      raise exception 'superseded draft is not compatible with this execution' using errcode = '42501';
    end if;
  end if;

  insert into public.agent_drafts (
    execution_action_id,
    space_id,
    agent_id,
    capability,
    policy_version,
    content,
    content_sha256,
    input_refs,
    supersedes_draft_id,
    status
  )
  values (
    v_action.id,
    v_action.space_id,
    v_action.agent_id,
    v_action.capability,
    v_action.policy_version,
    p_content,
    p_content_sha256,
    p_input_refs,
    p_supersedes_draft_id,
    'current'
  )
  returning id into v_draft_id;

  if p_supersedes_draft_id is not null then
    update public.agent_drafts
    set status = 'superseded'
    where id = p_supersedes_draft_id and status = 'current';

    if not found then
      raise exception 'superseded draft changed during execution' using errcode = '40001';
    end if;
  end if;

  update public.agent_execution_receipts
  set draft_id = v_draft_id,
      model_identifier = trim(p_model_identifier),
      output_sha256 = p_content_sha256,
      status = 'succeeded',
      completed_at = now()
  where id = p_receipt_id and status = 'running';

  if not found then
    raise exception 'execution finalization race detected' using errcode = '40001';
  end if;

  return v_draft_id;
end;
$$;

create or replace function public.complete_agent_execution_failure(
  p_receipt_id uuid,
  p_failure_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  if p_failure_code not in (
    'provider_unavailable',
    'provider_timeout',
    'provider_failure',
    'invalid_provider_output',
    'stale_input',
    'policy_mismatch'
  ) then
    raise exception 'unsupported execution failure code' using errcode = '22023';
  end if;

  select er.status
    into v_status
  from public.agent_execution_receipts er
  where er.id = p_receipt_id
  for update;

  if not found then
    raise exception 'execution receipt not found' using errcode = 'P0002';
  end if;
  if v_status <> 'running' then
    raise exception 'execution receipt is already finalized' using errcode = '55000';
  end if;

  update public.agent_execution_receipts
  set status = 'failed',
      failure_code = p_failure_code,
      completed_at = now()
  where id = p_receipt_id and status = 'running';

  if not found then
    raise exception 'execution failure finalization race detected' using errcode = '40001';
  end if;
end;
$$;

-- Human-authenticated request to submit an exact current draft for a separate
-- publication approval. The digest/capability/Space/agent are copied server-side.
create or replace function public.request_agent_draft_publication(
  p_draft_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_draft public.agent_drafts%rowtype;
  v_publish_capability text;
  v_publication_action_id uuid;
  v_expected_ref jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select d.*
    into v_draft
  from public.agent_drafts d
  where d.id = p_draft_id
  for update;

  if not found then
    raise exception 'agent draft not found' using errcode = 'P0002';
  end if;
  if v_draft.status <> 'current' then
    raise exception 'only a current draft may request publication' using errcode = '55000';
  end if;
  if v_draft.policy_version <> '0.1.0-alpha' then
    raise exception 'policy version is not admissible for publication' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.space_memberships sm
    where sm.space_id = v_draft.space_id
      and sm.user_id = v_user_id
  ) then
    raise exception 'Space membership required' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.agent_publications ap
    where ap.draft_id = p_draft_id
  ) then
    raise exception 'draft already has a publication request' using errcode = '55000';
  end if;

  if v_draft.agent_id = 'community_agent' and v_draft.capability = 'draft_public_content' then
    v_publish_capability := 'publish_public_content';
  elsif v_draft.agent_id = 'claim_agent' and v_draft.capability = 'draft_annotation' then
    v_publish_capability := 'publish_annotation';
  else
    raise exception 'draft capability cannot request publication' using errcode = '42501';
  end if;

  v_expected_ref := jsonb_build_array(
    jsonb_build_object(
      'type', 'agent_draft',
      'id', v_draft.id::text,
      'sha256', v_draft.content_sha256
    )
  );

  insert into public.agent_actions (
    agent_id,
    owner_id,
    space_id,
    action,
    capability,
    policy_version,
    approval_status,
    input_refs,
    output_refs
  )
  values (
    v_draft.agent_id,
    v_user_id,
    v_draft.space_id,
    'request:' || v_publish_capability,
    v_publish_capability,
    '0.1.0-alpha',
    'pending',
    v_expected_ref,
    '[]'::jsonb
  )
  returning id into v_publication_action_id;

  insert into public.agent_publications (publication_action_id, draft_id)
  values (v_publication_action_id, v_draft.id);

  return v_publication_action_id;
end;
$$;

-- Explicit human publication step. Approval has already happened on a separate
-- governed action; this function rechecks the exact draft binding and current
-- moderator authority before atomically admitting public content + provenance.
create or replace function public.publish_approved_agent_draft(
  p_publication_action_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_publication public.agent_publications%rowtype;
  v_action public.agent_actions%rowtype;
  v_draft public.agent_drafts%rowtype;
  v_expected_capability text;
  v_expected_ref jsonb;
  v_post_id uuid;
  v_provenance_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select ap.*
    into v_publication
  from public.agent_publications ap
  where ap.publication_action_id = p_publication_action_id
  for update;

  if not found then
    raise exception 'publication request not found' using errcode = 'P0002';
  end if;
  if v_publication.post_id is not null or v_publication.provenance_id is not null then
    raise exception 'publication action has already been consumed' using errcode = '55000';
  end if;

  select aa.*
    into v_action
  from public.agent_actions aa
  where aa.id = p_publication_action_id
  for update;

  if not found then
    raise exception 'publication action not found' using errcode = 'P0002';
  end if;
  if v_action.approval_status <> 'approved' then
    raise exception 'publication action is not approved' using errcode = '42501';
  end if;
  if v_action.policy_version <> '0.1.0-alpha' then
    raise exception 'policy version is not admissible for publication' using errcode = '42501';
  end if;
  if v_action.space_id is null then
    raise exception 'publication action must be Space scoped' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.space_memberships sm
    where sm.space_id = v_action.space_id
      and sm.user_id = v_user_id
      and sm.role in ('moderator','admin')
  ) then
    raise exception 'current moderator authority required to publish' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.space_memberships sm
    where sm.space_id = v_action.space_id
      and sm.user_id = v_action.owner_id
  ) then
    raise exception 'publication requester is no longer a Space member' using errcode = '42501';
  end if;

  select d.*
    into v_draft
  from public.agent_drafts d
  where d.id = v_publication.draft_id
  for update;

  if not found then
    raise exception 'bound draft not found' using errcode = 'P0002';
  end if;
  if v_draft.status <> 'current' then
    raise exception 'bound draft is no longer current' using errcode = '55000';
  end if;
  if v_draft.policy_version <> '0.1.0-alpha' then
    raise exception 'draft policy version is not admissible for publication' using errcode = '42501';
  end if;
  if v_draft.space_id <> v_action.space_id or v_draft.agent_id <> v_action.agent_id then
    raise exception 'publication binding crosses Space or agent identity' using errcode = '42501';
  end if;

  if v_draft.agent_id = 'community_agent' and v_draft.capability = 'draft_public_content' then
    v_expected_capability := 'publish_public_content';
  elsif v_draft.agent_id = 'claim_agent' and v_draft.capability = 'draft_annotation' then
    v_expected_capability := 'publish_annotation';
  else
    raise exception 'draft capability cannot be published' using errcode = '42501';
  end if;

  if v_action.capability <> v_expected_capability
    or v_action.action <> 'request:' || v_expected_capability then
    raise exception 'publication capability does not match bound draft' using errcode = '42501';
  end if;

  v_expected_ref := jsonb_build_array(
    jsonb_build_object(
      'type', 'agent_draft',
      'id', v_draft.id::text,
      'sha256', v_draft.content_sha256
    )
  );
  if v_action.input_refs <> v_expected_ref then
    raise exception 'publication digest binding is stale or malformed' using errcode = '55000';
  end if;

  insert into public.posts (
    space_id,
    author_id,
    body,
    kind,
    ai_assisted,
    ai_assistance_type,
    agent_id,
    human_approved
  )
  values (
    v_draft.space_id,
    v_action.owner_id,
    v_draft.content,
    'ai_assisted',
    true,
    'agent_generated',
    v_draft.agent_id,
    true
  )
  returning id into v_post_id;

  insert into public.provenance_records (
    post_id,
    source_refs,
    transformations,
    generated_at
  )
  values (
    v_post_id,
    v_draft.input_refs,
    jsonb_build_array(
      jsonb_build_object(
        'type', 'governed_agent_draft',
        'execution_action_id', v_draft.execution_action_id::text,
        'draft_id', v_draft.id::text,
        'content_sha256', v_draft.content_sha256,
        'publication_action_id', v_action.id::text
      )
    ),
    now()
  )
  returning id into v_provenance_id;

  update public.agent_publications
  set post_id = v_post_id,
      provenance_id = v_provenance_id,
      published_by = v_user_id,
      published_at = now()
  where id = v_publication.id and post_id is null and provenance_id is null;

  if not found then
    raise exception 'publication finalization race detected' using errcode = '40001';
  end if;

  update public.agent_drafts
  set status = 'published'
  where id = v_draft.id and status = 'current';

  if not found then
    raise exception 'draft changed during publication' using errcode = '40001';
  end if;

  return v_post_id;
end;
$$;

-- Execution mutation boundaries are server-only. Ordinary authenticated users
-- cannot call these RPCs directly to fabricate or consume model execution state.
revoke all on function public.claim_approved_agent_execution(uuid,uuid,text,text) from public;
revoke execute on function public.claim_approved_agent_execution(uuid,uuid,text,text) from anon;
revoke execute on function public.claim_approved_agent_execution(uuid,uuid,text,text) from authenticated;
grant execute on function public.claim_approved_agent_execution(uuid,uuid,text,text) to service_role;

revoke all on function public.complete_agent_execution_success(uuid,text,text,text,jsonb,uuid) from public;
revoke execute on function public.complete_agent_execution_success(uuid,text,text,text,jsonb,uuid) from anon;
revoke execute on function public.complete_agent_execution_success(uuid,text,text,text,jsonb,uuid) from authenticated;
grant execute on function public.complete_agent_execution_success(uuid,text,text,text,jsonb,uuid) to service_role;

revoke all on function public.complete_agent_execution_failure(uuid,text) from public;
revoke execute on function public.complete_agent_execution_failure(uuid,text) from anon;
revoke execute on function public.complete_agent_execution_failure(uuid,text) from authenticated;
grant execute on function public.complete_agent_execution_failure(uuid,text) to service_role;

-- Publication transitions are explicit human actions and remain authenticated.
revoke all on function public.request_agent_draft_publication(uuid) from public;
revoke execute on function public.request_agent_draft_publication(uuid) from anon;
grant execute on function public.request_agent_draft_publication(uuid) to authenticated;

revoke all on function public.publish_approved_agent_draft(uuid) from public;
revoke execute on function public.publish_approved_agent_draft(uuid) from anon;
grant execute on function public.publish_approved_agent_draft(uuid) to authenticated;
