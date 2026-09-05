# Golem model evaluation — 2026-08-05

> **Legacy timing semantics (v1)** — recorded before #57
> (`docs/decisions/0020-generation-timing-semantics.md`). The `ttft s` column
> is not a time to first token: llama.cpp measured from the end of prefill to
> the first token, and the MLX shim reconstructed the same window by
> subtracting its library-reported prompt time from the wall clock, which is
> why every MLX row below reads 0.000–0.002 s. Prefill, tokenization and
> worker dispatch are outside it. The decode and prompt tok/s columns kept
> their windows to within one sampling call. Answers, hashes, token counts
> and peak GiB are unaffected.

- Host: macos Version 26.5.2 (Build 25F84)
- Engine pins: llama.cpp b10241 (`9bd4c09e`), MLX Swift 0.31.6 / MLX Swift LM 3.31.4
- Mac numbers serve answer quality and relative comparison only — never quote them as mobile performance (`docs/notes/determinism-probe.md`).

## gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf · llamaCpp

- Artifact: gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf (2.44 GiB) — unsloth/gemma-4-E2B-it-qat-GGUF @ 66a399f6
- Load: 1.6 s
- Result: PASS

| prompt | ok | decode tok/s | prompt tok/s | ttft s | peak GiB | tokens | stop | fnv1a64 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| anchor-jupiter | pass | 49.8 | 2709.1 | 0.067 | 0.30 | 11 | endOfSequence | `d710455907eadf55` |
| arithmetic-17x23 | pass | 31.0 | 6981.3 | 0.056 | 0.30 | 3 | endOfSequence | `574702182262f0b0` |
| factual-capital | pass | 46.1 | 10162.6 | 0.053 | 0.30 | 7 | endOfSequence | `8bfd779284f134df` |
| factual-author | pass | 65.4 | 7047.6 | 0.053 | 0.31 | 33 | endOfSequence | `05f1df9ce1bcba1f` |
| instruction-one-word | pass | 14.4 | 10492.0 | 0.054 | 0.31 | 1 | endOfSequence | `6baf78886c99db89` |
| instruction-json | pass | 59.6 | 14080.8 | 0.079 | 0.31 | 26 | endOfSequence | `08124273507b0116` |
| instruction-translation | pass | 59.7 | 8157.4 | 0.055 | 0.31 | 19 | endOfSequence | `2151341bf8261da3` |
| multi-turn-recall | pass | 39.4 | 18615.9 | 0.079 | 0.31 | 7 | endOfSequence | `c531954b37e8abc4` |
| reasoning-speed | pass | 71.8 | 19763.4 | 0.078 | 0.32 | 534 | endOfSequence | `527f27adba863ab3` |
| long-synthesis | pass | 70.3 | 10491.3 | 0.054 | 0.32 | 176 | endOfSequence | `e489845ee39a819d` |

### Answers

#### anchor-jupiter — pass
- ✅ contains(Jupiter)
- ✅ stopped before the token budget [informational]

> The largest planet in the solar system is **Jupiter**.

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

> William Shakespeare wrote the play *Hamlet*.
> 
> It is widely considered to be his most famous play and one of the most influential works in English literature.

#### instruction-one-word — pass
- ✅ contains(yellow)
- ✅ regexp(^\W*\w+\W*$) [informational]
- ✅ stopped before the token budget [informational]

> Yellow

