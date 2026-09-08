# Local speech-to-writing evaluation

The latest reviewed host pipeline completed all six fixtures, with **four outputs meeting the strict ready-to-use standard**, up from two in the initial run. Email now has conventional salutation/closing punctuation and a separate supplied signature; Notes retains the exhibition purpose. The workshop's ambiguous opening `Ah` and the recognition error `J Jordan` still need correction. Successful API calls do not establish writing quality.

This is synthetic audio processed by real local Apple APIs on the Mac. It is **not** an iPhone microphone test, a simulator speech test, or validation of iOS 27.

## Later polish run

The [final production report](pipeline-evaluation-2026-09-07-polished-production.json), **September 7, 2026, 18:16:05–18:16:24 UTC**, uses the same six utterances, Samantha voice, real SpeechAnalyzer pipeline and strict editorial criterion as the initial run below. It records service SHA-256 `14aedc01978708ef9475c6a0e10468e5f730e8fdb4becbd478640eba0c5a899f`, on the same macOS 26.6.2 / SDK 26.5 host. All six rewrites were accepted on their first generation attempt. It includes the final pure-helper extraction and produced the same six transcripts and rewrites as the [18:08 reviewed run](pipeline-evaluation-2026-09-07-polished-final.json). The full [writing-polish report](INTELLIGENCE_POLISH_EVALUATION.md) records broader repeated and additional-case results, failed approaches, and the source chronology.

| Fixture | Later actual outcome |
| --- | --- |
| Invitation correction | **Ready.** Resolved 18 to 28, preserved 140 euros, and retained the instruction not to order envelopes. |
| Workshop uncertainty | **Needs cleanup.** Preserved `Ah`, `I think`, `Maybe`, Priya's reply condition and the instruction not to confirm. Ambiguous `Ah` is intentionally not stripped blindly. |
| Library message | **Needs correction.** The recognition error `Hey Jordan` → `J Jordan` remains in the accepted message. No unsupported name correction was guessed. |
| Invoice email | **Ready.** Renders `Hi Morgan,`, the complete body and question, then `Many thanks,` and `Jamie` on separate lines. |
| Exhibition notes | **Ready.** Five bullets retain the exhibition purpose, three tasks, Nadia's photographs/Thursday ownership, and the undecided extra table. |
| Notebook benefits | **Ready.** Exactly two distinct source-based bullets retain diagram space and pages lying flat. |

The earlier [17:48 polished run](pipeline-evaluation-2026-09-07-polished.json) had the same six judgments, before independent review tightened deterministic quotation, email and Notes parsing. These are repeated observations of six synthetic utterances, not additional independent accuracy examples. The original two-of-six run and every weaker output remain documented below.

## Reproduce

```sh
scripts/evaluate-pipeline.sh --output /tmp/sayso-pipeline.json
```

The script compiles the production `IntelligenceService.swift` and extracts the production `SpeechTranscriptAccumulator` from `SpeechService.swift`. The harness uses an installed Samantha English (US) voice through macOS `say` at 165 words per minute, writes temporary CAF files, recognizes each file with `SpeechAnalyzer` and `SpeechTranscriber`, and passes the recognized transcript into the production writing service. Every case runs sequentially with an empty contextual vocabulary. Temporary audio and compiled binaries are removed afterward.

No voice, speech asset, or model download is requested. The harness checks for the required voice and installed English speech assets and reports a setup error if they are unavailable. It does not exercise the app's iOS audio session, microphone conversion, interruption handling, import picker, or controller. It uses the same speech analyzer API and accumulator, rather than compiling the UIKit-dependent speech service on macOS.

Exit status 0 means all selected API operations completed. Exit status 1 records a per-case synthesis, recognition, or writing error; 2 records invalid arguments, unavailable prerequisites, or failure to save the report. **Exit 0 is not a quality pass.** The report preserves each intended utterance, recognized transcript, accepted rewrite or real error, generation-attempt count, timings, and raw word error calculation. Production guards do not expose a rejected candidate, so an error would preserve its description rather than an invented reconstruction of the rejected text.

## Initial recorded run

The [raw report](pipeline-evaluation-2026-09-07.json) was produced on **September 7, 2026, 17:01:17–17:01:33 UTC**, using the arm64 Mac host on **macOS 26.6.2 (25G83), Xcode 26.6 (17F113), macOS SDK 26.5**. The six fixtures were written for this pipeline evaluation and each ran once. There was no prompt tuning, output substitution, or debug rerun. The intelligence agent's separate model calls had finished before this run.

The compiled writing service SHA-256 was `0dae760f58e4eda8c652eb14fead98a8b55394320a8cab0c94b576283c4ab9ba`. The exact local Apple model revision is not exposed by the APIs in this implementation. Reruns can differ because generation and Apple's installed voice/model revisions are not pinned.

