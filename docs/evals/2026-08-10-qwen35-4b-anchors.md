# Qwen 3.5 4B text anchors after the #18 snapshot swap

> **Superseded for `reasoning-speed` by #80**
> (`2026-08-10-qwen35-mlx-thinking.md`): the thinking recipe changed to the
> Qwen 3.5 card's, so the 449-token / `dba9ee464930b4e1` GGUF baseline below
> is historical. Direct-mode anchors remain current.

> **Legacy timing semantics (v1)** — recorded before #57
> (`docs/decisions/0020-generation-timing-semantics.md`). The `ttft s` column
> is not a time to first token: llama.cpp measured from the end of prefill to
> the first token, and the MLX shim reconstructed the same window by
> subtracting its library-reported prompt time from the wall clock, which is
> why every MLX row below reads 0.000–0.002 s. Prefill, tokenization and
> worker dispatch are outside it. v2 also measures decode tok/s as
> `tokens − 1` over first token → end, so the tok/s columns are not over the
> same interval either. Answers, hashes, token counts and peak GiB are
> unaffected.

Re-run for #20. #18 replaced the Qwen 3.5 4B MLX artifact but did not re-run
its text anchors; this closes that gap and compares the two engines on the
exact artifacts the app pins today.

## Verdict

- **llama.cpp / GGUF — the shipping engine — passes all ten anchors**, and
  reproduces the 2026-08-05 baseline byte for byte on every shared prompt
  (`reasoning-speed`: 449 tokens, `dba9ee464930b4e1`, then and now).
- **MLX fails one anchor**: `reasoning-speed` spends its entire 4096-token
  thinking budget without reaching an answer, surfacing as the typed
  `budgetExhaustedBeforeAnswer` failure. The other nine pass.
- The 2026-08-05 MLX baseline was a *different* artifact
  (`YoozLabs/Qwen3.5-4B-qat-lean-4bit-mlx @ dc6b06e7`), so this anchor has
  never passed on the currently pinned `mlx-community/Qwen3.5-4B-MLX-4bit`.
  It is a gap on a validated-but-not-shipping engine, not a regression of a
  shipping path: `auto` composes llama.cpp on both platforms (ADR 0002).
- Five short-answer prompts hash identically across the two engines
  (`arithmetic-17x23`, `factual-capital`, `instruction-one-word`,
  `instruction-json`, `instruction-translation`), which is cross-engine
  determinism holding where sampling has little room to diverge.

Peak footprints are not comparable between the engines: llama.cpp mmaps its
weights, and clean file-backed pages are excluded from the Apple
physical-footprint metric, so its 0.34–0.43 GiB is not "less memory" than
MLX's 3.21–3.30 GiB.

## Run details

- Host: macos Version 26.6.1 (Build 25G76)
- Template profile: `qwen35` — thinking 4096/0.6/0.95, direct 2048/0.7/0.8; stop `<|im_end|>` [248046, 248044]
- Engine pins: llama.cpp b10241 (`9bd4c09e`), MLX Swift 0.31.6 / MLX Swift LM 3.31.4+31.g60bd0d78
- Mac numbers serve answer quality and relative comparison only — never quote them as mobile performance (`docs/notes/determinism-probe.md`).
## Qwen3.5-4B-qat-Q4_0.gguf · llamaCpp

- Artifact: Qwen3.5-4B-qat-Q4_0.gguf (2.37 GiB) — YoozLabs/Qwen3.5-4B-qat-GGUF @ 2d52e26b
- Profile: `qwen35`
- Load: 1.4 s
- Result: PASS

| prompt | ok | decode tok/s | prompt tok/s | ttft s | peak GiB | tokens | stop | fnv1a64 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| anchor-jupiter | pass | 39.3 | 2804.7 | 0.101 | 0.34 | 110 | endOfSequence | `436a1c1c87b8c9fd` |
| arithmetic-17x23 | pass | 18.3 | 14288.1 | 0.090 | 0.36 | 3 | endOfSequence | `574702182262f0b0` |
| factual-capital | pass | 26.8 | 12575.7 | 0.088 | 0.36 | 7 | endOfSequence | `8bfd779284f134df` |
| factual-author | pass | 38.8 | 9165.6 | 0.088 | 0.36 | 65 | endOfSequence | `b20319195c52c26a` |
| instruction-one-word | pass | 8.8 | 13327.1 | 0.088 | 0.36 | 1 | endOfSequence | `6baf78886c99db89` |
| instruction-json | pass | 31.4 | 16950.7 | 0.143 | 0.36 | 20 | endOfSequence | `0fef0c5ccef370f4` |
| instruction-translation | pass | 18.6 | 10617.8 | 0.087 | 0.36 | 3 | endOfSequence | `d8ac7c28f1265e24` |
| multi-turn-recall | pass | 22.1 | 21381.6 | 0.144 | 0.36 | 7 | endOfSequence | `c531954b37e8abc4` |
| reasoning-speed | pass | 40.4 | 18928.6 | 0.142 | 0.43 | 449 | endOfSequence | `dba9ee464930b4e1` |
| long-synthesis | pass | 40.0 | 13347.9 | 0.089 | 0.37 | 165 | endOfSequence | `c665ec00d00fc23c` |