#### instruction-json — pass
- ✅ contains("planet_count")
- ✅ regexp(\b8\b)
- ❌ notContains(```) [informational]
- ✅ stopped before the token budget [informational]

> ```json
> {
>   "name": "Solar System",
>   "planet_count": 8
> }
> ```

#### instruction-translation — pass
- ✅ contains(guten morgen)
- ✅ stopped before the token budget [informational]

> The most common and direct translation of "good morning" in German is **Guten Morgen**.

#### multi-turn-recall — pass
- ✅ contains(Zofia)
- ✅ stopped before the token budget [informational]

> Your name is Zofia.

#### reasoning-speed — pass
- ✅ regexp(\b80\b)
- ✅ stopped before the token budget [informational]

> 80

Reasoning (1409 chars): Here's the thinking process to solve the problem: 1. **Identify the given information:** * Distance ($D$) = 60 km * Time ($T$) = 45 minutes 2. **Identify the goal:** * Calculate the average speed ($S$) in kilometers per hour (km/h). 3. **Determine the required formula:** * Average Speed = Distance / Time 4. **Check units:** * The distance is in km (good). * The time is in minutes, but the required…

#### long-synthesis — pass
- ✅ contains(scatter)
- ✅ contains(Rayleigh) [informational]
- ✅ stopped before the token budget [informational]

> The sky appears blue primarily due to a phenomenon called **Rayleigh scattering**. Sunlight, which appears white to us, is actually composed of all the colors of the rainbow.
> 
> When sunlight enters the Earth's atmosphere, it strikes tiny gas molecules, like nitrogen and oxygen. These molecules scatter the light in different directions. Because blue and violet light have shorter wavelengths than other colors (like red and orange), they are scattered much more effectively by these atmospheric particles. 
> 
> This means that blue light is scattered across the entire sky, making it the color we see most. While violet light is scattered even more, the sky appears blue because our eyes are more sensitive to the amount of blue light that reaches us from every direction. When the sun is low on the horizon (sunrise or sunset), the light travels through more atmosphere, scattering away the blue and leaving us with warmer colors.

## gemma-4-e2b-it-4bit · mlx

- Artifact: gemma-4-e2b-it-4bit (3.34 GiB) — mlx-community/gemma-4-e2b-it-4bit @ 23876752
- Load: 2.1 s
- Result: PASS

| prompt | ok | decode tok/s | prompt tok/s | ttft s | peak GiB | tokens | stop | fnv1a64 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| anchor-jupiter | pass | 75.2 | 57.3 | 0.001 | 2.83 | 11 | stopToken | `d710455907eadf55` |
| arithmetic-17x23 | pass | 74.4 | 255.9 | 0.000 | 2.88 | 3 | stopToken | `574702182262f0b0` |
| factual-capital | pass | 75.0 | 226.1 | 0.000 | 2.87 | 7 | stopToken | `8bfd779284f134df` |
| factual-author | pass | 74.9 | 156.9 | 0.000 | 2.86 | 12 | stopToken | `b170d328186b2491` |
| instruction-one-word | pass | 73.4 | 226.6 | 0.000 | 2.86 | 1 | stopToken | `6baf78886c99db89` |
| instruction-json | pass | 73.8 | 227.0 | 0.000 | 2.90 | 26 | stopToken | `08124273507b0116` |
| instruction-translation | pass | 74.9 | 175.9 | 0.000 | 2.86 | 72 | stopToken | `693d79f2dd3cdb3e` |
| multi-turn-recall | pass | 75.1 | 282.1 | 0.000 | 2.92 | 7 | stopToken | `c531954b37e8abc4` |
| reasoning-speed | pass | 72.2 | 278.1 | 0.000 | 2.91 | 452 | stopToken | `43d0bb9a086b6541` |
| long-synthesis | pass | 74.2 | 220.0 | 0.000 | 2.87 | 157 | stopToken | `adb1e038f98832a5` |

### Answers

#### anchor-jupiter — pass
- ✅ contains(Jupiter)
- ✅ stopped before the token budget [informational]

> The largest planet in the solar system is **Jupiter**.

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

> The play *Hamlet* was written by **William Shakespeare**.

#### instruction-one-word — pass
- ✅ contains(yellow)
- ✅ regexp(^\W*\w+\W*$) [informational]
- ✅ stopped before the token budget [informational]

> Yellow

#### instruction-json — pass
- ✅ contains("planet_count")
- ✅ regexp(\b8\b)
- ❌ notContains(```) [informational]
- ✅ stopped before the token budget [informational]

> ```json
> {
>   "name": "Solar System",
>   "planet_count": 8
> }
> ```

#### instruction-translation — pass
- ✅ contains(guten morgen)
- ✅ stopped before the token budget [informational]

> The most common and direct translation of "good morning" in German is **Guten Morgen**.
> 
> However, depending on the context, you might also hear:
> 
> * **Guten Tag** (More general, used throughout the morning and afternoon, similar to "good day")
> * **Morgen** (Used informally, sometimes just as a greeting)

#### multi-turn-recall — pass
- ✅ contains(Zofia)
- ✅ stopped before the token budget [informational]

> Your name is Zofia.

#### reasoning-speed — pass
- ✅ regexp(\b80\b)
- ✅ stopped before the token budget [informational]

> 80

Reasoning (1225 chars): Here's my thought process for solving this problem: 1. **Understand the Goal:** The request asks for the average speed of a train given a distance (60 km) and a time (45 minutes), and the answer must be in kilometers per hour (km/h). 2. **Identify the Given Information:** * Distance ($D$) = 60 km * Time ($T$) = 45 minutes 3. **Determine the Required Units:** The final speed must be in km/h. This m…

#### long-synthesis — pass
- ✅ contains(scatter)
- ✅ contains(Rayleigh) [informational]
- ✅ stopped before the token budget [informational]

> The sky appears blue due to a phenomenon called **Rayleigh scattering**.
> 
> Sunlight, which appears white to us, is actually composed of various colors, including blue and other wavelengths. When this sunlight enters Earth's atmosphere, it encounters tiny molecules, primarily nitrogen and oxygen. These molecules are much smaller than the wavelength of visible light.
> 
> These molecules scatter the shorter, blue wavelengths of sunlight more effectively than the longer, red wavelengths. This scattering redirects the blue light in all directions across the sky, making our view of the sky predominantly blue. This is why the sky looks blue during the day, and it's also why sunsets and sunrises often display vibrant reds and oranges (because the light has traveled through more of the atmosphere, scattering away most of the blue).
