# ADR 0001: Lightweight Clean Architecture

Status: accepted

Context: the app grew as a flat `Sources/` folder with singletons and direct IOKit/Process calls, which made it untestable and hard for contributors.

Decision: four SwiftPM libraries (Domain, DesignSystem, Platform, Features) plus a composition-root executable. Ports live in Domain, adapters in Platform, enforced by `check-architecture.sh`. Violations that cannot be fixed yet are listed in an allowlist that may only shrink.

Consequences: logic is unit-testable with fakes; `package` access is used between targets (tools 5.9); some singleton debt remains.
