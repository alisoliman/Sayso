# Frozen structured Notes challenge v1

Corpus: `intelligence-structured-notes-challenge.json`, ID `structured-notes-challenge-2026-09-07-v1`. This independent synthetic corpus was authored before its reviewer saw the current owner-preservation investigation's candidate prompts, code, or outputs. Exact inputs were not provided to the candidate author before freezing.

## Fixed split

There are 12 cases: 6 English and 6 Dutch. Six are **preservation controls**, where accepted unchanged text can already be useful. Six are **required transformations**, where retaining source flaws must fail usefulness. The first `usefulEditCriteria` entry identifies each case's class in the evaluation report.

| Class | Case suffixes, omitting `structured-notes-` |
| --- | --- |
| Preservation controls | `en-heading-owners-preserve`, `nl-owner-and-status-labels-preserve`, `en-role-labels-preserve`, `nl-separate-headings-preserve`, `en-quoted-colon-content-preserve`, `nl-nested-owners-preserve` |
| Required transformations | `en-filler-runons-transform`, `nl-filler-runons-transform`, `en-superseded-assignment-transform`, `nl-recipient-and-direction-transform`, `en-quoted-instructions-transform`, `nl-nested-correction-transform` |

The negative cases make a blanket rule such as “text before every colon is an owner” invalid. A prefix may name an owner, a role, a decision, a global/local heading, literal quoted text, or a parent of nested tasks. An explicit correction may also supersede the apparent assignment that starts a bullet. Source text that resembles instructions to the editor remains source content.

## Blind comparison and scoring

Record both file hashes before evaluation. Keep source, vocabulary, rubric, model environment, and repetitions fixed across baseline and candidate. Retain every generation, rejection, error, attempt count, and latency. Review anonymized outputs before revealing their implementation labels. If these fixtures inform later tuning, report subsequent runs as challenge regression evidence rather than fresh holdout results.

Judge every per-case criterion on two axes:

- **Faithfulness:** every current owner, role, recipient, object, deadline, scope, negation, uncertainty, condition, quoted-content boundary, and resolved correction remains correct. Merely retaining a person's name somewhere is insufficient. For nested lists, reconstruct which parent governs each child. A single material relationship loss or invented claim fails this axis.
- **Usefulness:** the expected concise Notes structure is readable and complete. Preservation controls may remain unchanged. Required transformations must perform the stated cleanup/correction; copying already-bulleted source, protecting every colon prefix, or changing only bullet symbols cannot pass. Corrections must produce unambiguous current instructions, not parallel conflicting assignments. Complete nested or flattened forms are allowed where the case permits them.

Accept faithful paraphrases, semantic owner wording instead of literal `Name:`, equivalent bullet markers, and headings that retain the stated scope. Do not silently require a preferred rewrite. The quoted-content cases specify when the inner wording itself must stay intact. All outputs remain in their source language.

Mechanical phrase/forbidden checks and bullet ranges are deliberately incomplete diagnostics. A correct synonym or equivalent local-language deadline wording can miss a phrase check; record that mismatch separately after semantic review. Conversely, a mechanical pass never overrides wrong relationships, retained fillers, unresolved corrections, or meaningless list fragments. Nested parent labels count as bullets in the existing harness, which explains the wider ranges; their count is not a quality measure.

Report four separate outcome totals: successful preservation controls, useful-and-faithful transformations, safe fallbacks, and accepted defective outputs. For defects, separate semantic failure from faithful but ineffective formatting. A model rejection that leaves Original available is a safe fallback, not a successful transformation or accepted preservation result. Note harness/model-availability failures separately.

For each case and repetition, record the anonymous output label, both axis results, and the concrete relationship or required edit supporting the judgment. Do not combine the six preservation controls with the six required transformations into an undifferentiated headline pass rate. This corpus measures synthetic structured-Notes behavior; it does not validate physical audio, background execution, iOS 27, or general multilingual quality.
