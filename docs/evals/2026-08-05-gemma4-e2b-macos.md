# Golem model evaluation — 2026-08-05

- Host: macos Version 26.5.2 (Build 25F84)
- Engine pins: llama.cpp b10241 (`9bd4c09e`), MLX Swift 0.31.6 / MLX Swift LM 3.31.4
- Mac numbers serve answer quality and relative comparison only — never quote them as mobile performance (`docs/notes/determinism-probe.md`).

## gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf · llamaCpp

- Artifact: gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf (2.44 GiB) — unsloth/gemma-4-E2B-it-qat-GGUF @ 66a399f6
- Load: 11.9 s
- Result: PASS

| prompt | ok | decode tok/s | prompt tok/s | ttft s | peak GiB | tokens | stop | fnv1a64 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| anchor-jupiter | pass | 50.1 | 58.1 | 0.057 | 0.31 | 11 | endOfSequence | `d710455907eadf55` |
| arithmetic-17x23 | pass | 26.1 | 78.1 | 0.072 | 0.32 | 3 | endOfSequence | `574702182262f0b0` |
| factual-capital | pass | 46.0 | 10555.1 | 0.054 | 0.32 | 7 | endOfSequence | `8bfd779284f134df` |
| factual-author | pass | 64.5 | 7322.1 | 0.054 | 0.32 | 33 | endOfSequence | `05f1df9ce1bcba1f` |
| instruction-one-word | pass | 14.4 | 10706.2 | 0.054 | 0.32 | 1 | endOfSequence | `6baf78886c99db89` |
| instruction-json | pass | 59.3 | 16687.6 | 0.081 | 0.32 | 26 | endOfSequence | `08124273507b0116` |
| instruction-translation | pass | 59.3 | 8614.1 | 0.055 | 0.32 | 19 | endOfSequence | `2151341bf8261da3` |
| multi-turn-recall | pass | 39.3 | 3975.6 | 0.079 | 0.32 | 7 | endOfSequence | `c531954b37e8abc4` |
| reasoning-speed | pass | 71.9 | 19702.2 | 0.079 | 0.33 | 534 | endOfSequence | `527f27adba863ab3` |
| long-synthesis | pass | 70.9 | 10561.4 | 0.055 | 0.33 | 176 | endOfSequence | `e489845ee39a819d` |

### Answers

#### anchor-jupiter — pass
- ✅ contains(Jupiter)

> The largest planet in the solar system is **Jupiter**.

#### arithmetic-17x23 — pass
- ✅ regexp(\b391\b)

> 391

#### factual-capital — pass
- ✅ contains(Paris)

> The capital of France is Paris.

#### factual-author — pass
- ✅ contains(Shakespeare)

> William Shakespeare wrote the play *Hamlet*.
> 
> It is widely considered to be his most famous play and one of the most influential works in English literature.

#### instruction-one-word — pass
- ✅ contains(yellow)
- ✅ regexp(^\W*\w+\W*$) [informational]

> Yellow

