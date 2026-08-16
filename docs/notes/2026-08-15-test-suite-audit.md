# Test suite audit — 2026-08-15

## Purpose and decision boundary

An evidence-driven audit of the app and Inferno test suites for #120: which
tests carry unique fault-detection value, which do not, and what rule keeps the
answer from drifting. It touches product code twice — a behavior-preserving
extraction and one comment-and-placement correction — and it does not set a
target test count.

Baseline is `main` at `ccd16b5`. All measurements ran on macOS against the
pinned Flutter 3.44.8 / Dart 3.12.2 toolchain (an isolated 3.44.9 checkout; the
machine's global 3.47.0 cannot resolve this repository). CI is disabled while
the repository is private, so the local run is the only gate.

## Baseline

| | |
| --- | --- |
| App tests | 949, 8 skipped, 29.8 s |
| App tests with coverage instrumentation | 39.5 s |
| Line coverage, excluding `lib/l10n/generated/` | **87.4 %** (9,296 / 10,641) |
| Line coverage, counting the 13-locale ARB tables | 59.5 % (11,328 / 19,042) |
| Test source | 24,061 LOC across 70 files (69 of them test files), against 56,384 LOC of non-generated `lib` |
| Integration tests | 4,372 LOC across 15 files, none in scope |
| Inferno | 953 LOC across 8 files, most gated behind `INFERNO_*` |
| Goldens | 104 PNGs, 1.5 MB, from 46 `matchesGoldenFile` call sites |

Both coverage figures are recorded because only one of them is honest on its
own. The generated localizations are 8,401 lines of translation tables that no
test asserts line-by-line; quoting 59.5 % implies a gap that does not exist, and
quoting 87.4 % without saying what is excluded hides the exclusion.

**Speed is not the problem.** A 29.8 s suite costs nothing. The cost of
duplication here would be maintenance — one intentional behavior change breaking
N tests that assert the same thing — and false confidence from tests that cannot
fail.

## Instruments

Three, all kept so the audit is repeatable rather than a one-time opinion. The
third, `tool/mutation/decision_logic.xml`, is described under Mutation below.

**`tool/test_coverage_map.dart`** runs the suite one file at a time
(`flutter test --coverage --coverage-path`) and computes, for each test file F,
`unique(F)`: the `lib` lines F executes that every other file leaves at zero. A
full sweep is ~10 min. It also reports the three files each one overlaps most,
so a consolidation can be aimed rather than guessed.

**`tool/check_goldens.dart`** runs the suite with `GOLEM_GOLDEN_MANIFEST` set to
a directory, which makes the comparator in `app/test/flutter_test_config.dart`
record every compared golden name — one file per test process — then diffs that
set against `app/test/goldens/`. Golden names are interpolated
(`'goldens/chat-light${chromeSuffix()}.png'`), so running the suite is the only
way to know which files a run reaches.

A directory rather than one shared file, and no arguments accepted, because the
tool's output authorizes deletions and three separate paths led to it naming a
live golden as dead. Dart's `FileMode.append` is open-then-seek-to-end, **not**
`O_APPEND` — two handles on an empty file writing `AAAA` and `BB` leave `BBAA`,
four bytes — so concurrent test processes sharing one manifest can lose a line.
A filtered run reports everything it did not reach. And an empty recorded set
means the recorder never ran, not that every golden is stale; it is reported as
such rather than as 102 deletions.

## What the coverage map found

69 test files, 11,333 `lib` lines covered between them. **14 files cover nothing
uniquely.** Every one was then put to the real test: break the behavior the file
claims, run the whole suite, and see which files notice.

| candidate | verdict | evidence |
| --- | --- | --- |
| `android_packaging_test.dart` | keep | 0 lib lines by design — asserts Gradle/manifest files |
| `acceptance_hud_test.dart` | keep | covers `integration_test/support/`, which is not `lib` |
| `inferno_import_boundary_test.dart` | keep | scans source text; no lib lines to cover |
| `platform_assets_test.dart` | keep | asserts native asset/plist/storyboard files |
| `repository_resolver_live_test.dart` | keep | gated on `GOLEM_LIVE_HUB=1`; its 83 lines are imports |
| `provider_policy_test.dart` | keep | dropping one `retry: noRetry` fails 32 suites — this is the one that names which provider |
| `provider_lifecycle_test.dart` | keep | autoDispose lifecycle; no other file closes a listener and re-reads |
| `app_identity_test.dart` | keep | icon-tile fallback broken → **sole guard** |
| `context_window_test.dart` | keep | token estimate 4→5 chars → **sole guard** |
| `chat_template_fingerprint_test.dart` | keep | trailing-newline normalization narrowed → **sole guard** |
| `sheet_chrome_test.dart` | keep | keyboard padding dropped → **sole guard** |
| `response_style_test.dart` | keep | per-profile sampling table altered → **sole guard** |
| `model_label_test.dart` | keep | simulated/on-device labels swapped → also caught by `composer_test.dart`, `widget_and_golden_test.dart` |
| `progress_track_test.dart` | keep | see below |

**Nothing was removable.** Zero unique line coverage turned out to mean
"executes lines another file also executes while asserting something that file
does not" in every case examined, not "redundant".

The two files with a second guard are still worth keeping. `response_style_test.dart`
pins the layering algebra (`layerOverrides`) with named reasons per knob;
`controllers_test.dart` catches the same fault 1,300 lines away through the send
path. Duplication that shrinks the failure locus is a feature, not waste — but
it should be a decision, which is why the README rule now asks for it in words.

## One finding in shipping code

`lib/core/widgets/progress_track.dart` passes
`alignment: AlignmentDirectional.centerStart` to its `FractionallySizedBox`, with
a comment saying the default centre alignment "would grow a progress bar outward
from its middle". Mutating it to `center` changed nothing — no test noticed,
including the one named *the fill grows from the leading edge, not the middle*.

Probed directly: inside a `Stack` with the default loose fit, the
`FractionallySizedBox` shrink-wraps to its child, so the box lands wherever the
**Stack's** alignment puts it (`AlignmentDirectional.topStart` by default) and
its own `alignment` never applies. Both alignments produce
`Rect.fromLTRB(300, 297, 400, 303)`.

So the argument is inert and the comment names the wrong guarantee. What
actually holds the fill at the leading edge is the Stack default — and that *is*
guarded: mutating the Stack to `topEnd` is caught by `widget_and_golden_test.dart`.
The test file is sound; the source comment is not.

The inert argument is gone and the placement is stated on the `Stack`. Being
explicit about it changes no behavior — `AlignmentDirectional.topStart` is
already `Stack`'s default — so this is a clarification, not a defect fix, and
the right-to-left case it implies is now asserted, which nothing did before.

## Coverage gaps closed

Two files were uncovered for the same structural reason — every suite
substitutes a fake at the interface, so the implementation behind it was never
reached.

- `core/services/hugging_face_api.dart` (21.1 % of 57 lines). Only
  `repository_resolver_live_test.dart` reaches `HttpClientHuggingFaceApi`, and it
  needs `GOLEM_LIVE_HUB=1` and the real internet. Now covered offline over a
  loopback `HttpServer`: status→`HubErrorKind` for 401/403/404, 429/503 and
  anything else; malformed and non-object bodies; the byte ceiling; a server
  that ignores `Range` and starts streaming the whole file; a refused
  connection; a timeout; and the URL builders, including a git ref that must
  stay one path segment (`refs/pr/3`).
- `core/services/artifact_downloader.dart` (5.2 % of 231 lines).
  `BackgroundArtifactDownloader` reaches a **static** `FileDownloader` over a
  platform channel, so nothing in it runs off a device. The part that decides
  anything does not need the plugin, so it was extracted to
  `artifact_task_metadata.dart` — following the pattern
  `artifact_adoption_policy.dart` already set — and covered directly, including
  the rule its comment exists for: the install directory is keyed by artifact,
  not by commit, so the same destination from a re-pinned revision is **not**
  the same transfer.

The stream state machine in `download()` stays uncovered. Reaching it means
making the plugin statics injectable or mocking someone else's method channel;
neither belongs in a test-audit ticket, and it is recorded here rather than
implied away.

## Goldens

102 referenced, 104 on disk. The two orphans were
`settings-generation-{light,dark}.png`, recorded by the per-model generation
settings work in #39 and orphaned by the settings redesign in #51. Deleted.
`tool/check_goldens.dart` now fails on an unreferenced PNG and names it. It
also reports a referenced-but-missing one, but that half only fires off macOS:
here, a missing golden makes `LocalFileComparator` throw first, so the suite
goes red and the tool stops at "the recorded set is incomplete" without ever
reaching the missing list. The tool still fails — the message is just the
suite's rather than its own.

## Mutation

Bounded set in `tool/mutation/decision_logic.xml`: the files that decide things —
model activation and admission, device eligibility, download pacing, model
speed, response-style mapping, the profile spec, startup sequencing, backend
policy, context windowing, history stripping, runtime config, device
capability, both chat templates, and the artifact task metadata this ticket
extracted. 632 mutants at baseline and 637 once that extraction joined the set,
run against the suites that
reach those files (~8 s per mutant) in a throwaway `git worktree`, because
`mutation_test` rewrites sources in place. That is not a precaution — an aborted
run during this audit left a mutated file behind, and a second run started while
the first was still alive mutated the same tree underneath it, which the tool
reports as "running the test commands failed with unmodified code". One run per
worktree, and check the worktree is clean before starting.

Data classes are deliberately out: their equality and JSON round-trips are
already pinned by `domain_equality_test.dart`, and mutating them yields hundreds
of trivial mutants. Widgets, goldens and the FFI wrappers are out because their
oracle is a rendered frame or a platform channel, not an exit code.

**Baseline: 632 mutants, 102 undetected (16.14 %) — a mutation score of 83.9 %.
1 h 47 m elapsed, 2 timeouts, and "not covered by tests: 0", meaning every
mutated line was at least executed.**

| file | mutants | undetected before | after |
| --- | ---: | ---: | ---: |
| `core/domain/model_profile_spec.dart` | 204 | **58** | 1 |
| `core/domain/download_pace.dart` | 47 | 6 | 4 |
| `core/domain/model_speed.dart` | 22 | 5 | 0 |
| `core/startup/startup_sequence.dart` | 11 | 5 | 2 |
| `core/domain/device_eligibility.dart` | 56 | 4 | 4 |
| `broker/context_window.dart` | 23 | 4 | 0 |
| `broker/qwen35_chat_template.dart` | 55 | 4 | 1 |
| `core/domain/model_admission.dart` | 15 | 3 | 2 |
| `core/domain/model_activation.dart` | 25 | 2 | 0 |
| `broker/backend_policy.dart` | 59 | 2 | 1 |
| `broker/history_strip.dart` | 21 | 2 | 0 |
| `broker/device_capability.dart` | 6 | 2 | 2 |
| `broker/gemma4_chat_template.dart` | 62 | 2 | 0 |
| `broker/model_runtime_config.dart` | 16 | 1 | 0 |
| `core/domain/response_style_mapping.dart` | 10 | **0** | 0 |

The score is not spread evenly, and the concentration is the finding.
`model_profile_spec.dart` carries 58 of the 102, and reading them they fall into
two groups: every `==` inside `ProfileSampling`'s `operator ==` can be flipped to
`!=` unnoticed, and the constructor's argument guards (`topP <= 0 || topP > 1`,
`presencePenalty <= 0`) can have their boundaries moved without any test
failing. `domain_equality_test.dart` pins exactly this class of behavior for the
other value types; `ProfileSampling` was never added to it.

