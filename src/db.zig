const std = @import("std");
const metadata = @import("metadata.zig");

const testing = std.testing;
const Allocator = std.mem.Allocator;
const Type = metadata.Type;
const Signal = metadata.Signal;
const Id = Signal.Id;
const Ref = Signal.Ref;

pub const Database = struct {
    /// General purpose allocator used for all internal allocations.
    gpa: Allocator,
    /// List of all signals (these structures don't own their backing.
    /// memory, and are relatively cheap).
    signals: std.ArrayListUnmanaged(Signal),
    /// Mappings from permanent Ids to ephemeral Refs.
    map: std.AutoHashMapUnmanaged(Id, Ref),

    pub fn init(gpa: Allocator) Database {
        return .{
            .gpa = gpa,
            .signals = .empty,
            .map = .empty,
        };
    }

    pub fn deinit(db: *Database) void {
        db.signals.deinit(db.gpa);
        db.map.deinit(db.gpa);
    }

    pub fn insert(db: *Database, signal: Signal) !void {
        try db.signals.ensureUnusedCapacity(db.gpa, 1);
        try db.map.ensureUnusedCapacity(db.gpa, 1);
        // No errors beyond this point.
        errdefer comptime unreachable;

        const len: u32 = @intCast(db.signals.items.len);
        const ref: Ref = @enumFromInt(len);
        db.signals.appendAssumeCapacity(signal);
        db.map.putAssumeCapacity(signal.id, ref);
    }

    pub fn get(db: *const Database, id: Id) ?Signal {
        const ref = db.map.get(id) orelse return null;
        const index = @intFromEnum(ref);
        std.debug.assert(index < db.signals.items.len);
        return db.signals.items[index];
    }
};

test "insert signal" {
    const gpa = std.testing.allocator;

    var db: Database = .init(gpa);
    defer db.deinit();

    // Test a round trip through the database.
    const signal: Signal = .{
        .id = @enumFromInt(100),
        .type = .{ .kind = .quaternary, .width = 8 },
        .shape = .array,
        .len = 2,
        .payload = .{
            .timestamps = &.{ 0, 10 },
            .x0s = &.{ 0x00, 0xaa },
            .x1s = &.{ 0xff, 0x00 },
        },
    };
    try db.insert(signal);
    const fetch = db.get(signal.id) orelse unreachable;
    try testing.expectEqualDeep(signal, fetch);
}
