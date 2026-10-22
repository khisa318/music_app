# Security Policy

<p align="center">
  <a href="https://github.com/khisa318/music_app/releases/latest">
    <img src="https://img.shields.io/github/v/release/khisa318/music_app?style=flat-square&label=latest%20release" alt="Latest release" />
  </a>
  <a href="https://github.com/khisa318/music_app/security/advisories">
    <img src="https://img.shields.io/badge/security-advisories-blue?style=flat-square" alt="Security advisories" />
  </a>
</p>

MusiX is an open-source YouTube Music client for Android. We take security and
privacy seriously and appreciate responsible disclosure from the community.

## Supported Versions

Security fixes are provided for the latest stable release only. Older versions
do not receive backported patches, so please update before reporting an issue.

| Version | Supported |
| :------ | :-------: |
| Latest stable release | Yes |
| Older releases | No |
| Unreleased `main` builds | Best effort |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.** Public
disclosure before a fix is available puts users at risk.

Report privately through GitHub's **Private Security Advisory** flow:

> [Report a vulnerability privately](https://github.com/khisa318/music_app/security/advisories/new)

Please include:

- A clear description of the vulnerability and its potential impact.
- The affected version or commit.
- Steps to reproduce, or proof-of-concept code.
- Any suggested mitigation or fix.
- Whether you would like to be credited in the release notes.

If you are unsure whether something is a vulnerability, report it privately
anyway. We would rather triage a false alarm than miss a real issue.

### What not to include

- Do not attach real user data, credentials, or API keys.
- Do not test against other people's accounts or devices.
- Do not access, modify, or delete data beyond what is needed to demonstrate
  the issue.

## Response Timeline

| Step | Target |
| :--- | :----- |
| Initial acknowledgement | Within 48 hours |
| Triage and severity assessment | Within 5 business days |
| Fix or mitigation | Depends on severity; critical issues are prioritized |
| Public disclosure | Coordinated with the reporter after a fix ships |

We will keep you informed throughout the process and credit reporters who wish
to be acknowledged.

## Scope

### In scope

- Vulnerabilities in the MusiX application source code.
- Mishandling of locally stored data, including playback history, downloads,
  settings, and user-supplied API keys.
- Authentication or authorization flaws.
- Insecure network communication or certificate handling.
- Dependency vulnerabilities that are directly exploitable through MusiX.
- Leaked credentials or secrets committed to this repository.

### Out of scope

- Vulnerabilities in third-party services MusiX connects to, such as YouTube
  Music, JioSaavn, or LRCLib. Report those to the respective service.
- Issues that require physical access to an unlocked device.
- Denial-of-service attacks that require large amounts of resources.
- Social engineering, spam, or phishing attempts.
- General best-practice suggestions without a concrete, exploitable impact.
- Reports generated solely by automated scanners without a demonstrated impact.

## Disclosure Policy

We follow coordinated disclosure:

1. Report the issue privately and allow a reasonable window for a fix.
2. Avoid sharing details publicly until a patched release is available.
3. Work with us on a disclosure date if you plan to publish a write-up.

We will publish a security advisory for confirmed vulnerabilities and credit
the reporter with their permission.

## User Security Guidance

- Download MusiX only from the official
  [GitHub Releases](https://github.com/khisa318/music_app/releases) page.
- Verify the published checksum of the APK when one is provided.
- Never share personal API keys, bot tokens, or chat IDs in issues, pull
  requests, screenshots, or logs.
- Treat API keys entered in the app as sensitive; use keys restricted to the
  minimum required permissions.
- Keep Android and MusiX up to date.

## Safe Harbor

We will not pursue legal action against researchers who:

- Follow this policy in good faith.
- Avoid privacy violations, data destruction, and service disruption.
- Report findings promptly and privately.
- Give us a reasonable opportunity to fix the issue before disclosure.

## Acknowledgements

Thank you to everyone who reports issues responsibly and helps make MusiX safer
for all users.