- All six speech operations returned final results: **241 progressive updates and 18 final results** across **53.62 seconds of synthetic audio**.
- All six rewrites were accepted by the production service on the first generation attempt. There were no API errors or repair retries.
- File recognition took **0.16–0.37 seconds per case**, median **0.25 seconds**. Writing took **0.79–2.95 seconds**, median **0.97 seconds**. These are small, completed audio files processed on a Mac; they do not measure real-time microphone latency or iPhone performance. The first model call was the slowest, but the reason was not investigated.
- Raw word error rate was **7 edits / 160 reference words = 4.375%**. Six differences were filler handling or numeric/currency formatting; the remaining difference changed “Hey” into “J.” This metric is not a claim of general transcription accuracy.

## Manual assessment

The ready-to-use criterion here requires retaining all substantive information from the intended utterance, performing the requested cleanup, and producing the requested format without an obvious correction. The assessments below are editorial judgments from this single run, not automated semantic proofs. The email punctuation finding is a polish judgment, not a factual error.

| Fixture | Speech observation | Actual writing result and judgment |
| --- | --- | --- |
| Clean: invitation count correction | Removed initial “Um” and formatted “140 euros” as “€140”; preserved the correction from 18 to 28 and the instruction not to order envelopes yet. | **Ready.** “Send 28 invitation cards. The budget is 140 euros, and we should not order the envelopes yet.” Resolved the correction and retained the budget and negation. |
| Clean: workshop uncertainty | Changed “Uh” to “Ah” and “ten” to “10”; retained “I think,” “Maybe,” the instruction not to confirm, and Priya's reply condition. | **Needs cleanup.** Returned the recognized transcript unchanged, including the opening “Ah.” The uncertainty and condition are safe, but the requested filler cleanup did not happen. |
| Message: library and bakery | Changed “Hey Jordan” to **“J Jordan”** and “twenty” to “20.” The library's early closing, proposed bakery meeting, question, and approximate arrival time survived. | **Needs correction.** Removed “um” but kept “J Jordan.” This is a recognition error that propagated into an accepted rewrite. The model could not reliably infer the intended greeting from that transcript. |
| Email: invoice and supplied closing | All words matched after normalization, but speech punctuated the greeting as “Hi Morgan.” and the closing as “Many thanks. Jamie.” | **Readable, needs polish.** Produced separate greeting, body, and closing paragraphs and preserved the returned lamp, correction request, Friday deadline, and supplied name. It retained the awkward greeting/closing punctuation. A conventional salutation comma and separate signature line would be cleaner. |
| Notes: exhibition tasks and ownership | Word-for-word match after punctuation normalization. | **Mostly useful, loses context.** Correctly produced five bullets: print labels, check projector, count chairs, Nadia collecting framed photographs on Thursday, and the undecided extra table. It omitted **“For the exhibition,”** so the result loses the stated purpose when read on its own. |
| Custom: two notebook benefits | Removed initial “Um”; all remaining words matched. | **Ready.** Produced exactly two bullets: “I prefer the larger notebook because there is more room for diagrams.” and “The pages lie flat on my desk.” The preference and both benefits remain. |

The two strong examples show that the actual speech-to-writing route can resolve a numeric correction and fulfill a custom list request. The weaker examples show why preserving Original and providing editing remain necessary. In particular, passing writing guards did not detect a lost topic or guarantee cleanup and polished email formatting. These observations do not replace the broader failures documented in [the writing evaluation](INTELLIGENCE_EVALUATION.md).

## Word error interpretation and limits

The harness lowercases, folds curly apostrophes, strips punctuation, and computes Levenshtein substitutions, deletions, and insertions over words. Numeric words are not equated with digits. A separate Python implementation independently recomputed the six edit distances and word counts from the raw report; all matched the Swift calculation.

| Fixture | Substitutions | Deletions | Insertions | Reference words | Raw WER |
| --- | ---: | ---: | ---: | ---: | ---: |
| Invitation correction | 0 | 2 | 0 | 22 | 9.09% |
| Workshop uncertainty | 2 | 0 | 0 | 27 | 7.41% |
| Library message | 2 | 0 | 0 | 24 | 8.33% |
| Invoice email | 0 | 0 | 0 | 33 | 0% |
| Exhibition notes | 0 | 0 | 0 | 33 | 0% |
| Notebook benefits | 0 | 1 | 0 | 21 | 4.76% |

The invitation deletions are the filler “Um” and the token “euros,” represented by a currency symbol that normalization removes. The workshop substitutions are “Uh” → “Ah” and “ten” → “10.” The message substitutions are “Hey” → “J” and “twenty” → “20.” The notebook deletion is “Um.” Consequently, raw WER both penalizes useful formatting and misses punctuation defects. A zero WER also says nothing about later model changes, such as the Notes context omission.

These short, clearly articulated TTS passages lack real accents, room noise, conversational pacing, microphone variation, and most spoken corrections. They deliberately cover only English and one voice. Phone audio, long recordings, interruption behavior, other languages, difficult names, and the intended iOS 27 model/runtime still require separate validation.
