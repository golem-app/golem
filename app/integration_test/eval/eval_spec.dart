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
    this.maxTokens = 2048,
    this.temperature = 1,
    this.topP = 0.95,
    this.seed = 7,
  });

  final String id;
  final List<Map<String, String>> messages;
  final List<EvalCheck> checks;
  final bool reasoningEnabled;
  final int maxTokens;
  final double temperature;
  final double topP;
  final int seed;
}

/// The determinism anchor reuses the cross-device probe's exact prompt and
/// the app's exact sampling policy, so its fnv1a64 hash cross-references
/// `docs/notes/determinism-probe.md` (recorded: `d710455907eadf55` on both
/// engines at seed 7).
const evalAnchorPromptId = 'anchor-jupiter';

const defaultEvalPrompts = <EvalPrompt>[
  EvalPrompt(
    id: evalAnchorPromptId,
    messages: [
      {
        'role': 'user',
        'content': 'Name the largest planet in the solar system.',
      },
    ],
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
