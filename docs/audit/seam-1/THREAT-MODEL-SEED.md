# Threat-Model Seed — Seam 1: Authority and Governance

These are QUESTIONS to answer from the code in `audit-target/`, not statements
about the code. Where a prior finding (F-NN) is referenced, its record is in
`audit-context/aumm-deploy-docs/white_hat/AUREUM_WHITEHAT_OUTPUT.md`.

## Capability matrix

- Build the complete capability matrix after the Stage K migration: who holds
  what authority, over which contract, and for how long. Include the governance
  multisig (`GOVERNANCE_MULTISIG`), the governance contract, pool role accounts
  (`pauseManager`, `swapFeeManager`), and any EOA.

## Authority lifetime

- The 12-month emergency time-bomb in `AureumGovernanceAuthorizer` is claimed to
  be strictly `<` and immutable — is there any path that extends, restarts, or
  bypasses it? Is it block-based or timestamp-based, and is that base manipulable
  at the margin?
- The retained slice from decision K-D9: which functions still answer to
  `GOVERNANCE_MULTISIG`, and what can each do unilaterally?
- `setGovernanceContract` is re-settable — who can call it, and is there a path
  to point it at a hostile address?
- The Vault can swap authorizers via `setAuthorizer` — who can trigger that
  today, and does it contradict the immutability claim in the constitution?

## Governance mechanics

- `AureumGovernance` has three proposal types: check quorum, snapshot, and
  denominator handling for each. F-06 froze the denominator post-`endBlock`;
  F-15 is the sibling issue on the veto path and is ACCEPTED-RISK. Does that
  acceptance still hold against the current surface, or has context changed
  since adjudication?
- `VotingWeight`: the EMA freshness gate (F-05) — is there any consumer that
  reads weight without passing through the gate?
- Veto dedup (F-08, `hasVetoed`): is there another aggregate-weight counter
  anywhere that lacks dedup?

## Cross-cutting for this seam

- Every post-deployment mutation surface vs. the immutability claim and
  constitution §xxix (in `audit-context/spec/10_constitution.md`).
- `forge coverage` is structurally unavailable under the `via_ir` profile
  (stack-too-deep in Yul), so there is no coverage metric to lean on — flag any
  authority-bearing surface with no evidence of test execution.
