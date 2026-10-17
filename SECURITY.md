# Security

FloatNote has no server, no account and no analytics. It reads and writes plain `.txt` files in `Documents/FloatNote`, and opens web pages (Grok, Claude, X) in your browser only when you press the matching shortcut.

## Permissions it asks for

- **Accessibility**: to notice the Right Option / Right Command taps while another app is in front, and to read the text you selected for ⌃⌥S. It reads no other text, and never types for you (the ⌃⌥S fallback presses ⌘C in the front app and then restores your clipboard).
- **Documents folder**: your notes.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use GitHub's private reporting: the repository's **Security** tab > **Report a vulnerability**. Include the FloatNote version (shown in Finder under Get Info on the app), your macOS version and the steps to reproduce. You will get a reply as soon as the maintainers can; there is no bounty.

## Supported versions

Only the latest release is supported.

## About the download

Releases are signed with a self-made certificate, not an Apple Developer ID, and are not notarized; that is why macOS asks you to use **Open Anyway** the first time. You can always build the app yourself from source (see the README) and compare.
