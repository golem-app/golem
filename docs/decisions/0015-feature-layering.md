# Which feature may import which, and where the shell gate sits

Status: decided on `refactor/129-feature-layering` (issue #129)

Nothing in this app ever said which feature may reach into which, so the
answer became whatever each ticket needed. At the review that opened epic #132,
walking every `import`/`export` under `app/lib` produced this:

```
chat → models(7), settings(6), onboarding(3)
settings → chat(6), models(7), onboarding(1), legal(1)
onboarding → chat(1), models(6), settings(4), legal(1)
models → settings(1)          legal → settings(1)
```

`chat ↔ settings`, `chat ↔ onboarding` and `models ↔ settings` are cycles at
feature granularity. The session bridges (#88) exist precisely to break two
such edges — models→chat and settings→models — and they were the only two
anything defended. A rule that holds for two edges out of thirty is a habit,
not a boundary.

## The direction

Bottom to top. A feature imports strictly downward, and never sideways.

| Layer | Features | What lives there |
| --- | --- | --- |
| 5 | `settings` `onboarding` `benchmark` `eval` `splash` | Screens and flows that compose everything below |
| 4 | `chat` | Conversations, generation, composer, drawer, picker |
| 3 | `models` | Catalog, downloads, activation, storage accounting, model labels, consent, custom repositories |
| 2 | `preferences` | App-wide preferences and per-model generation settings |
| 1 | `legal` | Attribution and license copy; imports no feature |

Two rules complete it:

- **Nothing below the features may import one.** `core/`, `l10n/` and
  `broker/` are what every feature reads, so an edge the other way is a cycle
  with all of them at once.
- **Only the composition root may name them all,** and only downward.
  `app/lib/app/` and `main.dart` may import any feature — that is where
  features are wired together, which `launch_composition.dart` already says of
  itself — and no feature may import back into `app/`.

`tool/check_feature_imports.dart` enforces all three, the way
`check_inferno_imports.dart` enforces the Inferno boundary, and
`test/feature_import_boundary_test.dart` runs it under `flutter test` so the
gate that actually gets run locally catches drift. A feature missing from the
table fails the check rather than defaulting to permissive: adding a feature
means deciding, in review, where it sits.

## Sideways counts as a violation

Layer 5 has five members and no member may import another. This is not
pedantry — `settings → onboarding` existed for exactly one thing (the download
consent dialog), and it was the edge that made "settings is above onboarding"
and "onboarding is above settings" both true at once, depending on which file
you read. Anything two siblings share belongs underneath them, which is why
consent, the setup banner and the model label moved into `models`.

## The Models screen is a Settings screen

Ticket #129 asked for both the direction above *and* for
`features/settings/models_screen.dart` to move into `features/models/`, on the
grounds that a screen and its providers should live together. Those two asks
contradict each other. That screen reads three chat facts — whether a
generation is in flight, the active conversation's model key, and the whole
conversation list, from which the per-model measured decode rate is
attributed. Moving it creates `models → chat`, the edge the direction exists to
forbid.

So it stays where it is, and the rule it illustrates is stated instead: a
screen belongs to the layer of the *highest* thing it reads, not to the domain
it is named after. `/settings/models` composes chat, models and preferences;
composition is what layer 5 is for. The model providers stay in layer 3 because
chat depends on them, and a dependency that points down is the one thing the
whole table is protecting.

Rejected: publishing those three chat facts into `core/` as a reactive
projection so the screen could move. It would have satisfied the letter of the
ask by adding a second read path over chat state — a new drift surface, in a
ticket whose entire subject is drift.

## Where the storage accounting lives

`storageBreakdownProvider` counts models, chats, attachments and cache. The
chat drawer's meter watches it, and so does Settings — one consumer below chat
and one above, which is what made its old home in `features/settings/` a cycle
whichever way the direction ran.

It lives in `features/models/application/` because `ModelController` is its
only feature-level input; everything else it reads is a core seam. Its chat
input was never data but a *signal* — a cheap `(conversations, messages)`
signature that told it when to recompute. Signals point the other way from
dependencies: `ChatController` now invalidates the provider when those counts
change, which is the rule the file already followed for a cache clear
("staleness is owned by invalidation"). The count comparison survives as a
private field, so nothing recomputes more often than it did.

## The all-routes shell

`app/lib/app/app.dart` wraps every route in a `ShellRoute` whose builder is
`FirstRunGate`, and this had no record.

The gate enforces the required-model invariant (ADR 0012): until a compatible
model is downloaded and verified, no route content, semantics or keyboard
action is reachable. A `ShellRoute` is the only construct that makes that
true for *every* route including ones a deep link names directly — a wrapper
around the router's `builder`, or a redirect, would each leave a way in.

It sits below the root `Navigator` deliberately. Setup consent and the
missing-model recovery dialog are shown from inside the gated tree and need a
route context to push onto; a gate above the root Navigator has none, and those
dialogs would have nowhere to go.
