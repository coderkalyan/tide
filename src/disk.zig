const std = @import("std");

pub const Page = struct {
    /// Header information for the page. This is stored uncompressed
    /// at the start of the page file on disk, and contains its own
    /// checksum.
    header: Header,

    pub const Header = struct {
        magic: [4]u8 = "tide",
        version: u8,
        algorithm: u8,
    };
};
