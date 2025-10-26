//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const db = @import("db.zig");
const metadata = @import("metadata.zig");

comptime {
    _ = db;
    _ = metadata;
}
