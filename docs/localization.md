# Localization workflow

English (`app/lib/l10n/app_en.arb`) is the source and fallback catalog. Polish,
neutral Latin American Spanish, Brazilian Portuguese, Japanese, Indonesian,
Hindi, neutral international French, Vietnamese, Turkish, Korean, and Modern
Standard Arabic are maintained in the repository. Flutter's SDK
`gen-l10n` generator is the only localization framework; there is no runtime
translation or TMS.

## Where copy lives

Every user-facing sentence is in the catalogs, reached either through
`context.l10n` or through `app/lib/l10n/presentation_messages.dart`, which
words a domain classification for a screen. Below that line — `core/domain/`,
`broker/`, and every persisted store — carries kinds and redacted arguments,
never sentences: a string on a domain type is the English one nobody
translates, and a string in a store is a sentence a later release cannot
retranslate (and, for a failure, one that can quote a path off the device).

A pure function that produces copy takes a non-nullable `AppLocalizations`.
Tests that run without a widget tree construct `AppLocalizationsEn()`, which is
what `context.l10n` already falls back to; a nullable parameter with `?? '…'`
fallbacks is how a second, untranslated copy of the product's voice grows.

Exception `message` fields are the deliberate exception. They are English
diagnostics for logs and the gated acceptance suites, never rendered —
presentation switches on the accompanying kind.

## Product language

Polish copy is neutral, concise, and gender-neutral. Avoid `Pan/Pani` and avoid
addressing the reader directly when an impersonal construction is clearer.

| English concept | Preferred Polish | Notes |
| --- | --- | --- |
| model | model | Keep upstream model names unchanged. |
| download | pobieranie / pobierz | Use the noun for state and verb for actions. |
| reasoning | rozumowanie / tok rozumowania | Use *Rozumowanie* in compact controls and *tok rozumowania* in explanatory prose. |
| system prompt | prompt systemowy | Keep *prompt* consistently. |
| local inference | generowanie lokalne | Prefer user-facing meaning over jargon. |
| privacy | prywatność | Never imply telemetry exists. |
| benchmark | test wydajności | Internal IDs and exported diagnostics stay unchanged. |
| token | token | Inflect using Polish CLDR plural categories. |

Do not translate user messages, model responses, model/repository names,
engine and quantization tokens, file names, stable identifiers, URLs, or
diagnostic payloads.

“Pinned catalog” describes Golem’s built-in, release-fixed model selection; it
is not a visual pin. Translate that product meaning rather than the English
metaphor (for example, *wbudowany*, *integrado*, *prédefinido*, or the natural
equivalent in the target language).

Spanish copy is neutral Latin American Spanish. Avoid country-specific
idioms and use these terms consistently:

| English concept | Preferred Spanish | Notes |
| --- | --- | --- |
| model | modelo | Keep upstream model names unchanged. |
| download | descarga / descargar | Use the noun for state and verb for actions. |
| reasoning | razonamiento | Do not imply access beyond the model's presented reasoning. |
| system prompt | instrucción del sistema | Prefer the user-facing meaning over jargon. |
| on-device inference | inferencia en el dispositivo | Avoid remote-compute implications. |
| privacy | privacidad | Never imply telemetry exists. |
| benchmark | prueba de rendimiento | Internal IDs and exported diagnostics stay unchanged. |
| token | token | Use Spanish CLDR plural categories. |
| chat | chat / conversación | Use *chat* for compact labels and *conversación* in prose. |

Brazilian Portuguese copy follows contemporary Brazilian usage, not European
Portuguese. Flutter requires a base `app_pt.arb` beside `app_pt_BR.arb`; it is
an exact Brazilian fallback mirror so every Portuguese system locale receives
the same product copy.

| English concept | Preferred Brazilian Portuguese | Notes |
| --- | --- | --- |
| model | modelo | Keep upstream model names unchanged. |
| download | download / baixar | Use *download* for a compact state and *baixar* for actions. |
| reasoning | raciocínio | Do not imply hidden chain-of-thought access. |
| system prompt | prompt do sistema | Keep *prompt* consistent in technical settings. |
| on-device inference | inferência no dispositivo | Avoid remote-compute implications. |
| privacy | privacidade | Never imply telemetry exists. |
| benchmark | teste de desempenho | Internal IDs and exported diagnostics stay unchanged. |
| token | token | Use Brazilian Portuguese CLDR plural categories. |
| chat | conversa | Prefer *conversa* over European Portuguese forms. |

Japanese copy is concise and uses the standard polite register without adding
subjects where the interface context already supplies them.

| English concept | Preferred Japanese | Notes |
| --- | --- | --- |
| model | モデル | Keep upstream model names unchanged. |
| download | ダウンロード | Use consistently for noun and action labels. |
| reasoning | 思考 | Do not imply access beyond presented model reasoning. |
| system prompt | システムプロンプト | Keep the established technical term. |
| on-device inference | 端末上の推論 | Use 端末 for both supported mobile platforms. |
| privacy | プライバシー | Never imply telemetry exists. |
| benchmark | ベンチマーク | Internal IDs and exported diagnostics stay unchanged. |
| token | トークン | Japanese uses the CLDR `other` category. |
| chat | チャット | Use 会話 for longer explanatory prose where natural. |

