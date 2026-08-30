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

    test('>4096 image shows error and blocks', () async {
      final svc = ImageIoServiceImpl(getTempDirOverride: () async => tmp);
      final big = _makePng(4097, 100);
      expect(
        () => svc.validate(big),
        throwsA(predicate((e) =>
            e is UnsupportedError &&
            (e.message?.contains('Image exceeds 4096px') ?? false))),
      );
      // Also via pick should throw
      final file = File('${tmp.path}/big.png');
      await file.writeAsBytes(big);
      final svc2 = ImageIoServiceImpl(
        pickOverride: (_) async => XFile(file.path),
        getTempDirOverride: () async => tmp,
      );
      expect(() => svc2.pickFromGallery(), throwsA(isA<UnsupportedError>()));
    });

    test('4096 exactly passes', () async {
      final svc = ImageIoServiceImpl(getTempDirOverride: () async => tmp);
      final ok2 = _makePng(4096, 100);
      await svc.validate(ok2);
      expect(true, true);
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
      // For scaffold, just ensure stream getter doesn't throw
      expect(svc.sharedImageStream, isA<Stream<Uint8List?>>());
    });
  });
}
