# Writing polish evaluation — September 7, 2026

The new implementation improves useful email formatting and preserves explicit Notes context, but writing quality is still incomplete. On the six real local speech-to-writing fixtures, **four outputs are ready to use, up from two**. In the separate twelve-scenario polish corpus repeated twice, manual useful outcomes improved from **10/24 to 18/24**. The original nineteen-scenario corpus improved from **24/38 to 26/38 useful outcomes**, including two Original passthroughs. An additional eight variations repeated twice produced **15/16 useful outcomes**.

These are separate, small, synthetic cohorts. They must not be combined into an overall accuracy percentage. Repeated runs are not independent examples. The twelve polish scenarios were prepared before experiments but subsequently reused while tuning; their final results are validation evidence, not unbiased holdout accuracy. Original passthrough, a guard rejection, and faithful text that does not perform the requested cleanup are never counted as successful generative writing.

All generation used the real local Apple Intelligence model on the arm64 Mac running **macOS 26.6.2 (25G83), Xcode 26.6 (17F113), macOS SDK 26.5**. No hosted model or model download was used. These results do not validate an iPhone microphone, the iPhone model, or iOS 27. The installed APIs do not expose the exact model revision. The shared service's “this iPhone” availability sentence is app copy, not evidence that a report came from a phone.

A subsequent [fresh Notes challenge](NOTES_CHALLENGE_EVALUATION.md) found only **11/28 useful transformations** and **2/4 preserved controls**. Three segmentation experiments were rejected at that stage. A later [flat Notes change](STRUCTURED_NOTES_EVALUATION.md) improved a separate six-case challenge to **4/6 preserved controls** and **2/6 useful corrections**. The service hash below identifies this earlier evaluation; the later report records the promoted source. These cohorts remain separate, with unresolved failures.

## Production changes

Email generation edits the body through a guided field. A conservative local parser retains a supplied greeting, courtesy and sender separately, then renders conventional commas, paragraphs and signature lines. It recognizes limited English and Dutch forms; unsupported or ambiguous text remains in the body. A confident source-language hint tells the model to keep that language. This fixed the observed English greeting/closing punctuation and improved the Dutch uncertainty example without supplying fixture-specific names or sentences.

Clean applies a narrow final polish only when the source is confidently recognized as English or Dutch. It can remove punctuated opening `um`/`uh`-type pauses, while retaining uppercase initialisms, bare name-like words, `uh-huh`, `uh-oh`, ambiguous `Ah`, and uncertain or unsupported languages. The quotation rule protects recognized straight double quotes, curly double quotes and «guillemets»; other quotation forms are not covered. Changed quotation text requires matching complete ordered word sequences, including negation; ambiguous or reordered matches are rejected rather than reassigned by shared words. This deliberately refuses some legitimate reordering or paraphrasing.

Notes can retain a short, comma-delimited opening scope such as “For the exhibition,” when the first item demonstrably corresponds to the first source statement. It does not infer boundaries in unpunctuated introductions, prepend scope already retained elsewhere, or overwrite another explicit scope. Ambiguous repeated content is left alone. This protects the exhibition example, but does not solve general task segmentation or missing context.

List items also require source vocabulary support, in addition to the existing number, uncertainty, coverage, duplicate and structure checks. This caught an observed Custom output that invented a notebook benefit from an unrelated formatting example. The check is lexical, not a proof of meaning: it may refuse good paraphrases and miss changed relationships that reuse source words. There is still at most one repair attempt after a local validation error, with a fresh session and the original source. Model/runtime failures are not repeatedly retried.

## Recorded comparisons

