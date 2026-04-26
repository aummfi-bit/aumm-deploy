# Stage E — Living design + findings log

> **Status:** Stage E open at the `stage-e` branch from `main` (commit `57cd2ce` on 2026-04-25). Companion to `docs/STAGE_E_PLAN.md`.
>
> **Audience:** Sagix, plus any future Claude session that needs the running log of decisions resolved during implementation and the incidents caught at audit.
>
> **Why this file exists:** to keep design decisions resolved *during* implementation (not pre-locked at plan-authoring time) and implementation findings out of the plan file. `docs/STAGE_E_PLAN.md` is the operational document — sub-step bodies, verbatim commit messages, the Completion Log. This file is the living archive.

---

## How this file is organized

- **Design decisions during implementation (`E-D11` onward).** `E-D1` through `E-D10` are pre-locked in `docs/STAGE_E_PLAN.md`'s "Decisions locked in before Stage E starts" table. Any new design decision resolved *during* E1 / E2 / E3 / E4 / E5 gets the next free `E-D*` number and is recorded in this file's next subsection — not retro-edited into the plan file. Matches the `C-D*` / `D-D*` convention.
- **Findings (`E10` onward).** Implementation incidents, drift caught at audit, RPC quirks, env-key surprises, scope-expansion catches, contract-interface gotchas — anything worth a numbered log entry. Numbered from `E10` to avoid collision with `E-D*` planning codes (matches the `C10` / `D10` pattern in `docs/STAGE_C_NOTES.md` and `docs/STAGE_D_NOTES.md`).
- **Cross-reference convention** (per `CLAUDE.md` §5): `E-Dn` = planning decision n; `En` (n ≥ 10) = implementation finding n; `OQ-N` = open question N from `docs/FINDINGS.md`. `Cn` / `Dn` codes carry forward across stages — Stage E entries can cite `D32` or `D36` directly without re-explaining.

---

## Design decisions during implementation

> `E-D11` onward populates as decisions are made during E1 / E2 / E3 / E4 / E5 / E9.

---

## Findings

> `E10` onward populates as implementation incidents emerge.
