# Zero D-Rift Hydration Test

This packet verifies that a fresh account or session can continue Zero D-Rift
without relying on cloud memory or an old conversation. It tests reconstruction
of the project state, not recall of private history or similarity of writing style.

## Roles

- **Candidate:** the new account/session. It follows `CANDIDATE_PROMPT.md` and
  returns one read-only report using `RESPONSE_TEMPLATE.md`.
- **Evaluator:** the trusted current account/session. It checks the report against
  live Git and canonical sources using `EVALUATOR_GUIDE.md`.

The test is intentionally open-book. Reading the repository or rubric is not
cheating: the required capability is finding and applying the correct source.
A candidate cannot pass merely by repeating headings because the report requires
fresh Git state, source-backed claims, uncertainty handling and scenario reasoning.

## Run sequence

1. Finish or explicitly preserve any important uncommitted work.
2. Sign in with the candidate account and open this repository and branch.
3. Start a fresh Codex chat and send:

   ```text
   /hydration-test candidate
   ```

   If the client treats unknown slash text as a UI command, send this equivalent
   plain prompt instead:

   ```text
   Read and follow .agent/skills/zero-drift-hydration/SKILL.md in candidate mode.
   Return the complete read-only hydration report; do not modify anything.
   ```

4. Copy the complete candidate response without correcting it.
5. Return to the evaluator account, open the same repository state and send:

   ```text
   /hydration-test evaluator

   Candidate report follows:
   <paste the complete unedited report>
   ```

   Evaluator fallback prompt:

   ```text
   Read and follow .agent/skills/zero-drift-hydration/SKILL.md in evaluator mode.
   Grade the complete unedited candidate report below against live repository state.
   <paste report>
   ```

6. Accept continuity only when the evaluator returns `CONTINUITY_READY` with a
   checked score of at least 85 and no hard-fail condition.

Optional local report copies belong under `reports/`; that directory is ignored
because responses may contain machine paths or account aliases. Never store
credentials, account IDs, tokens, kubeconfig, Terraform state or raw sensitive
plans in a hydration report.

## What passing means

Passing means the candidate can determine where the project is, what is proven,
what comes next, what it may not do and which evidence is required. It does not
prove that every implementation detail is remembered or that the account has the
same personality and conversation history.
