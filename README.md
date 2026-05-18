# Granola Note Sync

## Project Brief

This tool automatically mirrors all your [Granola](https://granola.ai) meeting notes to local Word documents (`.docx`), preserving your Granola folder structure on disk. It runs on a schedule via macOS LaunchAgent.

**The problem it solves:** Granola is great for capturing and summarizing meetings, but its notes live inside the app with no easy way to search, reference, or archive them offline. This script exports everything to a readable, searchable folder of `.docx` files — one per meeting — each containing the AI-generated summary followed by the full transcript.

**Output location:** `~/Documents/Granola Notes/` by default — configurable via `GRANOLA_SYNC_OUTPUT` environment variable.

**Schedule:** Runs every Tuesday at 6:07 AM via macOS LaunchAgent.

**Manual refresh:** Double-click `~/Desktop/Sync Granola Notes.command` to run the same incremental sync on demand.

**What each document contains:**
- Title + date, folder, and participants
- **Notes section:** Granola's AI-generated summary (headings, bullets, structured)
- **Transcript section:** Full verbatim transcript of the meeting

---

## How it works

The script authenticates with the **Granola cloud API** using the bearer token the Granola desktop app stores locally — no extra credentials required. It then:

1. Fetches all your folders from the API (`/v1/get-document-lists-metadata`)
2. Fetches all documents per folder (`/v1/get-document-list`)
3. For each document that has changed since the last sync, fetches:
   - AI summary panels (`/v1/get-document-panels`)
   - Full transcript (`/v1/get-document-transcript`)
4. Builds a `.docx` and writes it to the output folder
5. Updates `manifest.json` to track synced files, transcript counts, and fetch status

**Incremental:** Only documents whose `updated_at` timestamp has changed or whose `.docx` is missing are re-synced. A full run on 200+ documents takes ~3 minutes; subsequent daily runs typically touch only a handful of files.

**Folder moves:** If you refile a note into a different Granola folder, the next sync detects the change and **moves** the existing `.docx` on disk rather than creating a duplicate.

---

## Compatibility

### Granola v7.195+ (May 2026)

Granola v7.195 encrypted its local storage, breaking earlier versions of this script that read from local cache files. The current script is fully compatible:

| What changed | Old approach (broken) | Current approach |
|---|---|---|
| Auth token | Read plaintext `supabase.json` | Decrypts `supabase.json.enc` via macOS Keychain + `storage.dek` |
| Document content | Read plaintext `cache-v6.json` | Fetches from Granola cloud API |
| Folder structure | Read plaintext `cache-v6.json` | Fetches from Granola cloud API |

The token decryption uses Granola's Keychain entry (`Granola Safe Storage` / `Granola Key`) with Chromium safeStorage-compatible PBKDF2 + AES-128-CBC. If decryption fails for any reason, the script falls back to the legacy plaintext `supabase.json`.

---

## Setup

```bash
git clone https://github.com/yourusername/granola-sync.git
cd granola-sync
./install.sh
```

To use a custom output folder (optional — defaults to `~/Documents/Granola Notes/`):
```bash
GRANOLA_SYNC_OUTPUT="$HOME/Documents/My Meeting Notes" ./install.sh
```

The installer:
1. Creates a Python venv at `~/.granola-sync-venv/` and installs dependencies
2. Creates local state/log directories under `~/Library/Application Support/granola-sync/`
3. Copies the runtime script there for LaunchAgent execution
4. **Generates** a LaunchAgent plist using your actual `$HOME` (no hardcoded usernames) and loads it

### Python dependencies

`requirements.txt` includes both `python-docx` and `cryptography`. The `cryptography` package decrypts the Granola token file. Without it, the script falls back to the legacy plaintext token which goes stale every ~6 hours.

### Verify the Granola desktop app is running

The Granola app must be running for the auth token to stay fresh (it refreshes every ~6 hours). The sync script reads the token from:

```
~/Library/Application Support/Granola/supabase.json.enc   ← current (encrypted)
~/Library/Application Support/Granola/supabase.json        ← legacy fallback (may be stale)
```

---

## Running manually

One-click refresh from your Desktop:
```bash
~/Desktop/Sync\ Granola\ Notes.command
```

Dry run — no files written, just shows what would change:
```bash
~/.granola-sync-venv/bin/python sync_granola.py --dry-run
```

Sync a single folder:
```bash
~/.granola-sync-venv/bin/python sync_granola.py --folder "Sales Org"
```

Force a full rebuild of all documents (ignores manifest):
```bash
~/.granola-sync-venv/bin/python sync_granola.py --full
```

Skip transcripts for a faster run (notes/summaries only):
```bash
~/.granola-sync-venv/bin/python sync_granola.py --skip-transcripts
```

Healthcheck dependencies, token decrypt, API access, and writable output folders:
```bash
~/.granola-sync-venv/bin/python sync_granola.py --healthcheck
```

Reconcile Granola API documents, `manifest.json`, and `.docx` files:
```bash
~/.granola-sync-venv/bin/python sync_granola.py --reconcile
```

Combine flags:
```bash
~/.granola-sync-venv/bin/python sync_granola.py --full --skip-transcripts --folder PMF
```

---

## How the schedule works

The LaunchAgent at `~/Library/LaunchAgents/com.arnab.granola-sync.plist` runs the sync every **Tuesday at 6:07 AM**. Logs go to:

```
~/Library/Application Support/granola-sync/logs/launchd.log          ← stdout/stderr from the scheduled run
~/Library/Application Support/granola-sync/logs/sync-YYYY-MM-DD.log  ← per-run log from the script itself
```

To trigger a manual run via launchd:
```bash
launchctl start com.arnab.granola-sync
```

To check the agent is loaded:
```bash
launchctl list | grep granola-sync
```

To temporarily disable:
```bash
launchctl unload ~/Library/LaunchAgents/com.arnab.granola-sync.plist
```

To re-enable:
```bash
launchctl load -w ~/Library/LaunchAgents/com.arnab.granola-sync.plist
```

---

## Troubleshooting

### "Granola API returned 401 — token expired"
The Granola desktop app must be running for the token to stay fresh. Open Granola and wait a moment for it to refresh, then re-run the sync.

### Notes section shows "(no notes)" for a document
The AI summary hasn't been generated yet in Granola (typically takes a few minutes after a meeting ends), or the document is very short/empty. Run the sync again after Granola has had time to process it. If the summary is visible in the Granola app but missing from the `.docx`, force a rebuild:
```bash
~/.granola-sync-venv/bin/python sync_granola.py --full --folder "Folder Name"
```

### Some documents are stale (old content despite changes in Granola)
The incremental sync only re-fetches documents whose `updated_at` timestamp changed. To force a full rebuild:
```bash
~/.granola-sync-venv/bin/python sync_granola.py --full
```

### Two sessions have the same filename
If two Granola sessions share the same title and date (e.g., a duplicate capture), both map to the same `.docx` filename. The script keeps the **more recently updated** one as the visible `.docx` and records the duplicate in the manifest as suppressed.

### "cryptography" module not found
```bash
~/.granola-sync-venv/bin/pip install cryptography
```
Without this package, the script can't decrypt `supabase.json.enc` and falls back to the stale `supabase.json`, which causes 401 errors once the token expires.

### A note appears in `_Unfiled/` but is filed in Granola
The API returns documents based on current folder memberships. Try a forced refresh:
```bash
~/.granola-sync-venv/bin/python sync_granola.py --full --folder "Folder Name"
```

---

## What lives where

```
notes-granola/
├── sync_granola.py                  # the sync script
├── install.sh                       # one-time setup
├── requirements.txt                 # python-docx
├── com.arnab.granola-sync.plist     # LaunchAgent (copied to ~/Library/LaunchAgents/)
└── .venv/                           # legacy local venv (gitignored, not used by launchd)
```

Runtime state:
```
~/Library/Application Support/granola-sync/
├── sync_granola.py                  # runtime copy used by launchd
├── logs/                            # daily log files
└── manifest.json                    # sync state — which docs are up to date
```

Output documents:
```
~/Documents/Stanford/Academics/Granola Notes/
├── PMF/
│   ├── 2026-01-06_STRAMGT 514.1 (Rachleff) - Class 1.docx
│   └── ...
├── Sales Org/
│   ├── 2026-04-02_STRAMGT 351.1 (Leslie-Herzberg).docx
│   └── ...
├── _Unfiled/
│   └── ...
└── ...
```

---

## Key design decisions

- **Cloud API over local cache:** Granola's local cache was plaintext in v7.112 but moved to encrypted SQLite in v7.195. The cloud API is stable and doesn't require reverse-engineering local storage.
- **Manifest-driven incremental sync:** Comparing `updated_at` timestamps avoids re-downloading 200+ documents on every run. `--full` overrides this for a clean rebuild.
- **Runtime state outside Desktop:** The LaunchAgent runs from `~/Library/Application Support/granola-sync/` so scheduled syncs are not blocked by macOS Desktop privacy controls.
- **AI panels as the primary notes source:** `original_content` from `/v1/get-document-panels` is clean HTML that renders well into Word. Raw handwritten notes live in Granola's Y.js document format (binary CRDT) and aren't exported by the API.
- **Deduplication by filename:** When two Granola sessions map to the same filename (same title + date), the one with the most recent `updated_at` wins — it's the one more likely to have a completed AI summary.
- **No rclone dependency at runtime:** The script writes directly to `~/Documents/`. Any cloud sync (iCloud, Google Drive Desktop) can be layered on top of that folder separately.
