# lib/website/pages

## Purpose

One file per site route. Presentational only — they compose the shell and widgets from
[../](../) and read their text from `SiteCopy` / `PolicyDocs`.

## Files

- `home_page.dart` — the landing page: hero → readings → how it works → pricing → FAQ →
  download. Declares: `HomePage` (takes an `anchor`, and scrolls to it after the first frame).
- `policy_page.dart` — renders **any** `PolicyDoc`; all five legal pages route here. Declares:
  `PolicyPage`.
- `contact_page.dart` — Contact Us, and the target of `/help`. Declares: `ContactPage`.
- `not_found_page.dart` — for a path that matches nothing, after `siteAliases` has had its
  chance. Declares: `NotFoundPage`.

## Notes

- There are only four page files for eight-plus routes because `policy_page.dart` is generic:
  `/privacy`, `/terms`, `/refund`, `/shipping` and `/delete-account` all resolve to it with a
  different `PolicyDoc`.
- `contact_page.dart` hides the phone row rather than printing a fake number while
  `SitePlaceholders.supportPhone` is null.
- Anchors on the home page come from `HomeAnchors` in
  [../site_shell.dart](../site_shell.dart); the nav links to `/#section` style targets through
  `goToSection`.
