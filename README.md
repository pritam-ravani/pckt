# Pckt

Automatic personal finance tracker for India. Reads bank / UPI / card alerts
from SMS and email, deduplicates them, categorises every transaction and
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
    email/              IMAP (enough_mail) + Gmail API sources, HTML→text, EmailSyncController
    parser/email_*      email parser: sender-domain directory, bank alerts via SMS rules, merchant receipts
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
| SMS ↔ email (different channels), no merchant/account conflict | +0.3 (≤30 min), +0.15 (≤3 h) |
| Same sender already reported it | −0.35 (two real ₹20 chais) |

≥ 0.75 merges automatically; 0.5–0.75 creates a *possible duplicate* the user confirms.
Merchant tokens include brand aliases for the legal names banks print (BUNDL → Swiggy,
Eternal → Zomato, …). When a merchant receipt email (Swiggy, Amazon, Uber…) merges
into a bank alert, its merchant name replaces the bank's and the category is re-derived
unless the user set one.
A debit from one own account and an equal credit to another within an hour is
marked as a self-transfer and excluded from spend/income.

## Email

Settings → Sources → Email → Connect. Pckt searches the INBOX since the chosen
import window (1/3/6/12 months, then incrementally with a 1-day overlap, max 400
messages per sync) for mail from known bank / card / UPI / merchant domains or with
payment words in the subject, downloads only those, converts HTML to text and runs
them through the same parse → dedup → categorise pipeline as SMS. Network and MIME
work runs in a background isolate. Settings live in SharedPreferences (`email.*`);
the password only in the Android keystore (`SecretStore`). Inspect shows every
email and why it was parsed, merged or ignored.

### App passwords (IMAP, no setup needed)

| Provider | Steps | Server |
|---|---|---|
| Gmail | Turn on 2-Step Verification (myaccount.google.com/security) → myaccount.google.com/apppasswords → create "Pckt" → paste the 16 characters | imap.gmail.com:993 |
| Outlook / Hotmail | Two-step verification → Advanced security options → app password. Microsoft is phasing out password IMAP for personal accounts; if it fails, forward alerts to Gmail/Zoho | outlook.office365.com:993 |
| Yahoo | login.yahoo.com/account/security → Generate app password | imap.mail.yahoo.com:993 |
| Zoho | Enable IMAP access in Mail settings; with 2FA create an app-specific password | imap.zoho.in:993 (imap.zoho.com outside India) |
| Other | Any IMAP server, SSL (993) or STARTTLS (143) | — |

### Gmail sign-in (OAuth, optional)

"Sign in with Google" (Gmail REST API, `gmail.readonly`) only appears when the build
has an OAuth client id. One-time Google Cloud setup:

1. console.cloud.google.com → create a project → *APIs & Services → Library* → enable **Gmail API**.
2. *OAuth consent screen*: External, app name "Pckt", add scope
   `https://www.googleapis.com/auth/gmail.readonly`, add your Google account as a **test user**
   (Testing mode is enough for personal use; `gmail.readonly` is a restricted scope, so
   publishing would need Google verification).
