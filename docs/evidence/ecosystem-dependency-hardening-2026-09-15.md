# Ecosystem dependency hardening evidence — 2026-09-15

## Evidence boundary

This record reconciles repository, Vercel, and Supabase dependency state without promoting implementation, production, or security claims beyond the observed evidence. An available connector or resource is not an admitted dependency by itself.

## Source and deployment identity

- Repository: `ndrorchestration/Intellectro`.
- Production deployment remains bound to commit `3b16fbb94a61219bae6a10f19862fdaa9956f514`.
- Repository `main` advanced to `3852ede2511db151ba9259a067ec4cdfdc7bcaa1` after that deployment. GitHub compare reports two commits ahead and **zero net changed files** between `3b16fbb...` and `3852ede...`; source-tree equivalence is therefore established for that comparison, while commit identity is no longer exact.
- Fresh push CI on `3852ede...` completed SUCCESS.
- Production `/api/health` reports `runtimeMode=misconfigured`, `persistence=disabled`, `configurationReason=production_persistence_missing`.
- Correct fail-closed conclusion: the dedicated Supabase project exists and is healthy, but production persistence is **not configured/admitted** until the required production environment binding is supplied and re-verified.

## Supabase ownership and key-class boundary

- Dedicated project reference: `hibesaapldkvgkydvbds`.
- Browser/runtime contract expects `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
- The Supabase project has an active modern publishable key and an active legacy `anon` key. Key values are intentionally not recorded here.
- No service-role or secret-key material is authorized for browser exposure. A future production binding should prefer the modern publishable key class.

## Migration custody reconciliation

The live migration ledger contains 10 applied names. The repository contains 10 migration files whose semantic names map one-for-one to those live ledger names. Repository timestamps and live ledger versions differ, so version-number equality is not claimed.

| Repository migration | Git blob SHA | Live ledger version | Live ledger name | Name custody |
|---|---|---:|---|---|
| `20260911030000_social_vertical_slice.sql` | `4631bfb7860b37151f3f0781e1c8b1d18fb27290` | `20260911041848` | `social_vertical_slice` | MATCH |
| `20260911034500_persisted_alpha_hardening.sql` | `3335b215a55f33da34e42c64194e260ca825f809` | `20260911041906` | `persisted_alpha_hardening` | MATCH |
| `20260911043000_function_execute_hardening.sql` | `303c98a49aca1baf387a7cc6bd36ca9539846035` | `20260911042225` | `function_execute_hardening` | MATCH |
| `20260911050000_social_safety_hardening.sql` | `ca407237ca0b716501f500aad9aca0c5cda9538a` | `20260911053355` | `social_safety_hardening` | MATCH |
| `20260911052000_governed_action_lifecycle.sql` | `9364bfd65108ac4388077b8fd208a6c5d43ea016` | `20260911053412` | `governed_action_lifecycle` | MATCH |
| `20260911054000_provenance_receipt_boundary.sql` | `8a80163addc82aad880934663af46ffdebaf8805` | `20260911053424` | `provenance_receipt_boundary` | MATCH |
| `20260911056000_correction_appeal.sql` | `19d90d9d5ccd98705bf29d348086172f7f061f23` | `20260911053449` | `correction_appeal` | MATCH |
| `20260911060000_connection_relationships.sql` | `7b6bf375271bfef6279c4ad065d9ce5ae2f02df6` | `20260911092212` | `connection_relationships` | MATCH |
| `20260911062000_space_invitations.sql` | `f1aed115ec29afceb19b88171aba77fe94a90146` | `20260912004221` | `space_invitations` | MATCH |
| `20260911064000_performance_hardening.sql` | `e146d2df92c6c9a03e1cc1482bbd4a665991edd5` | `20260912010210` | `performance_hardening` | MATCH |

**Classification:** `NAME-CUSTODY VERIFIED / SQL-CONTENT EQUIVALENCE NOT VERIFIED`.

The migration-history API exposes version/name metadata, not the originally applied SQL bytes. Therefore the repository blob SHA cannot honestly be promoted into a live-database content hash without an independent schema/function equivalence procedure.

## Privileged RPC negative authorization

The source-bound 16-function matrix remains the canonical accounting artifact. Current open evidence cells are bounded to 25 total:

- 12 invalid-input cases;
- 7 wrong-object/scope cases;
- 4 wrong-actor cases;
- 2 invalid/stale-lifecycle cases.

Only `create_space_with_owner` is currently fully `VERIFIED` across its applicable dimensions. Matrix existence is not broad security assurance.

## Package and CI custody

Baseline controls already present before this hardening lane:

- committed npm lockfile (lockfile v3);
- `npm ci` in CI;
- lifecycle scripts disabled with `--ignore-scripts`;
- Node 22 and 24 compatibility test matrix;
- production build job.

Hardening lane controls now proposed on PR #33:

- `.npmrc` minimum release age of 7 days;
- transitive exotic dependency sources restricted to root declarations (`git`, remote URL, file, directory);
- package manager declared as `npm@11.19.0`, derived from fresh CI rather than guessed;
- production-build and dependency-custody jobs pinned to Node `24.20.0`;
- a dedicated dependency-custody CI job that asserts the Node/npm identity and release-age policy;
- explicit lockfile non-mutation check after `npm ci`;
- `npm audit signatures` provenance/signature inspection.

The first dependency-custody run on PR #33 completed SUCCESS before the explicit version pin was added and established the evidence used for the pin:

- Node `v24.20.0`;
- npm `11.19.0`;
- frozen `npm ci` completed without lockfile mutation;
- 36 packages had verified registry signatures;
- 28 packages had verified attestations.

A fresh PR run after the explicit package-manager/runtime pin remains the acceptance evidence for the final PR head.

## Remaining controls

1. Configure the two required production Supabase environment bindings in Vercel and re-deploy/re-probe `/api/health`.
2. Complete Browser Gate B with real authenticated session/persistence evidence.
3. Execute the 25 remaining privileged-RPC negative cases with retained evidence; do not use matrix completion as a substitute for broader security testing.
4. Establish stronger live migration equivalence if needed by comparing live definitions/schema to source migrations; the ledger alone cannot prove byte equivalence.
5. Protect `main` with required CI/status checks. This is a repository-administration control and is not established by source configuration alone.
6. Perform a built-artifact/public-bundle scan for elevated key material before any production-readiness claim.

## State

`SOURCE CUSTODY HARDENING IN PR / PRODUCTION PERSISTENCE NOT CONFIGURED / RPC NEGATIVE EVIDENCE PARTIAL / MIGRATION NAME CUSTODY VERIFIED / SQL-CONTENT EQUIVALENCE NOT VERIFIED / PRODUCTION READINESS NOT ESTABLISHED`
