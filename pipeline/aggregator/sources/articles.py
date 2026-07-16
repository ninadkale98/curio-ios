"""
Articles source — curated blog/newsletter/lab posts, two shapes:

  1. RSS/Atom feeds (feedparser) — ~22 hand-picked high-signal sources.
  2. Framer-index blogs — sites exposing a JSON search index (Perplexity Research).

Unlike GitHub (stars) or papers (upvotes/citations), articles carry NO
engagement signal — a feed doesn't tell you how good a post is. So the quality
signal here is the SOURCE itself: we only track authoritative feeds, and rank
by source + recency. Curation lives in the source list below.

Metadata-only like the other channels: we take images the feed gives for free
but never fetch article pages here — the writer wing reads the full article and
sources a hero image at write time.

Dedup key is the article URL (source_key=url); RSS rows use source='rss',
Framer rows use source='blog'.
"""

import logging
import re
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

import feedparser
import requests

from ..queue_item import QueueItem

log = logging.getLogger(__name__)

HEADERS = {"User-Agent": "Curio-Bot/1.0 (content discovery)"}

# High-signal set (podcasts / Medium / weak roundups dropped).
RSS_SOURCES = [
    # First-party AI labs / infra
    {"id": "huggingface", "name": "Hugging Face Blog", "feed": "https://huggingface.co/blog/feed.xml", "category": "ai-research"},
    {"id": "deepmind", "name": "Google DeepMind", "feed": "https://deepmind.google/blog/rss.xml", "category": "ai-research"},
    {"id": "google-research", "name": "Google Research", "feed": "https://research.google/blog/rss/", "category": "ai-research"},
    {"id": "openai", "name": "OpenAI", "feed": "https://openai.com/news/rss.xml", "category": "ai-research"},
    {"id": "meta-engineering", "name": "Meta Engineering", "feed": "https://engineering.fb.com/feed/", "category": "ai-research"},
    {"id": "nvidia-ai", "name": "NVIDIA AI Blog", "feed": "https://blogs.nvidia.com/feed/", "category": "ai-research"},
    {"id": "together-ai", "name": "Together AI", "feed": "https://www.together.ai/blog/rss.xml", "category": "ai-research"},
    {"id": "aws-ml", "name": "AWS Machine Learning", "feed": "https://aws.amazon.com/blogs/machine-learning/feed/", "category": "cloud-ml"},
    {"id": "tensorflow", "name": "TensorFlow Blog", "feed": "https://blog.tensorflow.org/feeds/posts/default", "category": "frameworks"},
    {"id": "vllm", "name": "vLLM Blog", "feed": "https://vllm.ai/blog/rss.xml", "category": "inference"},
    # Academic labs
    {"id": "bair", "name": "BAIR Blog (Berkeley AI)", "feed": "https://bair.berkeley.edu/blog/feed.xml", "category": "academic"},
    {"id": "stanford-ai", "name": "Stanford AI Lab", "feed": "https://ai.stanford.edu/blog/feed.xml", "category": "academic"},
    # Individual top researchers
    {"id": "lilian-weng", "name": "Lilian Weng", "feed": "https://lilianweng.github.io/index.xml", "category": "researcher"},
    {"id": "jay-alammar", "name": "Jay Alammar", "feed": "https://jalammar.github.io/feed.xml", "category": "researcher"},
    {"id": "karpathy", "name": "Andrej Karpathy", "feed": "https://karpathy.github.io/feed.xml", "category": "researcher"},
    {"id": "sebastian-raschka", "name": "Sebastian Raschka", "feed": "https://sebastianraschka.com/rss_feed.xml", "category": "researcher"},
    # Strong newsletters
    {"id": "interconnects", "name": "Interconnects (Nathan Lambert)", "feed": "https://www.interconnects.ai/feed", "category": "newsletter"},
    {"id": "import-ai", "name": "Import AI (Jack Clark)", "feed": "https://importai.substack.com/feed", "category": "newsletter"},
    {"id": "the-gradient", "name": "The Gradient", "feed": "https://thegradientpub.substack.com/feed", "category": "newsletter"},
    {"id": "sebastian-ruder", "name": "Sebastian Ruder (NLP News)", "feed": "https://newsletter.ruder.io/feed", "category": "newsletter"},
    {"id": "algorithmic-bridge", "name": "The Algorithmic Bridge", "feed": "https://thealgorithmicbridge.substack.com/feed", "category": "newsletter"},
    {"id": "pragmatic-engineer", "name": "The Pragmatic Engineer", "feed": "https://newsletter.pragmaticengineer.com/feed", "category": "newsletter"},
]

