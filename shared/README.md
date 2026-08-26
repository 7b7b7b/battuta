# Shared assets

This directory owns assets and contracts consumed by more than one Battuta
platform. Platform projects may depend on `shared/`; neither platform may read
assets from the other platform's project directory.

## Layout

- `audio/builtin/` — the canonical 237-file base desktop audio tree.
- `soundpacks/bundled/` — redistributable read-only sound packs shared by both
  desktop applications. The authorized BCP (Suit80) pack contains 28 WAV files.
- `brand/source/` — editable/master artwork used to derive platform icons.
- `licenses/` — source provenance and redistribution records.
- `contracts/` — platform-neutral formats such as `.simuboardpack`.

The project `LICENSE` and aggregate `THIRD_PARTY_NOTICES.md` intentionally stay
at repository root so GitHub and packaging tools continue to discover them.

The browser extension keeps its original 151 MP3 files at repository-level
`audio/` for now. They must remain a byte-identical subset of
`shared/audio/builtin/`; the repository verifier enforces that relationship.

## macOS bundle path

The macOS runtime already resolves samples below `Resources/Audio`. Xcode also
uses a source folder's basename as the copied bundle name. Therefore
`SimuBoardMac/SimuBoardMac/Resources/Audio` is a tracked relative symlink to
`shared/audio/builtin`: it gives the source a single owner while preserving the
existing bundle contract. Do not replace that link with a direct Xcode folder
reference named `builtin`, which would produce `Resources/builtin`.

The same rule applies to read-only bundled packs:
`SimuBoardMac/SimuBoardMac/Resources/BundledSoundPacks` is a tracked relative
symlink to `shared/soundpacks/bundled`. Windows copies that same directory into
its existing `BundledSoundPacks` output path. Across the base tree and the BCP
pack, both desktop applications ship 21 keyboard profiles and 265 recordings.

## Updating shared assets

1. Add or replace redistributable source files only in the appropriate shared
   directory.
2. Record provenance and processing in `licenses/AUDIO_SOURCES.md`.
3. Keep unlicensed local evaluation material outside the public shared tree and
   outside Git. BCP/Suit80 is bundled because its Battuta redistribution
   permission is recorded in the pack and provenance inventory.
4. Run `./scripts/verify-shared-resources.sh` from the repository root.
5. Run both platform test suites before publishing a release.
