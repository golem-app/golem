import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// An image validated and measured, ready to become an attachment.
final class PreparedImage {
  const PreparedImage({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;
}

/// Why an image was refused. Semantic rather than copy, so presentation owns
/// the wording (handbook v4.2A §5.2).
enum ImageRejection {
  /// Not an image type any engine path accepts.
  unsupportedType,

  /// Larger than the intake byte ceiling.
  tooLarge,

  /// The bytes are not a decodable image of the type they claim.
  undecodable,
}

final class ImageRejectedException implements Exception {
  const ImageRejectedException(this.reason);

  final ImageRejection reason;
}

/// Validates, bounds, and measures an image chosen for a chat.
///
/// Deliberately no image-processing dependency: `dart:ui`'s codec is the
/// platform decoder Flutter already ships. Every accepted image is decoded
/// and written as canonical PNG pixels, which applies EXIF orientation once
/// and removes the platform-dependent metadata before either native engine
/// sees it. `targetWidth`/`targetHeight` downscale during decode rather than
/// after, so a 48-megapixel photo never materializes at full size.
final class ImageIntake {
  const ImageIntake();

  /// The types every declared image path accepts. HEIC is absent on purpose:
  /// the pickers hand back JPEG for library photos, and letting an
  /// undecodable-on-Android container into the store would strand a message.
  static const supportedMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};

  /// Source ceiling. Generous for a phone photo, low enough that a pathological
  /// file cannot exhaust memory before it is measured.
  static const maxSourceBytes = 20 * 1024 * 1024;

  /// Longest edge kept. Above this the image is re-decoded smaller: vision
  /// encoders tile to a few hundred pixels, so more only costs memory.
  static const maxDimension = 2048;

  /// Total decoded pixels kept. Qwen's proven processor path is capped at one
  /// megapixel and the broker reserves 1,280 visual tokens per image; keeping
  /// a multi-megapixel photo would violate both that memory and context
  /// contract even when neither edge exceeds [maxDimension].
  static const maxPixelCount = 1024 * 1024;

  Future<PreparedImage> prepare(
    Uint8List bytes, {
    required String mimeType,
  }) async {
    if (!supportedMimeTypes.contains(mimeType)) {
      throw const ImageRejectedException(ImageRejection.unsupportedType);
    }
    if (bytes.lengthInBytes > maxSourceBytes) {
      throw const ImageRejectedException(ImageRejection.tooLarge);
    }

    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 || height <= 0) {
        throw const ImageRejectedException(ImageRejection.undecodable);
      }

      final longestEdge = math.max(width, height);
      final edgeScale = maxDimension / longestEdge;
      final pixelScale = math.sqrt(maxPixelCount / (width * height));
      final scale = math.min(1.0, math.min(edgeScale, pixelScale));
      int? targetWidth;
      int? targetHeight;
      if (scale < 1) {
        // Floor rather than round: the prepared image must never cross the
        // advertised pixel ceiling because of two independent round-ups.
        targetWidth = (width * scale).floor().clamp(1, maxDimension);
        targetHeight = (height * scale).floor().clamp(1, maxDimension);
      }
      codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      if (encoded == null) {
        throw const ImageRejectedException(ImageRejection.undecodable);
      }
      return PreparedImage(
        bytes: encoded.buffer.asUint8List(),
        mimeType: 'image/png',
        width: image.width,
        height: image.height,
      );
    } on ImageRejectedException {
      rethrow;
    } catch (_) {
      throw const ImageRejectedException(ImageRejection.undecodable);
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
