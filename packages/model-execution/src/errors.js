export const EXECUTION_ERROR_CODES = Object.freeze(new Set([
  'provider_unavailable',
  'action_not_approved',
  'action_already_executed',
  'execution_in_progress',
  'stale_input',
  'policy_mismatch',
  'provider_timeout',
  'provider_failure',
  'invalid_provider_output',
  'draft_superseded',
  'publication_not_approved',
  'publication_replay',
  'cross_space_binding'
]));

export class ExecutionError extends Error {
  constructor(code, message = code) {
    if (!EXECUTION_ERROR_CODES.has(code)) {
      throw new TypeError(`Unsupported execution error code: ${code}`);
    }
    super(message);
    this.name = 'ExecutionError';
    this.code = code;
  }
}
