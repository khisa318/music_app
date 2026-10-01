# Contributing to MusiX

## The short version

```bash
git switch main && git pull
git switch -c fix/player-seek-crash
# ...work...
flutter analyze && flutter test
git push -u origin fix/player-seek-crash
```

Open a PR. Get it reviewed, merge it, then delete the branch.

Never commit directly to `main`, never force-push to `main`, and never tag
anything to "test the release flow" — a pushed tag is a release, and tags are
never moved or deleted once published.

## Branch naming

| Prefix | Use for |
| --- | --- |
| `feat/` | new user-visible capability |
| `fix/` | bug fix |
| `refactor/` | no behaviour change |
| `perf/` | same behaviour, measurably faster |
| `docs/` | documentation only |
| `chore/` | tooling, CI, dependencies, formatting |

Keep branches short-lived. If a PR is more than a few days old or has picked up
unrelated work, split it — a reviewer who must read 800 unrelated lines will
not review it properly.

## Before you push

```bash
flutter pub get
flutter analyze     # must be clean
flutter test        # must pass
```

`flutter analyze` reporting zero issues is a hard requirement; CI enforces it.
If you touch Android native code, also build once:

```bash
flutter build apk --debug
```

Formatting is not enforced in CI because the existing codebase is not
format-clean. Format the files you actually touched:

```bash
dart format lib/features/player test/update
```

Do not run a repo-wide `dart format` inside an unrelated PR. If you want to do
it, open a dedicated `chore/format` PR so the noise is reviewable on its own.

## Pull requests

Fill in the template. A reviewer should be able to understand the change from
the description and screenshots alone.

- One logical change per PR.
- Explain *why*, not just *what*. The diff already shows what.
- State what you actually tested. "Should work" is not a test plan.
- Screenshots or a short recording for any UI change.
- Note follow-up work you are deliberately leaving out.

Draft PRs are welcome for early feedback — CI still runs.

## Commit messages

Use the imperative, and say why:

```
fix: stop playback restarting when seeking past the track end

seekTo() with a target past the end triggered an out-of-range clamp and
reloaded the queue from position 0. Clamp to the last frame instead.
```

A subject line under ~72 characters. A body explaining the reasoning when the
reasoning isn't obvious from the diff. No "fixes" without a what after it.

## Secrets and signing

**Never commit** `android/key.properties`, a `.jks`, `.keystore`, `.p12`, or any
password. All are gitignored, but gitignore is a safety net, not a plan.

Release signing is configured via `android/key.properties` locally and via the
`MUSIX_KEYSTORE_*` GitHub secrets in CI. See the README section
[Release signing](README.md#release-signing).

If you ever commit a secret, assume it is compromised: rotate it immediately.
Deleting the file in a follow-up commit does not remove it from history.

## Releasing

Bumping `version:` in `pubspec.yaml` **is** the release. Full procedure in the
README: [Releasing](README.md#releasing).

```bash
# edit pubspec.yaml -> version: 1.1.0+2
# commit, PR, merge to main. That is the whole release.
```

Merging a version bump to `main` makes CI push the matching tag, which builds,
signs and publishes the APK. Never type `git tag` for a stable release.

Raise **both** halves. `1.0.9+7` → `1.0.10+1` passes a glance but produces an
APK Android refuses to install, because `versionCode` went backwards. CI fails
this and tells you the next legal value.

Pre-releases are tagged by hand; see
[Pre-releases](README.md#pre-releases).

## Getting set up

The toolchain, including the Rust/NDK requirements for `metadata_god`, is
documented in the README: [Requirements](README.md#requirements).