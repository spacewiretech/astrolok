# web/icons

## Purpose

PWA icons referenced by [../manifest.json](../manifest.json).

## Files

- `Icon-192.png`, `Icon-512.png` — the standard icons.
- `Icon-maskable-192.png`, `Icon-maskable-512.png` — the maskable variants, which need their
  content inside the safe zone so a platform can crop them to any shape.

## Notes

- All four are **upscaled from the 80×80 `assets/icons/om_mark.png`** and are visibly soft at
  512px. A full-size export of the mark is already needed for the store listings; the same file
  fixes these, the launcher icons and the listings together.
