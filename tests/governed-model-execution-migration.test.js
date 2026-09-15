import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(
  new URL('../supabase/migrations/20260912060000_governed_model_execution.sql', import.meta.url),
  'utf8'
);

function escaped(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

test('governed model execution schema is append-only and replay resistant', () => {
  assert.match(sql, /create table public\.agent_drafts/i);
  assert.match(sql, /execution_action_id uuid not null unique/i);
  assert.match(sql, /content_sha256 text not null/i);
  assert.match(sql, /status text not null[^;]+current[^;]+superseded[^;]+published/is);
  assert.match(sql, /create table public\.agent_execution_receipts/i);
  assert.match(sql, /execution_action_id uuid not null unique/i);
  assert.match(sql, /claimed_by uuid not null/i);
  assert.match(sql, /running[^;]+succeeded[^;]+failed/is);
  assert.match(sql, /create table public\.agent_publications/i);
  assert.match(sql, /publication_action_id uuid not null unique/i);
  assert.match(sql, /draft_id uuid not null unique/i);
});

test('ordinary browser roles cannot write execution artifacts directly', () => {
  for (const table of ['agent_drafts', 'agent_execution_receipts', 'agent_publications']) {
    assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`, 'i'));
  }
  assert.doesNotMatch(sql, /create policy[^;]+agent_drafts[^;]+for insert[^;]+to authenticated/is);
  assert.doesNotMatch(sql, /create policy[^;]+agent_execution_receipts[^;]+for insert[^;]+to authenticated/is);
  assert.doesNotMatch(sql, /create policy[^;]+agent_publications[^;]+for insert[^;]+to authenticated/is);
});

test('execution claim and finalizers are server-only while human publication RPCs remain authenticated', () => {
  for (const signature of [
    'public.claim_approved_agent_execution(uuid,uuid,text,text)',
    'public.complete_agent_execution_success(uuid,text,text,text,jsonb,uuid)',
    'public.complete_agent_execution_failure(uuid,text)'
  ]) {
    assert.match(sql, new RegExp(`revoke execute on function ${escaped(signature)} from authenticated`, 'i'));
    assert.match(sql, new RegExp(`grant execute on function ${escaped(signature)} to service_role`, 'i'));
  }
  for (const signature of [
    'public.request_agent_draft_publication(uuid)',
    'public.publish_approved_agent_draft(uuid)'
  ]) {
    assert.match(sql, new RegExp(`revoke execute on function ${escaped(signature)} from anon`, 'i'));
    assert.match(sql, new RegExp(`grant execute on function ${escaped(signature)} to authenticated`, 'i'));
  }
  assert.match(sql, /p_actor_id uuid/i);
  assert.match(sql, /approval_status\s*<>\s*'approved'/i);
  assert.match(sql, /policy_version\s*<>\s*'0\.1\.0-alpha'/i);
  assert.match(sql, /content_sha256/i);
  assert.match(sql, /for update/i);
});

test('draft requests are post-scoped and canonicalized inside the database boundary', () => {
  const signature = 'public.request_governed_post_agent_action(uuid,text,text)';
  assert.match(sql, /create or replace function public\.request_governed_post_agent_action\s*\(/i);
  assert.match(sql, /select p\.space_id[^;]+from public\.posts p[^;]+where p\.id = p_post_id/is);
  assert.match(sql, /jsonb_build_array\s*\(\s*jsonb_build_object\s*\(\s*'type'\s*,\s*'post'\s*,\s*'id'\s*,\s*p_post_id::text/is);
  assert.match(sql, /public\.is_space_member\(v_space_id\)/i);
  assert.match(sql, new RegExp(`revoke execute on function ${escaped(signature)} from anon`, 'i'));
  assert.match(sql, new RegExp(`grant execute on function ${escaped(signature)} to authenticated`, 'i'));
});
