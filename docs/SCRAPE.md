# 🕷️ Jeeves Web Scraping Tool

**File:** `tools/scrape/scrape_tools.py`  
**Version:** 2.0  
**Depends on:** `scrapling` (parser only), `requests` (already in venv)  
**No browser / Playwright / camoufox required**

---

## Overview

The scrape tool gives Jeeves the ability to fetch and extract structured data from the web. It uses `requests` for HTTP and Scrapling's `Adaptor` class for HTML parsing — no headless browser, no Playwright, no extra RAM overhead on the Pi.

Jeeves can scrape a page, extract prices, query by CSS selector, or run a DuckDuckGo search — all from Discord, all processed locally.

---

## Commands

### `!scrape <url>`
Extract the main readable content from any webpage.

```
!scrape https://news.ycombinator.com
!scrape https://arstechnica.com/science/latest
```

Jeeves prioritizes semantic content containers (`article`, `main`, `[role='main']`) before falling back to paragraph extraction. Cookie banners, newsletter prompts, and nav noise are automatically filtered.

---

### `!scrape price <url>`
Extract pricing information from a product page.

```
!scrape price https://www.bhphotovideo.com/c/product/12345
!scrape price https://www.newegg.com/p/N82E16814126578
!scrape price https://www.microcenter.com/product/12345
```

Uses retailer-specific CSS selectors for B&H (`.your-price`, `.pricingArea`), Newegg (`.price-current`, `.pb-large`), and generic selectors (`[class*='price']`, `span[itemprop='price']`, etc.) with a regex fallback scan of the full page.

**Supported retailers:**
| Retailer | Works | Notes |
|----------|-------|-------|
| B&H Photo | ✅ | Retailer-specific selectors |
| Newegg | ✅ | Retailer-specific selectors |
| Micro Center | ✅ | Standard price selectors |
| Adorama | ✅ | Standard price selectors |
| Best Buy | ⚠️ | May require JS rendering |
| Walmart | ⚠️ | May require JS rendering |
| Amazon | ⛔ | Blocked — use `!scrape search` instead |

---

### `!scrape search <query>`
Search DuckDuckGo and return the top 5 organic results. Ads are automatically filtered out.

```
!scrape search RTX 5090 price today
!scrape search Raspberry Pi 5 NVMe SSD benchmark
!scrape search Python asyncio best practices 2025
```

Returns titles and snippets for the top organic results. Uses `quote_plus` encoding and tries 3 fallback selector variants if DDG changes its HTML structure.

---

### `!scrape css=<selector> <url>`
Extract elements matching a specific CSS selector from a page.

```
!scrape css=h2 https://news.ycombinator.com
!scrape css=.product-title https://www.bhphotovideo.com/c/search?Ntt=rtx+5090
!scrape css=span[itemprop='price'] https://somesite.com/product
```

Returns up to 15 matched elements with their text content.

---

## Natural Language Triggers

Jeeves also responds to natural language scraping requests without the `!scrape` prefix, as long as a URL is present:

| Phrase | Example |
|--------|---------|
| `check the price of X at <url>` | "check the price of the RTX 5090 at bhphotovideo.com/..." |
| `scrape <url>` | "scrape https://example.com" |
| `get the content from <url>` | "get the content from https://..." |
| `what does <url> say about X` | "what does arstechnica.com say about..." |
| `check this link <url>` | "check this link https://..." |
| `fetch <url>` | "fetch https://..." |
| `how much is X at <url>` | "how much is the 5090 at newegg.com/..." |

---

## Architecture

```
Discord command
      │
      ▼
assistant_tools.py → handle_tool()
      │
      ├── "!scrape" prefix match → handle_scrape_tool()
      │
      └── natural language + URL → is_scrape_query() → handle_scrape_tool()
                                           │
                                           ▼
                              ┌────────────────────────┐
                              │   scrape_tools.py v2   │
                              │                        │
                              │  1. Domain check       │
                              │     (blocked / tough)  │
                              │         │              │
                              │         ▼              │
                              │  2. _fetch()           │
                              │     requests.Session   │
                              │     + retry logic      │
                              │     + realistic headers│
                              │         │              │
                              │         ▼              │
                              │  3. Adaptor(html)      │
                              │     Scrapling parser   │
                              │         │              │
                              │         ▼              │
                              │  4. Extraction         │
                              │     content/price/css  │
                              │         │              │
                              │         ▼              │
                              │  5. _truncate(1800)    │
                              │     Discord safe       │
                              └────────────────────────┘
                                           │
                                           ▼
                              (True, response_string)
                                           │
                                           ▼
                                    Discord reply
```

