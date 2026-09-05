# Golem model evaluation — 2026-09-05

- Host: macos Version 26.6.2 (Build 25G83)
- Suite: `default`
- Template profile: `gemma4` — thinking 2048/1.0/0.95, direct 2048/1.0/0.95; stop `<turn|>` [1, 106]
- Engine pins: llama.cpp b10241 (`9bd4c09e`), MLX Swift 0.31.6 / MLX Swift LM 3.31.4+31.g60bd0d78
- Timing semantics v2 (ADR 0020): `ttft s` is native request acceptance → first output token, worker dispatch, tokenization and prefill included; decode tok/s is tokens over first token → end; elapsed is acceptance → generation end.
- Mac numbers serve answer quality and relative comparison only — never quote them as mobile performance (`docs/notes/determinism-probe.md`).

## gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf · llamaCpp

- Artifact: gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf (2.44 GiB) — unsloth/gemma-4-E2B-it-qat-GGUF @ 66a399f6
- Profile: `gemma4`
- Load: 1.8 s
- Result: PASS

| prompt | ok | decode tok/s | prompt tok/s | ttft s | peak GiB | tokens | stop | fnv1a64 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| anchor-jupiter | pass | 68.1 | 234.7 | 0.094 | 0.29 | 11 | endOfSequence | `d710455907eadf55` |
| arithmetic-17x23 | pass | 68.0 | 393.7 | 0.080 | 0.29 | 3 | endOfSequence | `574702182262f0b0` |
| factual-capital | pass | 68.1 | 405.1 | 0.071 | 0.29 | 7 | endOfSequence | `8bfd779284f134df` |
| factual-author | pass | 65.9 | 272.5 | 0.071 | 0.30 | 33 | endOfSequence | `05f1df9ce1bcba1f` |
| instruction-one-word | pass | 63.7 | 401.7 | 0.071 | 0.30 | 1 | endOfSequence | `6baf78886c99db89` |
| instruction-json | pass | 66.5 | 446.0 | 0.097 | 0.30 | 26 | endOfSequence | `08124273507b0116` |
| instruction-translation | pass | 65.4 | 302.9 | 0.073 | 0.30 | 19 | endOfSequence | `2151341bf8261da3` |
| multi-turn-recall | pass | 66.0 | 554.4 | 0.099 | 0.30 | 7 | endOfSequence | `c531954b37e8abc4` |
| reasoning-speed | pass | 62.8 | 553.2 | 0.097 | 0.31 | 534 | endOfSequence | `527f27adba863ab3` |
| long-synthesis | pass | 62.4 | 400.3 | 0.082 | 0.30 | 176 | endOfSequence | `e489845ee39a819d` |

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
- Profile: `gemma4`
- Load: 2.9 s
- Result: PASS

| prompt | ok | decode tok/s | prompt tok/s | ttft s | peak GiB | tokens | stop | fnv1a64 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| anchor-jupiter | pass | 69.7 | 30.3 | 0.597 | 3.12 | 11 | stopToken | `d710455907eadf55` |
| arithmetic-17x23 | pass | 70.4 | 500.2 | 0.051 | 3.13 | 3 | stopToken | `574702182262f0b0` |
| factual-capital | pass | 69.4 | 433.3 | 0.051 | 3.14 | 7 | stopToken | `8bfd779284f134df` |
| factual-author | pass | 68.4 | 301.4 | 0.051 | 3.14 | 12 | stopToken | `b170d328186b2491` |
| instruction-one-word | pass | 70.9 | 452.1 | 0.049 | 3.14 | 1 | stopToken | `6baf78886c99db89` |
| instruction-json | pass | 69.5 | 544.0 | 0.067 | 3.15 | 26 | stopToken | `08124273507b0116` |
| instruction-translation | pass | 69.1 | 344.1 | 0.050 | 3.15 | 84 | stopToken | `3fdfa2b6b0acbffa` |
| multi-turn-recall | pass | 69.4 | 714.7 | 0.064 | 3.16 | 7 | stopToken | `c531954b37e8abc4` |
| reasoning-speed | pass | 67.1 | 696.1 | 0.064 | 3.17 | 701 | stopToken | `37db256a7e189b84` |
| long-synthesis | pass | 69.6 | 455.7 | 0.051 | 3.16 | 162 | stopToken | `d9036a20dd6bc30a` |

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

> The most common and direct translation of "good morning" into German is **Guten Morgen**.
> 
> However, depending on the context, you might also hear:
> 
> * **Guten Tag** (This is more of a general "good day" and can be used in the morning, especially in a slightly more formal way.)
> * **Guten Morgen** (This is the direct equivalent for the morning greeting.)

#### multi-turn-recall — pass
- ✅ contains(Zofia)
- ✅ stopped before the token budget [informational]

> Your name is Zofia.

#### reasoning-speed — pass
- ✅ regexp(\b80\b)
- ✅ stopped before the token budget [informational]

> 80

Reasoning (1830 chars): Here's my thought process for solving this problem: 1. **Understand the Goal:** The request asks for the average speed of a train given a distance (60 km) and a time (45 minutes), and the answer must be in kilometers per hour (km/h). 2. **Identify the Given Information:** * Distance ($D$) = 60 km * Time ($T$) = 45 minutes 3. **Determine the Required Formula:** Speed is calculated as Distance / Tim…

#### long-synthesis — pass
- ✅ contains(scatter)
- ✅ contains(Rayleigh) [informational]
- ✅ stopped before the token budget [informational]

> The sky appears blue due to a phenomenon called **Rayleigh scattering**.
> 
> Sunlight, which appears white to us, is actually composed of various colors, including blue and other wavelengths. When this sunlight enters Earth's atmosphere, it encounters tiny gas molecules, primarily nitrogen and oxygen.
> 
> These molecules are much smaller than the wavelengths of visible light. When sunlight strikes these molecules, the light is **scattered** in different directions. Blue light, having shorter wavelengths, is scattered most effectively by these molecules across the entire sky.
> 
> This scattered blue light then reaches our eyes, making the sky look predominantly blue, especially when the sun is high. This same principle explains why sunsets appear red—because the light has traveled through more of the atmosphere, scattering away most of the blue light before it reaches us.
