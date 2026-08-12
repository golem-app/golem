# Localization workflow

English (`app/lib/l10n/app_en.arb`) is the source and fallback catalog. Polish,
neutral Latin American Spanish, Brazilian Portuguese, Japanese, Indonesian,
and Modern Standard Arabic are maintained in the repository. Flutter's SDK
`gen-l10n` generator is the only localization framework; there is no runtime
translation or TMS.

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
names, stable language endonyms, standardized units (`GB`, `MB`, `tok/s`), ICU
placeholder-only fragments, and established technical parameter names such as
`Top-p` and `Top-k`. Indonesian also retains the standard loanwords *model*
and *prompt*; Brazilian Portuguese retains *download* and *prompt*
where they are the natural compact technical labels. Every exception must be
documented here before joining the test allowlist.
Spanish also retains the ordinary response word *No*, whose spelling matches
the English source.

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

The four initial global locales share a smaller `global-language-smoke` suite:
one non-reasoning arithmetic instruction per language, fixed at seed 7 and 64
output tokens. Each assertion requires both `391` and the requested native
answer phrase. Run it against the same two representative GGUF artifacts by
replacing `arabic-smoke` above with `global-language-smoke`.

Localized strings belong only at presentation boundaries. Domain objects,
repositories, broker code, and persisted JSON carry enums, stable codes,
numbers, and structured arguments; diagnostic causes remain unlocalized.