Indonesian copy uses standard Indonesian and avoids region-specific slang.

| English concept | Preferred Indonesian | Notes |
| --- | --- | --- |
| model | model | A standard Indonesian technical loanword; names stay unchanged. |
| download | unduhan / unduh | Use the noun for state and verb for actions. |
| reasoning | penalaran | Do not imply hidden chain-of-thought access. |
| system prompt | prompt sistem | Keep *prompt* consistent in technical settings. |
| on-device inference | inferensi di perangkat | Avoid remote-compute implications. |
| privacy | privasi | Never imply telemetry exists. |
| benchmark | tolok ukur | Internal IDs and exported diagnostics stay unchanged. |
| token | token | Indonesian uses the CLDR `other` category. |
| chat | percakapan | Use consistently for the durable conversation object. |

Catalog leakage tests allow source-identical copy only for product and speaker
names, stable language endonyms, standardized units (`GB`, `MB`, `MB/s`, `tok/s`), ICU
placeholder-only fragments, and established technical parameter names such as
`Top-p` and `Top-k`. Indonesian also retains the standard loanwords *model*
and *prompt*; Brazilian Portuguese retains *download* and *prompt*
where they are the natural compact technical labels. Every exception must be
documented here before joining the test allowlist.
Spanish also retains the ordinary response word *No*, whose spelling matches
the English source.

Golem Model Lab (the macOS `lab` flavor, ADR 0021) adds its product name,
the `GML` version tag, the `ttft` acronym, contract chips built from
single-letter parameter symbols (`ctx`, `t`, `p`, `k`), and unit-only
fragments (`GB`, `tok`, `tok/s`, `s`) to the shared exceptions. Indonesian
and Vietnamese retain *seed* and Indonesian *batch* as established technical
loanwords; French retains the compact abbreviation *max*.

Hindi copy uses concise modern Devanagari and avoids gendered forms where an
impersonal construction is natural. Preserve conjunct clusters during layout;
never add letter spacing to Devanagari headings.

| English concept | Preferred Hindi |
| --- | --- |
| model / download | मॉडल / डाउनलोड |
| reasoning / system prompt | तर्क / सिस्टम प्रॉम्प्ट |
| on-device inference / privacy | डिवाइस पर इन्फ़रेंस / निजता |
| benchmark / token | प्रदर्शन परीक्षण / टोकन |
| chat / attachment | चैट / अटैचमेंट |
| deterministic simulation | नियतात्मक सिम्युलेशन |

French copy is neutral international French. Use non-breaking punctuation
spacing and avoid country-specific administrative vocabulary.

| English concept | Preferred French |
| --- | --- |
| model / download | modèle / téléchargement |
| reasoning / system prompt | raisonnement / instruction système |
| on-device inference / privacy | inférence sur l’appareil / confidentialité |
| benchmark / token | test de performances / token |
| chat / attachment | conversation / pièce jointe |

Vietnamese copy uses standard, region-neutral Vietnamese. Catalogs are NFC;
user and model text may remain in any canonically equivalent representation.

| English concept | Preferred Vietnamese |
| --- | --- |
| model / download | mô hình / tải xuống |
| reasoning / system prompt | lập luận / lời nhắc hệ thống |
| on-device inference / privacy | suy luận trên thiết bị / quyền riêng tư |
| benchmark / token | kiểm tra hiệu năng / token |
| chat / attachment | cuộc trò chuyện / tệp đính kèm |
| deterministic simulation | mô phỏng tất định |

Turkish copy follows contemporary Türkiye usage. Any presentation casing must
respect dotted `i/İ` and dotless `ı/I`; never apply locale-blind uppercasing.

| English concept | Preferred Turkish |
| --- | --- |
| model / download | model / indirme |
| reasoning / system prompt | akıl yürütme / sistem istemi |
| on-device inference / privacy | cihaz üzerinde çıkarım / gizlilik |
| benchmark / token | performans testi / token |
| chat / attachment | sohbet / ek |

Korean copy uses concise standard South Korean UI language. Prefer natural
word wrapping, allow character wrapping where the platform requires it, and
do not add Latin letter spacing to Hangul headings.

| English concept | Preferred Korean |
| --- | --- |
| model / download | 모델 / 다운로드 |
| reasoning / system prompt | 추론 / 시스템 프롬프트 |
| on-device inference / privacy | 온디바이스 추론 / 개인정보 보호 |
| benchmark / token | 벤치마크 / 토큰 |
| chat / attachment | 대화 / 첨부 파일 |

Arabic copy uses concise Modern Standard Arabic. It does not claim support for
regional spoken dialects. Use these terms consistently:

