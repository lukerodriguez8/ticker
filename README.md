# Ticker

A small macOS menu bar app that shows something new next to your clock throughout the day. Native Swift, no dependencies, and no account or API keys needed.

- Quotes
- Facts
- News
- Research
- On this day
- And more

## Features

- Thumbs up or down to tune what shows up
- Long lines scroll like a news ticker
- Click for the full text and a link to the source

## Install

You need macOS 13 or later and Apple's Command Line Tools. If you don't have them, running `xcode-select --install` in Terminal installs them.

```bash
git clone https://github.com/lukerodriguez8/ticker.git
cd ticker
./build.sh
```

This builds `Ticker.app` into `~/Applications` and starts it. The first time it runs, it sets itself to open at login. You can turn that off from its menu.

The build script also works around a known Command Line Tools bug ("redefinition of module 'SwiftBridging'"), if your Mac has it.

## Make it yours

- **Quotes and facts:** edit `Content.swift`.
- **News, AI, research and reading sources:** edit `Feeds.swift`. Any RSS or Atom feed works, and Substack sites use their free-post filter.
- **Wikiquote authors:** edit the list at the top of `Wikiquote.swift`.
- **Your own lines:** use **Add my own lines…** in the menu, one per line. To add a source, put it after a `|`.

Run `./build.sh` again after changing anything.

## Where things live

| What | Where |
|---|---|
| App | `~/Applications/Ticker.app` |
| Your lines, ratings, downloaded quotes | `~/Library/Application Support/Ticker/` |
| Open-at-login setting | `~/Library/LaunchAgents/local.ticker.plist` |

## Uninstall

Quit Ticker from its menu, then delete the three locations in the table above.

## License

MIT. See [LICENSE](LICENSE).
