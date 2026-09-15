import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ExecutionError,
  executeClaimedDraft
} from '../packages/model-execution/src/index.js';

const CONTEXT = Object.freeze({
  policyVersion: '0.1.0-alpha',
  agentId: 'claim_agent',
  capability: 'draft_annotation',
  space: { id: 'space-1', slug: 'research' },
  post: { id: 'post-1', body: 'Claim body' },
  sources: [{ id: 'source-1', url: 'https://example.com/source', title: 'Source', publisher: 'Example' }],
  inputRefs: [{ type: 'post', id: 'post-1' }],
  supersedesDraftId: null
});

function fixtureProvider(overrides = {}) {
  return {
    kind: 'fixture',
    async generateDraft() {
      return {
        content: 'Deterministic draft',
        providerKind: 'fixture',
        modelIdentifier: 'deterministic-v1',
        ...overrides
      };
    }
  };
}

test('executor claims before provider and finalizes exactly one success', async () => {
  const calls = [];
  const result = await executeClaimedDraft({
    context: CONTEXT,
    provider: {
      kind: 'fixture',
      async generateDraft(input) {
        calls.push('provider');
        assert.equal(input.executionIdempotencyKey, 'receipt-1');
        return fixtureProvider().generateDraft(input);
      }
    },
    claimExecution: async ({ inputSha256, providerKind }) => {
      calls.push('claim');
      assert.match(inputSha256, /^[0-9a-f]{64}$/);
      assert.equal(providerKind, 'fixture');
      return { receiptId: 'receipt-1' };
    },
    finalizeSuccess: async ({ receiptId, contentSha256, providerResult }) => {
      calls.push('success');
      assert.equal(receiptId, 'receipt-1');
      assert.match(contentSha256, /^[0-9a-f]{64}$/);
      assert.equal(providerResult.providerKind, 'fixture');
      return { draftId: 'draft-1' };
    },
    finalizeFailure: async () => calls.push('failure')
  });
  assert.deepEqual(calls, ['claim', 'provider', 'success']);
  assert.equal(result.draftId, 'draft-1');
});

test('claim failure prevents any provider call', async () => {
  let providerCalls = 0;
  await assert.rejects(
    () => executeClaimedDraft({
      context: CONTEXT,
      provider: {
        kind: 'fixture',
        async generateDraft() { providerCalls += 1; return fixtureProvider().generateDraft(); }
      },
      claimExecution: async () => { throw new ExecutionError('action_already_executed'); },
      finalizeSuccess: async () => { throw new Error('must not finalize'); },
      finalizeFailure: async () => { throw new Error('must not finalize'); }
    }),
    (error) => error.code === 'action_already_executed'
  );
  assert.equal(providerCalls, 0);
});

test('provider failure finalizes failure once and never retries', async () => {
  let providerCalls = 0;
  let failureCalls = 0;
  await assert.rejects(
    () => executeClaimedDraft({
      context: CONTEXT,
      provider: {
        kind: 'fixture',
        async generateDraft() {
          providerCalls += 1;
          throw new ExecutionError('provider_failure');
        }
      },
      claimExecution: async () => ({ receiptId: 'receipt-1' }),
      finalizeSuccess: async () => { throw new Error('must not finalize success'); },
      finalizeFailure: async ({ receiptId, failureCode }) => {
        failureCalls += 1;
        assert.equal(receiptId, 'receipt-1');
        assert.equal(failureCode, 'provider_failure');
      }
    }),
    (error) => error.code === 'provider_failure'
  );
  assert.equal(providerCalls, 1);
  assert.equal(failureCalls, 1);
});

test('provider may not misreport its adapter identity', async () => {
  let failureCalls = 0;
  await assert.rejects(
    () => executeClaimedDraft({
      context: CONTEXT,
      provider: fixtureProvider({ providerKind: 'other-provider' }),
      claimExecution: async () => ({ receiptId: 'receipt-1' }),
      finalizeSuccess: async () => { throw new Error('must not finalize success'); },
      finalizeFailure: async ({ failureCode }) => {
        failureCalls += 1;
        assert.equal(failureCode, 'invalid_provider_output');
      }
    }),
    (error) => error.code === 'invalid_provider_output'
  );
  assert.equal(failureCalls, 1);
});
