# ADR 0002: No network, no auto-update

Status: superseded by [ADR 0004](0004-update-check.md) (the update check is the only network code allowed)

Decision: the app contains no network code, telemetry or updater. Updates are manual releases.

Consequences: smaller attack surface and no privacy concerns; users update by downloading a release. Do not add networking without a new ADR.
