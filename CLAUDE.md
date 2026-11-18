# Notes for Claude Code

- The findings in `docs/hardware.md` are settled: do not test them again.
- Reuse CWA's existing kosync protocol and KOReader's document digest; never invent an endpoint or field.
- Ask for missing information (CWA URL, credentials) instead of assuming it.
- Files the plugin writes on the e-reader must not end in `.txt`: the PocketBook library lists them as books.
- Deploy the plugin over KOReader's SSH server (port 2221, user `reader`) with `COPYFILE_DISABLE=1 tar`, so macOS does not add `._*` files.