#### instruction-json — pass
- ✅ contains("planet_count")
- ✅ regexp(\b8\b)
- ❌ notContains(```) [informational]

> ```json
> {
>   "name": "Solar System",
>   "planet_count": 8
> }
> ```

#### instruction-translation — pass
- ✅ contains(guten morgen)

> The most common and direct translation of "good morning" in German is **Guten Morgen**.

#### multi-turn-recall — pass
- ✅ contains(Zofia)

> Your name is Zofia.

#### reasoning-speed — pass
- ✅ regexp(\b80\b)

> 80

Reasoning (1409 chars): Here's the thinking process to solve the problem: 1. **Identify the given information:** * Distance ($D$) = 60 km * Time ($T$) = 45 minutes 2. **Identify the goal:** * Calculate the average speed ($S$) in kilometers per hour (km/h). 3. **Determine the required formula:** * Average Speed = Distance / Time 4. **Check units:** * The distance is in km (good). * The time is in minutes, but the required…

#### long-synthesis — pass
- ✅ contains(scatter)
- ✅ contains(Rayleigh) [informational]

> The sky appears blue primarily due to a phenomenon called **Rayleigh scattering**. Sunlight, which appears white to us, is actually composed of all the colors of the rainbow.
> 
> When sunlight enters the Earth's atmosphere, it strikes tiny gas molecules, like nitrogen and oxygen. These molecules scatter the light in different directions. Because blue and violet light have shorter wavelengths than other colors (like red and orange), they are scattered much more effectively by these atmospheric particles. 
> 
> This means that blue light is scattered across the entire sky, making it the color we see most. While violet light is scattered even more, the sky appears blue because our eyes are more sensitive to the amount of blue light that reaches us from every direction. When the sun is low on the horizon (sunrise or sunset), the light travels through more atmosphere, scattering away the blue and leaving us with warmer colors.

## gemma-4-e2b-it-4bit · mlx

- Artifact: gemma-4-e2b-it-4bit (3.34 GiB) — mlx-community/gemma-4-e2b-it-4bit @ 23876752
- Load: 2.3 s
- Result: PASS

| prompt | ok | decode tok/s | prompt tok/s | ttft s | peak GiB | tokens | stop | fnv1a64 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| anchor-jupiter | pass | 75.0 | 76.1 | 0.000 | 2.84 | 11 | stopToken | `d710455907eadf55` |
| arithmetic-17x23 | pass | 74.5 | 255.2 | 0.000 | 2.89 | 3 | stopToken | `574702182262f0b0` |
| factual-capital | pass | 75.4 | 224.3 | 0.000 | 2.89 | 7 | stopToken | `8bfd779284f134df` |
| factual-author | pass | 74.8 | 155.8 | 0.000 | 2.87 | 12 | stopToken | `b170d328186b2491` |
| instruction-one-word | pass | 74.0 | 226.2 | 0.000 | 2.87 | 1 | stopToken | `6baf78886c99db89` |
| instruction-json | pass | 59.8 | 69.7 | 0.000 | 2.91 | 26 | stopToken | `08124273507b0116` |
| instruction-translation | pass | 74.5 | 175.5 | 0.000 | 2.88 | 72 | stopToken | `693d79f2dd3cdb3e` |
| multi-turn-recall | pass | 74.6 | 161.8 | 0.000 | 2.94 | 7 | stopToken | `c531954b37e8abc4` |
| reasoning-speed | pass | 72.0 | 276.6 | 0.000 | 2.94 | 452 | stopToken | `43d0bb9a086b6541` |
| long-synthesis | pass | 74.3 | 220.6 | 0.000 | 2.90 | 157 | stopToken | `adb1e038f98832a5` |

### Answers

#### anchor-jupiter — pass
- ✅ contains(Jupiter)

> The largest planet in the solar system is **Jupiter**.

#### arithmetic-17x23 — pass
- ✅ regexp(\b391\b)

> 391

#### factual-capital — pass
- ✅ contains(Paris)

> The capital of France is Paris.

#### factual-author — pass
- ✅ contains(Shakespeare)

> The play *Hamlet* was written by **William Shakespeare**.

#### instruction-one-word — pass
- ✅ contains(yellow)
- ✅ regexp(^\W*\w+\W*$) [informational]

> Yellow

#### instruction-json — pass
- ✅ contains("planet_count")
- ✅ regexp(\b8\b)
- ❌ notContains(```) [informational]

> ```json
> {
>   "name": "Solar System",
>   "planet_count": 8
> }
> ```

#### instruction-translation — pass
- ✅ contains(guten morgen)

> The most common and direct translation of "good morning" in German is **Guten Morgen**.
> 
> However, depending on the context, you might also hear:
> 
> * **Guten Tag** (More general, used throughout the morning and afternoon, similar to "good day")
> * **Morgen** (Used informally, sometimes just as a greeting)

#### multi-turn-recall — pass
- ✅ contains(Zofia)

> Your name is Zofia.

#### reasoning-speed — pass
- ✅ regexp(\b80\b)

> 80

Reasoning (1225 chars): Here's my thought process for solving this problem: 1. **Understand the Goal:** The request asks for the average speed of a train given a distance (60 km) and a time (45 minutes), and the answer must be in kilometers per hour (km/h). 2. **Identify the Given Information:** * Distance ($D$) = 60 km * Time ($T$) = 45 minutes 3. **Determine the Required Units:** The final speed must be in km/h. This m…

#### long-synthesis — pass
- ✅ contains(scatter)
- ✅ contains(Rayleigh) [informational]

> The sky appears blue due to a phenomenon called **Rayleigh scattering**.
> 
> Sunlight, which appears white to us, is actually composed of various colors, including blue and other wavelengths. When this sunlight enters Earth's atmosphere, it encounters tiny molecules, primarily nitrogen and oxygen. These molecules are much smaller than the wavelength of visible light.
> 
> These molecules scatter the shorter, blue wavelengths of sunlight more effectively than the longer, red wavelengths. This scattering redirects the blue light in all directions across the sky, making our view of the sky predominantly blue. This is why the sky looks blue during the day, and it's also why sunsets and sunrises often display vibrant reds and oranges (because the light has traveled through more of the atmosphere, scattering away most of the blue).
