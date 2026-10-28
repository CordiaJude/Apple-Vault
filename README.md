# Vault

A secure, private home for your important documents — passport, driver’s license, insurance cards, birth certificates, registrations and more — built for iOS 26 in Swift 6 and SwiftUI, with Apple frameworks only.

- **Private by design.** No analytics, no network calls. Optional iCloud sync is off by default (and compiled out unless you enable it).
- **Encrypted at rest.** Images, PDFs, numbers, notes and scanned text are sealed with AES‑256‑GCM using a key kept in the Keychain (`WhenUnlockedThisDeviceOnly`), on top of iOS Data Protection class *Complete*.
- **Locked by Face ID.** On launch, on return from the background (immediately, 1 or 5 minutes), before revealing a masked number, and before opening anything from Siri, widgets, Control Center, Spotlight or Quick Actions.
- **Liquid Glass.** Glass on the controls layer only (tab bar, toolbars, floating buttons, HUDs); documents are solid, Wallet‑style cards.

---

## Architecture

```
SwiftUI views ──► @Observable app state (AppRouter, AppLock, VaultStore, HUDCenter)
      │                         │
      ▼                         ▼
 SwiftData models ◄──── VaultCrypto (CryptoKit + Keychain) ──► encrypted blobs
 (Person, VaultDocument,        │
  DocumentPage, Category)       ▼
      │                 SecureFiles (Data Protection: Complete)
      ▼
 SystemSync ──► VaultSnapshot.json (names + dates only, App Group)
                    ├─► WidgetKit widgets + Control Center control
                    ├─► App Intents / Siri / Shortcuts
                    └─► Quick Actions, Spotlight (titles only, opt‑in)
```

| Layer | What it does |
| --- | --- |
| **Model** (`Vault/Model`) | SwiftData models designed to CloudKit’s rules (all defaults, optional relationships, no unique constraints). Only what’s needed to list and remind (title, kind, color, dates) is stored in the clear; fields, notes, recognized text, images and PDFs are encrypted blobs. 19 built‑in templates in `DocumentKind`. |
| **Security** (`Vault/Security`) | `VaultCrypto` (AES‑GCM, Keychain key, PBKDF2 for backups), `AppLock` (LocalAuthentication), `PrivacyWindow` (lock screen and App Switcher cover in their own window above every sheet), `ScreenCaptureMonitor` (hides documents while recording/mirroring), `Clipboard` (local‑only, 60‑second expiry for sensitive values). |
| **Scanning** (`Vault/Scanning`) | VisionKit document camera → Vision `RecognizeDocumentsRequest` (iOS 26) + a literal `RecognizeTextRequest` pass for MRZ lines → `MRZParser` (ICAO 9303 TD1/TD2/TD3/MRV with check‑digit repair) → `FieldExtractor` heuristics → Foundation Models `@Generable` extraction when Apple Intelligence is available. The person always confirms before saving. |
| **Services** | Notifications (smart defaults: passports 9 & 6 months, others 60 & 14 days), EventKit (calendar sheet needs no permission; Reminders), PDF/image export (optionally password‑protected), encrypted backup/restore, Spotlight, Quick Actions, Share‑extension inbox. |
| **Extensions** | `VaultWidgets` (Home Screen + Lock Screen widgets, Control Center control) and `VaultShare` (“Save to Vault”). Both read/write only the App Group; neither can decrypt the vault. |

### File structure

```
Config/                 xcconfigs, Info.plists, entitlements  ← edit Signing.xcconfig
Shared/                 code shared by app + extensions (App Group, snapshot, deep links, colors)
SharedIntents/          App Intents shared by app + widgets (DocumentEntity, OpenDocumentIntent)
Vault/
  App/                  VaultApp, RootView, MainTabView, AppRouter, AppDelegate, FeatureFlags
  Model/                SwiftData models, templates, fields, reminders
  Persistence/          VaultStore (container, iCloud toggle), DocumentFactory, SampleData (DEBUG)
  Security/             crypto, keychain, lock, privacy window, capture shield, clipboard
  Scanning/             camera, OCR, MRZ, heuristics, Apple Intelligence
  Services/             notifications, export, backup, Spotlight, widgets sync, inbox
  Intents/              Siri phrases and App Shortcuts
  DesignSystem/         cards, glass helpers, avatars, UIKit bridges (zoom, PDFKit, share, events)
  Features/             Documents, Expiring, People, Search, Editor, Settings
VaultWidgets/           widgets + Control Center control
VaultShare/             Share extension
scripts/                generate_xcodeproj.py, make_icon.py, sdk_probe.sh
```

