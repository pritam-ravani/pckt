# Contributing to Pckt

Thanks for helping. The most useful contributions are usually **messages Pckt reads wrongly or not at all**.

## Reporting a message Pckt doesn't read

Open an issue with:

- the sender (e.g. `VM-HDFCBK`, `alerts@axisbank.com`)
- the message text, **with personal details replaced**: your name, full or partial account and card
  numbers, UPI IDs, reference numbers and balances. Keep the layout, punctuation and wording exactly
  as they are, because the parser depends on them.
- what Pckt showed (Settings → Sources → Inspect explains each decision) and what it should have shown

## Code

```sh
flutter pub get
dart run build_runner build -d
flutter test
```

- Parser fixes come with a test in `test/sms_parser_test.dart` or `test/parser_regressions_test.dart`
  using the anonymised message.
- Bump `smsParserVersion` when a parser change should re-read existing SMS.
- Keep data on the device. Nothing may leave the phone unless the user connected an LLM and switched
  on the feature that sends it (see *Privacy* in the README).
- Icons come from `tool/gen_icons.js`, and brand assets from `tool/gen_brand_assets.js`. Edit the
  generators, not their output.

By contributing you agree that your contribution is licensed under GPL-3.0.
