# Nostur localization style guide

Translations must describe the control in Nostur, not translate an isolated
English word. Keep placeholders, Markdown, URLs, NIP numbers, `nostr:` links,
and whitespace that affects rendering unchanged.

## Shared Nostr terminology

| English | Spanish (`es`) | Indonesian (`id`) |
| --- | --- | --- |
| Nostr | `Nostr` | `Nostr` |
| relay / relays | `relay` / `relays` | `relay` (also for plural) |
| event | `evento` | `event` |
| note | `nota` | `catatan` |
| post (noun) | `publicación` | `postingan` |
| post (verb) | `publicar` | `kirim` or `terbitkan`, according to context |
| repost | `republicar`, `republicación` | `posting ulang` |
| feed | `feed` | `feed` |
| thread | `hilo` | `utas` |
| zap | `zap`; `enviar un zap` | `zap`; `kirim zap` |
| private/public key | `clave privada/pública` | `kunci privat/publik` |
| remote signer | `firmante remoto` | `penanda tangan jarak jauh` |
| sign/signing | `firmar` / `firmando` | `tanda tangani` / `menandatangani` |
| direct message | `mensaje directo` | `pesan langsung` |
| mute/unmute | `silenciar/reactivar` | `bisukan/aktifkan suara` |

Product and protocol names such as Blossom, Cashu, NWC, NIP-17, NIP-46,
Nostr, Nostur, Tor, and Web of Trust are not translated.

## Spanish

- Use neutral, concise Spanish with informal `tú` throughout the UI.
- Use sentence case. Avoid title case copied from English.
- Use `Ajustes` for the app section and `configuración` for configuration as a
  general concept.
- Keep the Nostr community term `relay`. Use `relays` as its plural. This is
  intentionally not the electrical term `relé`.
- Translate an action as an action: `Save` is `Guardar`, `Clear` is `Borrar`,
  `Post` is `Publicar`, and `Sign` is `Firmar`.
- `Following` is `Siguiendo` when it labels accounts the user follows. It must
  never be translated as `Siguiente` (next).

## Indonesian

- Address the user consistently as `Anda`.
- Prefer short imperative button labels: `Tambah`, `Hapus`, `Simpan`, `Kirim`,
  `Bagikan`, and `Tampilkan`.
- `Relay` does not take the English plural `relays`.
- Keep protocol concepts as `event`, `kind`, `relay`, and `zap` where
  translating them would change their Nostr meaning.
- Use `feed` consistently for the social feed. Do not use the literal verb
  `memberi makan`.
- Use `utas` for a conversation thread; `benang` means physical thread.

## Review process

1. Locate the string's use and read its translator comment.
2. Translate the complete message in context; do not assemble grammar from
   independently translated fragments.
3. Run `ruby scripts/lint-localizations.rb`.
4. Review key/account deletion, payments, remote signing, DMs, and relay setup
   in the running app with a native speaker before release.
