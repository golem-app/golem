/// The fixed evaluation spec: prompts, per-prompt sampling, and deterministic
/// checks. Checks marked `required: false` are informational — recorded in the
/// report but never fail a run — for signals that are useful to track without
/// being stable enough to gate on.
library;

enum EvalCheckKind { contains, notContains, regexp }

final class EvalCheck {
  const EvalCheck.contains(this.value, {this.required = true})
    : kind = EvalCheckKind.contains;

  const EvalCheck.notContains(this.value, {this.required = true})
    : kind = EvalCheckKind.notContains;

  const EvalCheck.regexp(this.value, {this.required = true})
    : kind = EvalCheckKind.regexp;

  final EvalCheckKind kind;
  final String value;
  final bool required;

  /// Checks score the parsed answer channel only, never reasoning text.
  /// `contains`/`notContains` are case-insensitive; `regexp` compiles
  /// case-insensitively.
  bool passes(String answer) => switch (kind) {
    EvalCheckKind.contains => answer.toLowerCase().contains(
      value.toLowerCase(),
    ),
    EvalCheckKind.notContains => !answer.toLowerCase().contains(
      value.toLowerCase(),
    ),
    EvalCheckKind.regexp => RegExp(
      value,
      caseSensitive: false,
    ).hasMatch(answer),
  };

  String describe() =>
      '${kind.name}($value)${required ? '' : ' [informational]'}';
}

final class EvalPrompt {
  const EvalPrompt({
    required this.id,
    required this.messages,
    required this.checks,
    this.reasoningEnabled = false,
    this.maxTokens,
    this.temperature,
    this.topP,
    this.seed = 7,
  });

  final String id;
  final List<Map<String, String>> messages;
  final List<EvalCheck> checks;
  final bool reasoningEnabled;

  /// Null means "use the profile's shipped default", so evaluations reflect
  /// app behavior per model. Explicit values pin a prompt's sampling across
  /// profiles — the determinism anchor relies on that.
  final int? maxTokens;
  final double? temperature;
  final double? topP;
  final int seed;
}

/// The determinism anchor reuses the cross-device probe's exact prompt and
/// the app's exact sampling policy, so its fnv1a64 hash cross-references
/// `docs/notes/determinism-probe.md` (recorded: `d710455907eadf55` on both
/// engines at seed 7).
const evalAnchorPromptId = 'anchor-jupiter';
const defaultEvalSuite = 'default';
const arabicSmokeEvalSuite = 'arabic-smoke';
const globalLanguageSmokeEvalSuite = 'global-language-smoke';

const defaultEvalPrompts = <EvalPrompt>[
  EvalPrompt(
    id: evalAnchorPromptId,
    messages: [
      {
        'role': 'user',
        'content': 'Name the largest planet in the solar system.',
      },
    ],
    // Pinned to the probe's exact sampling regardless of profile, so the
    // hash stays comparable with docs/notes/determinism-probe.md.
    maxTokens: 2048,
    temperature: 1,
    topP: 0.95,
    checks: [EvalCheck.contains('Jupiter')],
  ),
  EvalPrompt(
    id: 'arithmetic-17x23',
    messages: [
      {
        'role': 'user',
        'content': 'What is 17 × 23? Reply with just the number.',
      },
    ],
    checks: [EvalCheck.regexp(r'\b391\b')],
  ),
  EvalPrompt(
    id: 'factual-capital',
    messages: [
      {
        'role': 'user',
        'content':
            'What is the capital of France? Answer in one short sentence.',
      },
    ],
    checks: [EvalCheck.contains('Paris')],
  ),
  EvalPrompt(
    id: 'factual-author',
    messages: [
      {'role': 'user', 'content': 'Who wrote the play Hamlet?'},
    ],
    checks: [EvalCheck.contains('Shakespeare')],
  ),
  EvalPrompt(
    id: 'instruction-one-word',
    messages: [
      {
        'role': 'user',
        'content': 'Reply with exactly one word: what color is a ripe banana?',
      },
    ],
    checks: [
      EvalCheck.contains('yellow'),
      // One token of latitude for punctuation, but no full sentences.
      EvalCheck.regexp(r'^\W*\w+\W*$', required: false),
    ],
  ),
  EvalPrompt(
    id: 'instruction-json',
    messages: [
      {
        'role': 'user',
        'content':
            'Return a JSON object with the keys "name" and "planet_count" '
            'describing our solar system. Output only the JSON object.',
      },
    ],
    checks: [
      EvalCheck.contains('"planet_count"'),
      EvalCheck.regexp(r'\b8\b'),
      EvalCheck.notContains('```', required: false),
    ],
  ),
  EvalPrompt(
    id: 'instruction-translation',
    messages: [
      {'role': 'user', 'content': "Translate 'good morning' into German."},
    ],
    checks: [EvalCheck.contains('guten morgen')],
  ),
  EvalPrompt(
    id: 'multi-turn-recall',
    messages: [
      {'role': 'user', 'content': 'My name is Zofia. Please remember it.'},
      {'role': 'assistant', 'content': 'Understood — your name is Zofia.'},
      {'role': 'user', 'content': 'What is my name?'},
    ],
    checks: [EvalCheck.contains('Zofia')],
  ),
  EvalPrompt(
    id: 'reasoning-speed',
    reasoningEnabled: true,
    messages: [
      {
        'role': 'user',
        'content':
            'A train travels 60 km in 45 minutes. What is its average speed '
            'in km/h? Give the final number.',
      },
    ],
    checks: [EvalCheck.regexp(r'\b80\b')],
  ),
  EvalPrompt(
    id: 'long-synthesis',
    messages: [
      {
        'role': 'user',
        'content': 'Explain in about 150 words why the sky is blue.',
      },
    ],
    checks: [
      EvalCheck.contains('scatter'),
      EvalCheck.contains('Rayleigh', required: false),
    ],
  ),
];

