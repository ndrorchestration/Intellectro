import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

function source(path) {
  return readFileSync(new URL(path, import.meta.url), 'utf8');
}

test('execution admin client is server-only and uses a non-public service-role variable', () => {
  const admin = source('../apps/web/lib/supabase/execution-admin.js');
  assert.match(admin, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(admin, /NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(admin, /persistSession:\s*false/);
  assert.match(admin, /autoRefreshToken:\s*false/);
  assert.match(admin, /detectSessionInUrl:\s*false/);
  assert.doesNotMatch(admin, /console\.(?:log|error|warn).*SERVICE_ROLE/is);
});

test('execution context resolves approved post-scoped input and rejects arbitrary prompts', () => {
  const context = source('../apps/web/lib/model-execution/context.js');
  assert.match(context, /agent_actions/);
  assert.match(context, /approval_status/);
  assert.match(context, /0\.1\.0-alpha/);
  assert.match(context, /input_refs/);
  assert.match(context, /type\s*===\s*['"]post['"]/);
  assert.match(context, /post_sources/);
  assert.match(context, /sources/);
  assert.doesNotMatch(context, /prompt\s*=/i);
  assert.doesNotMatch(context, /formData/i);
});

test('run boundary derives actor separately from service-role mutation authority', () => {
  const run = source('../apps/web/lib/model-execution/run.js');
  assert.match(run, /actorId/);
  assert.match(run, /createExecutionAdminClient/);
  assert.match(run, /claim_approved_agent_execution/);
  assert.match(run, /p_actor_id:\s*actorId/);
  assert.match(run, /complete_agent_execution_success/);
  assert.match(run, /complete_agent_execution_failure/);
  assert.match(run, /provider\.kind\s*===\s*['"]disabled['"]/);
  assert.match(run, /provider_unavailable/);
  assert.doesNotMatch(run, /NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY/);
});

test('draft request path uses post-scoped database RPC rather than arbitrary input refs', () => {
  const actions = source('../apps/web/app/app/actions.js');
  assert.match(actions, /request_governed_post_agent_action/);
  assert.match(actions, /p_post_id:\s*postId/);
  assert.doesNotMatch(actions, /request_governed_post_agent_action[^}]+p_input_refs/is);
});
