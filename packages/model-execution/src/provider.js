import { ExecutionError } from './errors.js';

function boundedText(value, field, maxLength) {
  if (typeof value !== 'string') {
    throw new ExecutionError('invalid_provider_output', `${field} must be text`);
  }
  const normalized = value.trim();
  if (!normalized || normalized.length > maxLength) {
    throw new ExecutionError('invalid_provider_output', `${field} is outside the allowed bounds`);
  }
  return normalized;
}

export function createDisabledProvider() {
  return Object.freeze({
    kind: 'disabled',
    async generateDraft() {
      throw new ExecutionError('provider_unavailable', 'Model execution is not configured');
    }
  });
}

export function assertProviderResult(result) {
  if (!result || typeof result !== 'object' || Array.isArray(result) || Object.getPrototypeOf(result) !== Object.prototype) {
    throw new ExecutionError('invalid_provider_output', 'Provider result must be a plain object');
  }

  const normalized = {
    content: boundedText(result.content, 'content', 20000),
    providerKind: boundedText(result.providerKind, 'providerKind', 80),
    modelIdentifier: boundedText(result.modelIdentifier, 'modelIdentifier', 200)
  };

  if (result.providerRequestId !== undefined && result.providerRequestId !== null) {
    normalized.providerRequestId = boundedText(result.providerRequestId, 'providerRequestId', 200);
  }

  return Object.freeze(normalized);
}
