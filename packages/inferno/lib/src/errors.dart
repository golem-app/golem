enum InfernoErrorCode {
  invalidState,
  invalidModelPath,
  incompatibleModel,
  corruptModel,
  nativeUnavailable,
  loadFailed,
  generationFailed,

  /// The rendered prompt plus the token budget exceed the context window;
  /// retrying the identical request can never succeed.
  contextExhausted,

  /// The engine could not allocate the memory a load or generation needs;
  /// retrying after freeing memory can succeed.
  outOfMemory,

  /// The device's CPU lacks an instruction-set extension this build's
  /// kernels were compiled for. Refused before the first kernel runs, so
  /// the alternative is an illegal-instruction crash, not a slower answer;
  /// no retry on this device can succeed.
  unsupportedDevice,
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
