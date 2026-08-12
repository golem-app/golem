# Localization workflow

English (`app/lib/l10n/app_en.arb`) is the source and fallback catalog. Polish
(`app_pl.arb`) is the first translation. Flutter's SDK `gen-l10n` generator is
the only localization framework; there is no runtime translation or TMS.

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

## Adding a language

1. Add the semantic language/code to `AppLanguage`, the generated supported
   locale list, and the Settings language screen. Keep System default sparse.
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

Localized strings belong only at presentation boundaries. Domain objects,
repositories, broker code, and persisted JSON carry enums, stable codes,
numbers, and structured arguments; diagnostic causes remain unlocalized.
