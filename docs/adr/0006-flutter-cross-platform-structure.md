# ADR 0006: هيكل Flutter عابر للمنصات (Android-first)

- **Date:** 2026-08-30
- **Status:** Accepted

## Context
الطلب Flutter لكن التركيز Android. البدائل: `android/` فقط مع كود native، أو هيكل `lib/core + features` عابر.

## Decision
هيكل **lib/features/** مع عزل المحرك:
```
lib/
├── core/
│   ├── engine/tflite_engine.dart
│   └── catalog/catalog_service.dart
├── features/
│   ├── upscale/
│   └── catalog/
└── main.dart
```
Build واختبار لـ Android في MVP، لكن لا كود حصري في `android/` إلا الأذونات.

## Consequences
- جاهز لـ iOS/Desktop لاحقاً بدون إعادة كتابة.
- Gallery/Camera/Share-intent عبر `image_picker` + `receive_sharing_intent`.
