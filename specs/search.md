# Search

Search returns recent clipboard items matching user text.

MVP behavior:

- Empty query returns recent items.
- Non-empty query searches text content.
- Pinned items sort before unpinned items.
- Newer `LastUsedAt` items sort before older items.
- Result count is capped to keep the UI responsive.