3. *Credentials → Create credentials → OAuth client ID → Android*: package name
   `com.pckt.pckt`, SHA-1 of the signing key. For debug builds:
   ```sh
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
   ```
   (Release builds need the release key's SHA-1 as a second Android client.)
4. *Create credentials → OAuth client ID → Web application* (no redirect URIs needed). Android's
   Credential Manager uses this one as the *server client id*.
5. Build with the **Web** client id:
   ```sh
   flutter run --dart-define=GOOGLE_OAUTH_CLIENT_ID=1234567890-abc.apps.googleusercontent.com
   ```

Without the define the button is hidden and app passwords are used.
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
| On this phone (Gemma) | LiteRT-LM via `flutter_edge_ai` | model picked for the device, downloaded once; see below |

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

## On-device models

Settings → Connect your LLM → *On this phone (Gemma)*. Pckt reads the phone's RAM, chip, free
storage, Android version and GPU support (`pckt/device` channel) and recommends the most capable
model that fits (`lib/llm/on_device/model_catalog.dart`):

| Model | Download | Picked when | Ask tab |
|---|---|---|---|
| Gemma 4 E4B | 3.4 GB | ≥ 10.5 GB RAM | ✓ |
| Gemma 4 E2B | 2.4 GB | ≥ 5.2 GB RAM (6 GB phones) | ✓ |
| Gemma 3 1B | 0.6 GB | small phones, with a Hugging Face token (gated licence) | — |
| Qwen3 0.6B | 0.3 GB | small phones, no token | ✓ |

- Runs on the GPU (OpenCL) and falls back to CPU; Gemma 4 runs at float32 because half precision
  copies digits wrongly from long prompts.
- Downloads run as a `dataSync` foreground service with a notification (WorkManager otherwise kills
  them at 9 minutes, and Hugging Face files can't resume). Mobile data is never used without asking;
  if Wi-Fi drops the download stops, and orphaned downloads are cancelled at startup.
- Needs Android 11+ on arm64 (`minSdk 30`). Qualcomm / Tensor NPU bundles are in the catalog but off:
  enabling them means `qualcomm_npu: true` in pubspec (Qualcomm's licence, +83 MB).
- Measured on a Galaxy F23 (6 GB, Snapdragon 750G): Gemma 4 E2B loads on the GPU and calls tools,
  but memory is tight and a multi-step Ask answer takes minutes.

## Real-time SMS alerts (Android)

`SmsAlertReceiver.kt` listens for `SMS_RECEIVED` (permission `RECEIVE_SMS`, asked together with
`READ_SMS`). If a message comes from a known bank DLT sender (`VM-HDFCBK`, `AD-ICICIT-S`, not
`-P` promos) and has a completed debit/credit verb plus an amount, it posts *"₹250 debited · HDFC —
Tap to review"* on the **Transaction alerts** channel. Tapping opens Pckt, which syncs SMS on resume;
the receiver itself stores nothing, so the Dart pipeline stays the source of truth. Turn it off in
Settings → SMS → *Instant alerts* (pref `sms.alerts`, read natively as `flutter.sms.alerts`).
Android 13+ also needs the notification permission, which Pckt asks for once.

## Share to Pckt & iOS Shortcuts

Any text can be fed through the normal pipeline (parse → dedup → categorise → store) as source
`shortcut`; a snackbar says whether it was added, matched an existing transaction or ignored.

- **Android share sheet:** long-press a bank SMS → Share → Pckt.
- **Link:** `pckt://ingest?text=<url-encoded message>&sender=<url-encoded sender>` (`sender` is
  optional; without it the bank is guessed from the text). Works on Android and iOS.

iOS gives apps no SMS access, but a Shortcuts automation can forward each bank message:

1. Shortcuts → **Automation** → **+** → **Message**. *Message Contains*: `debited` (make a second
   automation for `credited`, and for `spent` if your card SMS use it). Choose **Run Immediately**.
2. Add **URL Encode** → input: *Shortcut Input* → **Content** (tap the variable to pick it).
3. Add a second **URL Encode** → input: *Shortcut Input* → **Sender**.
4. Add **Text**: `pckt://ingest?text=` *URL Encoded Text (1)* `&sender=` *URL Encoded Text (2)*.
5. Add **Open URLs** with that Text.

Each matching message then opens Pckt briefly and shows what was recorded. Sharing the same message
twice is a no-op (content-hashed id), and a message that also arrives by email is merged by dedup.

## Export & backup

Settings → Data:

- **Export transactions (CSV)** — date, amount (₹), direction, merchant, category, account, mode,
  reference, note, sources; UTF-8 with BOM so Excel shows ₹ and names correctly.
- **Back up everything** — a JSON dump of every table (accounts, categories, transactions, raw
  messages, merchant rules and anything added later) with format and schema versions.
- **Restore from backup** — validates the file (format, schema version not newer than the app,
  required tables), shows what it contains, and after confirmation replaces all data in a single
  DB transaction (nothing changes if anything fails).

Files go out through the share sheet or a *Save to device* dialog.

## Roadmap

- [x] Phase 1 — app shell, theme, DB, dashboard, activity, insights, manual entry
- [x] Phase 2 — Android SMS import + parser, dedup, auto-categorisation, account discovery
- [x] Phase 3 — Email: IMAP with app passwords (Gmail, Outlook, Yahoo, Zoho, any IMAP) + optional
      Gmail OAuth (`gmail.readonly`); email parser feeding the same pipeline, SMS↔email dedup
- [x] Phase 4 — Bring-your-own LLM: OpenAI-compatible / Anthropic / Gemini, key in secure storage;
      LLM fallback for unreadable messages; agent chat with tools over the local DB
- [ ] Phase 5 — budgets, subscription detection, SQLCipher encryption (done: on-device Gemma
      models, iOS Shortcuts / share bridge, real-time SMS alerts, CSV export & JSON backup)