### Answers

#### anchor-jupiter — pass
- ✅ contains(Jupiter)
- ✅ stopped before the token budget [informational]

> The largest planet in the solar system is **Jupiter**.
> 
> Discovered by ancient astronomers, Jupiter is a gas giant located fifth from the Sun. It has a diameter of approximately **139,911 kilometers**, which is more than twice the diameter of Earth. Its mass is so great (about 318 times that of Earth) that it would take more than 700 Earths to create a sphere the same volume as Jupiter. Despite its immense size, it is a planet composed primarily of hydrogen and helium.

#### arithmetic-17x23 — pass
- ✅ regexp(\b391\b)
- ✅ stopped before the token budget [informational]

> 391

#### factual-capital — pass
- ✅ contains(Paris)
- ✅ stopped before the token budget [informational]

> The capital of France is Paris.

#### factual-author — pass
- ✅ contains(Shakespeare)
- ✅ stopped before the token budget [informational]

> The play **_Hamlet_** was written by **William Shakespeare**.
> 
> It is widely considered one of the greatest tragedies in the English language and was likely written around **1599–1601**. The play has been performed and adapted countless times, becoming a cornerstone of world literature and theater history.

#### instruction-one-word — pass
- ✅ contains(yellow)
- ✅ regexp(^\W*\w+\W*$) [informational]
- ✅ stopped before the token budget [informational]

> Yellow

