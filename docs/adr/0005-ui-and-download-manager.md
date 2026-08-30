# ADR 0005: إدارة التنزيل وتصميم الواجهة

- **Date:** 2026-08-30
- **Status:** Accepted

## Context
بعد تثبيت الكتالوج والتقسيم، نحتاج نظام تنزيل موثوق وواجهة واضحة. البدائل: تنزيل بسيط بدون استئناف، أو مدير كامل مع تحقق وحذف.

## Decision
- **Download manager:** resumable (Range), SHA256 verify بعد الاكتمال، إلغاء/حذف مع تأكيد، `clear cache`.
- **UI:** تبويبان `Upscale` (pick → select Model → progress per tile → preview/save/share) و `Catalog` (list مع حالات Bundled/Downloaded/Update).
- **Design:** التزام بـ `impeccable` — رموز تصميم متسقة (tokens, typography, spacing) وليس قوالب افتراضية.
- **Permissions:** طلب عند الحاجة (scoped storage + camera), إعدادات GPU toggle و cache limit 500MB افتراضي.
- **Errors:** فحص قبل المعالجة (>4096 → اقتراح تصغير)، OOM → fallback tile 64 أو رسالة واضحة، model corrupt → إعادة تنزيل.

## Consequences
- تجربة مستخدم لا تتجمد (Isolate + progress).
- التزام بالترخيص يبقى ظاهراً في كل CatalogEntry.
