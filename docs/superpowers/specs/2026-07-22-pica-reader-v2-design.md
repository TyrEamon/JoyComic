# Pica-Style Reader V2 Design

## Goal

Replace JoyComic's patched reader rendering/loading kernel with an isolated `reader_v2` based on PicaComic's proven architecture, while preserving JoyComic's source APIs, routes, chapters, history, downloads, settings, toolbar, and diagnostics.

## Evidence

The July 22 device log proves JM download, recombination, JPEG validation, codec creation, and later-page widget frames succeed. Black screen occurs because the production reader starts all 45 page providers together, distant pages receive frames before page zero, and an obsolete session continues after a second trace starts. The current global `ReaderPipeline` then attributes old work to the new trace.

## Boundary

Replace page provider lifecycle, scheduling, viewports, preload policy, image cache ownership, cancellation, trace ownership, and frame/error state. Preserve `ComicSource`, `ComicState`, `ReaderChapter`, current chapter APIs, source-aware URL/header/fallback/JM transform configuration, history, local downloads, reader settings, and outer controls.

## Components

### Data Adapter

`ReaderV2DataAdapter` converts existing route and source contracts into immutable `ReaderV2Page` values containing chapter/page identity, URL candidates, headers, cache key, and optional bytes transformer. Reader widgets consume only this descriptor.

### Session

Every entry/chapter load owns a `ReaderV2Session` with an immutable trace and cancellation signal. Chapter changes, retries, route disposal, and replacement cancel the previous session. Cancelled completion cannot publish bytes, cache entries, UI state, or events.

### Scheduler

One `ReaderV2Scheduler` owns page work:

- at most three active jobs;
- visible page before preload;
- page zero first on entry;
- preload limited to configured 2-8 pages;
- duplicate cache keys share one future;
- fallback hosts tried serially inside one job;
- cancelled generations discarded.

### Image Lifecycle

`ReaderV2ImageProvider` and `ReaderV2PageImage` follow PicaComic's StreamImageProvider/ComicImage pattern: Flutter ImageStream/ImageCache, `ScrollAwareImageProvider`, stable non-zero placeholders, frame-boundary disposal of old `ImageInfo`, in-slot retry, and frame reporting only after `ImageInfo` reaches the widget. Download and optional JM transform happen through the scheduler before Flutter decode.

### Viewports

Vertical continuous and paged modes are lazy builders with no chapter-wide cache extent. Horizontal, vertical-paged, and double-page modes all use the same page widget and scheduler. Existing chrome wraps v2 through a compatibility shell; no mode may keep an independent loader.

### Diagnostics

Diagnostics are session-owned and record session start/cancel/end, page queue/start/download/transform/decode/frame/error, active/queued counts, cancellation reason, and first-frame latency. Old traces can be logged only as discarded and never relabeled.

## Migration

1. Build and test v2 without changing `/reader`.
2. Add all viewports through the shared kernel.
3. Switch `/reader` to the v2 compatibility shell.
4. Keep old files for one device-validation cycle as code rollback only.
5. Remove the old kernel after iPhone validation in a separate cleanup.

## Acceptance

- A 45-page chapter starts no more than three active jobs.
- Initial work is page zero plus the configured nearby window.
- Page zero frames before distant pages.
- Leaving/reloading cancels old work.
- Old trace events never contaminate a new trace.
- JM and Pica pages share one renderer.
- All reading modes retain navigation, gestures, toolbar, chapter switching, history, and local downloads.
- Production and diagnostic tests use the same rendering path.

## Tests

Unit tests cover priority, concurrency, deduplication, cancellation, trace isolation, serial fallbacks, and adapter fidelity. Widget tests cover a real frame, bounded 45-page startup, page-zero priority, scrolling window updates, disposal cancellation, shared renderer use, and non-zero loading/retry slots. Codemagic IPA validation on iPhone must prove bounded concurrency, page-zero frame, re-entry, and no trace contamination for JM and Pica.

## Reference And License

The lifecycle/data flow adapts PicaComic's MIT-licensed reader. Substantial adapted code retains its MIT copyright and license notice.
