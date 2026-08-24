/// Project-wide provider retry policy (handbook v5.0 §4.5): no provider-level
/// retry. Retry stays explicit in the owning controller or UI
/// (`ChatController.retryFailure`, `StartupController.retry`), and the
/// `background_downloader` task in `core/services/artifact_downloader.dart`
/// is the sole named retry owner for artifact downloads. Without this,
/// every fallible build inherits `ProviderContainer.defaultRetry`: ten
/// retries over ~38.2 s during which the error is hidden inside a
/// retrying `AsyncLoading`.
Duration? noRetry(int retryCount, Object error) => null;