BLOG_SOURCES = [
    {"id": "perplexity-research", "name": "Perplexity Research", "base_url": "https://research.perplexity.ai", "article_prefix": "/articles/"},
]
SKIP_SLUGS = {"/", "/articles", "/404", "/blog", "/index"}


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def _clean_html(text: str) -> str:
    text = re.sub(r"<[^>]+>", " ", text or "")
    text = re.sub(r"&#?\w+;", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def _iso(dt: datetime | None) -> str | None:
    return dt.isoformat() if dt else None


# ---------------------------------------------------------------------------
# RSS / Atom
# ---------------------------------------------------------------------------

def _entry_date(entry) -> datetime | None:
    for key in ("published_parsed", "updated_parsed"):
        t = entry.get(key)
        if t:
            try:
                return datetime(*t[:6], tzinfo=timezone.utc)
            except (TypeError, ValueError):
                pass
    if entry.get("published"):
        try:
            return parsedate_to_datetime(entry.published)
        except (TypeError, ValueError):
            pass
    return None


def _entry_image(entry) -> str | None:
    """An image the feed gives for free — no page fetch."""
    for media in entry.get("media_thumbnail", []) or entry.get("media_content", []):
        if media.get("url"):
            return media["url"]
    for link in entry.get("links", []):
        if link.get("rel") == "enclosure" and (link.get("type") or "").startswith("image"):
            return link.get("href")
    for content in entry.get("content", []):
        m = re.search(r'<img[^>]+src=["\']([^"\']+)["\']', content.get("value", ""))
        if m:
            return m.group(1)
    return None


def fetch_feed(source: dict) -> list[dict]:
    parsed = feedparser.parse(source["feed"], request_headers=HEADERS)
    if parsed.bozo and not parsed.entries:
        log.warning(f"  bad feed {source['id']}: {parsed.get('bozo_exception')}")
        return []

    posts = []
    for entry in parsed.entries:
        url = (entry.get("link") or "").strip()
        if not url:
            continue
        desc = entry.get("summary") or (entry.get("content") or [{}])[0].get("value", "")
        posts.append({
            "url": url,
            "title": _clean_html(entry.get("title", "")),
            "summary": (_clean_html(desc)[:400] or None),
            "author": (entry.get("author") or "").strip() or None,
            "image": _entry_image(entry),
            "published_at": _entry_date(entry),
        })
    return posts


def _rss_to_queue_item(source: dict, p: dict) -> QueueItem:
    return QueueItem(
        source="rss",
        source_key=p["url"],
        url=p["url"],
        title=p["title"],
        summary=p["summary"],
        raw_text=None,  # writer fetches the full article
        raw_json={
            "discovered_via": "rss",
            "source_id": source["id"],
            "source_name": source["name"],
            "author": p["author"],
            "category": source["category"],
        },
        image_url=p["image"],
        topic=source["category"],
        published_at=_iso(p["published_at"]),
    )


def iter_rss(backfill, existing_keys, existing_story_urls=frozenset(), done_topics=frozenset()):
    # backfill has no effect — RSS feeds only expose their current window; the
    # archive builds up over time as the cron runs.
    seen: set[str] = set()
    for source in RSS_SOURCES:
        if source["id"] in done_topics:
            continue
        items = []
        for p in fetch_feed(source):
            url = p["url"]
            if url in existing_keys or url in seen or url in existing_story_urls or not p["title"]:
                continue
            seen.add(url)
            items.append(_rss_to_queue_item(source, p))
        yield source["id"], items
        time.sleep(0.5)


# ---------------------------------------------------------------------------
# Framer-index blogs
# ---------------------------------------------------------------------------

_DATE_RE = re.compile(r"^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},\s+\d{4}$")
_KNOWN_CATEGORIES = {"systems", "search", "research", "agents", "models", "security", "infrastructure", "ml", "nlp"}


def _get(url: str):
    try:
        r = requests.get(url, headers=HEADERS, timeout=15)
        return r if r.status_code == 200 else None
    except requests.RequestException as e:
        log.warning(f"  GET {url} failed: {e}")
        return None


def _search_index(base_url: str) -> dict | None:
    r = _get(base_url)
    if not r:
        return None
    m = re.search(r'framer-search-index["\s]+content="([^"]+)"', r.text)
    if not m:
        log.warning(f"  no framer-search-index at {base_url}")
        return None
    idx = _get(m.group(1))
    return idx.json() if idx else None


def _is_real_article(slug: str, source: dict) -> bool:
    if slug in SKIP_SLUGS:
        return False
    prefix = source.get("article_prefix", "/articles/")
    return slug.startswith(prefix) and len(slug) > len(prefix)


def _parse_blog(source: dict, slug: str, raw: dict) -> dict:
    date_str, category, summary_lines = None, None, []
    for para in raw.get("p", []):
        para = para.strip()
        if not para:
            continue
        if _DATE_RE.match(para):
            date_str = para
            continue
        if para.lower() in _KNOWN_CATEGORIES:
            category = para.lower()
            continue
        if "perplexity research advances our mission" in para.lower() or "we're hiring" in para.lower():
            continue
        summary_lines.append(para)
        if len(summary_lines) >= 3:
            break

    published_at = None
    if date_str:
        try:
            published_at = datetime.strptime(date_str, "%b %d, %Y").replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    desc = raw.get("description") or None
    if desc and "perplexity research advances our mission" in desc.lower():
        desc = None
    return {
        "url": source["base_url"] + slug,
        "title": raw.get("title", ""),
        "summary": (" ".join(summary_lines)[:600] or desc),
        "category": category,
        "published_at": published_at,
    }


def _blog_to_queue_item(source: dict, p: dict) -> QueueItem:
    return QueueItem(
        source="blog",
        source_key=p["url"],
        url=p["url"],
        title=p["title"],
        summary=p["summary"],
        raw_text=None,
        raw_json={
            "discovered_via": "blog",
            "source_id": source["id"],
            "source_name": source["name"],
            "category": p["category"],
        },
        image_url=None,  # Framer index has no image; writer sources it
        topic=p["category"] or "blog",
        published_at=_iso(p["published_at"]),
    )


def iter_blog(backfill, existing_keys, existing_story_urls=frozenset(), done_topics=frozenset()):
    seen: set[str] = set()
    for source in BLOG_SOURCES:
        if source["id"] in done_topics:
            continue
        index = _search_index(source["base_url"])
        items = []
        for slug, raw in (index or {}).items():
            if not _is_real_article(slug, source):
                continue
            p = _parse_blog(source, slug, raw)
            url = p["url"]
            if url in existing_keys or url in seen or url in existing_story_urls or not p["title"]:
                continue
            seen.add(url)
            items.append(_blog_to_queue_item(source, p))
        yield source["id"], items
