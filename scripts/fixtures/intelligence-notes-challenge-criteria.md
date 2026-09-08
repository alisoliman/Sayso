# Frozen Notes challenge v1

Corpus: `intelligence-notes-challenge.json`, ID `notes-challenge-2026-09-07-v1`. Authored independently on 7 September 2026 after reading the evaluation schema and existing fixture inputs. The author has not viewed baseline or candidate outputs for these cases, candidate prompts, or candidate implementation changes. All names and scenarios are synthetic.

## Review protocol

Freeze and record the file hashes before the comparison. Keep these exact inputs and criteria unchanged for baseline and candidate runs, with the same model environment and repetition count. Preserve every output, error, generation attempt count, and latency; do not cherry-pick successful repetitions. Label outputs anonymously for manual review and reveal baseline/candidate identity after recording judgments. If these cases are later used to tune a candidate, describe subsequent results as challenge-set regression results, not fresh holdout evidence.

Review the source and every `usefulEditCriteria` entry for each output. The JSON intentionally asserts only stable names, deadlines, and broad list size mechanically. Automated pass counts do not establish the manual result. Accept faithful synonyms, equivalent local-language date wording, natural punctuation, and headings that preserve scope; record a harmless phrase-check mismatch separately rather than treating it as semantic loss. Notes must stay in the source language.

Score each output on two independent axes:

- **Faithfulness:** pass only when every action, owner, recipient, object, deadline, dependency, context boundary, negation, uncertainty, and resolved correction is preserved with no invented claim. A retained word assigned to the wrong person or task fails. One material relationship error is sufficient to fail.
- **Useful Notes:** pass only when the output provides the expected readable task/status grouping specified per case, with complete bullets and appropriate scope. One long bullet containing the source, an unedited unpunctuated transcript, arbitrary count-matching fragments, or duplicated/padded bullets fails. Legitimate conjunctions inside a comparison or a joint precondition stay together; separate actionable commitments should be independently scannable. Two already-good controls permit faithful unchanged output and do not require gratuitous rewriting.

An ordinary challenge output is **useful and faithful** only when both axes pass. An already-good control is **preserved** when both pass; report those controls separately from transformation wins. A rejected generation with Original retained is **safe fallback**, not a useful Notes success. An accepted output with a material semantic error is **unsafe rewrite**. An accepted faithful output with poor grouping is **faithful but not useful**. Distinguish these outcomes from harness or model availability errors.

For each judgment, record the case ID, repetition, anonymous output label, both axis results, and a short concrete reason tied to a violated or satisfied relationship. Do not use a preferred paraphrase as a hidden golden answer. The stated list size alone is never sufficient evidence.

## Coverage

| Cases | Primary challenge |
| --- | --- |
| `en-unpunctuated-shift`, `nl-unpunctuated-exchange` | Speech boundaries, shared context, owners, deadlines, unresolved status |
| `en-joint-comparison`, `nl-joint-label-check` | Multiple objects within one task; sequence and prerequisite relationships |
| `en-global-test-conditions`, `nl-local-context-exception` | Global context versus a local exception; conditional actions and rejected alternatives |
| `en-two-jobs-reference`, `nl-nested-local-restrictions` | Multiple scopes, referents, distinct actions joined by conjunctions, restrictions attached to only one task |
| `en-uncertain-freezer`, `nl-uncertain-rehearsal-owner` | Uncertainty, negation, conditional permission, tentative versus confirmed ownership |
| `en-corrected-owner`, `nl-corrected-date-and-object`, `en-recipient-swap` | Corrections whose relationships cannot be verified by count or vocabulary overlap |
| `nl-conjunctive-preconditions` | Logical AND, interim logging, and a separate negative instruction |
| `en-already-good`, `nl-already-good` | Preserve useful existing notes without unnecessary expansion or semantic drift |

All table IDs omit the common `notes-challenge-` prefix. There are 16 cases: 8 English, 8 Dutch; 14 transformation challenges and 2 already-good controls. This synthetic corpus is not evidence of physical-device audio, continuous background execution, iOS 27 compatibility, or broad language/model quality.