The engine-facing files score best — `backend_policy.dart` 2/59,
`gemma4_chat_template.dart` 2/62 — which is what a suite built around prompt
rendering and engine composition should look like.

Two caveats on the number. Mutants are not uniformly meaningful: a literal
changed in a branch nothing reads counts the same as `minimum - elapsed`
becoming `minimum + elapsed` in the splash timing, which is a real hole. And the
run cost 1 h 47 m for 632 mutants, so this is a deliberate, occasional
measurement, not something to put in front of a commit.

**After: 19 undetected of 637 (2.98 %) — a mutation score of 97.0 %, 1 h 49 m
elapsed.** Seventeen of those nineteen are listed and reasoned about below; the
other two are the run's timeouts. The five mutants the extracted
`artifact_task_metadata.dart` contributes are all killed — it was added to the
set only after review caught that a new decision file had been written without
one, which is the same omission that invalidated the first pass.

### What was done about them

Eighty-three were killed. The work fell into three shapes.

**One class, most of the count.** `model_profile_spec.dart`'s 58 were almost all
one mistake repeated: the round-trip test compared `toJson()` maps rather than
the objects, so every field comparison inside three `operator ==`
implementations could be flipped unnoticed. Comparing the objects — and adding a
field-by-field inequality table for `ProfileSampling` and `ChatTemplateSpec` —
took that file to 5. The last five were all in `validate()`, the entry point for
const-built specs, which no test called at all; `fromJson` has its own inline
checks and every existing case went through it.

