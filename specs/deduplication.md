# Deduplication

If `PayloadType` and `ContentHash` are equal, the new clipboard snapshot is treated as a duplicate.

Duplicate handling:

- Update `LastUsedAt`.
- Increment `UsageCount`.
- Preserve `IsPinned`.
- Preserve user-assigned categories when categories are implemented.

The original clipboard content must not be used directly as `ContentHash`; all platforms use SHA256.
