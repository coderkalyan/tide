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
    timestamps: [max_timestamps]Timestamp,

    const page_size = 16 * 1024; //< 16 KiB pages
    const max_timestamps = page_size / @sizeOf(Timestamp);
};
