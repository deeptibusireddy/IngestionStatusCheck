# Handoff Checklist

A simple implementation checklist for engineering productization. This tool helps content and support teams check whether a URL has been ingested into the content system, is blocked, or is unaccounted for.

## Core Experience
- User can paste a single URL or multiple URLs and get a status for each.
- User can upload a CSV file for bulk checks.
- Each URL returns one of these statuses: found, blocked, missing, not-testable.
- Each status includes a short reason so the user understands why.
- Results page shows a summary count (found, blocked, missing, total) at the top.

## Status Model
- **found** — URL exists in the ingested content dataset.
- **blocked** — URL is intentionally excluded from ingestion.
- **missing** — URL was not found in either dataset.
- **not-testable** — URL cannot be checked because the tool does not have access (e.g. requires a sign-in). Route these to a content expert for manual confirmation. Support engineers should not be shown content they are not authorized to access.
- Each status must include a human-readable reason (e.g. "matched by GUID", "permission-required").

## Matching Rules
- Accept any URL format the user pastes — canonical, shortened, redirect target, legacy GUID-based, or human-readable — and automatically convert it to whatever format is needed to match against the ingested and blocked datasets.
- Normalize URLs before matching (strip tracking params, fix casing, standardize scheme, sort query params) so formatting differences don't cause missed matches.
- Check blocked first, then ingested (blocked takes priority).
- If the URL is an Azure DevOps wiki link, match by wiki page ID so links in different URL formats still resolve correctly.
- If the URL contains a GUID, use it as a fallback identifier to find a match even if the rest of the URL has changed.
- If the URL returns a redirect (301/302), follow it and attempt to match the destination URL as well.

## Input and Data Sources
- Accept pasted text (one URL per line).
- Accept CSV or TXT file upload for batch mode.
- Load source datasets (ingested and blocked URL lists) at runtime.
- If source files are missing or unreadable, show a clear error before the user tries to run a check.

## Useful Enhancements
- Live HTTP status checks per URL (200, 301, 404, 410, etc.) so users can spot dead or redirected links.
- Show the redirect target URL when a 301/302 is detected.
- Show the canonical URL when a match is found by GUID or redirect.
- Downloadable export of results.
- Flag likely duplicate index entries caused by a redirect source and its destination both being indexed.

## Quick Definitions
- **Ingested URL** — A URL from an approved content source that has been added to the content index.
- **Blocked URL** — A URL that is intentionally excluded from ingestion, usually because the content is restricted or irrelevant.
- **GUID** — A unique identifier that appears in some legacy or migrated URLs. Used to match content that has moved to a new URL.
- **Canonical URL** — The preferred, authoritative URL for a piece of content. What should be indexed.
- **Not-testable** — The tool could not verify this URL because it requires authentication the tool does not have.

## Engineering Note
- PowerShell implementation is optional. Engineering can choose any stack that best supports a production-ready solution.
- Target integration with the Content Health Dashboard.
