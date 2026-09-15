import { createHash } from 'node:crypto';

const DRAFT_CAPABILITIES = new Map([
  ['community_agent', 'draft_public_content'],
  ['claim_agent', 'draft_annotation']
]);

function requiredText(value, field, maxLength = 20000) {
  if (typeof value !== 'string' || !value.trim()) {
    throw new TypeError(`${field} is required`);
  }
  const normalized = value.trim();
  if (normalized.length > maxLength) {
    throw new TypeError(`${field} is too long`);
  }
  return normalized;
}

function optionalText(value, field, maxLength = 1000) {
  if (value === null || value === undefined || value === '') return null;
  if (typeof value !== 'string') throw new TypeError(`${field} must be text or null`);
  const normalized = value.trim();
  if (normalized.length > maxLength) throw new TypeError(`${field} is too long`);
  return normalized || null;
}

function normalizeSource(source) {
  if (!source || typeof source !== 'object' || Array.isArray(source)) {
    throw new TypeError('source must be an object');
  }
  const id = requiredText(source.id, 'source.id', 80);
  const rawUrl = requiredText(source.url, 'source.url', 2000);
  const parsed = new URL(rawUrl);
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    throw new TypeError('source.url must use http or https');
  }
  return Object.freeze({
    id,
    url: parsed.toString(),
    title: optionalText(source.title, 'source.title', 500),
    publisher: optionalText(source.publisher, 'source.publisher', 500)
  });
}

export function buildCanonicalExecutionInput(context) {
  if (!context || typeof context !== 'object' || Array.isArray(context)) {
    throw new TypeError('execution context must be an object');
  }

  const policyVersion = requiredText(context.policyVersion, 'policyVersion', 80);
  if (policyVersion !== '0.1.0-alpha') throw new TypeError('policyVersion is not admissible');

  const agentId = requiredText(context.agentId, 'agentId', 80);
  const capability = requiredText(context.capability, 'capability', 120);
  if (DRAFT_CAPABILITIES.get(agentId) !== capability) {
    throw new TypeError('agent/capability pair is not an executable draft capability');
  }

  const space = Object.freeze({
    id: requiredText(context.space?.id, 'space.id', 80),
    slug: requiredText(context.space?.slug, 'space.slug', 63)
  });
  const post = Object.freeze({
    id: requiredText(context.post?.id, 'post.id', 80),
    body: requiredText(context.post?.body, 'post.body', 20000)
  });

  if (!Array.isArray(context.sources)) throw new TypeError('sources must be an array');
  const sources = context.sources
    .map(normalizeSource)
    .sort((a, b) => a.id.localeCompare(b.id) || a.url.localeCompare(b.url));
  Object.freeze(sources);

  return Object.freeze({
    version: 'intellectro.execution-input.v1',
    policyVersion,
    agentId,
    capability,
    space,
    post,
    sources
  });
}

export function serializeCanonicalExecutionInput(input) {
  const canonical = buildCanonicalExecutionInput(input);
  return JSON.stringify(canonical);
}

export function sha256Hex(value) {
  if (typeof value !== 'string') throw new TypeError('sha256 input must be text');
  return createHash('sha256').update(value, 'utf8').digest('hex');
}
