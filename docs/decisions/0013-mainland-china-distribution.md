# ADR 0013: Mainland China distribution viability

- Status: accepted
- Date: 2026-08-13
- Issue: #102
- Decision: no-go

## Context

GOLEM can serve a mainland China user only if an owner of compatible hardware
can discover, install, update, activate, and download the pinned model without
a VPN, ADB, developer mode, or specialist instructions. Both iOS and Android
must have broad, supportable first-party distribution. One isolated OEM store
or a sideload-only APK is not sufficient.

This spike permits no mainland publisher or operator partner, paid reachability
service, artifact mirror, or China-hosted backend. It does not weaken immutable
revisions, expected sizes, SHA-256 verification, license presentation, or
offline inference. It also does not add a Simplified Chinese locale.

The implementation work proceeded before the website prerequisite was live by
explicit product-owner waiver. That waiver changed sequencing only; it did not
turn an unmet release gate into a pass.

This record is engineering evidence, not legal advice. A row marked
`counsel-required` fails the release gate until qualified mainland counsel has
provided a written conclusion for the actual developer entity and product.

## Decision

Do not distribute or localize GOLEM for mainland China now.

The public mainland iOS channel has a usable installation and update mechanism,
and several Android OEM stores have public APK submission paths. GOLEM does not,
however, have evidence that its current first-party entity can complete the
required filings and AI qualifications. The legal treatment of phone-side
offline generative AI is unresolved, and the CAC now publishes registrations
for phone-side generative-AI services. Initial mainland reachability evidence
is incomplete and already inconsistent. No real first-run download has
completed on mainland consumer connectivity for either platform or either
default model tier.

The decision rule therefore produces `no-go`: mandatory legal conclusions are
unresolved, broad Android distribution is unproven, model delivery is not
reliable enough to support without a mirror, and the required recurring
first-party operation has no assigned owner. No `zh-Hans` implementation ticket
is created.

## Distribution gate

| Channel | Ordinary install | Signed updates | Current GOLEM eligibility | Result |
| --- | --- | --- | --- | --- |
| Apple mainland App Store | Public App Store is the normal iOS channel | App Store apps update automatically by default | No verified mainland App Store record, ICP/app filing number, matching filing entity, or completed China compliance review | **Fail** |
| Huawei AppGallery | Public APK submission and search/discovery are documented | AppGallery owns the installed-app update path | Requires real-name developer verification, APP filing, privacy URL, and applicable qualifications; none is evidenced for GOLEM | **Fail** |
| Honor App Market | Public APK submission and search/discovery are documented | Store-managed releases are documented | Mainland distribution asks for APP filing information and a unified social credit identifier; GOLEM has neither | **Fail** |
| Xiaomi App Store | Public APK submission exists | Store documentation supports application updates | Current guidance requires APP filing and software-copyright/industry qualifications; generative AI calls for algorithm filing evidence; GOLEM has none | **Fail** |
| OPPO/OnePlus Software Store | Public APK submission exists | The platform documents an application update service | Submission requires APP filing, a privacy URL, copyright evidence, matching ICP information, and applicable safety/industry evidence; GOLEM has none | **Fail** |
| vivo App Store | A first-party developer platform and consumer store exist | No complete current update/qualification path was captured in this spike | No verified first-party eligibility, APP filing, AI qualification, or accepted release evidence | **Fail** |
| Tencent MyApp | A consumer Android store exists | No complete current update/qualification path was captured in this spike | No verified first-party eligibility, APP filing, AI qualification, or accepted release evidence | **Fail** |
| Signed APK on `golem.app` | Possible only after the website is live; users must allow browser-origin installation | No implemented first-party automatic-update channel | Not broad store distribution and cannot compensate for missing OEM coverage | **Fallback only; fail as primary path** |

Apple's metadata reference says apps offered in mainland China may require a
valid ICP filing number whose metadata matches the MIIT filing. Apple also
requires a privacy-policy URL. iPhone and iPad App Store downloads update
automatically by default. These facts make the Apple mechanism supportable in
principle, but do not establish GOLEM's eligibility.

