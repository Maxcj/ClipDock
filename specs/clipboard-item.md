# Clipboard Item

ClipDock stores clipboard records with platform-specific capture and shared behavior.

Required fields:

- `PayloadType`: physical clipboard format such as text, image, file, or HTML.
- `SemanticType`: interpreted meaning such as plain text, link, code, color, or unknown.
- `ContentHash`: lowercase SHA256 hash derived from stable snapshot content.
- `CreatedAt`: first time the item was stored.
- `LastUsedAt`: most recent capture or copy-back time.
- `UsageCount`: number of duplicate captures observed.
- `IsPinned`: user-controlled retention flag.

Core logic must not access platform clipboard APIs directly.
