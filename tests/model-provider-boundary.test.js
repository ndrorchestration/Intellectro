import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  ExecutionError,
  assertProviderResult,
  createDisabledProvider
} from '../packages/model-execution/src/index.js';

test('disabled provider fails closed without output', async () => {
  const provider = createDisabledProvider();
  assert.equal(provider.kind, 'disabled');
  await assert.rejects(
    () => provider.generateDraft({ executionIdempotencyKey: 'receipt-1' }),
    (error) => error instanceof ExecutionError && error.code === 'provider_unavailable'
  );
});

test('provider output must be bounded text with non-secret identifiers', () => {
  assert.throws(
    () => assertProviderResult({ content: '', providerKind: 'fixture', modelIdentifier: 'deterministic-v1' }),
    (error) => error instanceof ExecutionError && error.code === 'invalid_provider_output'
  );
  assert.throws(
    () => assertProviderResult({ content: 'x'.repeat(20001), providerKind: 'fixture', modelIdentifier: 'deterministic-v1' }),
    (error) => error instanceof ExecutionError && error.code === 'invalid_provider_output'
  );

  const normalized = assertProviderResult({
    content: '  bounded draft  ',
    providerKind: 'fixture',
    modelIdentifier: 'deterministic-v1',
    providerRequestId: 'req-1'
  });
  assert.deepEqual(normalized, {
    content: 'bounded draft',
    providerKind: 'fixture',
    modelIdentifier: 'deterministic-v1',
    providerRequestId: 'req-1'
  });
  assert.equal(Object.isFrozen(normalized), true);
});

test('unsupported execution error codes fail closed', () => {
  assert.throws(() => new ExecutionError('invented_authority_state'), /Unsupported execution error code/);
});

test('executable provider source exposes no deterministic runtime selector or public provider secret', () => {
  const executableSource = [
    '../packages/model-execution/src/errors.js',
    '../packages/model-execution/src/provider.js',
    '../packages/model-execution/src/canonical-input.js',
    '../packages/model-execution/src/index.js'
  ]
    .map((path) => readFileSync(new URL(path, import.meta.url), 'utf8'))
    .join('\n');

  assert.doesNotMatch(executableSource, /NEXT_PUBLIC_[A-Z0-9_]*(?:MODEL|PROVIDER)/);
  assert.doesNotMatch(executableSource, /INTELLECTRO_PROVIDER\s*=\s*['"]?(?:test|deterministic)/i);
  assert.doesNotMatch(executableSource, /process\.env\.[A-Z0-9_]*(?:MODEL|PROVIDER)/);
});
