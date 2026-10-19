# Pckt

Automatic personal finance tracker for India. Reads bank / UPI / card alerts
from SMS and email, deduplicates them, categorises every transaction and
(soon) lets you plug in your own LLM for insights.

Local-first: all data lives in an on-device SQLite database. Nothing is uploaded.

## Run

```sh
flutter pub get
dart run build_runner build -d   # drift codegen
flutter run                      # phone connected with USB debugging on
flutter test                     # parser + dedup pipeline tests
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
  features/             dashboard, activity, insights, settings, onboarding
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

## Roadmap

- [x] Phase 1 — app shell, theme, DB, dashboard, activity, insights, manual entry
- [x] Phase 2 — Android SMS import + parser, dedup, auto-categorisation, account discovery
- [x] Phase 3 — Email: IMAP with app passwords (Gmail, Outlook, Yahoo, Zoho, any IMAP) + optional
      Gmail OAuth (`gmail.readonly`); email parser feeding the same pipeline, SMS↔email dedup
- [ ] Phase 4 — Bring-your-own LLM: OpenAI-compatible / Anthropic / Gemini, key in secure storage;
      LLM fallback for unreadable messages; agent chat with tools over the local DB
- [ ] Phase 5 — budgets, subscription detection, iOS Shortcuts bridge, SQLCipher encryption,
      on-device model, real-time SMS receiver