Repository and account evidence contains no qualifying mainland legal entity,
unified social credit identifier, ICP/app filing, store acceptance, or assigned
China release owner. An individual Apple membership may distribute under the
member's legal name, while an organization enrollment requires a recognized
legal entity and D-U-N-S number. Neither membership form, by itself, answers the
mainland filing and AI-service questions.

## Legal and product gate

| Area | Engineering evidence | Qualification still required | Result |
| --- | --- | --- | --- |
| MIIT APP/ICP filing | GOLEM downloads model artifacts and therefore cannot be assumed to be a disconnected single-player resource. MIIT requires apps providing internet information services in China to file before operating. Apple and Android stores expose filing fields. | Confirm the proper filing route and whether the current non-mainland entity can file without a mainland operator or access provider. | **Counsel-required; fail** |
| Generative-AI / algorithm registration | The app provides generated text to users. User-supplied images are multimodal inputs only; GOLEM does not generate images. The CAC measures apply broadly to generative services offered to the public in China. A 2026 CAC notice expressly lists seven registered phone-side generative-AI services. | Determine provider identity, filing/registration, safety assessment, algorithm filing, and foreign-investment consequences for fully offline text generation. | **Counsel-required; fail** |
| AI-generated-content labeling | Current generated-text output has no China-specific explicit/implicit labeling or export metadata. The labeling measures cover generated text and require distribution platforms to verify labeling materials for AI apps. | Determine the exact UI, copied/shared/exported-text, service-agreement, and logging duties. Uploaded image inputs are not generated output and must be assessed separately under content-handling and privacy obligations. Product changes are likely. | **Counsel-required; fail** |
| Content handling | Inference is local and private; GOLEM has no server-side moderation, user account, complaint workflow, regulator-reporting path, or retained generation log. | Determine how provider duties to stop prohibited generation, handle complaints, retain required evidence, and report incidents apply without collecting private prompts. | **Counsel-required; fail** |
| PIPL | Prompts, conversations, and canonicalized user-supplied image inputs stay on-device; image attachments can participate in platform backup. Model downloads still disclose normal network metadata to Hugging Face/CDN infrastructure, and future support interactions may process user-supplied data. | Confirm notices, processor/controller roles, image-input and backup treatment, cross-border transfer implications, support handling, deletion rights, and whether any store SDK adds processing. | **Counsel-required; fail** |
| Model redistribution rights | The app fetches immutable Apache-2.0-attributed artifacts directly from their publishers, shows licenses offline, and does not operate a mirror. The existing license audit is ADR 0009. | Confirm mainland distribution of each conversion/projector artifact and whether store review requires additional authorization evidence. | **Counsel-required; fail** |
| Cryptography | TLS protects downloads and SHA-256 verifies pinned files. Apple separately requires export-compliance analysis. | Confirm Apple export declarations and mainland commercial-cryptography/import treatment for the actual binaries and service. | **Counsel-required; fail** |
| Product change | Offline inference, immutable pins, expected sizes, SHA-256, and license presentation can remain intact. | Labeling, complaint/reporting, service-agreement, and content-control obligations may require behavior not currently present and potentially inconsistent with local-only privacy. | **Unresolved; fail** |

Offline inference must not be treated as an exemption. The CAC's July 2026
phone-side registration announcement is direct evidence that device-side
execution can still enter the regulatory workflow.

## First-party endpoint and model-delivery evidence

The required protocol is three time windows over two days, covering China
Telecom, China Unicom, and China Mobile in at least three regions. Each endpoint
must prove DNS resolution, TLS, redirects, HTTP status, latency, and expected
content. The protocol was not completed, so reachability cannot pass even if an
individual probe looks healthy.

### Window 1 — 2026-08-13, approximately 14:08 Europe/London

