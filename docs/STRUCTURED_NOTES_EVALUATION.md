# Structured Notes evaluation

**Historical model-quality snapshot:** these observations were produced on macOS 26.6.2 / SDK 26.5 using the frozen D source identified below. The live production file has since received the iOS 27 API migration and does not have that historical hash. Results, frozen files and comparisons here remain unchanged; none is a fresh iOS 27 model-quality result. See [current migration](IOS27_MIGRATION.md) and [verification boundaries](VERIFICATION.md).

Candidate D is a narrow improvement for existing flat bullet lists. In the fresh comparison, useful preservation increased from **3/6 to 4/6 observations** and useful, faithful corrections from **0/6 to 2/6**. It still loses explicit role information and leaves Dutch spoken corrections unresolved. These are synthetic local-model results, not a general Notes quality guarantee.

## Promoted behavior

The D snapshot promoted at evaluation time has SHA-256 `b6ae39008b04678810663c19c5297d048921fb55dbd0d3ba558640f526f27518`; that identity belongs to the retained [frozen source](intelligence-flat-notes-trials/candidate-d.swift). The subsequently migrated [current IntelligenceService.swift](../Sayso/Services/IntelligenceService.swift) is a separate source snapshot.

The special Notes copyediting prompt applies when every nonempty source line starts with a top-level `-`, `*`, or `•` bullet. An additional schema field supplies recognized literal colon labels when present. Separate headings, numbered lists, and indented nested lists are ineligible for this route and continue through ordinary Notes handling. Generation remains mandatory; there is no whole-source passthrough shortcut.

After generation, label restoration requires the same item count and an ordered correspondence across the entire list. After removing bullet markers and trimming surrounding whitespace, each item must match its source line or the body following its source label exactly, allowing only one initial lowercase character to become uppercase. Punctuation, quotation marks, other capitalization, and word changes do not qualify. A mismatch leaves the whole generated list untouched. Labels are literal source content, not inferred owners; substantive edits still depend on the model and existing guards.

This differs from candidate C, whose comparator discarded punctuation and case when comparing word sequences. D tightens that comparator without changing C's prompt or schema. C and D are distinct evaluated implementations; earlier C results are not D results. The [C-to-D patch](intelligence-notes-owners-trials/candidate-c-to-d-safety.patch) records the distinction.

## Fresh independent comparison

An independently authored [12-case structured corpus](../scripts/fixtures/intelligence-structured-notes-challenge.json) and [rubric](../scripts/fixtures/intelligence-structured-notes-challenge-criteria.md) were frozen before candidate exposure. Every case contains a separate heading, so none exercises this route. They were **not run** and contribute no model results here.

A second, independently authored [six-case flat corpus](../scripts/fixtures/intelligence-flat-notes-challenge.json) and [rubric](../scripts/fixtures/intelligence-flat-notes-challenge-criteria.md) were frozen before exposure. All six contain only top-level bullets: three preservation controls and three required corrections, balanced across English and Dutch. Each implementation ran each case twice, giving 12 observations per implementation, not 12 distinct cases.

All 24 outputs were scored anonymously on faithfulness and usefulness before implementation labels were revealed. The reviewer had no candidate-code or candidate-output exposure before authoring this corpus or scoring the anonymous packet. Root subsequently checked every source/output/error hash and every distinct output, agreeing with all judgments. The [anonymous review](intelligence-flat-notes-trials/anonymous-manual-review.json) includes the packet, fixture, rubric, and observation hashes; the [decoded review](intelligence-flat-notes-trials/manual-review-decoded.json) records reconciliation.

| Separate outcome | Baseline | D |
| --- | ---: | ---: |
| Successful preservation controls | 3/6 | 4/6 |
| Useful and faithful required corrections | 0/6 | 2/6 |
| Required corrections that remain faithful but ineffective | 2/6 | 4/6 |
| Required corrections with semantic failures | 4/6 | 0/6 |
| Automatic constraint passes, diagnostic only | 5/12 | 12/12 |

Both implementations lose the Dutch primary-contact and backup-contact role assertions in both repetitions. D preserves the English owner/status control twice, versus once for baseline. Both preserve the literal printed-warning control. D removes both English fillers and punctuates the run-on in both repetitions; baseline leaves one filler and the run-on. D's two Dutch correction cases retain the original spoken correction clauses in both repetitions. Those outputs retain recoverable meaning but fail the requested transformation. Baseline instead loses required owner assignments in those cases.

All 24 observations returned accepted output, with no final generation errors. Baseline used 12 generation attempts and D used 17, including bounded repairs. An error retaining Original would count as safe fallback, not a successful edit. The **12/12 automatic result does not establish semantic quality**: phrase and bullet-count checks miss both omitted roles and unresolved corrections. See the full [baseline report](intelligence-flat-notes-trials/baseline.json), [D report](intelligence-flat-notes-trials/candidate-d.json), and [provenance manifest](intelligence-flat-notes-trials/manifest.json).

Recorded per-observation median latency increased from 1.19 seconds to 1.71 seconds; the slowest observations were 2.15 and 2.32 seconds respectively. These are short synthetic inputs on this Mac, including repair time, not iPhone performance targets.

## Earlier investigation, kept separate

The [earlier package manifest](intelligence-notes-owners-trials/manifest.json) preserves development and independent C trials. On its development set, C preserved **5/5 controls** and completed **2/5 required edits**. On its separate independent comparison, baseline and C each preserved **2/4 controls** and completed **0/8 required edits**; each also had two control refusals. That review anonymized outputs, but its reviewer disclosed prior exposure to C's design. It is not the fresh blind D comparison above. These different corpora, variants, and review conditions are not pooled into one quality metric.

## Environment and limits

The baseline and D model reports record **macOS 26.6.2 (25G83), SDK 26.5, and Xcode 26.6 (17F113)**. They exercise the local Apple model using synthetic text. The service's generic availability message mentions an iPhone; the recorded execution environment is a Mac. These results do not validate iOS 27, physical iPhone audio, background recording, or broad multilingual quality. App build and unit/UI validation are tracked separately in [VERIFICATION.md](VERIFICATION.md).

After promotion, **29 text-rule tests passed**, including a new test method with 13 restoration cases, and the unsigned arm64 Release build passed. Release inspection verified both extensions and absence of test-only strings. The [manifest](intelligence-flat-notes-trials/manifest.json) binds those validation artifacts to the exact source. The full UI suite was not rerun for this isolated writing change; iOS 27 and physical-device validation remain unexecuted.
