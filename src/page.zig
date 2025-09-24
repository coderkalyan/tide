const std = @import("std");

pub const Timestamp = u64;

/// A page index contains the metadata for a single page. This allows
/// efficient searching through pages without loading the entire page
/// from disk into memory.
pub const PageIndex = extern struct {
    /// Unique identifier for this page. Used to locate the page on disk
    /// and build index structures.
    ref: Ref,
    /// Earliest event time captured in this page (inclusive).
    start_time: u64,
    /// Latest event time captured in this page (inclusive).
    end_time: u64,

    pub const Ref = enum(u64) { _ };
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
pub fn Page(comptime Word: type) type {
    return struct {
        /// Unique identifier for this page. Used to locate the page on disk
        /// and build index structures.
        ref: PageIndex.Ref,
        /// Pointer to the underlying buffer that stores the page data.
        /// This is not allocated inline so all pages can instead be allocated
        /// out of a single large memory-mapped region. The page struct itself
        /// is extremely lightweight and can be passed around by value.
        payload: *align(page_align) const [page_size_bytes]u8,

        const element_count = 1024; //< 1024 elements per page.
        const page_align = 64; //< Cache line aligned pages.
        const page_size_bytes = element_count * (@sizeOf(Timestamp) + @sizeOf(Word));

        comptime {
            // Pages should be aligned to timestamp alignment at the least.
            std.debug.assert(page_align >= @alignOf(Timestamp));
            // An even number of timestamps should fit in a page.
            std.debug.assert(page_size_bytes % @sizeOf(u64) == 0);
        }

        pub fn timestamps(page: Page) *const [element_count]Timestamp {
            const ptr: [*]const Timestamp = @ptrCast(page.payload);
            return ptr[0..element_count];
        }

        pub fn values(page: Page) *const [element_count]Word {
            const ptr: [*]const u8 = page.payload + element_count * @sizeOf(Timestamp);
            return ptr[0..element_count];
        }
    };
}