| Target and tool | Sanitized outcome | Result |
| --- | --- | --- |
| `https://golem.app/`, local direct request | Timed out after 20 seconds without an HTTP response | **Fail** |
| `https://golem.app/`, 17CE GET | 174 probe points across 36 regions; aggregate result included non-200 responses. Telecom had no successful line summary. Unicom ranged from 0.65 s in Zhejiang to 1.61 s in Shanxi (1.13 s average). The only Mobile summary was 1.59 s in Jiangxi. Many detailed rows timed out or did not respond. | **Fail** |
| Exact pinned Gemma MLX `config.json` resolve URL, 17CE GET | 174 probe points across 35 regions; aggregate result included non-200 responses and inconsistent reported file/download sizes. No Unicom line succeeded. One mainland Telecom line in Jiangxi returned in 0.71 s; the Mobile summary was from Hong Kong, not a mainland Mobile region. | **Fail** |
| ITDOG HTTP probe | The service returned a 403 bot-verification page before a test could be submitted. | **Operationally unavailable; fail** |
| `/privacy/`, `/privacy/policy.json`, `/support/` | Not separately probed because the root site itself was not live and website issues #1/#4 plus app issue #22 remained open. | **Fail** |
| Remaining pinned resolve origins | Not run after the first exact origin already failed the carrier/content gate; two further windows were also unavailable on the decision date. | **Incomplete; fail** |

The exact pinned source origins that a future recheck must cover are:

- `mlx-community/gemma-4-e2b-it-4bit@238767527555cb75a05732a84dff5d6ba0dd6809`
- `unsloth/gemma-4-E2B-it-qat-GGUF@66a399f68ddd113b06dff02fca9523e55465d11d`
- `ggml-org/gemma-4-E2B-it-GGUF@64ef033dc9f85a88f88e70cceb0a7457366bea64`
- `mlx-community/Qwen3.5-2B-4bit@674aaa7240b91e8012fcad5d791b7dfe5ba90207`
- `unsloth/Qwen3.5-2B-GGUF@f6d5376be1edb4d416d56da11e5397a961aca8ae`
- `prithivMLmods/Qwen3.5-2B-MTP-GGUF@d4a4b305fe76ab01b541278d3078cd25c825530a`

No raw probe IP address, device identifier, local path, credential, model file,
or user/account data is retained in this record.

## Artifact and physical-device evidence

The feasibility suite is one fixed-seed, non-reasoning, 64-token prompt. It
requires both `391` and the exact phrase `计算结果是`; passing it is a
compatibility smoke, not a fluency claim.

| Artifact key | Engine | Expected bytes | Primary weights/snapshot SHA-256 | Projector SHA-256 |
| --- | --- | ---: | --- | --- |
| `gemma4-mlx` | MLX | 3,583,086,498 | `038e39a37a7667373d2c3991375446b10c96ae1d717a68674870343db376b76e` | included in snapshot |
| `qwen35-2b-mlx` | MLX | 1,749,079,691 | `713fe7e5d3c3965f7106b0d0ee17615f7869c23c8d327996df8c1196fbcf07d5` | included in snapshot |
| `gemma4-gguf` | llama.cpp | 3,177,739,040 | `e531007218dfab990486a5de7676a6932d6ea8dea233d1f698d7c21cf8a16889` | `9406f99c16d68cda4f1f0552192dcc99021ea1fc6d2fd50b1dc3ccf30d04b292` |
| `qwen35-2b-gguf` | llama.cpp | 1,579,538,240 | `cd70221bebaee0503e0f6717e174250cd7825aa88438b3aabec9ad55731d9bb1` | `526dbf85f350baf3a5107b1f14e629e94571c7cbab4277476fbdaaa8c4a31a64` |

| Device evidence | Outcome | Result |
| --- | --- | --- |
| Physical OnePlus 12R, QA, `--no-uninstall`, typography probe | Passed the gated integration test at 1.6x. Captured screen showed complete glyphs and natural wrapping with no visible clipping. Mixed model names and numbers remained legible. No obvious Japanese/Korean regional form substitution was seen, but native-speaker type review remains required before localization. | **Instrument pass; manual qualification pending** |
| Physical OnePlus 12R, `gemma4-gguf,qwen35-2b-gguf` | Both model loads failed immediately because the requested QA artifacts were not installed in the app sandbox. No generation result or performance claim was recorded. | **Evidence unavailable; fail** |
| Physical iPhone 17 | No device run was performed after the device was reserved for other work. A pre-install QA build attempt had already failed locally because no Development Team/provisioning profile was configured; it never installed or launched the app. Production identity `app.golem` was not used. | **Evidence unavailable; fail** |
| Mainland consumer connectivity, both platforms and both tiers | No free mainland device access was available to perform a first-run download, exact-size/SHA-256 verification, load, and answer without VPN or manual recovery. | **Operational inability; fail** |