| English concept | Preferred Arabic | Notes |
| --- | --- | --- |
| model | النموذج | Keep upstream model names unchanged. |
| download | التنزيل / نزّل | Use the noun for state and verb for actions. |
| reasoning | التفكير | Avoid terms that imply hidden chain-of-thought access. |
| system prompt | تعليمات النظام | Prefer the user-facing meaning over transliteration. |
| on-device inference | التشغيل على الجهاز | Avoid remote-compute implications. |
| privacy | الخصوصية | Never imply telemetry exists. |
| benchmark | اختبار الأداء | Internal IDs and exported diagnostics stay unchanged. |
| token | رمز | Use all six Arabic CLDR plural branches. |
| chat | محادثة | Use consistently for the durable conversation object. |
| attachment | مرفق | Use إرفاق for the action. |

RTL is a presentation contract, not a data transformation. App chrome follows
the ambient `Directionality`; user and model paragraphs use the first strong
character; code, paths, URLs, model names, filenames, sizes, and identifiers
remain LTR. Wrap technical values only at the presentation boundary with a
Unicode isolate, and never persist the isolate characters.

## Adding a language

1. Add the semantic language/code to `AppLanguage` and the Settings language
   screen. `gen-l10n` derives the supported locale list. Keep System default
   sparse. A regional catalog may require a generator-only base fallback; keep
   such a mirror mechanically identical and test it for drift.
2. Copy `app_en.arb`, set `@@locale`, and translate every resource from its
   English description and UI context. Preserve ICU braces and placeholder
   names exactly; never concatenate plural-sensitive sentences in Dart.
3. Run `flutter gen-l10n`. The catalog parity test must report identical,
   non-empty keys and English metadata for every resource.
4. Perform a second translation pass for terminology, grammar, punctuation,
   plural categories, accessibility labels, and the exclusions above.
5. Test system-locale resolution, explicit selection, persistence/rollback,
   representative navigation, all plural branches, supported large text,
   light/dark appearance, and RTL construction.
6. Review the main app journey on iOS and Android. Check every major screen,
   dialog, sheet, toast, progress state, and screen-reader label for source
   language leakage. Record any deliberate untranslated product term here.
7. Generate twice and require a clean second diff, then run the repository's
   full format, boundary, analysis, test, golden, and platform-build gates.

For Arabic model smoke on a QA Android install that already contains the two
representative GGUF artifacts, preserve the app after the run so its model
files are not removed:

```sh
flutter test integration_test/model_eval_test.dart -d <device> --flavor qa \
  --no-uninstall \
  --dart-define=GOLEM_EVAL_INSTALLED=gemma4-gguf,qwen35-2b-gguf \
  --dart-define=GOLEM_EVAL_SUITE=arabic-smoke
```

The nine global locales share the `global-language-smoke` suite: one
non-reasoning arithmetic instruction per language, fixed at seed 7 and 64
output tokens. Each assertion requires both `391` and a language-specific
word or script signal while accepting natural wording variants. Run it against
the same two representative GGUF artifacts by
replacing `arabic-smoke` above with `global-language-smoke`.

The mainland China distribution spike has a narrower, non-production
`simplified-chinese-feasibility` suite. It contains one fixed-seed,
non-reasoning, 64-token arithmetic prompt and requires both `391` and the exact
Simplified Chinese phrase `计算结果是`. This is a compatibility smoke, not a
fluency claim. Run the physical-device matrix against installed QA artifacts:

```sh
# iPhone 17 — never use the production app.golem identity.
flutter test integration_test/model_eval_test.dart -d <iphone> --flavor qa \
  --no-uninstall \
  --dart-define=GOLEM_EVAL_INSTALLED=gemma4-mlx,qwen35-2b-mlx \
  --dart-define=GOLEM_EVAL_SUITE=simplified-chinese-feasibility

# OnePlus 12R.
flutter test integration_test/model_eval_test.dart -d <android> --flavor qa \
  --no-uninstall \
  --dart-define=GOLEM_EVAL_INSTALLED=gemma4-gguf,qwen35-2b-gguf \
  --dart-define=GOLEM_EVAL_SUITE=simplified-chinese-feasibility
```

The separately gated script probe renders representative Simplified Chinese
through the shipping typography at 1.6x without adding a locale or production
route. Run `integration_test/simplified_chinese_typography_probe_test.dart` on
both devices with
`--dart-define=GOLEM_SIMPLIFIED_CHINESE_TYPOGRAPHY_PROBE=true` and optionally
`--dart-define=GOLEM_SCRIPT_PROBE_HOLD_SECONDS=20`. Inspect missing glyphs,
Simplified Chinese versus Japanese/Korean Han forms, wrapping, clipping,
accessibility semantics, and the platform's native font behavior.

Localized strings belong only at presentation boundaries. Domain objects,
repositories, broker code, and persisted JSON carry enums, stable codes,
numbers, and structured arguments; diagnostic causes remain unlocalized.
