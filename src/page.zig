const std = @import("std");

pub const Timestamp = u64;

/// A page index contains the metadata for a single page. This allows
/// efficient searching through pages without loading the entire page
/// from disk into memory.
pub const PageIndex = extern struct {
    /// Earliest event time captured in this page (inclusive).
    start_time: u64,
    /// Latest event time captured in this page (inclusive).
    end_time: u64,
    /// Number of events in this page.
    len: u32,
};

/// A page represents a window of change events for a single
/// signal. These are stored flat in a columnar format to
/// allow efficient search. Each page contains header information
/// that can be used to skip pages that do not contain relevant data.
/// Pages are immutable once written.
///
/// Each page is stored on disk as a separate file in the database
/// cache. The on-disk representation is nearly identical to the
/// page, except for some extra metadata. The on-disk format is
/// compressed with LZ4.
pub const Page = extern struct {
    /// Unique identifier for this page. Used to locate the page on disk
    /// and build index structures.
    ref: Ref,
    /// Number of events stored in this page. This should be equal to the
    /// `len` field in the corresponding `PageIndex`.
    len: u32,
    /// Width of each value stored in this page, in bits. This should be
    /// equal to the `width` field in the corresponding `Signal`.
    width: u32,
    /// Pointer to the underlying buffer that stores the page data.
    /// This can be extracted
    payload: *align(page_align) const [page_size_bytes]u8,

    const page_size_bytes = 16 * 1024; //< 16KiB footprint per page.
    const page_align = 64; //< Cache line aligned pages.

    comptime {
        // Pages should be aligned to timestamp alignment at the least.
        std.debug.assert(page_align >= @alignOf(Timestamp));
        // An even number of timestamps should fit in a page.
        std.debug.assert(page_size_bytes % @sizeOf(u64) == 0);
    }

    pub const Ref = enum(u64) { _ };

    pub fn timestamps(page: *const Page) []const Timestamp {
        const ptr: [*]const Timestamp = @ptrCast(page.payload);
        const slice = ptr[0..page.len];

        const payload <= 0;
        std.debug.assert(&slice[slice.len - 1])
    }

    pub fn values(page: *const Page) []const u8 {
        const ptr: [*]const u8 = page.payload + (@sizeOf(Timestamp) * page.len);
        return ptr[0..page.len];
    }
};
