# المساهمة في Omega — Contributing Guide

شكراً لاهتمامك بالمساهمة! هذا المشروع مفتوح للجميع.

## كيف تساهم؟

### 1. الإبلاغ عن مشكلة
- افتح Issue جديد باستخدام قالب `Bug Report`
- اشرح المشكلة بوضوح مع خطوات إعادة الإنتاج

### 2. اقتراح ميزة
- افتح Issue بقالب `Feature Request`
- اشرح الـ use case والقيمة

### 3. إرسال Pull Request

```bash
# 1. Fork ثم Clone
git clone https://github.com/YOUR_USERNAME/omega.git
cd omega

# 2. أنشئ branch
git checkout -b feat/awesome-feature
# أو fix/bug-name, docs/..., chore/...

# 3. اعمل التعديلات + Tests
npm test  # أو pnpm test

# 4. Commit برسالة واضحة (Conventional Commits)
git commit -m "feat: add awesome feature"
# feat:, fix:, docs:, chore:, refactor:, test:

# 5. Push وافتح PR
git push origin feat/awesome-feature
gh pr create --fill
```

## معايير الكود

- استخدم **TDD** عند الإمكان (`/tdd` skill)
- شغّل `code-review` قبل الـ PR (`/code-review`)
- اكتب ADR لأي قرار معماري مهم (`/domain-modeling`)
- التزم بـ SOLID و Clean Code

## الـ Skills المساعدة

المشروع مهيأ بـ skills تسهل عملك:

- `/triage` — لفرز الـ Issues
- `/to-spec` — لتحويل فكرة إلى spec
- `/to-tickets` — لتقسيم العمل
- `/implement` — للتنفيذ
- `/diagnosing-bugs` — للتشخيص

اسأل `ask-matt` إذا احترت أي skill تستخدم.

## ميثاق السلوك

بمساهمتك توافق على الالتزام بـ [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md).

شكراً لك! 🙌
