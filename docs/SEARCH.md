# Local Search

Local Search is a native addition to the independent Mac fork, introduced in
0.13.0. Original Tunguska remains credited to Viktor Lofgren. The search code is
GPL-2.0-or-later and runs on the Mac CPU, outside the emulated ternary machine.

## Use it

Open **Local Search** in the sidebar or press **⌘F**. Choose one folder containing
`.txt`, `.md`, `.markdown`, or PDFs with selectable text. Search returns up to 20
passages, their source filenames, and PDF page numbers. Select a result for an
excerpt and choose **Show in Finder** to reach its source. Keyword search matches
any query term and ranks using BM25. It folds case, accents and character width;
quotes and punctuation are separators, not phrase/Boolean query operators.

For English paraphrases such as “proof of purchase for living room furniture,”
check **Include meaning search** before choosing a folder, or check it and press
**Refresh**. Then switch from Keywords to **Meaning · English**. This uses Apple's
installed English sentence embedding model. If that model is unavailable,
keyword search still works; the app does not download a replacement. Meaning
indexing takes considerably longer and is opt-in. The approximate results are
experimental and can miss useful passages; check the source.

**Refresh** rebuilds the selected folder to pick up edits. **Cancel** abandons a
new index while preserving the previous one. **Forget folder** releases the
index and selected-folder access. The index exists only in memory until forgotten
or the app quits; no persistent bookmarks, background crawler or cloud service.
Closing the search window cancels work but retains its completed index for the
current app session. Opening search pauses the original emulated computer.

## What is ternary here?

Meaning search normalizes 512-dimensional sentence vectors and quantizes each
coordinate to −1, 0 or +1, using a zero band of half the vector's RMS magnitude.
Two 512-bit masks store positive and negative coordinates. Population counts
produce a coarse cosine score without floating-point multiplication. The best
`max(512, floor(N/10))` candidates are reranked with their **original FP32** vectors.
Collections with at most 512 vectors use exhaustive FP32 retrieval.

The packed signature occupies 136 bytes (including alignment padding) per passage in this implementation,
versus 2,048 bytes for the original vector. **Both are retained.** This prototype
therefore uses additional memory; it does not demonstrate a smaller total index.
The inverted keyword index is conventional native C++, not ternary arithmetic.
Any keyword speedup must be attributed to that implementation, not to ternary.

## Measure instead of assume

**Measure this query** runs both implementations 21 times in alternating order,
after one warmup each. **Export measurement** saves every timing and result ID,
hardware/OS/model details, corpus/query fingerprints and quality checks. The UI
export excludes document contents, query text and file paths, though fingerprints
and IDs should still be treated as information about your corpus.

The timed interval is **query string → materialized result records**: query
canonicalization or a fresh embedding, scoring, top-20 selection and title/path/
page/excerpt creation. It excludes initial indexing, reference-index preparation,
cold application/model startup, input debounce, main-queue scheduling, and screen
drawing. There is no cached query vector or result. This is an end-to-end search
pipeline measurement, **not a measurement of visible UI response time**.

- Keywords: comparison with the system SQLite FTS5, an optimized in-memory index,
  a cached prepared statement and `ORDER BY rank LIMIT 20`. Both use identical
  canonical tokens and BM25 parameters. Acceptance requires nonempty reference
  results, identical top-20 sets, and matched score error below `1e-8`.
- Meaning: comparison with exhaustive normalized FP32 cosine scoring using
  Apple's Accelerate matrix/vector multiply. Acceptance requires at least 98%
  aggregate recall of the reference top 20, and at least 95% on every nonempty
  query. This measures agreement with that model, not human relevance judgments.
- Both: the quality gate and a median baseline/native ratio of at least 2 must
  pass before the UI reports the 2× target met. Empty-result workloads cannot pass.

The baseline is not HNSW, Spotlight, or a commercial search engine. Warm in-memory
microsecond keyword timings will not translate into equally large improvements
in perceived app responsiveness. Index construction, PDF extraction, cache state,
corpus, model, hardware and query mix can dominate a real workflow.

## Measured on this Mac

On Apple M5 Max, macOS 27.0 build 26A428, 20 queries × nine rounds/path,
2026-09-25:

| Mode and corpus | Native median | Reference median | Ratio | Top-20 recall | 2× gate |
| --- | ---: | ---: | ---: | ---: | --- |
| Keywords: 2,696 manual files / 30,803 passages | 0.074 ms | 0.889 ms | **12.00×** | 100% | Passed |
| Meaning: 400 manual files / 3,298 passages | 1.611 ms | 1.571 ms | **0.98×** | 99.75% | Failed |

Every keyword query's individual median speedup exceeded 2× in this run
(range 2.11–37.38×); all ordered result lists matched. Keyword p90 latency was
0.107 ms versus 1.922 ms. Keyword indexing took 2.17 seconds. Meaning indexing
took 353.6 seconds; it is optional for this reason. These are observed runs on
a development machine, not isolated-hardware performance guarantees.

