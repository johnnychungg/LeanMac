# ADR 0003: Privileged helper via sudoers

Status: accepted

Decision: SMC writes and charge control go through two helper binaries in `/Library/PrivilegedHelperTools`, run via a sudoers rule limited to one user. Arguments are typed and validated (`HelperCommand`, `ChargeLimit`); a single function builds the sudo line.

Consequences: no resident root daemon and no XPC service to secure; the install step needs the user's password once. Dev mode (`LEANMAC_DEV=1`) makes everything read-only.