/// Bounded Modern Standard Arabic smoke coverage. This checks that each
/// shipping model family can understand and answer two simple Arabic prompts;
/// it does not claim quality for regional spoken dialects.
const arabicSmokeEvalPrompts = <EvalPrompt>[
  EvalPrompt(
    id: 'arabic-largest-planet',
    messages: [
      {
        'role': 'user',
        'content': 'ما أكبر كوكب في المجموعة الشمسية؟ أجب بجملة عربية قصيرة.',
      },
    ],
    checks: [
      EvalCheck.contains('المشتري'),
      EvalCheck.regexp(r'[\u0600-\u06ff]'),
    ],
  ),
  EvalPrompt(
    id: 'arabic-arithmetic-17x23',
    messages: [
      {
        'role': 'user',
        'content': 'ما حاصل ضرب 17 في 23؟ أجب بجملة عربية قصيرة تتضمن النتيجة.',
      },
    ],
    checks: [
      EvalCheck.regexp(r'(391|٣٩١)'),
      EvalCheck.regexp(r'[\u0600-\u06ff]'),
    ],
  ),
];

/// Bounded instruction-following coverage for the first global locale wave.
/// Each prompt asks the same arithmetic question and requires one native
/// answer phrase; this is a compatibility smoke, not a fluency claim.
const globalLanguageSmokeEvalPrompts = <EvalPrompt>[
  EvalPrompt(
    id: 'spanish-arithmetic-17x23',
    messages: [
      {
        'role': 'user',
        'content':
            '¿Cuánto es 17 × 23? Responde con una frase corta en español '
            'que incluya «El resultado es» y el número.',
      },
    ],
    maxTokens: 64,
    checks: [
      EvalCheck.regexp(r'\b391\b'),
      EvalCheck.contains('El resultado es'),
    ],
  ),
  EvalPrompt(
    id: 'brazilian-portuguese-arithmetic-17x23',
    messages: [
      {
        'role': 'user',
        'content':
            'Quanto é 17 × 23? Responda com uma frase curta em português '
            'do Brasil que inclua “O resultado é” e o número.',
      },
    ],
    maxTokens: 64,
    checks: [EvalCheck.regexp(r'\b391\b'), EvalCheck.contains('O resultado é')],
  ),
  EvalPrompt(
    id: 'japanese-arithmetic-17x23',
    messages: [
      {
        'role': 'user',
        'content':
            '17 × 23 はいくつですか。必ず「答えは」で始め、数値を含む'
            '短い日本語の文だけで答えてください。',
      },
    ],
    maxTokens: 64,
    checks: [EvalCheck.regexp(r'\b391\b'), EvalCheck.contains('答えは')],
  ),
  EvalPrompt(
    id: 'indonesian-arithmetic-17x23',
    messages: [
      {
        'role': 'user',
        'content':
            'Berapakah 17 × 23? Jawab dengan kalimat pendek dalam bahasa '
            'Indonesia yang memuat frasa “Hasilnya adalah” dan angkanya.',
      },
    ],
    maxTokens: 64,
    checks: [
      EvalCheck.regexp(r'\b391\b'),
      EvalCheck.contains('Hasilnya adalah'),
    ],
  ),
];

List<EvalPrompt> evalPromptsForSuite(String suite) => switch (suite) {
  defaultEvalSuite => defaultEvalPrompts,
  arabicSmokeEvalSuite => arabicSmokeEvalPrompts,
  globalLanguageSmokeEvalSuite => globalLanguageSmokeEvalPrompts,
  _ => throw ArgumentError.value(
    suite,
    'suite',
    'Expected $defaultEvalSuite, $arabicSmokeEvalSuite, or '
        '$globalLanguageSmokeEvalSuite',
  ),
};
