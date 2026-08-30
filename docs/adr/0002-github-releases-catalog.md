# ADR 0002: الكتالوج الرسمي للنماذج عبر GitHub Releases

- **Date:** 2026-08-30
- **Status:** Accepted

## Context
نحتاج توزيع نماذج Upscale قابلة للتنزيل داخل التطبيق بدون خادم خاص. الخيارات: GitHub Releases، Firebase Storage، CDN خاص، أو تضمين كل النماذج في APK.

## Decision
نستخدم **GitHub Releases ككتالوج رسمي**: ريبو يحتوي `catalog.json` + كل نموذج كـ Release asset مع `sha256, scale, type, size`. التطبيق يقرأ `catalog.json` من `https://raw.githubusercontent.com/...` أو `api.github.com/repos/.../releases/latest`.

## Alternatives Considered
- **Bundled only:** APK ضخم، لا تحديث بدون نشر.
- **Firebase/CDN:** يحتاج حساب وبنية وفواتير.
- **User upload إلى GitHub:** يتطلب auth ومراجعة نماذج، معقد للـ MVP.

## Consequences
- لا مصاريف استضافة، versioning مجاني، checksum يضمن السلامة.
- حد GitHub Releases (2GB per asset) كافٍ لنماذج TFLite (~5-20MB).
- يحتاج آلية cache وتحديث دوري للكتالوج.
