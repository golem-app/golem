# Localization workflow

English (`app/lib/l10n/app_en.arb`) is the source and fallback catalog. Polish
(`app_pl.arb`) and Modern Standard Arabic (`app_ar.arb`) are maintained in the
repository. Flutter's SDK `gen-l10n` generator is the only localization
framework; there is no runtime translation or TMS.

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
   sparse.
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

Localized strings belong only at presentation boundaries. Domain objects,
repositories, broker code, and persisted JSON carry enums, stable codes,
numbers, and structured arguments; diagnostic causes remain unlocalized.
