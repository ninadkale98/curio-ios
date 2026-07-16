from dataclasses import dataclass, field
from typing import Optional


@dataclass
class QueueItem:
    """The common shape every source module produces before handing off to db.upsert()."""

    source: str  # 'github' | 'arxiv' | 'hf' | 'rss' | 'blog' | 'hn' | 'youtube'
    source_key: str  # the source's own unique id — stable across re-crawls
    url: str
    title: str
    summary: Optional[str] = None
    raw_text: Optional[str] = None
    raw_json: dict = field(default_factory=dict)
    image_url: Optional[str] = None
    topic: Optional[str] = None
    published_at: Optional[str] = None  # ISO8601 string
