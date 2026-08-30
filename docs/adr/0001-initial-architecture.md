# ADR 0001: الهيكل المبدئي للمشروع

- **Date:** 2026-08-30
- **Status:** Accepted

## Context

المشروع بدأ كـ repo فارغ. نحتاج هيكل مفتوح، قابل للتوسع، ومهيأ للعمل الجماعي.

## Decision

- استخدام **MIT License** — أكثر ترخيص مرن للمشاريع المفتوحة
- تهيئة بـ **mattpocock/skills (37 skill)** لإدارة دورة الحياة الهندسية (TDD, review, triage, wayfinder)
- هيكل GitHub standard: `README`, `CONTRIBUTING`, `CODE_OF_CONDUCT`, `.github/ISSUE_TEMPLATE`, `workflows/ci`
- `package.json` بحد أدنى (ESM, Node >=18) — قابل للتبديل لـ monorepo لاحقاً

## Consequences

- أي مساهم يستطيع البدء فوراً بدون إعدادات معقدة
- الـ skills توفر workflow موحد للـ spec → tickets → implement → review
