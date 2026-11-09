# Search follow-ups after TestFlight 1.0.2 (9)

These findings were deferred from TestFlight 1.0.2 (9) and are addressed in the search correctness follow-up. Regression coverage is in SearchRequestTests, SearchIndexInvalidationTests and AnalysisRetryTests.

- [x] P1: Clear/cancel Ask results on Private scope changes, locking and library mutations; enforce current visibility when rendering cached matches.
- [x] P1: Move the URLSession download temporary file synchronously before the completion handler returns, before scheduling MobileCLIP installation.
- [x] P2: Cancel or version Ask and visual-search requests so an older query cannot overwrite a newer query's results.
- [x] P2: Reindex cover/custom-image edits promptly and invalidate embeddings when synced image content changes.
- [x] P2: Distinguish keyword-generation failures from valid empty results; retry failures with a bound instead of persisting a successful analysis version.
- [x] P2: Skip legacy HistoryImport for both in-memory demo modes, including real-link fixtures.

Validation limitation: the current simulator fails real FoundationModels inference. No mocked Apple Intelligence response is shipped. Real-device streaming and CLIP quality still require supported-device testing.

Verification: 90 tests passed, 2 live-network tests skipped; iOS app/extensions and Mac app built successfully. Independent review identified repeated whole-library hashing; indexing now traverses one snapshot per pass. Existing embedding files without an image fingerprint are regenerated on demand.
