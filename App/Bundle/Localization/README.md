# Translations

English is the source language: the text written in code, `tr("Scanning…")`, is the key.
Every other language is one folder here:

```
Localization/<code>.lproj/Localizable.strings   UI text (key = English text)
Localization/<code>.lproj/InfoPlist.strings      macOS permission prompts
```

To add a language (for example `fr`):

1. Copy `vi.lproj` to `fr.lproj` and translate the right-hand side of every `"key" = "value";` line.
2. Add `case fr` (and its native `displayName`) to `AppLanguage` in `Sources/LeanDomain/Localization/Localization.swift`.
3. Add `<string>fr</string>` to `CFBundleLocalizations` in `App/Bundle/Info.plist`.
4. Run `Scripts/check-l10n.py` – it reports missing, unused and malformed entries.

Placeholders: `%@` is a runtime value, `%1$@`, `%2$@` let you reorder values, `%%` is a literal percent sign.
Keep them in every translation.