The Xcode project uses folder‑synchronized groups: add a Swift file to any of these folders and it’s in the right target automatically. `scripts/generate_xcodeproj.py` regenerates `Vault.xcodeproj` if you change target structure.

### Verification

There is no Mac in the environment this was written in, so every stage was compiled with `xcodebuild` on GitHub Actions’ `macos-26` runner (Xcode 26) — see `.github/workflows/build.yml`. CI builds two configurations (Debug; Release with the CloudKit flag on) and fails on any warning. `scripts/sdk_probe.sh` prints the real iOS 26 SDK declarations (Vision, Foundation Models, App Intents) used to check API shapes. The MRZ parser and field extractor were also unit‑tested against ICAO specimen data.

---

## Installing on your iPhone

You need a Mac with **Xcode 26** and an iPhone on **iOS 26**.

1. **Open the project.** Double‑click `Vault.xcodeproj`.
2. **Set your bundle identifier and team.** Open `Config/Signing.xcconfig` and change:
   - `VAULT_BUNDLE_ID_PREFIX = com.example` → something unique to you, e.g. `com.janeappleseed`.
   - `DEVELOPMENT_TEAM =` → your Team ID (Xcode ▸ Settings ▸ Accounts ▸ select your Apple ID ▸ the team; a free “Personal Team” works). Or leave it blank and choose the team in each target’s **Signing & Capabilities** tab (Vault, VaultWidgets, VaultShare).
3. **Add your Apple ID to Xcode** if you haven’t: Xcode ▸ Settings ▸ Accounts ▸ “+” ▸ Apple ID.
4. **Connect your iPhone** with a cable (or on the same Wi‑Fi after pairing once). Tap **Trust** on the phone if asked.
5. **Turn on Developer Mode** on the iPhone: Settings ▸ Privacy & Security ▸ Developer Mode ▸ On, then restart and confirm. (The option appears after the phone has been connected to Xcode once.)
6. **Pick your iPhone** as the run destination in Xcode’s toolbar and press **Run** (⌘R). Choose the **Release** configuration (Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Build Configuration) if you don’t want the sample documents.
7. **Trust the developer** (free accounts only): the first launch shows “Untrusted Developer”. On the iPhone go to Settings ▸ General ▸ VPN & Device Management ▸ your Apple ID ▸ **Trust**. Launch Vault again.
8. Optional: add the widgets (long‑press the Home Screen ▸ Edit ▸ Add Widget ▸ Vault), the Control Center control (Control Center ▸ “+” ▸ Vault ▸ Open Document), and try “Hey Siri, show my insurance card in Vault”.

### Free Apple developer account: what’s different

| Feature | Free (Personal Team) | Paid Developer Program |
| --- | --- | --- |
| App, scanning, encryption, Face ID, export, backup | ✅ | ✅ |
| Notifications, Calendar, Reminders, Siri & Shortcuts, Spotlight, Quick Actions | ✅ | ✅ |
| Widgets, Control Center, Share extension (App Groups) | ✅ (normally) | ✅ |
| **iCloud sync (CloudKit)** | ❌ not available | ✅ set `VAULT_USE_CLOUDKIT = YES` |
| App lifetime | **7 days**, then re‑run from Xcode | 1 year |

- **iCloud sync** is compiled out by default (`VAULT_USE_CLOUDKIT = NO`). Settings shows “iCloud Sync: Off” with an explanation, and everything else works normally from local storage. With a paid account, set it to `YES`; the toggle appears in Settings (still off until you turn it on). When on, the vault key moves into iCloud Keychain so your other devices can decrypt synced documents.
- **App Groups** are supported by free accounts. If signing ever fails with an App Groups error, set `VAULT_USE_APP_GROUP = NO`: the app still works fully, but widgets show “Open Vault”, the Control Center control can’t list documents, Siri can’t answer expiration questions, and “Save to Vault” explains it’s unavailable.
- **7‑day expiry.** Free provisioning profiles expire after a week. Your data is safe — just reconnect and press Run again to re‑sign. Make an encrypted backup (Settings ▸ Backup & Restore) before you uninstall, because deleting the app deletes its Keychain key and data.
- Free accounts can register a limited number of App IDs per week; this project uses three (app, widgets, share).

### Siri phrases

Siri requires the app name in no‑setup phrases:

- “Show my insurance card in Vault” / “Show my passport in Vault” (opens Present mode after Face ID)
- “When does my passport expire in Vault?” (answers with the date only)
- “Open Vault”

---

## Privacy

Vault makes no network connections and includes no analytics or third‑party code. Widgets, Siri, Control Center, Quick Actions and Spotlight only ever see document **names and dates** (from `Snapshot.json` in the App Group), never numbers, images, notes or scanned text. Text recognition and Apple Intelligence run entirely on device.