#### instruction-json — pass
- ✅ contains("planet_count")
- ✅ regexp(\b8\b)
- ✅ notContains(```) [informational]
- ✅ stopped before the token budget [informational]

> {
>   "name": "Solar System",
>   "planet_count": 8
> }

#### instruction-translation — pass
- ✅ contains(guten morgen)
- ✅ stopped before the token budget [informational]

> Guten Morgen

#### multi-turn-recall — pass
- ✅ contains(Zofia)
- ✅ stopped before the token budget [informational]

> Your name is Zofia.

#### reasoning-speed — pass
- ✅ regexp(\b80\b)
- ✅ stopped before the token budget [informational]

> 80

Reasoning (1077 chars): Thinking Process: 1. **Analyze the Request:** * Distance ($d$) = 60 km * Time ($t$) = 45 minutes * Goal: Calculate average speed ($v$) in km/h. * Output requirement: Final number only. 2. **Recall the Formula:** * Average Speed ($v$) = Total Distance ($d$) / Total Time ($t$) 3. **Perform Unit Conversion:** * The speed is required in km/h. * The distance is already in km. * The time is in minutes. …

#### long-synthesis — pass
- ✅ contains(scatter)
- ✅ contains(Rayleigh) [informational]
- ✅ stopped before the token budget [informational]

> The sky appears blue due to a phenomenon called **Rayleigh scattering**. As sunlight enters Earth's atmosphere, it encounters gas molecules like nitrogen and oxygen. Sunlight consists of all colors of the rainbow, each with a different wavelength. Blue light has a much shorter wavelength than other colors like red or yellow, making it scatter more easily when it hits these small atmospheric particles.
> 
> While all colors scatter, blue scatters in all directions much more strongly than the longer wavelengths. When you look up at the sky, your eyes detect this scattered blue light coming from every direction. Although the sun itself often looks yellowish-white because the blue light is scattered away from the direct path, the diffuse blue light filling the rest of the sky gives it its characteristic color. This effect is most pronounced when the sun is high in the sky.

## Qwen3.5-4B-MLX-4bit · mlx

- Artifact: Qwen3.5-4B-MLX-4bit (2.85 GiB) — mlx-community/Qwen3.5-4B-MLX-4bit @ 32f3e8ec
- Profile: `qwen35`
- Load: 2.3 s
- Result: FAIL — 1 failure(s)

| prompt | ok | decode tok/s | prompt tok/s | ttft s | peak GiB | tokens | stop | fnv1a64 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| anchor-jupiter | pass | 51.4 | 13.0 | 0.001 | 3.21 | 89 | stopToken | `b95815b2dde08e9e` |
| arithmetic-17x23 | pass | 50.8 | 163.2 | 0.000 | 3.25 | 3 | stopToken | `574702182262f0b0` |
| factual-capital | pass | 51.4 | 147.6 | 0.000 | 3.23 | 7 | stopToken | `8bfd779284f134df` |
| factual-author | pass | 51.9 | 113.4 | 0.000 | 3.23 | 110 | stopToken | `6b5fa331dff7fb32` |
| instruction-one-word | pass | 51.8 | 147.5 | 0.000 | 3.24 | 1 | stopToken | `6baf78886c99db89` |
| instruction-json | pass | 52.0 | 130.9 | 0.000 | 3.27 | 20 | stopToken | `0fef0c5ccef370f4` |
| instruction-translation | pass | 51.7 | 118.3 | 0.000 | 3.24 | 3 | stopToken | `d8ac7c28f1265e24` |
| multi-turn-recall | pass | 51.3 | 162.4 | 0.000 | 3.30 | 8 | stopToken | `da172194ffebe228` |
| reasoning-speed | error | — | — | — | — | — | — | — |
| long-synthesis | pass | 51.8 | 157.6 | 0.000 | 3.27 | 149 | stopToken | `4a0104b787e35229` |

### Answers

#### anchor-jupiter — pass
- ✅ contains(Jupiter)
- ✅ stopped before the token budget [informational]

> The largest planet in the solar system is **Jupiter**.
> 
> It is more than twice as massive as all the other planets combined. With a diameter of approximately 139,820 kilometers (86,881 miles), it is slightly smaller in size than the entire solar system's other planets, but it is still much larger than any other planet. Its mass is roughly 318 times that of Earth.

#### arithmetic-17x23 — pass
- ✅ regexp(\b391\b)
- ✅ stopped before the token budget [informational]

> 391

#### factual-capital — pass
- ✅ contains(Paris)
- ✅ stopped before the token budget [informational]

> The capital of France is Paris.

#### factual-author — pass
- ✅ contains(Shakespeare)
- ✅ stopped before the token budget [informational]

> The play **Hamlet** was written by **William Shakespeare**, one of the most famous playwrights and poets in the English language.
> 
> First published in the First Folio in 1623, *Hamlet* is widely considered Shakespeare's masterpiece. The play is a tragedy that explores themes of grief, madness, revenge, and existentialism, following the Prince of Denmark's struggle to avenge his father's murder by his uncle, Claudius. It remains one of the most frequently performed and studied works in the English theatrical canon.

#### instruction-one-word — pass
- ✅ contains(yellow)
- ✅ regexp(^\W*\w+\W*$) [informational]
- ✅ stopped before the token budget [informational]

> Yellow

#### instruction-json — pass
- ✅ contains("planet_count")
- ✅ regexp(\b8\b)
- ✅ notContains(```) [informational]
- ✅ stopped before the token budget [informational]

> {
>   "name": "Solar System",
>   "planet_count": 8
> }

#### instruction-translation — pass
- ✅ contains(guten morgen)
- ✅ stopped before the token budget [informational]

> Guten Morgen

#### multi-turn-recall — pass
- ✅ contains(Zofia)
- ✅ stopped before the token budget [informational]

> Your name is **Zofia**.

#### reasoning-speed — error
> The response used its whole token budget before reaching an answer. Try again, or turn reasoning off.

#### long-synthesis — pass
- ✅ contains(scatter)
- ✅ contains(Rayleigh) [informational]
- ✅ stopped before the token budget [informational]

> The sky appears blue due to a phenomenon called **Rayleigh scattering**. When sunlight reaches Earth's atmosphere, it interacts with gas molecules, primarily nitrogen and oxygen. Sunlight contains all colors of the visible spectrum, each with a different wavelength. Shorter wavelengths, such as blue and violet, scatter much more efficiently off these small particles than longer wavelengths like red or yellow.
> 
> Although violet light scatters even more than blue, our eyes are far more sensitive to blue, and the sun emits more energy in the blue part of the spectrum. Consequently, as sunlight passes through the atmosphere, the blue light is scattered in all directions. When you look up at the sky, your eyes detect this scattered blue light, creating the familiar blue dome overhead.
