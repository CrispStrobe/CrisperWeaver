# App Store handoff — 2026-10-03

This handoff follows a read-only inspection of App Store Connect. The exact
snapshot is retained in [status.json](status.json). No app listing, territory
setting, review message or submission was changed.

## Full: current rejected version

App ID `6789600762`, bundle ID `com.crispstrobe.crisperweaver`.
macOS version `1.0` remains `REJECTED`, with build `85` attached and `VALID`.
China mainland (`CHN`) reports `available: false` / `CANNOT_SELL`; Germany,
the United States and Hong Kong report available. This is an observed state,
not a change made by this work. The API does not explain the reason for
`CANNOT_SELL`; confirm China mainland is deselected in Availability before
sending the reply below. Availability is app-level, so inspect the existing
iOS listing too before any territory write.

The existing Review Notes say “Fully offline. No network access needed.”
That should be corrected when preparing the next submission: Full permits
optional remote services and model downloads. Preserve the build-specific
sandbox and entitlement explanation when editing its notes.

Draft reply for the rejected macOS submission, after confirming China mainland
is deselected in App Store Connect:

> Hello App Review,
>
> We have excluded China mainland from CrisperWeaver's App Store availability.
> We are taking the storefront-exclusion option described in your Guideline 5
> message for submission c4f644f5-afda-4947-a046-a693b4098a1e. Please re-review
> macOS version 1.0, build 85, for the remaining selected storefronts. Thank you.

This draft has not been sent. Re-review is still required; a territory flag
does not clear the rejected version automatically.

Suggested replacement opening for Full's Review Notes, after checking it
against the build being submitted:

> No account or login is required. On-device transcription and synthesis can
> run offline once their models are installed. Model downloads use the network.
> Optional remote processing is available only when explicitly configured and
> enabled by the user. China mainland is excluded from this app's selected
> storefronts.

Keep the existing build-85 sandbox, file-picker and local-server entitlement
details below this opening when resubmitting that build. Verify China mainland
is deselected before retaining the last sentence. This replacement is a draft;
the existing Apple notes have not been edited.

## Lite: separate app record

The Lite bundle ID is registered, but a separate App Store Connect app record
was absent during this inspection. Create the record in
[App Store Connect](https://appstoreconnect.apple.com/apps), using these values:

| Field | Value |
| --- | --- |
| Platform | macOS |
| Name | CrisperWeaver Lite |
| Primary language | English (U.S.) / `en-US` |
| Bundle ID | `com.crispstrobe.crisperweaver.lite` |
| Suggested SKU | `crisperweaver-lite-macos` |
| Access | Full Access |

Apple documents this creation flow in
[Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app).
The sibling `appstore.md` records that app-record creation is unavailable
through this account's API; this task has not attempted an unsupported write.
After creation, retain the new numeric app ID for `LITE_APPSTORE_APP_ID`.
The package source is `0.13.1+89`; the Lite App Store version must match the
package marketing version `0.13.1` before attaching build `89`.

Listing text and the Review Notes draft are in
[STORE_LISTING.md](../../STORE_LISTING.md#lite-mac-app-store-listing).
Use that Lite copy, not the Full description. Model downloads remain enabled,
as requested; they download weights for local inference. Embedded engines run
on-device. Optional HTTP model servers are restricted to literal loopback
addresses and must themselves be configured for local inference. Lite cannot
guarantee the network behavior of a separately installed server.

Screenshots must come from the actual native Lite build and show its real
settings and available engines. Existing Full screenshots and browser captures
are not proof of the native Lite artifact. Native Lite screenshots are captured as described below; the new record's
privacy answers remain to be completed before a submission.
The sibling `appstore.md` documents the account's privacy-form workflow.
Local-only processing does not establish approval for China mainland; Apple
must review the actual artifact, listing and permitted local functionality.

## Lite privacy form evidence

Use the Lite-specific policy in [PRIVACY.md](../../PRIVACY.md), rather than
copying Full's cloud-feature answers. The source contains no developer
backend, account system, analytics or tracking SDK. Embedded inference keeps
audio, transcripts, speaker profiles and embeddings on-device. Local history
and recordings are stored on the Mac. Model discovery and download requests
expose ordinary connection metadata and, if configured, the user's optional
HuggingFace authentication token (`ModelService` / `DownloadEngine`).

Apple's [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
define collection using retention beyond servicing a request and require
considering third-party partners. Do not infer the final privacy-form answer
from local inference alone; check download-provider retention and the actual
configuration. This handoff documents app behavior and has not saved privacy
answers to Apple.

## Native screenshots

[Lite Mac-only capture](https://github.com/CrispStrobe/CrisperWeaver/actions/runs/37100584737)
passed at source `adcd49c`. The app code matches `c30ae26`; the added workflow
and test select the Lite compile-time flavor. Its artifact is
`app-store-screenshots-lite`: eight English PNGs, each `2880 × 1800`.
Lite identity, downloads-enabled policy and remote-engine rejection assertions
passed. All eight images were visually inspected and render without errors or
visible OpenAI/ChatGPT references. Hashes are retained in [status.json](status.json).

These are native debug UI captures with seeded example transcripts and sparse
placeholder model files. They demonstrate the actual Lite UI; they do not
prove inference or downloaded-weight validity. The separately signed package
is built in release mode. The home heading still uses the shared
“CrisperWeaver” name; the synthesis welcome identifies “CrisperWeaver Lite”.
The optional translation example mentions “phone” on Mac.

Use the six primary captures for the initial handoff: `01_transcript`,
`02_history`, `03_transcribe`, `04_synthesize`, `05_models`, `08_settings`.
Keep the optional music and translation shots for further editorial review.
The captures have not been uploaded to Apple.

Reproduce a Lite Mac-only capture with:

```sh
gh workflow run screenshots.yml --ref main -f flavor=lite -f mac_only=true -f locales=en -f macos=true
```

## Signed package and validation

The earlier signed Lite package passed CI at source `9cf9155`:
[package-only run](https://github.com/CrispStrobe/CrisperWeaver/actions/runs/36966052131).
The fresh package-only run for source `c30ae26` passed:
[37100259898](https://github.com/CrispStrobe/CrisperWeaver/actions/runs/37100259898).
It verified version `0.13.1` (build `89`), 15 Mach-O files, startup smoke,
and app/installer signing. The downloaded package matches its SHA-256 sidecar:
`ba15149106726c260b370eb157c6dcfc638b62ea162eb1266d07f424f4f1317e`.
It tests Lite policy, reuses the existing signing certificate, verifies app
and installer signatures, and retains a SHA-256 sidecar. It does not upload
to Apple, validate through Apple's upload service, or submit for review.

To reproduce that package-only build on GitHub:

```sh
gh workflow run ci.yml --ref main -f build_lite=true
```

The current production browser validation is complete without retries:
[Full](https://github.com/CrispStrobe/CrisperWeaver/actions/runs/37048167419)
passes 42 tests per browser with two Lite-only skips;
[Lite](https://github.com/CrispStrobe/CrisperWeaver/actions/runs/37048174888)
passes 44 per browser in Chromium, Firefox and WebKit.
[Native CI](https://github.com/CrispStrobe/CrisperWeaver/actions/runs/37048167412)
passes Linux/macOS analysis, tests and desktop builds. These checks concern
source `c30ae26`; they do not constitute Apple approval or native Lite screenshots.
