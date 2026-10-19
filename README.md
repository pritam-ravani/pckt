# Pckt

Automatic personal finance tracker for India. Reads bank / UPI / card alerts
from SMS (and soon email), deduplicates them, categorises every transaction and
lets you plug in your own LLM to read odd messages, fix categories and answer questions.

Local-first: all data lives in an on-device SQLite database. Nothing is uploaded
unless you connect an LLM and switch on a feature that uses it (see *Privacy*).

## Run

```sh
flutter pub get
dart run build_runner build -d   # drift codegen
flutter run                      # phone connected with USB debugging on
flutter test                     # parser, dedup pipeline, LLM providers, agent
```

## Architecture

```
lib/
  ingestion/            source-agnostic pipeline: RawInput → parse → dedup → categorise → store
    parser/             rule-based SMS parser (bank sender ids, amounts, refs, VPAs, merchants)
    dedup/              scoring engine that merges the same payment seen via multiple sources
    categorizer.dart    learned merchant rules → structural hints → keyword lists → fallback
    sms/                Android SMS inbox reader (MethodChannel `pckt/sms`, see MainActivity.kt)
  data/db/              drift schema: accounts, categories, transactions, raw_messages, merchant_rules
  llm/                  bring-your-own LLM: LlmClient + OpenAI-compatible / Anthropic / Gemini clients,
                        fallback parser, AI categoriser, agent + tools over the local DB
  features/             dashboard, activity, insights, assistant (Ask), settings, onboarding
  core/theme/           palette (validated categorical colors), typography, icon map
```

### Deduplication

Every raw message is kept in `raw_messages` and linked to the transaction it
produced or merged into, so merges are explainable and reversible.

| Signal | Effect |
|---|---|
| Same UPI ref / RRN | certain match |
| Different refs | certain non-match |
| Same account last-4 | +0.25 (different: −0.5) |
| Time proximity | +0.45 (≤5 min) … +0.1 (≤24 h) |
| Merchant token overlap | +0.2 (none: −0.1) |
| Same sender already reported it | −0.35 (two real ₹20 chais) |

≥ 0.75 merges automatically; 0.5–0.75 creates a *possible duplicate* the user confirms.
A debit from one own account and an equal credit to another within an hour is
marked as a self-transfer and excluded from spend/income.

## Bring your own LLM

Settings → *Connect your LLM*. Requests go straight from the phone to the provider you
pick; there is no Pckt server. Models are listed live from the provider's models endpoint
(free text works too).

| Provider | API | Notes |
|---|---|---|
| OpenAI, OpenRouter, Groq, DeepSeek, any OpenAI-compatible | Chat Completions + `tools` | configurable base URL |
| Ollama / LM Studio on your computer | OpenAI-compatible at `http://<LAN-IP>:11434/v1` / `:1234/v1` | key optional; pick a model with tool calling |
| Anthropic Claude | Messages API + tool use | |
| Google Gemini | `generateContent` + function declarations | |
| On-device | — | coming in phase 5 |

What it does:

- **AI reading** of messages the rules flagged as unreadable. The answer is strict JSON, validated
  (the amount must literally appear in the message), and fed through the same dedup → categorise →
  store path as rule-parsed messages, so an AI-read email still merges with its SMS. Non-transactions
  are ignored with an `AI: …` reason. AI-read transactions are marked for a quick review.
- **AI categorisation** of transactions left in *Other* / *Other Income*. Names are validated against
  your categories; confident merchant-level answers become merchant rules, so the rule engine learns.
  AI choices are never locked — your own edits always win.
- **Ask** tab: an agent (max 8 tool steps) with `query_transactions`, `spending_summary`,
  `list_categories`, `list_accounts`, `find_recurring` and `recategorize` (asks you to confirm first).

### Privacy

The API key is stored in the Android keystore (flutter_secure_storage); provider, URL, model and
toggles in SharedPreferences under `llm.*`. Nothing is sent until a provider is saved **and** the
matching switch is on:

| Switch | Default | What leaves the phone |
|---|---|---|
| AI categorisation | on | merchant, counterparty/VPA, amount, direction, payment mode, date |
| AI reading of unreadable messages | **off** | the full text and sender of those messages |
| Assistant chat | on | your questions + structured tool results (totals, matching transactions); never raw messages |

## Roadmap

- [x] Phase 1 — app shell, theme, DB, dashboard, activity, insights, manual entry
- [x] Phase 2 — Android SMS import + parser, dedup, auto-categorisation, account discovery
- [ ] Phase 3 — Gmail (OAuth, `gmail.readonly`) + IMAP fallback; email parser feeding the same pipeline
- [x] Phase 4 — Bring-your-own LLM: OpenAI-compatible / Anthropic / Gemini, key in secure storage;
      LLM fallback for unreadable messages; agent chat with tools over the local DB
- [ ] Phase 5 — budgets, subscription detection, iOS Shortcuts bridge, SQLCipher encryption,
      on-device model, real-time SMS receiver
