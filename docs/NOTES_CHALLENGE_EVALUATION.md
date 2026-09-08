# Notes challenge — 7 September 2026

**Notes writing is not yet consistently useful.** A fresh 16-case English/Dutch challenge, repeated twice, produced **11/28 faithful, useful transformations** and preserved **2/4 already-good controls**. Three separate development experiments were rejected; the production writing service was not changed.

That statement describes this challenge and its three experiments. A subsequent [flat Notes investigation](STRUCTURED_NOTES_EVALUATION.md) promoted a narrow label-preservation change, with separately reported evidence and continuing role/correction failures. The 16-case results below remain tied to their recorded earlier service hash.

## Independent challenge

An agent prepared [16 fixtures](../scripts/fixtures/intelligence-notes-challenge.json) and a [semantic rubric](../scripts/fixtures/intelligence-notes-challenge-criteria.md) before seeing candidate outputs. The fixture SHA-256 was frozen as `d10cd132e17d4db2cf6b9162eddba8b4c07beb27ac110c2c77fda3cd52a89d68`. Eight cases are English and eight Dutch. Fourteen require a transformation; two are already-good controls. Cases cover owners, deadlines, shared and local context, conjunctions within one task, uncertainty, corrections and conditional instructions. They do not duplicate the existing source fixtures.

The real local Mac model ran production service SHA-256 `14aedc01978708ef9475c6a0e10468e5f730e8fdb4becbd478640eba0c5a899f` sequentially from **19:53:32 to 19:54:16 UTC**. The [raw report](intelligence-notes-challenge-2026-09-07.json) contains source, output/error, constraints, attempts and runtime metadata. Environment: Apple silicon Mac, macOS 26.6.2 (25G83), Xcode 26.6 (17F113), SDK 26.5. This is not iPhone or iOS 27 model evidence.

| Outcome | Transformations | Already-good controls |
| --- | ---: | ---: |
| Faithful and useful, or control preserved | 11/28 | 2/4 |
| Faithful meaning, but poor writing | 1/28 | 0/4 |
| Accepted output loses or changes meaning | 10/28 | 2/4 |
| Generation rejected; Original retained | 6/28 | 0/4 |

Mechanical constraints pass **18/32**, but miss context and grammar failures. They are not the quality score. Repeated outputs are correlated; this small, deliberately challenging synthetic set does not estimate real-world accuracy and must not be pooled with earlier cohorts.

An independent agent manually assessed every run against the frozen criteria, then the root agent read every source/output and reconciled the findings. The [manual record](intelligence-notes-challenge-manual-2026-09-07.json) binds each judgment to hashes and preserves its reason. Reviewers knew this was the production baseline; the review was not blinded. No candidate was tuned using these results during this evaluation.

## Concrete failures

- Both volunteer-shift outputs preserve owners and times but drop the shared radio-shift context. Phrase checks pass; faithfulness fails.
- Both Dutch poetry-evening outputs remove Sander as the ticket owner and misread “los daarvan” as part of the ticket task.
- Both bicycle-workshop outputs attach the repair-collection condition to helmet counting instead of returning old parts, and lose the workshop context. All mechanical checks pass.
- Corrections to the panel/date and receipt/warranty recipients become contradictory instructions retaining the superseded actions. Both repetitions fail.
- Both English already-good controls remove Cora as the rehearsal-room owner. Existing Notes formatting is not a reason to tolerate that loss.
- One Dutch label-check run preserves the intended check and recipient but produces the ungrammatical “Controleer van … staan”. It fails useful writing despite passing phrase checks.

The overnight-test scope remains understandable in the first bullet and subsequent test references, so both runs pass. Joint comparisons, uncertainty and conjunctive conditions are also preserved in several cases. Safe rejection is recorded separately from successful Notes writing; accepted semantic failures show that the lexical guards are incomplete.

## Rejected development experiments

Before the independent challenge, three approaches were tried on twelve existing Notes cases. The [evidence manifest](intelligence-notes-trials/manifest.json) includes exact source snapshots, diffs, logs, available JSON reports and file hashes.

| Approach | Automatic checks | Manually useful | Decision |
| --- | ---: | ---: | --- |
| Current production baseline | 7/12 | 6/12 | Baseline; a punctuated launch loses explicit context despite passing inherited checks. |
| A: shorter segmentation prompt, no four-item example | 5/12 | 4/12 | Rejected; worse grouping and Dutch ownership. |
| B: guided source excerpt/note pairs | 1/6 completed | 1/6 completed | Stopped after repeated 45.6- and 53.8-second capacity failures; six cases unfinished. Rejected. |
| C: model-selected word boundaries, host-rendered original words | 0/12 | 0/12 | Rejected; whole-passage bullets, fragmentation or formatting errors. |

Candidate A completed its printed outputs but could not save its final JSON because the Mac ran out of disk space; the complete log remains. Candidate B has no final report, and its unfinished cases are not treated as measured outcomes. All original result bundles were retained; only duplicate exported screenshots were removed to recover space. No experimental source was promoted into the app.

## Reproduce and next gate

```sh
scripts/evaluate-intelligence.sh \
  --fixtures scripts/fixtures/intelligence-notes-challenge.json \
  --repeat 2 --output /tmp/sayso-notes-challenge.json
```

Run model evaluations sequentially, then apply the semantic rubric to each actual output. Original remains the default mode. Notes still needs better preservation and useful segmentation, and the intended iOS 27 model must be evaluated on its own SDK/runtime and later on the physical iPhone. Passing controller or UI tests does not close that writing-quality gate.