The semantic experiment preserved at least 19 of 20 reference results on every
query and passed its quality gate, but **did not meet the requested 2× speed
objective**. This release demonstrates faster conventional keyword search, not
a ternary semantic performance win. A faster GUI or indexing-plus-query workflow
has also not been established. Raw [keyword results](benchmarks/search-keywords-m5-max.json)
and [meaning results](benchmarks/search-meaning-m5-max.json) include all samples,
queries, platform and source fingerprints. Measurements precede final UI-only
and test-harness fixes; the measured search/scoring implementation is unchanged.
Nothing here establishes performance
on millions of documents or across millions of users' machines.

## Reproduce

```sh
make search-check search-sanitize rendering-check rendering-sanitize sandbox-check
python3 scripts/benchmark_search.py --output build/search-benchmark-keywords
python3 scripts/benchmark_search.py --meaning --max-files 400 --output build/search-benchmark-meaning
```

Use a fresh output directory on subsequent runs. The script locally copies
regular UTF-8 manual sources from `/usr/share/man`, writes source hashes and 20
fixed queries, and records nine rounds per query/path. It does not download or
redistribute the manuals. Their contents and available files vary with macOS.
Checked-in reports under `docs/benchmarks/` contain measurements and provenance,
not manual text. The query list is public test data; it is included by this
script, unlike private UI exports. Source-file hashes identify the measured
implementation independently of a later documentation commit.

For your own corpus:

```sh
build/search-cli /path/to/folder 'certificate signing' --keywords-only
build/search-cli /path/to/folder 'proof of purchase for a sofa' --meaning
build/search-cli /path/to/folder unused --keywords-only --benchmark queries.txt
```

The developer CLI is unsandboxed, does not retain an index between invocations,
and is not included in the distributed app. Without `--keywords-only`, the CLI
builds embeddings, even when issuing a keyword query. Query files contain one
query per line, up to 100 queries. The app is the convenient reusable index.

## Input boundaries and remaining limits

The app keeps its existing App Sandbox and user-selected-file entitlement; no
network entitlement. Hidden files, package descendants and symbolic links are
skipped. Reads use directory-relative descriptors with `O_NOFOLLOW` on every
path component, require regular files, and reject FIFOs/devices and oversized or
growing files. Source files are never executed. Finder reveal rechecks paths.

Limits: 200,000 enumerated entries, 100,000 passages, 128 MiB extracted UTF-8 text,
8 MiB/text file, 32 MiB/PDF, 1,000 PDF pages and 8 million UTF-16 code units of
extracted text per PDF. Passages are approximately 1,200 UTF-16 code units and do
not overlap. UTF-8 and UTF-16 text are accepted. Queries are at most 4,096 UTF-8
bytes and keyword queries at most 64 terms. Scanned PDFs need external OCR;
password-protected or malformed PDFs are skipped. Hover over the file counts to
read up to 100 skipped-file explanations.

PDFKit parses in the app process. Input limits and App Sandbox do **not** provide
a hard per-document time/memory limit or isolate a PDFKit vulnerability. Cancel
is cooperative between document/page/passage operations. Adversarial PDF parsing
needs a separate constrained helper before claiming production hardening for
arbitrary corpora. Automatic refresh, persistent/incremental indexing, OCR,
multilingual semantic models and million-document scaling are not implemented.

## Release verification

Version **0.13.0 (build 11)** was built from
`1fd85a9185fe2647f72152414f2f1de455e1c146`. The clean universal build passed core,
assembler, compiler, image-mutation, Vision, Explorer, GPU, search, AppKit,
sanitizer, release-integrity and real App Sandbox gates. Native smoke testing
verified folder selection, PDF page results, contextual excerpts, English
paraphrases, refresh, Forget folder, keyboard editing, scrolling and JSON export.
The new UI lifetime regressions were also confirmed to reject the earlier code.

Apple accepted notarization submission
`978a8ecf-3efd-4c78-bafd-e9cc81a4f971`. The final ZIP was extracted and independently
checked for a timestamped Developer ID signature, the exact minimal entitlements,
hardened runtime, stapled notarization, Gatekeeper acceptance and both `arm64`
and `x86_64` slices. The app, source archive, final ZIP and SHA256SUMS were
reverified together. Runtime tests executed the ARM64 slice on this Mac;
Intel and older macOS runtime validation remain outstanding.

Local distribution files are under `build/releases/0.13.0-1fd85a9185fe/`:
`Tunguska-0.13.0-universal2.zip`,
`Tunguska-0.13.0-source-1fd85a9185fe.tar.gz`, and `SHA256SUMS`.
Distribute all three together, with the included notices. No public GitHub
binary release was published by this work.
