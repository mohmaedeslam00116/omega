import 'dart:io';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:share_plus/share_plus.dart';

enum OutputImageFormat { png, jpeg, webp }

abstract class ImageIoService {
  Future<Uint8List?> pickFromGallery();
  Future<List<Uint8List>> pickMultipleFromGallery();
  Future<Uint8List?> pickFromCamera();
  Future<Uint8List?> getInitialSharedImage();
  Stream<Uint8List?> get sharedImageStream;
  Future<void> validate(Uint8List bytes);
  Future<String> saveToGallery(
    Uint8List bytes, {
    String? filename,
    bool asJpeg = false,
    int jpegQuality = 90,
    OutputImageFormat format = OutputImageFormat.png,
  });
  Future<void> shareImage(Uint8List bytes, {String filename});
}

class ImageIoServiceImpl implements ImageIoService {
  final ImagePicker picker;
  final Future<Directory> Function()? getTempDirOverride;
  final Future<void> Function(Uint8List bytes, String name)? galPutOverride;
  final Future<void> Function(XFile file)? shareOverride;
  final Future<XFile?> Function(ImageSource source)? pickOverride;
  final Future<List<XFile>> Function()? pickMultipleOverride;

  ImageIoServiceImpl({
    ImagePicker? picker,
    this.getTempDirOverride,
    this.galPutOverride,
    this.shareOverride,
    this.pickOverride,
    this.pickMultipleOverride,
  }) : picker = picker ?? ImagePicker();

  Future<Directory> _getTempDir() async {
    if (getTempDirOverride != null) return getTempDirOverride!();
    return getTemporaryDirectory();
  }

  Future<Uint8List?> _readXFile(XFile? file) async {
    if (file == null) return null;
    return file.readAsBytes();
  }

  @override
  Future<Uint8List?> pickFromGallery() async {
    final file = pickOverride != null
        ? await pickOverride!(ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery);
    final bytes = await _readXFile(file);
    if (bytes != null) await validate(bytes);
    return bytes;
  }

  @override
  Future<List<Uint8List>> pickMultipleFromGallery() async {
    final files = pickMultipleOverride != null
        ? await pickMultipleOverride!()
        : await picker.pickMultiImage();
    final List<Uint8List> results = [];
    for (final f in files) {
      final b = await f.readAsBytes();
      await validate(b);
      results.add(b);
    }
    return results;
  }

  @override
  Future<Uint8List?> pickFromCamera() async {
    final file = pickOverride != null
        ? await pickOverride!(ImageSource.camera)
        : await picker.pickImage(source: ImageSource.camera);
    final bytes = await _readXFile(file);
    if (bytes != null) await validate(bytes);
    return bytes;
  }

  @override
  Future<Uint8List?> getInitialSharedImage() async {
    final media = await ReceiveSharingIntent.instance.getInitialMedia();
    if (media.isEmpty) return null;
    final path = media.first.path;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    await validate(bytes);
    return bytes;
  }

  @override
  Stream<Uint8List?> get sharedImageStream =>
      ReceiveSharingIntent.instance.getMediaStream().asyncMap((media) async {
        if (media.isEmpty) return null;
        final file = File(media.first.path);
        if (!await file.exists()) return null;
        final bytes = await file.readAsBytes();
        await validate(bytes);
        return bytes;
      });

  @override
  Future<void> validate(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Failed to decode image');
    }
    // Only guard against extreme input image sizes that exceed tile indexing limits
    if (decoded.width > 4096 || decoded.height > 4096) {
      throw UnsupportedError(
          'Image exceeds 4096px, please crop or choose smaller');
    }
  }

  @override
  Future<String> saveToGallery(
    Uint8List bytes, {
    String? filename,
    bool asJpeg = false,
    int jpegQuality = 90,
    OutputImageFormat format = OutputImageFormat.png,
  }) async {
    final bool isJpeg = asJpeg || format == OutputImageFormat.jpeg;
    final bool isWebp = format == OutputImageFormat.webp;

    String ext = 'png';
    if (isJpeg) ext = 'jpg';
    if (isWebp) ext = 'webp';

    final name = filename ?? 'omega_upscaled_${DateTime.now().millisecondsSinceEpoch}.$ext';
    
    Uint8List payload;
    if (isJpeg) {
      payload = _reencodeJpeg(bytes, jpegQuality);
    } else {
      payload = bytes;
    }

    // Try Gal (MediaStore) for direct gallery insertion
    try {
      if (galPutOverride != null) {
        await galPutOverride!(payload, name);
      } else {
        // Stream to temp file first to prevent memory spikes, then put into Gal
        final dir = await _getTempDir();
        final tempFile = File('${dir.path}/$name');
        await tempFile.create(recursive: true);
        await tempFile.writeAsBytes(payload, flush: true);
        await Gal.putImage(tempFile.path);
      }
      return 'gallery:$name';
    } catch (_) {
      // Fallback: write to app storage and return file path
      final dir = await _getTempDir();
      final file = File('${dir.path}/$name');
      await file.create(recursive: true);
      await file.writeAsBytes(payload, flush: true);
      return file.path;
    }
  }

  /// Re-encodes PNG bytes to high-quality JPEG
  Uint8List _reencodeJpeg(Uint8List pngBytes, int quality) {
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) throw Exception('Failed to decode image');
    return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
  }

  @override
  Future<void> shareImage(
    Uint8List bytes, {
    String filename = 'omega_upscaled.png',
  }) async {
    final dir = await _getTempDir();
    final file = File('${dir.path}/$filename');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    if (shareOverride != null) {
      await shareOverride!(XFile(file.path));
    } else {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Upscaled with Omega'),
      );
    }
  }
}