**Two files with no owner.** `model_speed.dart`'s attribution walk (which
artifact a measurement belongs to, and which turns count as measurements) and
`history_strip.dart` (the only reason reasoning never returns to the model) were
reached only through the surfaces that quote them, so the assertions were about
sentences rather than rules. Both now have their own suite.

**Single rules elsewhere.** The tier credited for a choice a dart-define made;
an artifact refused by naming the engine this build runs; a loadable preference
losing to catalog order; a text-only artifact inheriting a vision template's
capability; which channel labels are visible; a chunk that opens with a stray
think close; the constants the download note quotes.

It took two passes. The first left fifteen alive across four files that should
have died: the context-window budgets sat on exact multiples of the per-message
cost, so a cost drifting by a few tokens evicted the same number of messages and
the leading-assistant trim absorbed what was left; a negative remaining byte
count was small enough that the division rounded the wrong answer back to zero;
and `model_speed_test.dart` and `history_strip_test.dart` were never added to
the mutation command, so nothing they guard was exercised against a mutant at
all. Worth recording: an instrument silently measuring less than you think is
the same failure mode as a test that cannot fail.

### The seventeen left, and why

Not every mutant should die. Each of these was traced to a reason.

| count | where | why it stays |
| ---: | --- | --- |
| 4 | `device_eligibility.dart` | `Object.hash` argument permutations. The only contract `hashCode` has is agreement with `==`, which every permutation preserves; killing them means asserting literal hash values, which is not a contract and would break on any Dart change. |
| 4 | `download_pace.dart` | Guards a downstream clamp already absorbs — `aboutMinutes` floors at one whichever way the guard reads — plus one where `mbPerSecond` can never return a negative, so `<= 0` and `== 0` cannot differ. |
| 2 | `startup_sequence.dart` | A negative `Future.delayed` is identical to zero, and `minimum + elapsed` only makes startup slower, never wrong. Killing the second needs a wall-clock upper bound, and a flaky assertion in the only gate this repo has is worse than an unkilled mutant. |
| 2 | `model_admission.dart` | The light-tier `qwen35-2b-` family filter duplicates a rule the admission block above it already enforces, so the enabled set is that family before the filter runs. Provable from the code, not an accident of the catalog. |
| 2 | `device_capability.dart` | Inside `_engineSupported`, the thin adapter to Inferno's native probe. The host suite deliberately links no native assets; the injectable `engineProbe` seam exists so the policy is testable without them, and the adapter is covered on-device. |
| 2 | two files | Mutations whose replacement is textually identical to the original. |
| 1 | `qwen35_chat_template.dart` | The leading-whitespace trim in `finish()` is unreachable: the held string is only ever a partial marker, which begins with `<`. |