| Corpus and run | Automatic checks | Manual useful outcomes | Remaining failures |
| --- | ---: | ---: | --- |
| Twelve new polish scenarios × 2, [baseline](intelligence-polish-trials/baseline.json), 17:14:47–17:15:18 UTC | 18/24 | 10/24 | Automatic preservation checks miss email punctuation and incomplete filler cleanup. |
| Same corpus, [candidate H](intelligence-polish-trials/polish-validation-h.json), 17:46:06–17:46:30 UTC | 18/24 | 18/24 | Three unpunctuated Notes scenarios fail twice: lost orchard context/owners, mural-restoration purpose, and library scope. Accepted outputs are still failed writing outcomes. |
| Original nineteen scenarios × 2, [candidate G](intelligence-polish-trials/original-corpus-g.json), 17:42:24–17:43:01 UTC | 30/38 | 26/38, including 2 Original | Eight automatic failures: merged launch tasks, retained superseded English/Dutch numeric values, and merged Dutch owners' tasks. Four additional English/Dutch dictated-command outputs remain run-on text despite matching constraints. |
| Eight additional variations × 2, [reviewed production](intelligence-polish-variations-2026-09-07-final.json), 18:06:36–18:06:52 UTC | 15/16 | 15/16 | One Dutch Notes run merges the vegetarian-option check and plate count into one bullet; the repeat separates all four tasks. |
| Six TTS → SpeechAnalyzer → writing fixtures, [reviewed production](pipeline-evaluation-2026-09-07-polished-final.json), 18:08:22–18:08:36 UTC | 6/6 API completions | 4/6 | The workshop still starts with ambiguous `Ah`; the library greeting retains the speech error `J Jordan`. |
| Same six pipeline fixtures, [final production](pipeline-evaluation-2026-09-07-polished-production.json), 18:16:05–18:16:24 UTC | 6/6 API completions | 4/6 | Includes the pure-helper extraction. All six transcripts and rewrites match the reviewed run; the same two outputs still need correction. |

The original-corpus comparison is **24/36 useful generative outputs versus 22/36 previously**, excluding Original. Its two improved outcomes are the Dutch hedge cleanup. The result is still well below a claim that all supported modes consistently produce useful text.

The additional variations were frozen before candidate G and include supplied initials, body uses of “thanks,” an uppercase acronym, acknowledgments, opposite quoted statements, English/Dutch opening contexts, local scope, and absent scope. Candidate G initially lost the period in a one-letter sender initial, producing [14/16 checks](intelligence-polish-trials/variations-g.json). The renderer now preserves the initial. The final 15/16 result records the remaining Notes segmentation failure instead of changing its expected four tasks.

The reviewed production reports record service SHA-256 **`da90939dbc0620c8744e263dd3e4adad5f95cfb9736f5b2a47c73817a26c2824`**. A subsequent source refactor separates language recognition from deterministic cleanup so tests can supply confidence explicitly; it leaves the production recognition and 0.8 threshold unchanged. The current SHA is **`14aedc01978708ef9475c6a0e10468e5f730e8fdb4becbd478640eba0c5a899f`**, confirmed by the final six-case real pipeline rerun. Historical candidate reports preceding hash recording remain identified by their saved source diffs and timestamps.

## Safety review and implementation checks

Independent review found and fixed concrete deterministic errors before the reviewed production runs:

- Email words such as “works best with newer hardware,” “my best wishes,” and “I liked your work best” were misread as closings. Extraction now requires appropriate boundary and supplied-name evidence.
- A phone-only signature could disappear. Unknown contact text now stays in the body; the parser never turns an unrecognized suffix into an empty sender.
- Initials such as `J. Smith` and `T.` lost punctuation or name boundaries. Ambiguous greetings such as “Hi Sam Happy Birthday” also consumed the message. The parser now retains uncertain structures as body content.
- Global filler removal damaged German `Um 18 Uhr…`, Portuguese `Um café…`, and the name `Um Bongo`. The final operation is gated on confident English/Dutch recognition and punctuated pause evidence.
- Positionally restoring quotes using a shared-word test could swap “send it” and “don't send it” between Alice and Bob. Complete ordered quotation matching now rejects that repair.
- Prepending Notes context using shared task words could attach the new studio to a task for the old house. Existing, conflicting and ambiguous scope now prevent that repair.

Standalone Swift compilation and pure checks passed all of these counterexamples. Thirteen additional XCTest methods cover the polish and review rules. An integrated simulator run exposed one test that assumed a short sentence's language confidence would match the Mac: the simulator correctly retained `um, uh, the cable is orange.` because confidence was insufficient. The test now supplies explicit language/confidence to the pure helper, with separate unknown-language, low-confidence, German and Portuguese preservation cases. This is not a relaxation of the production safety gate. The subsequent integrated v4 run passed **all 94 unit tests**, including this helper and the app's separate startup-interruption regression. UI test status is recorded separately by the app's main validation report; implementation tests do not establish model quality.

