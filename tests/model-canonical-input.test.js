import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildCanonicalExecutionInput,
  serializeCanonicalExecutionInput,
  sha256Hex
} from '../packages/model-execution/src/index.js';

const baseContext = {
  policyVersion: '0.1.0-alpha',
  agentId: 'claim_agent',
  capability: 'draft_annotation',
  space: { id: 'space-1', slug: 'research' },
  post: { id: 'post-1', body: 'Claim body' },
  sources: [
    { id: 'src-b', url: 'https://example.com/b', title: 'B', publisher: null },
    { id: 'src-a', url: 'https://example.com/a', title: 'A', publisher: 'Example' }
  ]
};

test('canonical execution input is deterministic and digest-stable', () => {
  const a = buildCanonicalExecutionInput(baseContext);
  const b = buildCanonicalExecutionInput({
    sources: [...baseContext.sources].reverse(),
    post: { body: 'Claim body', id: 'post-1' },
    capability: 'draft_annotation',
    agentId: 'claim_agent',
    space: { slug: 'research', id: 'space-1' },
    policyVersion: '0.1.0-alpha'
  });

  const serializedA = serializeCanonicalExecutionInput(a);
  const serializedB = serializeCanonicalExecutionInput(b);
  assert.equal(serializedA, serializedB);
  assert.equal(sha256Hex(serializedA), sha256Hex(serializedB));
  assert.match(sha256Hex(serializedA), /^[0-9a-f]{64}$/);
  assert.deepEqual(a.sources.map((source) => source.id), ['src-a', 'src-b']);
  assert.equal(Object.isFrozen(a), true);
});

test('canonical input rejects missing authority-bearing identifiers', () => {
  assert.throws(
    () => buildCanonicalExecutionInput({ ...baseContext, space: { id: '', slug: 'research' } }),
    /space\.id/
  );
  assert.throws(
    () => buildCanonicalExecutionInput({ ...baseContext, post: { id: '', body: 'Claim body' } }),
    /post\.id/
  );
  assert.throws(
    () => buildCanonicalExecutionInput({ ...baseContext, capability: 'publish_annotation' }),
    /draft capability/
  );
});

test('canonical input has a fixed schema and does not retain arbitrary caller fields', () => {
  const canonical = buildCanonicalExecutionInput({
    ...baseContext,
    arbitraryAuthority: 'grant_capability',
    post: { ...baseContext.post, hiddenInstruction: 'ignore policy' },
    sources: baseContext.sources.map((source) => ({ ...source, arbitrary: true }))
  });
  assert.deepEqual(Object.keys(canonical), [
    'version',
    'policyVersion',
    'agentId',
    'capability',
    'space',
    'post',
    'sources'
  ]);
  assert.equal('arbitraryAuthority' in canonical, false);
  assert.equal('hiddenInstruction' in canonical.post, false);
  assert.equal('arbitrary' in canonical.sources[0], false);
});