Two of those are findings rather than excuses — a rule stated twice in
admission, and a dead branch in the Qwen parser — recorded here rather than
changed, because both are defensive and neither is wrong.

## Where this leaves the suite

| | before | after |
| --- | ---: | ---: |
| App tests | 949 (8 skipped) | 1051 (8 skipped) |
| Line coverage, excluding `lib/l10n/generated/` | 87.4 % | **88.6 %** |
| Line coverage, all files | 59.5 % | 60.2 % |
| Mutation score, bounded set | 83.9 % | **97.0 %** |
| Goldens on disk / referenced | 104 / 102 | 102 / 102 |
| Test files | 69 | 73 |
| `lib` lines the suite reaches | 11,333 | 11,470 |

Re-running the coverage map afterwards names the same fourteen zero-unique
files: none was created by the consolidation, and none left the list. All four
new files carry unique coverage — `hugging_face_api_test.dart` 40 lines,
`artifact_task_metadata_test.dart` 9, `history_strip_test.dart` 5,
`model_speed_test.dart` 2.

Four files were added and none removed, which is the honest shape of what the
evidence supported: the suite was not carrying dead weight, it was carrying
tests that could not fail and rules nobody owned. `model_speed_test.dart`,
`history_strip_test.dart`, `hugging_face_api_test.dart` and
`artifact_task_metadata_test.dart` exist because their subjects had no owner.
What was removed was duplication rather than files: three rejection cases in
`model_profile_spec_test.dart` superseded by stricter ones that also assert the
message, two dead golden images, and four of the five copies of Inferno's MLX
staging helper.

## What this audit did not do

- **No test-level sweep.** Attribution was measured per file. Doing it per test
  (776 of them) would cost about an hour of wall clock; the file-level result
  and the pump map both point the same way, so it was not run. If the question
  is reopened, that is the next instrument to build.
- **No changes to `app/integration_test/`.** The gated acceptance instruments
  are the only source of real-model evidence.
- **No device work.** Nothing here touches a platform surface or a
  native-inference path. The suite was the only gate.