---

## Fetching Strategy

The tool uses a tiered approach based on the target domain:

### Tier 1 — Blocked domains
Amazon, LinkedIn, Instagram, Twitter/X are returned immediately with a helpful error message. No network request is made.

### Tier 2 — Tough domains  
B&H, Best Buy, Walmart, Target, Newegg, Micro Center, Adorama, Costco get:
- Extra `Sec-Ch-Ua` browser fingerprint headers
- Random `User-Agent` rotation across 4 realistic agents
- Small random delay (0.5–1.2s) to avoid rate limiting
- Auto-retry with a different UA on 403

### Tier 3 — Standard domains
Everything else gets a clean `requests.Session` with:
- Retry policy: 3 attempts, 0.5s backoff, retries on 429/5xx
- Realistic `Accept`, `Accept-Language`, `Sec-Fetch-*` headers
- Google referer header to appear as organic traffic

---

## Installation

Scrapling must be installed into the **venv** the service uses, not the system Python:

```bash
# Install into the correct venv
/mnt/storage/pi-assistant/venv/bin/pip install scrapling

# Verify the parser works (all that's needed — no Playwright required)
/mnt/storage/pi-assistant/venv/bin/python3 -c "from scrapling.parser import Adaptor; print('OK')"

# Restart the service
sudo systemctl restart pi-assistant
```

**Do not** run `scrapling install` — that tries to install Playwright browsers which are not available on Pi ARM and are not needed by this tool.

---

## File Structure

```
tools/
└── scrape/
    ├── __init__.py          ← empty, required for Python package
    └── scrape_tools.py      ← all logic lives here
```

The tool registers itself in `assistant_tools.py` via a safe import:

```python
try:
    from tools.scrape.scrape_tools import handle_scrape_tool, is_scrape_query
    _SCRAPE_OK = True
except Exception:
    _SCRAPE_OK = False
```

If Scrapling is not installed or fails to import, the tool degrades gracefully — Jeeves continues running normally and returns a helpful install message if `!scrape` is invoked.

---

## Limitations

| Limitation | Reason | Workaround |
|-----------|--------|-----------|
| JavaScript-rendered pages | Requests fetches raw HTML only | Use `!scrape search <product>` to find data via DDG instead |
| Amazon | Aggressive bot detection | `!scrape search <product> amazon price` |
| Twitter/X, LinkedIn | Login walls + bot blocking | No workaround |
| Cloudflare-protected sites | JS challenge page returned | No workaround without Playwright |
| Pages > 1800 chars | Discord message limit | Response is truncated with char count shown |

---

## Adding to `!help`

Add `!scrape` to the help text in `assistant_tools.py`:

```python
_HELP_TEXT = (
    ...
    "**Browser:** !browse <url> • ... \n\n"
    "**Scrape:** !scrape <url> • price <url> • css=<sel> <url> • search <query>\n\n"
    ...
)
```

---

## Future Enhancements

- **`!scrape summarize <url>`** — fetch page then pipe content through the Pi's local model for a 3-sentence summary
- **Scheduled scraping** — integrate with the scheduler tool to monitor a price URL and notify Discord when it drops below a threshold: `!schedule scrape price <url> every 1 hour notify if < $500`
- **Camoufox support** — if Playwright ever becomes available on Pi ARM, swap `_fetch()` to use Scrapling's `StealthyFetcher` for Cloudflare bypass
- **Caching** — cache fetched pages for 5 minutes in BrainDB to avoid hammering the same URL

---

## Changelog

| Version | Changes |
|---------|---------|
| 1.0 | Initial release — basic fetch + Scrapling Adaptor |
| 1.1 | Fixed `get_text` → `::text` + `.getall()` Scrapling API |
| 2.0 | Tiered fetching, Session + retry, ad filtering, `quote_plus` search encoding, blocked domain detection, rotating user agents, retailer-specific price selectors, noise filtering in content extraction |