## Rejected experiments and preserved evidence

| Trial | Automatic result | Decision |
| --- | ---: | --- |
| [Development A](intelligence-polish-trials/development-a.json), 17:12:33–17:12:41 UTC | 6 API/fixture passes | Not a quality claim: exploratory fixtures lacked complete assertions. Manual inspection found duplicated Notes context, unchanged `Ah`, and an invented notebook benefit. |
| [B](intelligence-polish-trials/trial-b.json), 17:16:34–17:17:04 UTC | 15/24 | Four model-generated email fields made absent metadata unreliable. Rejected. |
| [C](intelligence-polish-trials/trial-c.json), 17:20:33–17:21:06 UTC | 15/24 | Optional email fields still hallucinated metadata. Rejected; the source-language hint was useful for Dutch body text. |
| [D](intelligence-polish-trials/trial-d.json), 17:25:29–17:25:52 UTC | 16/24 | Local envelope/body-only generation improved boundaries; one English body still remained raw. Continued with a simpler body prompt. |
| [E, email subset](intelligence-polish-trials/trial-e-email.json), 17:28:37–17:28:43 UTC | 8/8 | Simpler body prompting retained details. Local question and envelope punctuation still needed review. |
| [F](intelligence-polish-trials/trial-f.json), 17:35:49–17:36:13 UTC | 18/24 | Supported the promoted approach; unpunctuated Notes failures remained. |
| [G, original corpus](intelligence-polish-trials/original-corpus-g.json) and [variations](intelligence-polish-trials/variations-g.json) | 30/38 and 14/16 | Broader comparison retained existing limitations and exposed the sender-initial defect. |
| [H, polish validation](intelligence-polish-trials/polish-validation-h.json) | 18/24 | Repeated improvement in the tuned corpus; further review tightened deterministic parsing and restoration. |

The [trial A](intelligence-polish-trials/trial-a.patch), [B](intelligence-polish-trials/trial-b.patch), [C](intelligence-polish-trials/trial-c.patch), [D](intelligence-polish-trials/trial-d.patch), [E](intelligence-polish-trials/trial-e.patch), [F](intelligence-polish-trials/trial-f.patch), [G](intelligence-polish-trials/trial-g.patch), and [H](intelligence-polish-trials/trial-h.patch) diffs preserve the temporary candidate sources relative to the reviewed `da90939d…` service snapshot. The [helper extraction diff](intelligence-polish-trials/runtime-helper-extraction.patch) records the complete change from that snapshot to current `14aedc01…`; reverse it on a temporary copy before reconstructing a trial. These are historical reconstruction artifacts, not patches to apply to the current app. All recorded outputs and failures are retained. The earlier [polished pipeline run](pipeline-evaluation-2026-09-07-polished.json) also remains available; it predates the review fixes.

## Reproduce

```sh
scripts/evaluate-intelligence.sh --suite all --repeat 2 --output /tmp/sayso-original-corpus.json
scripts/evaluate-intelligence.sh --fixtures scripts/fixtures/intelligence-polish-holdouts.json --repeat 2 --output /tmp/sayso-polish.json
scripts/evaluate-intelligence.sh --fixtures scripts/fixtures/intelligence-polish-variations.json --repeat 2 --output /tmp/sayso-variations.json
scripts/evaluate-pipeline.sh --output /tmp/sayso-pipeline.json
```

Run model evaluations sequentially. The harness preserves source, mode, actual output/error, automatic constraints, manual criteria, generation-attempt counts, timing and current service hash. Inspect the requested editing and all semantic relationships as well as the checks; phrase matches can miss lost context, bad task boundaries, raw passthrough and reassigned facts. Six historical guard-replay expectations still pass in the recorded writing runs. Those are protective checks, not six new successful generations.

Real iPhone recordings, difficult accents/names, mixed-language text, longer dictation and the intended iOS 27 SDK/runtime remain unverified. Unsupported or uncertain cases can retain Original or refuse a rewrite; that is necessary protection, not completion of the writing-quality goal.
