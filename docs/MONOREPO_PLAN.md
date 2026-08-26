# Battuta monorepo implementation plan

Battuta keeps macOS and Windows in one repository because audio contracts,
licenses, issues, versions, and releases are still shared. The immediate goal
is to correct resource ownership without moving application source trees during
an active release cycle.

## Invariants

- macOS Bundle ID, Sparkle feed URL/public key, and signing identity stay
  unchanged.
- Windows Package Identity and Publisher stay unchanged.
- Release asset names and the GitHub repository stay unchanged.
- Public built-in audio and bundled sound packs have one canonical source under
  `shared/`.
- A platform may depend on `shared/`, but never on the other platform project.
- Local-only or unlicensed evaluation recordings must not enter public source,
  application bundles, or release assets.

## Phase 0 — repository hygiene

1. Ignore the complete `SimuBoardMac/build/` directory.
2. Remove historical DMGs from the current Git tree while leaving any local
   files untouched where possible.
3. Publish installers only as GitHub Release assets.
4. Do not rewrite Git history during this phase; history cleanup is a separate,
   explicitly approved maintenance operation if repository transfer size later
   becomes a real problem.

Acceptance: `git ls-files '*.dmg'` returns no files, and a local DMG build does
not dirty the worktree.

## Phase 1 — shared ownership

1. Move the complete public desktop audio tree to `shared/audio/builtin/`.
2. Move redistributable read-only sound packs to `shared/soundpacks/bundled/`.
3. Move brand masters to `shared/brand/source/`.
4. Move audio provenance and the DIY package contract to `shared/licenses/`
   and `shared/contracts/`.
5. Point Windows project files, packaging scripts, and tests directly at the
   shared paths.
6. Preserve the macOS runtime `Resources/Audio` and `Resources/BundledSoundPacks`
   contracts with relative source links to the shared trees; point import and
   regression scripts at the canonical paths.
7. Add a repository verifier for counts, browser-subset equality, bundled-pack
   manifest/permission, forbidden
   local-only assets, brand files, and cross-platform dependency direction.
8. Build macOS and inspect the actual `.app`; run available macOS and Windows
   tests.

Acceptance: both platforms consume the same 237-file base tree and authorized
28-file BCP pack (21 keyboard profiles and 265 recordings total), the macOS
bundle still contains `Resources/Audio` and `Resources/BundledSoundPacks`, and
no Windows project reference contains a `SimuBoardMac` asset path.

## Phase 2 — application directory normalization

Do this only in a later, isolated pull request after a stable release:

1. Move platform roots to `apps/macos/` and `apps/windows/` with `git mv`.
2. Update Xcode, MSBuild, packaging, documentation, and developer scripts in one
   commit.
3. Prove that application identifiers, signing inputs, update feeds, data paths,
   and release filenames did not change.
4. Keep compatibility wrappers for frequently used build commands for one
   release cycle.

This phase is intentionally separate because directory churn creates large,
low-value diffs and makes release fixes harder to review.

## Phase 3 — path-aware CI

1. Run shared contract checks whenever `shared/**` or either platform changes.
2. Run macOS build/tests for `apps/macos/**` or `shared/**` changes.
3. Run Windows build/tests for `apps/windows/**` or `shared/**` changes.
4. Add release validation that checks both platform artifacts use the same
   version and expected shared-audio inventory.

## Phase 4 — optional sparse checkout

Document sparse checkout for contributors who only work on one platform. Do not
split repositories until the products have independent versions, release
cadences, teams, or permissions; current tracked platform source size does not
justify the extra release and asset-versioning overhead.
