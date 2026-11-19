# sweep

[![ci](https://github.com/VivianSobers/sweep/actions/workflows/ci.yml/badge.svg)](https://github.com/VivianSobers/sweep/actions/workflows/ci.yml)

See how much space your macOS app and developer caches use, then clean only the categories you choose.

## What it looks like

This report was produced by running `bin/sweep` against a fixture home with Xcode, Homebrew, Slack, Android Studio, and other cache folders:

```text
  CATEGORY             LOCATION                                     SIZE
  ──────────────────────────────────────────────────────────────────────
  Xcode                ~/Library/Developer/Xcode/DerivedData        2.0M
  Homebrew             ~/Library/Caches/Homebrew                    1.0M
  Slack                ~/Library/Application Support/Slack/Code Ca… 512K
  Other caches         ~/Library/Caches (other)                     256K
  Android Studio       ~/Library/Caches/Google/AndroidStudio-2025.1 128K
  ──────────────────────────────────────────────────────────────────────
  Reclaimable                                                       3.9M
```

## Install

```sh
git clone https://github.com/VivianSobers/sweep.git
cd sweep
ln -s "$PWD/bin/sweep" /usr/local/bin/sweep
```

## Usage

```sh
sweep                         # report only
sweep list                    # show cache paths
sweep clean xcode slack       # confirm each category
sweep clean --dry-run --all   # preview all cleanable categories
sweep clean --yes homebrew    # skip confirmation
```

`clean --all` includes every category except `library` (Other caches). Name `library` explicitly to clean those other cache folders. A dry run never prompts or deletes. `--yes` skips confirmations for scripts.

## Safety

- Running `sweep` without arguments only reports sizes; it never deletes anything.
- Cleanup accepts category IDs from a built-in registry. It does not accept arbitrary paths.
- Before removing a folder, `sweep` resolves it and checks that it is inside your home directory, at least two folders below it, and outside Documents, Desktop, Downloads, Pictures, Movies, and Music. A symlink that resolves outside your home is refused.
- `sweep` refuses to run as root and skips a category while its app is running.
- When a category has its own cleanup command, `sweep` uses that command if it is installed. Otherwise it removes only the registered cache folders. Docker cleanup runs `docker builder prune --force`; it never prunes containers.
- Xcode Archives are not included because they can contain debugging symbols.
- All requested category IDs are checked before cleanup starts. An unknown ID stops the command without cleaning anything.

## What it cleans

These paths are grouped from `sweep list` in a fixture home. Android Studio's wildcard path is shown as the fixture match; `sweep list` expands it to matching folders on your Mac. Docker is tool-only and has no filesystem path to list.

| ID | Category | Paths |
|---|---|---|
| `xcode` | Xcode | `~/Library/Developer/Xcode/DerivedData`<br>`~/Library/Developer/Xcode/iOS DeviceSupport`<br>`~/Library/Developer/CoreSimulator/Caches` |
| `homebrew` | Homebrew | `~/Library/Caches/Homebrew` |
| `npm` | npm | `~/.npm/_cacache` |
| `pnpm` | pnpm | `~/Library/pnpm/store` |
| `yarn` | Yarn | `~/Library/Caches/Yarn` |
| `pip` | pip | `~/Library/Caches/pip` |
| `conda` | conda | `~/miniconda3/pkgs`<br>`~/anaconda3/pkgs`<br>`~/miniforge3/pkgs` |
| `gradle` | Gradle | `~/.gradle/caches` |
| `android` | Android Studio | `~/Library/Caches/Google/AndroidStudio-2025.1`<br>`~/.android/cache` |
| `cocoapods` | CocoaPods | `~/Library/Caches/CocoaPods` |
| `chrome` | Chrome | `~/Library/Caches/Google/Chrome` |
| `safari` | Safari | `~/Library/Caches/com.apple.Safari` |
| `firefox` | Firefox | `~/Library/Caches/Firefox` |
| `arc` | Arc | `~/Library/Caches/company.thebrowser.Browser` |
| `slack` | Slack | `~/Library/Application Support/Slack/Cache`<br>`~/Library/Application Support/Slack/Code Cache`<br>`~/Library/Application Support/Slack/Service Worker/CacheStorage` |
| `discord` | Discord | `~/Library/Application Support/discord/Cache`<br>`~/Library/Application Support/discord/Code Cache` |
| `spotify` | Spotify | `~/Library/Caches/com.spotify.client` |
| `vscode` | VS Code | `~/Library/Application Support/Code/Cache`<br>`~/Library/Application Support/Code/CachedData`<br>`~/Library/Application Support/Code/CachedExtensionVSIXs` |
| `teams` | Teams | `~/Library/Containers/com.microsoft.teams2/Data/Library/Caches` |
| `zoom` | Zoom | `~/Library/Caches/us.zoom.xos` |
| `library` | Other caches | `~/Library/Caches` (direct children not covered above or under Google) |

## Run tests

```sh
brew install bats-core shellcheck
shellcheck bin/sweep lib/*.sh
bats tests
```

## License

MIT. See [LICENSE](LICENSE).
