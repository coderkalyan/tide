const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Database = struct {
    /// General purpose allocator used for all internal
    /// allocations.
    gpa: Allocator,

    pub fn init(gpa: Allocator) Database {
        return .{
            .gpa = gpa,
        };
    }
};
