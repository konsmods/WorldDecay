# Changelog

## 2.0.1

- Fixed fence generator crash spam: `isEntityObject()` used `obj:getClass():getSimpleName()`, which Kahlua can't reflect as an indexable table in B42, throwing a `RuntimeException` on every fence-bearing square. Now uses `instanceof(obj, "IsoEntity")`.
- Stopped vines spawning on `construction_*` sprites (scaffolding/construction objects).
