# Battuta Windows design QA

Final result: passed for the current Windows port milestone.

## Source hierarchy

1. `SimuBoardMac/SimuBoardMac/Models`, `Services`, and `Tests` define behavior,
   persisted data, defaults, privacy rules, and failure semantics.
2. SwiftUI views and `BattutaVisualStyle.swift` define application-owned layout,
   spacing, typography hierarchy, colors, and interaction flow.
3. Windows owns notification-area behavior, native title bars, key labels, file
   dialogs, startup registration, and the portable update handoff.
4. Screenshots are visual evidence only; they are not a source for business data.

## Runtime evidence

- macOS tray reference: `../media/battuta-sound-poster.jpg`
- macOS statistics reference: `../media/battuta-stats-poster.jpg`
- macOS DIY reference: `../media/battuta-diy-editor.png`
- Windows real-data statistics: `qa/08-stats-runtime-real.png`
- Windows functional DIY editor: `qa/09-diy-runtime-real.png`
- Windows live tray panel: `qa/10-tray-runtime-real.png`
- Broken transparent tray icon evidence: `qa/11-tray-overflow-current.png`
- Fixed multi-frame tray icon: `qa/12-tray-overflow-fixed.png`
- Fixed native context menu: `qa/13-tray-context-menu-fixed.png`
- Fixed persistent tray panel: `qa/14-tray-panel-fixed.png`
- Broken history layout: `qa/15-stats-history-1024-before.png`
- No-input flicker contact sheet: `qa/20-recording-contact-sheet.png`
- Fixed 1100 DIP history layout: `qa/26-history-fixed-full-dpi.png`
- Fixed tray slider geometry: `qa/19-tray-sliders-fixed.png`
- Fixed heatmap fill and legend bounds: `qa/28-history-heatmaps-fixed.png`
- Fixed native ComboBox colors: `qa/31-combobox-colors-fixed.png`

The Windows captures use the real Release `Battuta.exe` and `PrintWindow`; they
contain only the application windows, not the user's desktop. The statistics
capture uses the actual local SQLite state and correctly renders an empty data
set as zero/empty states.

## Verified invariants

- Tray: 360 DIP wide, fixed header/footer, vertically scrolling card stack, and
  the same section order as Swift `MenuBarView`.
- Statistics: 1100×760 ideal and 1100×600 minimum; today/history/keyboard pages,
  four timeline ranges, application timelines, annual comparison, and key heatmap.
- DIY: 1240×760 ideal and 1120×660 minimum; 236/flexible/340 three-column layout,
  three mapping modes, stable physical-key selection, inspector, and save actions.
- Audio split: 760×630 modal, real waveform, split/release controls, confidence,
  warnings, preview, confirm, and cancel cleanup.
- Shared visual tokens: lime accent, olive/charcoal surfaces, 14/10 radii, 20 DIP
  page padding, 16 DIP cards, and Windows system fonts.

## Issues found and corrected

1. Replaced macOS traffic-light chrome with native dark Windows title bars,
   including Alt+Space, Snap, standard resize borders, and caption buttons.
2. Removed deterministic demo counts, applications, dates, chart seeds, and
   hard-coded update/login success states. Every displayed value now comes from
   a ViewModel/service or an explicit empty/loading/error state.
3. Replaced label-based keyboard identity with stable `PhysicalKeyId` and a tested
   Windows ANSI visual catalog (`Ctrl`, `Win`, `Alt`, `Backspace`, `Enter`, etc.).
4. Connected tray, statistics, DIY, and audio-split controls to their real state
   transitions and guarded dirty/busy/close behavior from the Swift implementation.
5. Removed the synchronous flyout `Deactivated` race. Popup actions now run after
   dismissal, and the context menu uses a coherent dark/high-contrast template.
6. Restored persisted `custom:<uuid>` sound packs on startup and merged them into
   the tray profile list.
7. Visual QA caught a DIY `SlotChoice` record string and clipped numeric-keypad
   captions; both were corrected and covered by regression checks.
8. Replaced the transparent single-frame 4bpp ICO with nine 32bpp frames and
   removed duplicate VERSION_4/legacy notification callbacks that made one left
   click open and immediately close the panel.
9. Replaced the ownerless WPF context menu with the native Win32 popup-menu
   contract. It has no white check gutter and reliably closes on an outside click.
10. Removed the history width-switching feedback loop found in the user's video.
    The window now stops at 1100 DIP and the top cards always remain horizontal at
    530/16/400+, so scrollbar changes cannot trigger wide/stacked oscillation. A
    four-second, 40-frame `PrintWindow` run produced one identical frame hash.
11. Rebuilt the shared Slider template around an explicit 4 DIP rail. Its 14 DIP
    thumb now shares the same Y centre and remains inside both endpoints.
12. Made both heatmaps calculate cells from their actual width. The 24-hour and
    53-week grids now fill their cards, while the year legend is measured and
    inset inside the lower-right edge.
13. Returned tray profile controls to the Windows system ComboBox/ComboBoxItem
    templates. Popup item mouse-up is explicitly committed before the tray can
    process deactivation, so clicking an item changes the active profile and closes
    the list.
14. Recolored the native ComboBox visual tree without replacing its system template.
    Closed fields and Popup surfaces are dark, normal text remains readable, and
    hover/selected states use distinct Battuta greens instead of the system blue.

## Accepted platform differences

- Segoe UI Variable / Microsoft YaHei UI and Fluent glyphs replace Apple fonts
  and SF Symbols.
- The portable build opens the validated GitHub Release page for an update;
  Sparkle is macOS-only.
- Schema-v1 `.simuboardpack` compatibility currently uses directory selection on
  Windows; a ZIP container is a separate cross-platform format decision.
- Application statistics currently use a generic app glyph because the persisted
  snapshot does not expose a stable icon token. Application names and values are real.
- Rhythm and year heatmaps expose an overall automation name and mouse tooltips;
  per-cell UI Automation peers remain an accessibility follow-up.

## Automated gates

- Release solution build with `-warnaserror`: 0 warnings, 0 errors.
- Core tests: 121/121.
- Windows tests: 209/209.
- Production UI data/localization guard and window-construction smoke tests pass.
- Production source scan has no demo/fake statistics, fixed example apps/dates,
  Mac-only visible key labels, missing XAML handlers, TODOs, or stale chart controls.
