# Omega

> مشروع مفتوح المصدر — Open Source

## نبذة / About

**Omega** هو مشروع مفتوح المصدر مبني بمعايير هندسية حديثة. يهدف لتوفير قاعدة نظيفة، قابلة للتوسع، ومهيأة للعمل الجماعي.

**Omega** is an open-source project built with modern engineering standards — clean, scalable, and collaboration-ready.

## المميزات / Features

- ✅ هيكل مشروع جاهز للتوسع
- ✅ مهيأ بـ [Matt Pocock Skills](https://github.com/mattpocock/skills) — 37 skill هندسية (TDD, code-review, triage, wayfinder...)
- ✅ جاهز للمساهمات الخارجية
- ✅ ترخيص MIT

## البدء السريع / Quick Start

```bash
# 1. استنساخ المشروع
git clone https://github.com/mohmaedeslam00116/omega.git
cd omega

# 2. تثبيت الأدوات (Node 18+)
npm install

# 3. تثبيت الـ skills (إن لم تكن مثبتة)
npx skills@latest add mattpocock/skills --all

# 4. تهيئة إعدادات المشروع الهندسية
# في أي agent يدعم الـ skills (Claude Code, Cursor, ...):
# /setup-matt-pocock-skills
```

## هيكل المشروع / Project Structure

```
omega/
├── .agents/skills/      # 37 skill هندسية (universal)
├── .claude/skills/      # روابط للـ Claude Code
├── docs/
│   ├── adr/             # Architecture Decision Records
│   └── agents/          # وثائق الـ agents
├── .github/             # templates & workflows
├── README.md
├── LICENSE
└── CONTRIBUTING.md
```

## المساهمة / Contributing

نرحب بجميع المساهمات! اقرأ [CONTRIBUTING.md](./CONTRIBUTING.md) و [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) قبل البدء.

We welcome contributions! Please read `CONTRIBUTING.md` first.

```bash
# إنشاء branch جديد
git checkout -b feat/my-feature

# بعد التعديل
npm run check  # إن وجد
git commit -m "feat: add my feature"
gh pr create
```

## الـ Skills المتاحة / Available Skills

المشروع مهيأ بـ 37 skill من `mattpocock/skills`:

| الفئة | Skills |
|------|--------|
| **Engineering** | `tdd`, `code-review`, `codebase-design`, `diagnosing-bugs`, `domain-modeling` |
| **Planning** | `wayfinder`, `to-spec`, `to-tickets`, `grill-me`, `grilling` |
| **Workflow** | `implement`, `prototype`, `research`, `triage`, `wizard` |
| **Writing** | `writing-beats`, `writing-shape`, `writing-fragments` |

استخدم `ask-matt` لتوجيهك للـ skill المناسب.

## الترخيص / License

[MIT](./LICENSE) © 2026 Mohamedeslamkg

---

**Made with ❤️ — مفتوح للجميع**
