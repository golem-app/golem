enum InfernoErrorCode {
  invalidState,
  invalidModelPath,
  incompatibleModel,
  corruptModel,
  nativeUnavailable,
  loadFailed,
  generationFailed,
  cancelled,
  internal,
}

/// A failure that callers can catch without depending on native error types.
final class InfernoException implements Exception {
  const InfernoException(this.code, this.message, {this.cause});

  final InfernoErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'InfernoException(${code.name}): $message';
}
