/// How Golem writes a size on disk, in one place. Decimal gigabytes, matching
/// what both stores and Hugging Face quote, so a download's advertised size and
/// the figure the app shows are the same number.
///
/// Shared because chat and Settings now quote sizes for the same artifacts
/// (#79): two formatters would eventually disagree by a rounding digit and read
/// as two different downloads.
library;

String gigabytes(int bytes) => '${(bytes / 1000000000).toStringAsFixed(2)} GB';
