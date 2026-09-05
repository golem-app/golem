# Reporting a security problem

Golem runs a language model on the user's own device and talks to the
network only to fetch model files the user asked for, so most security
reports will concern model-file verification, the download path, local
storage, or the native engines.

Do not open a public issue for a vulnerability. Use **Report a
vulnerability** on this repository's Security tab (GitHub's private
vulnerability reporting). If that button is not offered to you, open an
issue titled "Security contact request" with no details in it, and the
maintainer will reach you privately.

Golem ships no telemetry and has no server, so there is no bug-bounty
program and no service to test against; please keep testing to builds you
run yourself.
