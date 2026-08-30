import 'dart:io';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:share_plus/share_plus.dart';

abstract class ImageIoService {
  Future<Uint8List?> pickFromGallery();
  Future<Uint8List?> pickFromCamera();
  Future<Uint8List?> getInitialSharedImage();
  Stream<Uint8List?> get sharedImageStream;
  Future<void> validate(Uint8List bytes);
  Future<String> saveToGallery(Uint8List bytes,
      {String filename, bool asJpeg = false});
  Future<void> shareImage(Uint8List bytes, {String filename});
}

class ImageIoServiceImpl implements ImageIoService {
  final ImagePicker picker;
  final Future<Directory> Function()? getTempDirOverride;
  final Future<void> Function(Uint8List bytes, String name)? galPutOverride;
  final Future<void> Function(XFile file)? shareOverride;
  final Future<XFile?> Function(ImageSource source)? pickOverride;

  ImageIoServiceImpl({
    ImagePicker? picker,
    this.getTempDirOverride,
    this.galPutOverride,
    this.shareOverride,
    this.pickOverride,
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
    if (decoded.width > 4096 || decoded.height > 4096) {
      throw UnsupportedError(
          'Image exceeds 4096px, please crop or choose smaller');
    }
  }

  @override
  Future<String> saveToGallery(Uint8List bytes,
      {String filename = 'omega_upscaled.png', bool asJpeg = false}) async {
    // Validate first
    await validate(bytes);
    // Try Gal (MediaStore) if available
    try {
      if (galPutOverride != null) {
        await galPutOverride!(bytes, filename);
      } else {
        // Gal expects image bytes; it handles scoped storage
        await Gal.putImageBytes(bytes, name: filename);
      }
      return 'gallery:$filename';
    } catch (_) {
      // Fallback: write to temp and return path
      final dir = await _getTempDir();
      final file = File('${dir.path}/$filename');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      return file.path;
    }
  }

  @override
  Future<void> shareImage(Uint8List bytes,
      {String filename = 'omega_upscaled.png'}) async {
    final dir = await _getTempDir();
    final file = File('${dir.path}/$filename');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    if (shareOverride != null) {
      await shareOverride!(XFile(file.path));
    } else {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Upscaled with Omega'),
      );
    }
  }
}
