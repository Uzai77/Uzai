# Security

## Reporting a vulnerability

Please do **not** open a public issue. Report it privately through GitHub: open the repository's **Security** tab
and choose **Report a vulnerability**. Helpful details: Uzai version, Windows version, steps to reproduce, what an
attacker needs and what they gain. Please don't attack other people's accounts, servers or devices to demonstrate
a problem.

Only the latest release gets fixes.

## What Uzai protects

- **Sign-ins** stay on your PC, sealed with Windows DPAPI. They never go into plain files, logs or URLs.
- **Updates** are installed only if their RSA signature matches the public key built into Uzai. The private key never
  lives in this repository.
- **Content from other people** (chat messages, links, room invites, plugin output, game folders and manifests) is
  treated as untrusted. That means: no network shares, no unknown URL schemes, and strict size limits.
- **Local connections** (the room network and the phone remote) are limited to what each feature needs.

The full threat model, every past finding and the remaining risks are documented in German in
[`docs/SECURITY.md`](docs/SECURITY.md).

## Not included

Uzai ships no games, ROMs, BIOS files or console keys and never downloads them.

Some third-party services are used through their public app client IDs, for example the YouTube TV, Epic Games
Launcher and Twitch web clients. These IDs are not secrets of this project; see `docs/SECURITY.md`.
