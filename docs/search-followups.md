# Search follow-ups after TestFlight 1.0.2 (9)

The search integration ships before these review findings are addressed. Track each fix separately, with regression coverage for the affected behavior.

- [ ] P1: Clear/cancel Ask results on Private scope changes, locking and library mutations; enforce current visibility when rendering cached matches.
- [ ] P1: Move the URLSession download temporary file synchronously before the completion handler returns, before scheduling MobileCLIP installation.
- [ ] P2: Cancel or version Ask and visual-search requests so an older query cannot overwrite a newer query's results.
- [ ] P2: Reindex cover/custom-image edits promptly and invalidate embeddings when synced image content changes.
- [ ] P2: Distinguish keyword-generation failures from valid empty results; retry failures with a bound instead of persisting a successful analysis version.
- [ ] P2: Skip legacy HistoryImport for both in-memory demo modes, including real-link fixtures.

Validation limitation: the current simulator fails real FoundationModels inference. No mocked Apple Intelligence response is shipped. Real-device streaming and CLIP quality still require supported-device testing.
