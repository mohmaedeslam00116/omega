# ADR 0004: مخطط الكتالوج والنموذج الافتراضي

- **Date:** 2026-08-30
- **Status:** Accepted

## Context
بعد اعتماد GitHub Releases (ADR-0002) و TFLite (ADR-0003)، نحتاج تحديد شكل `catalog.json` وكيف نختار النموذج الافتراضي، خاصة بعد تأكيد البحث أن كل المقاطع الموثوقة هي 4x بحجم 128→512 per tile.

## Decision
- **catalog.json:** مصفوفة `CatalogEntry` بكل من `id, name, scale(4), type(general/anime/face), inputSize(128), fileSize, sha256, url, license, version`. يُحفظ على `raw.githubusercontent.com` ويُحدّث عند كل Release، cache 24h في التطبيق.
- **Bundled default:** `realesr-general-x4v3` LiteRT FP16 (3.5MB) — أخف، 1-2ms/tile GPU، license BSD-3، يعمل offline فوراً.
- **On-demand:** `Real-ESRGAN-x4plus` w8a8 (16.7MB) للجودة العالية، GPU delegate + fallback XNNPACK.
- **Tiling:** tile ثابت 128 overlap 32 tilePad 10، معالجة sequential في Isolate مع progress.

## Alternatives Considered
- **Tile 256/512:** يتطلب إعادة تصدير نموذج وذاكرة أعلى (OOM على 3GB).
- **Bundled x4plus:** حجم APK يتجاوز 70MB.

## Consequences
- `catalog.json` يصبح مصدر الحقيقة الوحيد للتحقق من النزاهة والترخيص.
- anime/face مؤجلة حتى يكتمل pipeline تحويل موثوق.