## Operations and ownership

A viable first-party release needs named owners for:

- Apple mainland metadata, filings, review replies, and update releases;
- Huawei, Honor, Xiaomi, OPPO/OnePlus, vivo, and Tencent submissions and
  consistent signed updates from one protected signing lineage;
- quarterly and pre-release mainland carrier reachability checks;
- legal-change monitoring, renewals, complaints, regulator requests, and
  takedowns;
- bandwidth and provenance monitoring for every pinned Hugging Face origin;
- privacy/support response in a time zone and language users can rely on.

No such recurring ownership, filing capability, or service level is assigned.
The no-partner/no-mirror constraint means direct Hugging Face reachability is a
hard dependency rather than an incident that operations can route around.

## Reconsideration triggers

Reopen the decision only when all of the following can be evidenced together:

1. `golem.app`, `/privacy/`, `/privacy/policy.json`, and `/support/` are live,
   stable, and policy-approved.
2. Qualified mainland counsel gives written answers for MIIT filing, CAC
   generative-AI/algorithm registration, labeling, content handling, PIPL,
   model redistribution, cryptography, and the actual first-party entity.
3. The first-party entity is accepted for the mainland App Store and enough of
   Huawei, Honor, Xiaomi, OPPO/OnePlus, vivo, and Tencent to cover mainstream
   compatible Android devices with consistent signed updates.
4. 17CE and ITDOG (or approved equivalents if either is unavailable) complete
   three sanitized windows over two days across Telecom, Unicom, and Mobile in
   at least three regions for every first-party endpoint and pinned origin.
5. A physical mainland first-run succeeds for both default tiers on iOS and
   Android, including exact bytes, SHA-256, load, and a successful answer,
   without VPN or manual recovery.
6. Named first-party release, legal, support, and reachability owners accept the
   recurring work and incident policy.

Only a later `go` or `conditional-go` decision may create a `zh-Hans` child
ticket under #101.

## Sources reviewed

- Apple mainland metadata and filing fields:
  <https://developer.apple.com/help/app-store-connect/reference/app-information/app-information>
- Apple App Store updates:
  <https://support.apple.com/en-us/102629>
- Apple program enrollment and legal entities:
  <https://developer.apple.com/help/account/membership/program-enrollment>
- Apple encryption export compliance:
  <https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations>
- MIIT APP filing notice:
  <https://www.miit.gov.cn/zwgk/zcwj/wjfb/tz/art/2023/art_920db564162e4312916a01bed6540ad8.html>
- CAC generative-AI measures:
  <https://www.cac.gov.cn/2023-07/13/c_1690898327029107.htm>
- CAC phone-side generative-AI registrations:
  <https://www.cac.gov.cn/2026-07/15/c_1785861480767004.htm>
- AI-generated-content labeling measures:
  <https://www.cac.gov.cn/2025-03/14/c_1743654684782215.htm>
- Personal Information Protection Law:
  <https://www.miit.gov.cn/jgsj/zfs/fl/art/2022/art_515a4b20c12f430eab54bb4f56d89f56.html>
- Cryptography Law:
  <https://www.nca.gov.cn/sca/xxgk/2023-06/04/content_1057225.shtml>
- Huawei AppGallery distribution and filing:
  <https://developer.huawei.com/consumer/cn/appgallery/devstart/>
- Honor application review and APK publication:
  <https://developer.honor.com/cn/doc/guides/100879>
  and <https://developer.honor.com/cn/doc/guides/100884>
- Xiaomi developer registration, filing, and application qualifications:
  <https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1145>,
  <https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1739>, and
  <https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2251>
- OPPO application publication:
  <https://open.oppomobile.com/bbs/forum.php?mod=viewthread&tid=6304>
- GOLEM model/software license audit: ADR 0009
- Website prerequisites:
  <https://github.com/golem-app/website/issues/1>,
  <https://github.com/golem-app/website/issues/4>, and
  <https://github.com/golem-app/golem/issues/22>
