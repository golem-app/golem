# How Golem presents a model choice

Status: decided on `feat/79-curated-model-selection` (issue #79)

Every earlier decision about models governed what would *run*: which engine is
composed (ADR 0002), which artifact a device gets (ADR 0003), whether a device
is admitted at all (ADR 0007), whether an artifact may claim image input
(ADR 0004). None of them governed what a user is *told* before choosing.

The per-chat picker inherited that gap. A row read

```
Gemma 4 E2B QAT
GGUF · Q4_K_XL · Images · Installed
```

which is four facts about a file and none about the choice. A row that was not
downloaded was inert and pointed at Settings. A row this build's engine could
not load was removed from the list with one sentence covering all of them. This
decision says what a row owes a user.

## Plain language leads; the artifact is Advanced

A row leads with the model's name, what it costs (size on disk), what it can do
(image input, where proven), how fast it has been here (only where measured),
and one sentence on what it is *for*. The exact artifact — engine format,
quantization, source repository — appears only under the **Advanced mode**
preference that already gates the sampling controls, the system prompt, and the
custom-repository loader.

Rejected: dropping the artifact from chat entirely. Operators read the picker
too, and Settings ▸ Models is a different screen with a different scroll
position; one toggle away is discoverable, another screen away is not.

Rejected: keeping engine and quantization on the primary line, as the design
handoff's All-models screen shows them. That screen is a first-run decision
made once with full attention; the picker is opened mid-conversation.

Consequence: display names lost their quantization. `Gemma 4 E2B QAT` is now
`Gemma 4 E2B`, and two entries of one family may share a name. The picker
appends the format token only when two rows on screen at once share one —
common in the simulated catalog, which lists all six, and reachable on a
shipping build whenever an artifact of the other engine is installed and
therefore listed under the rule below.

## The recommendation names what the build resolved

One row carries a `RECOMMENDED` badge and a sentence saying why. The key comes
from `InferenceBackendConfig.artifactKey` — the artifact
`resolveBackendPolicy`'s `auto` branch already selected from the single device
classification taken at launch — and never from a second reading of the 7 GiB
rule in the UI. Two readings could disagree; one cannot.

The reason is the user-facing half of that classification:

| Situation | Sentence |
| --- | --- |
| preferred tier | This phone has the memory for the larger model. |
| light tier, memory read | Sized to fit this phone's memory. |
| light tier, memory unreadable | The lighter model, picked because this phone's memory could not be read. |
| artifact fixed by a dart-define | This build's default model. |
| simulated backend | This build's default model. |
| refused device, or an operator sideload | *no badge at all* |

The light tier is reached two ways — a small phone, and a probe that answered
nothing (ADR 0007: unknown is not a refusal) — so `DeviceEligibility` carries
`memoryKnown` and the second case says so rather than claiming a measurement.
An explicit `GOLEM_MODEL_ARTIFACT` or `GOLEM_MODEL_PROFILE` bypasses the device
policy entirely, so no memory sentence is offered there either: the tier
explains the choice only when the choice is the one the tier makes.

Which artifacts a device may have at all is not decided here. That is
`core/domain/model_admission.dart`, the policy first run already consulted
(#26) — asked rather than restated, because when the two surfaces each answered
for themselves they disagreed, and the picker offered a light-tier phone the
larger model that onboarding had just refused it.

A simulated build never probed a phone, so it claims nothing about one; it
falls back to the state's active artifact and says only that this is the
build's default. A device outside every supported tier is recommended nothing,
because there is nothing it could be recommended.

## Absence is explained, and the explanation is not repeated

Two different absences, and they are not the same problem:

- **Installed, but this build's engine cannot load it.** Previously filtered
  out, which is what made a user who installed a model in Settings unable to
  find it in chat. Now listed last, dimmed, with copy naming the engine that is
  running. Settings already keeps these visible; chat now matches.
- **Not installed and not loadable here.** Still not listed — a dead
  multi-gigabyte option (#63) — but counted, with the running engine named.

A refusal that applies to the *whole sheet* — an unsupported device, an
operator sideload — is spelled out once in the footnote, and each row says only
that it is refused. Six copies of one sentence explain it no better than one.

The type system carries this: `ModelChoice` asserts that a row a user cannot
choose has a reason, so a new refusal cannot be added without copy.

## Downloading is reachable from the choice

A row that is not installed offers `Download · <size>`, then progress with
Pause, then Resume or Retry. It calls the same `ModelController` methods
Settings calls, so verification, receipts, reconciliation and the disk
preflight are one implementation with two entrances.

Cancel and delete stay in Settings. A transient sheet is the wrong place to
discard gigabytes, and the confirmation such an action needs does not belong
over a chat.

On a refused device the affordance is **withheld, not disabled** — the rule
ADR 0007 set for the model cards, for the same reason: a full-width button that
does nothing when tapped undoes the honesty of the copy beside it.

## No number without a measurement

The row quotes a decode rate only where a generation recorded one for that
artifact (`core/domain/model_speed.dart`), and labels the fake's canned rate
`simulated` rather than "on this phone". A model never run here shows no speed
at all, and the design handoff's "about 22 tok/s" on an unrun model is
deliberately not implemented.

Summaries describe shape and speed, never answer quality. The only comparative
evidence this project holds is decode rates and the records under
`docs/evals/`, and Qwen 3.5 2B's accuracy caveats in `../real-model-matrix.md`
are exactly why no entry claims to be the better answerer.
