# Stage F — Living design + findings log

> **Status:** Stage F open at the `stage-f` branch from `main` (commit `26178db` on 2026-04-29). Companion to `docs/STAGE_F_PLAN.md`.
>
> **Audience:** Sagix plus any future Claude session that needs the running log of decisions resolved during implementation and the incidents caught at audit.
>
> **Why this file exists:** to keep design decisions resolved *during* implementation (not pre-locked at plan-authoring time) and implementation findings out of the plan file. `docs/STAGE_F_PLAN.md` is the operational document — sub-step bodies, verbatim commit messages, the Completion Log. This file is the living archive.

---

## How this file is organized

- **Design decisions during implementation (`F-D15` onward).** `F-D1` through `F-D14` are pre-locked in `docs/STAGE_F_PLAN.md`'s "Decisions locked in before Stage F starts" table. Any new design decision resolved *during* F1 / F2 / F3 / F4 / F5 gets the next free `F-D*` number and is recorded in this file's next subsection — not retro-edited into the plan file. Matches the `C-D*` / `D-D*` / `E-D*` convention.
- **Findings (`F10` onward).** Implementation incidents, drift caught at audit, RPC quirks, env-key surprises, scope-expansion catches, contract-interface gotchas — anything worth a numbered log entry. Numbered from `F10` to avoid collision with `F-D*` planning codes (matches the `C10` / `D10` / `E10` pattern in earlier stage notes).
- **Cross-reference convention (per `CLAUDE.md` §5):** `F-Dn` = planning decision n; `Fn` (n ≥ 10) = implementation finding n; `OQ-N` = open question N from `docs/FINDINGS.md`. `Cn` / `Dn` / `En` codes carry forward across stages — Stage F entries can cite `D32` or `E10` directly without re-explaining.

---

## Design decisions during implementation

> `F-D15` onward populates as F1 sub-steps land.

---

## Findings

> `F10` onward populates as implementation incidents emerge.
