# Frozen flat Notes challenge v1

Corpus: `intelligence-flat-notes-challenge.json`, ID `flat-notes-challenge-2026-09-07-v1`. These are six new synthetic cases independently authored before candidate code or output exposure. They do not replace or modify either earlier challenge corpus. Exact inputs were kept from the candidate author until freezing.

Every source consists solely of top-level `- ` bullet lines: no separate heading, blank line, indentation, or nested list. This isolates flat-list behavior without assuming that every colon prefix represents an owner.

| Class | Cases, omitting `flat-notes-` |
| --- | --- |
| Preservation controls | `en-owner-and-status-preserve`, `nl-role-labels-preserve`, `en-literal-colon-preserve` |
| Required corrections | `nl-corrected-owner-transform`, `en-filler-runons-transform`, `nl-recipient-deadline-transform` |

There are three English and three Dutch cases. Preservation controls can pass with accepted unchanged output because their source is already useful. The correction cases must remove their stated flaws: broad passthrough cannot pass. Apparent owner labels can be superseded by explicit corrections, while status, role, and quoted-content prefixes must not become invented assignments.

Freeze both file hashes before evaluation. Use the same fixture file, model environment, vocabulary, and repetition count for each implementation. Keep every output, rejection, error, attempt count, and latency. Review anonymously before exposing implementation identity. Once used for tuning, later runs are challenge regression evidence rather than independent holdout evidence.

Score each output on two independent axes:

- **Faithfulness:** all current owners, recipients, roles, objects, deadlines, scope, uncertainty, negation, dependencies, and literal-content boundaries remain correct. Resolve spoken corrections before judging the active assignments. The occurrence of a name or date somewhere in a list is not proof that its relationship survived.
- **Useful Notes:** the output contains the expected complete, readable bullets. Already-good controls may remain unchanged. Required corrections must actually remove the stated filler/run-on or superseded assignment. Formatting-only edits, arbitrary splitting, duplicate tasks, and competing current assignments do not pass.

Use every `usefulEditCriteria` entry in the JSON. Allow faithful synonyms, natural source-language phrasing, equivalent bullet markers, and clear semantic owner wording in place of literal `Name:` labels. The literal-content case separately specifies which inner words and colon must remain intact. Do not introduce an unstated golden paraphrase.

Mechanical phrase checks and bullet ranges are diagnostic. A mechanical pass cannot excuse a wrong assignment or retained correction. A harmless equivalent deadline phrase can miss a required substring; record that diagnostic mismatch separately from the manual judgment. Report the three preservation controls and three required corrections separately so safe preservation cannot hide failed transformations.

Classify accepted outputs as successful preservation, useful-and-faithful correction, semantic failure, or faithful but ineffective formatting. A rejected generation with Original retained is safe fallback, not successful rewriting. Distinguish harness/model-availability errors. Record a short concrete reason for each axis, case, and repetition. This bounded synthetic set does not validate physical audio, iOS 27, background behavior, or broad language quality.
