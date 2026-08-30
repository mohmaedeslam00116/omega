# ADR 0003: محرك TFLite المحلي بدل ONNX

- **Date:** 2026-08-30
- **Status:** Accepted

## Context
الفلتر يحتاج محرك on-device لتشغيل نماذج RealESRGAN/ESRGAN. البدائل: ONNX Runtime (يدعم النماذج الأصلية مباشرة)، TFLite (أخف، يحتاج تحويل)، NCNN/MNN (native أسرع لكن جسر Flutter أقل).

## Decision
اخترنا **TFLite** مع `tflite_flutter` + GPU delegate اختياري، وتنفيذ في **Isolate** لتجنب تجميد UI. النماذج في الكتالوج تُنشر بصيغة TFLite (يُحوّل ONNX→TFLite بالـ pipeline قبل Release).

## Alternatives Considered
- **ONNX Runtime Flutter:** يدعم النماذج الأصلية لكن حجم SDK أكبر واستهلاك ذاكرة أعلى على Android المتوسط.
- **NCNN:** أداء أعلى لكن يتطلب كتابة Platform Channel وNDK build معقد.

## Consequences
- حجم APK أقل (~5MB للمحرك + 6MB للنموذج الافتراضي).
- نحتاج pipeline تحويل موثوق (ONNX→TFLite float16) واختبار دقة مقارنة بالأصل.
- GPU delegate قد لا يتوفر على كل الأجهزة → fallback إلى CPU.
