# Privileged RPC negative-authorization live verification — 2026-09-15

## Purpose

Close the source-bound negative-authorization evidence cells in `governance/privileged-rpc-negative-authorization-matrix.json` for the 16 authenticated-callable `SECURITY DEFINER` RPCs reported by the live Supabase security advisor.

This is **database-level live verification**, not Browser Gate B and not a claim of broad security assurance. The tests exercised the live functions in project `hibesaapldkvgkydvbds` under PostgreSQL role `authenticated` with transaction-local `request.jwt.claim.sub` values so `auth.uid()` resolved to controlled synthetic actors. All synthetic fixture writes were enclosed in transactions and rolled back.

## Source / runtime binding

- Repository: `ndrorchestration/Intellectro`
- Repository `main` at evidence admission preparation: `3852ede2511db151ba9259a067ec4cdfdc7bcaa1`
- Live Supabase project: `hibesaapldkvgkydvbds`
- Test date: 2026-09-15
- Persistent schema / function changes: **NONE**
- Persistent test data: **NONE**

## Auth-context preflight

A rollback-only preflight set `role authenticated` and a transaction-local `request.jwt.claim.sub`; `auth.uid()` resolved to the supplied UUID. This established that the negative tests exercised the same `auth.uid()`-dependent function branches under an authenticated database role rather than running as an unauthenticated/admin shortcut.

This does **not** establish browser session propagation, HTTP gateway behavior, production Vercel persistence configuration, or Browser Gate B.

## Invalid-input sweep

The 12 previously open `invalid_input` cells were exercised against the live functions. Each assertion required the exact expected rejection/fail-closed behavior; an unexpected success raised a test exception and would have failed the transaction.

| Function | Negative input | Required result | Result |
|---|---|---|---|
| `block_user` | null target | SQLSTATE `22023` | VERIFIED |
| `decide_connection_request` | unsupported decision | `22023` | VERIFIED |
| `decide_governed_agent_action` | unsupported decision | `22023` | VERIFIED |
| `decide_space_invitation` | unsupported decision | `22023` | VERIFIED |
| `invite_to_space` | null invitee | `22023` | VERIFIED |
| `is_blocked_with_current_user` | null other user | boolean `true` fail-closed | VERIFIED |
| `join_open_space` | null/nonexistent Space | `P0002` | VERIFIED |
| `record_approved_action_provenance` | non-array `source_refs` | `22023` | VERIFIED |
| `request_connection` | null recipient | `22023` | VERIFIED |
| `request_correction_or_appeal` | no target | `22023` | VERIFIED |
| `resolve_correction_or_appeal` | unsupported status | `22023` | VERIFIED |
| `set_space_join_policy` | unsupported policy | `22023` | VERIFIED |

The transaction completed its assertion block and rolled back.

## Actor / scope / lifecycle sweep

A second rollback-only transaction created three synthetic auth users plus two synthetic Spaces and the minimum rows required to exercise the 13 remaining actor, object/scope, and lifecycle cells. No production/user rows were selected as test fixtures.

| Function | Dimension | Negative case | Required result | Result |
|---|---|---|---|---|
| `block_user` | wrong object/scope | nonexistent target user | FK rejection `23503` | VERIFIED |
| `decide_connection_request` | wrong actor | outsider accepts A→B pending request | `42501` | VERIFIED |
| `decide_connection_request` | wrong object/scope | nonexistent request | `P0002` | VERIFIED |
| `disconnect_connection` | wrong actor | nonparticipant disconnects accepted A↔C connection | `42501` | VERIFIED |
| `record_approved_action_provenance` | wrong object/scope | approved S1 action references S2 post | `42501` | VERIFIED |
| `record_approved_action_provenance` | invalid/stale lifecycle | provenance requested for pending, non-approved action | `42501` | VERIFIED |
| `request_connection` | wrong object/scope | request crosses an existing block relation | `42501` | VERIFIED |
| `request_correction_or_appeal` | wrong actor | S1 member who is neither action owner nor moderator targets S1 action | `42501` | VERIFIED |
| `request_correction_or_appeal` | wrong object/scope | actor not in S2 targets S2 post | `42501` | VERIFIED |
| `request_governed_agent_action` | wrong object/scope | actor requests action in Space where actor is not a member | `42501` | VERIFIED |
| `resolve_correction_or_appeal` | wrong object/scope | S1 authority attempts to resolve S2 correction | `42501` | VERIFIED |
| `revoke_space_invitation` | wrong actor | outsider revokes pending S1 invitation | `42501` | VERIFIED |
| `revoke_space_invitation` | invalid/stale lifecycle | S1 admin revokes already-declined invitation | `55000` | VERIFIED |

The assertion block completed successfully and the transaction rolled back.

## Fixture-control provenance

The first attempt to construct the second sweep's fixtures was rejected before any authorization assertion because the database correctly enforced `connection_requests_active_pair_idx`: the draft fixture attempted to create both a pending and accepted connection for the same unordered actor pair. The transaction aborted. A direct residue check then returned zero synthetic rows in every touched table.

The corrected fixture used A→B for the pending request and A↔C for the accepted connection. After the successful assertion transaction rolled back, a second residue query again returned zero synthetic users, Spaces, connections, invitations, actions, posts, corrections, and blocks.

This failed fixture attempt is retained as test-harness provenance and is **not** counted as authorization evidence.

## Result

All 25 cells that were `NOT_VERIFIED` in the source-bound 16-function matrix at the start of this sweep now have live database-level negative evidence:

- invalid input: **12 / 12 VERIFIED**;
- wrong object/scope: **7 / 7 VERIFIED**;
- wrong actor: **4 / 4 VERIFIED**;
- invalid/stale lifecycle: **2 / 2 VERIFIED**.

The matrix may therefore classify every applicable negative-authorization dimension as `VERIFIED`, while preserving `NOT_APPLICABLE` where the function has no meaningful instance of that dimension.

## Non-claims / remaining gates

This verification does **not** establish:

- Browser Gate B;
- configured Vercel production persistence;
- HTTP/API-gateway or browser-token end-to-end authorization behavior;
- absence of vulnerabilities outside these declared negative dimensions;
- production readiness;
- autonomous-agent safety;
- external penetration-test or independent security certification.

The 16 Supabase advisor warnings remain architectural review signals associated with authenticated `SECURITY DEFINER` execution; closing this matrix means the declared negative cases have evidence, not that the warnings should automatically be dismissed.

## Classification

`16-FUNCTION NEGATIVE-AUTHORIZATION MATRIX = DATABASE-LEVEL VERIFIED / SYNTHETIC FIXTURES ROLLED BACK / BROWSER GATE B NOT VERIFIED / PRODUCTION PERSISTENCE NOT CONFIGURED / BROAD SECURITY ASSURANCE NOT ESTABLISHED`
