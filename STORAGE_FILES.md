# Files written by Nostur

Paths below are relative to the main app's sandbox unless stated otherwise.
This inventory covers explicit app file writes and the configured storage used by
Core Data, Nuke, UserDefaults, and the share extension. Frameworks can create
additional internal cache files.

| Files | Location | Purpose and cleanup |
| --- | --- | --- |
| Temporary videos: downloaded Twitter playback, picked/camera videos, trims, compressed uploads, share exports, thumbnail/range extraction | `tmp/NosturTemporaryMedia/<session UUID>/media/` | Normal completion cleanup where available; previous sessions are swept on launch and maintenance. Playback downloads are removed on player close/replacement, including abandoned loads. Current-session files remain available for replay, drafts, and uploads. |
| Voice recordings | Same session `media/` directory, UUID `.m4a` | Reset deletes the captured recording URL; failed recording setup deletes its partial file. Previous-session leftovers are swept. |
| Downloaded voice messages, WebM conversions, extension-inferred audio links/copies | `tmp/NosturTemporaryMedia/<session UUID>/downloads-a0/` | Session-scoped downloads; converted files stay beside the original. Previous sessions are swept. |
| GIF share exports | Session `media/` directory, UUID `.gif` | Normal share completion cleanup; previous-session fallback. |
| Pending outgoing DM attachments | `tmp/NosturTemporaryMedia/<session UUID>/dm-attachments/` | Picker copies and staged attachments; normal attachment removal plus previous-session fallback. Separate from persistent received DM files. |
| Legacy temporary media | Directly under `tmp`: UUID `.mp4`/`.mov`/`.m4v`/`.webm`, `nostur_shared_<UUID>.mp4/.gif`, `temp_gif.gif`, `dm_file.<extension>`; `tmp/dm-attachments/`; `Library/Caches/a0/` and `a0-own-recordings/` | Known files older than two hours at session start are swept. Recent legacy files, unrelated root files, symlinks, and unrecognized nested folders are preserved. |
| Per-account WoT snapshots | `Library/Application Support/Nostur/web-of-trust-<pubkey>.bin`; legacy `Library/Caches/web-of-trust-<pubkey>.bin/.txt` | Startup removes snapshots whose pubkey is absent from saved accounts. Logout removes that account's snapshot. Switching accounts preserves all saved accounts, including read-only accounts. |
| Learned WoT | `Library/Application Support/Nostur/learned-web-of-trust.json` | Shared learned interactions, with CloudKit synchronization. Not a per-account disposable snapshot. Preserved by inactive-account cleanup. |
| Image/video disk caches | `Library/Caches/`, Nuke namespaces `com.nostur.image.pfp`, `.banner`, `.content`, `.communities`, `.badges`, `.emoji`, and `com.nostur.video.content`; also Nuke's default shared pipeline cache | Cache limits are configured in `ImageProcessing.swift`. Existing settings Clear actions cover pfp, banner, content, and badges only. Communities, emoji, video, and the default shared cache are not individually exposed there. |
| Decrypted received DM files | `Library/Caches/DMFiles/<conversation hash>/<file hash>.<extension>` plus `conversation-id` marker | Persistent DM cache, default 500 MB. Has separate settings; kept conversations are protected from automatic/bulk clearing. Preserved by temporary-media cleanup. |
| Databases and sidecars | Core Data Application Support directory: `Nostur.sqlite`, `NosturCloud.sqlite`, SQLite/framework sidecars | Events, contacts, accounts, feeds, CloudKit state, etc. Existing maintenance remains responsible for database cleanup. No database cleanup changes in this work. |
| Preferences and feed/draft state | UserDefaults-managed preferences | Settings, account selection, text drafts/mentions, local feed positions, DM retention preferences, etc. Media drafts are held in memory; previous-session temporary media is not restored as an attachment draft. |
| Account profile images for sharing | App Group `group.com.nostur.Share`: `account-pfp-<pubkey>.png` | Cached account image passed to the share extension. Separate from Nuke caches. |
| Share account/relay metadata | App Group UserDefaults | Encoded account list, active pubkey, write relay list. |
| Share extension original/prepared attachments | Extension's own `tmp/ShareWithNosturMedia/` and `tmp/ShareWithNosturPreparedMedia/`, UUID files | Extension-owned copies and resized JPEGs. Separate sandbox from the main app's temporary directory; not swept by the main app session cleanup. |
| Credentials | Keychain | Nostr keys and remote-signer session secrets; not ordinary app cache files. |

Temporary cleanup runs on a detached utility task at launch, independently of the
24-hour database-maintenance throttle. Maintenance also sweeps abandoned sessions
and legacy files. It never recursively clears all of `tmp` or `Library/Caches`.
