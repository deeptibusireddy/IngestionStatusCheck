# Ingestion Link Audit

Simple URL audit for ingested content.

## Setup

1. In SharePoint, open the document library and click Sync.
2. Approve the OneDrive prompt.
3. In the synced local folder, keep these files together:
   - ingestion_link_audit.ps1
   - IngestedURLs.xlsx
   - BlockedURLs.xlsx

## Run

Open PowerShell in the synced folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\ingestion_link_audit.ps1
```

The script prompts for:

- Input file path
- Optional output tag

Optional non-interactive run:

```powershell
powershell -ExecutionPolicy Bypass -File .\ingestion_link_audit.ps1 -InputFile .\YourInputFile.xlsx -OutputTag teamA
```

Header rows are auto-detected. If needed, force no-header mode:

```powershell
powershell -ExecutionPolicy Bypass -File .\ingestion_link_audit.ps1 -InputFile .\YourInputFile.xlsx -InputNoHeader
```

## Output

- Default folder: .\audit_results\
- <inputname>_truly_missing_[tag_]yyyyMMdd_HHmmss.csv
- <inputname>_match_audit_[tag_]yyyyMMdd_HHmmss.csv

Options:
- `-OutputFolder <path>` to change where output files are written.
- `-InputFile <path>` to skip the input prompt.

### Status Meaning

- found: URL exists in ingested content.
- blocked: URL is in the blocked list.
- not-testable: URL requires sign-in; cannot be validated anonymously.
- missing: URL not found by URL/path/GUID matching.

Run the script from the local synced folder, not from the SharePoint web page.
