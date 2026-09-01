import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:omega/core/image/image_io_service.dart';

Uint8List _makePng(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(10, 20, 30));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('omega_image_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('ImageIoService', () {
    test('Gallery pick returns imageBytes', () async {
      final bytes = _makePng(100, 100);
      final file = File('${tmp.path}/pick.png');
      await file.writeAsBytes(bytes);
      final svc = ImageIoServiceImpl(
        pickOverride: (source) async => XFile(file.path),
        getTempDirOverride: () async => tmp,
      );
      final result = await svc.pickFromGallery();
      expect(result, isNotNull);
      expect(result!.length, bytes.length);
    });

    test('pickMultipleFromGallery returns multiple images', () async {
      final bytes1 = _makePng(50, 50);
      final bytes2 = _makePng(60, 60);
      final file1 = File('${tmp.path}/p1.png');
      final file2 = File('${tmp.path}/p2.png');
      await file1.writeAsBytes(bytes1);
      await file2.writeAsBytes(bytes2);

      final svc = ImageIoServiceImpl(
        pickMultipleOverride: () async => [XFile(file1.path), XFile(file2.path)],
        getTempDirOverride: () async => tmp,
      );
      final list = await svc.pickMultipleFromGallery();
      expect(list.length, 2);
      expect(list[0].length, bytes1.length);
      expect(list[1].length, bytes2.length);
    });

    test('Camera capture works', () async {
      final bytes = _makePng(200, 200);
      final file = File('${tmp.path}/cam.png');
      await file.writeAsBytes(bytes);
      final svc = ImageIoServiceImpl(
        pickOverride: (source) async {
          expect(source, ImageSource.camera);
          return XFile(file.path);
        },
        getTempDirOverride: () async => tmp,
      );
      final result = await svc.pickFromCamera();
      expect(result, isNotNull);
    });

    test('Large input image (>4096px) validates and picks successfully', () async {
      final svc = ImageIoServiceImpl(getTempDirOverride: () async => tmp);
      final big = _makePng(4097, 100);
      await svc.validate(big); // does not throw

      final file = File('${tmp.path}/big.png');
      await file.writeAsBytes(big);
      final svc2 = ImageIoServiceImpl(
        pickOverride: (_) async => XFile(file.path),
        getTempDirOverride: () async => tmp,
      );
      final res = await svc2.pickFromGallery();
      expect(res, isNotNull);
    });

    test('Large upscaled image (>4096px) saves to gallery successfully without throwing', () async {
      // Simulates saving a 4800x4800 upscaled output
      final largeBytes = _makePng(5000, 100);
      var galCalled = false;
      final svc = ImageIoServiceImpl(
        getTempDirOverride: () async => tmp,
        galPutOverride: (b, name) async {
          galCalled = true;
          expect(b.length, largeBytes.length);
        },
      );
      final path = await svc.saveToGallery(largeBytes, filename: 'large_upscaled.png');
      expect(galCalled, true);
      expect(path, contains('gallery:'));
    });

    test('Save to Gallery shows in Photos (via Gal override) and fallback',
        () async {
      final bytes = _makePng(50, 50);
      var galCalled = false;
      final svc = ImageIoServiceImpl(
        getTempDirOverride: () async => tmp,
        galPutOverride: (b, name) async {
          galCalled = true;
          expect(b.length, bytes.length);
        },
      );
      final path = await svc.saveToGallery(bytes, filename: 'test.png');
      expect(galCalled, true);
      expect(path, contains('gallery:'));

      // Fallback when Gal throws
      final svc2 = ImageIoServiceImpl(
        getTempDirOverride: () async => tmp,
        galPutOverride: (b, name) async => throw Exception('Gal not available'),
      );
      final fallbackPath = await svc2.saveToGallery(bytes, filename: 'fallback.png');
      expect(await File(fallbackPath).exists(), true);
    });

    test('saveToGallery re-encodes JPEG when asJpeg', () async {
      final bytes = _makePng(50, 50);
      Uint8List? captured;
      final svc = ImageIoServiceImpl(
        getTempDirOverride: () async => tmp,
        galPutOverride: (b, name) async => captured = b,
      );
      final path = await svc.saveToGallery(bytes,
          filename: 'test.jpg', asJpeg: true, jpegQuality: 80);
      expect(path, contains('gallery:'));
      expect(captured, isNotNull);
      // JPEG SOI magic
      expect(captured![0], 0xFF);
      expect(captured![1], 0xD8);
      expect(captured!.length, isNot(bytes.length));
    });

    test('saveToGallery supports OutputImageFormat.webp', () async {
      final bytes = _makePng(50, 50);
      String? savedName;
      final svc = ImageIoServiceImpl(
        getTempDirOverride: () async => tmp,
        galPutOverride: (b, name) async => savedName = name,
      );
      final path = await svc.saveToGallery(
        bytes,
        format: OutputImageFormat.webp,
      );
      expect(path, contains('gallery:'));
      expect(savedName, contains('.webp'));
    });

    test('saveToGallery passes PNG bytes through by default', () async {
      final bytes = _makePng(50, 50);
      Uint8List? captured;
      final svc = ImageIoServiceImpl(
        getTempDirOverride: () async => tmp,
        galPutOverride: (b, name) async => captured = b,
      );
      await svc.saveToGallery(bytes, filename: 'test.png');
      expect(captured, bytes);
    });

    test('share sheet opens via shareOverride', () async {
      final bytes = _makePng(10, 10);
      var shared = false;
      final svc = ImageIoServiceImpl(
        getTempDirOverride: () async => tmp,
        shareOverride: (file) async {
          shared = true;
          expect(await file.readAsBytes(), bytes);
        },
      );
      await svc.shareImage(bytes, filename: 'share.png');
      expect(shared, true);
    });

    test('Share-intent stream is available (scaffold)', () async {
      final svc = ImageIoServiceImpl(getTempDirOverride: () async => tmp);
      expect(svc.sharedImageStream, isA<Stream<Uint8List?>>());
    });
  });
}
