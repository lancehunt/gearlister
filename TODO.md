# TODO

Improvements to implement next:

- Data model: Store per-slot structured fields in history entries (slotId, itemId, itemLink, itemName) and generate display strings at render time. Remove regex parsing across UI/compare paths.
- Memory/performance: Reuse visual frames or add a small frame pool to avoid creating/destroying frames each refresh. Consider caching parsed slot->itemId maps for snapshots.
- Text mode robustness: In `GetEquippedItems`, include items even when `GetItemInfo` is not cached; fall back to itemLink-derived name and refresh on `GET_ITEM_INFO_RECEIVED` similar to visual mode.
- UX: Standardize window title to `GearLister` everywhere; add a Copy button and auto-select in text mode; include realm in history display labels when available.
- API robustness: Add inspect throttle/backoff and use `CanInspect("target")`; guard and optionally unregister `GET_ITEM_INFO_RECEIVED` when `pendingItemLoads` is empty.
- Code organization: Split `GearLister.lua` into modules (`core`, `db`, `ui`, `inspect`, `compare`, `utils`) loaded via TOC for maintainability.
- Tooling: Add `luacheck` with WoW globals, `stylua`, and a basic CI job to run them. Add a quick `luac -p` syntax check.
- Release/Docs: Sync README badges (version/interface) with `GearLister.toc`; add `CHANGELOG.md`; ensure GitHub Actions workflow matches `scripts/release.sh` expectations and `addon.yml` packaging rules.
