const std = @import("std");
const metadata = @import("metadata.zig");

const testing = std.testing;
const Allocator = std.mem.Allocator;
const Type = metadata.Type;
const Signal = metadata.Signal;
const Id = Signal.Id;
const Ref = Signal.Ref;
const Timestamp = Signal.Timestamp;

pub const Database = struct {
    /// General purpose allocator used for all internal allocations.
    gpa: Allocator,
    /// List of all signals (these structures don't own their backing.
    /// memory, and are relatively cheap).
    signals: std.ArrayListUnmanaged(Signal),
    /// Mappings from permanent Ids to ephemeral Refs.
    map: std.AutoHashMapUnmanaged(Id, Ref),

    pub const Query = struct {
        /// Id (primary key) of the signal being queried.
        id: Id,
        /// Type of signal.
        type: Type,
        /// Length of the queried range in samples.
        len: u64,
        /// FIXME: These slices are wasteful since the lengths can be derived from `len` and `type.`
        /// However this interface will be changed anyway to a streaming model.
        ///
        /// Slice of timestamps within [start, end).
        timestamps: []const Timestamp,
        /// Slice of x0 change samples within [start, end).
        x0s: []const u8,
        /// Slice of x1 change samples within [start, end).
        x1s: []const u8,
    };

    /// Initialize an empty database instance with a backing allocator.
    pub fn init(gpa: Allocator) Database {
        return .{
            .gpa = gpa,
            .signals = .empty,
            .map = .empty,
        };
    }

    /// Deinitialize the database instance, freeing all internal resources.
    pub fn deinit(db: *Database) void {
        db.signals.deinit(db.gpa);
        db.map.deinit(db.gpa);
    }

    /// Insert a new (immutable) signal into the database.
    pub fn insert(db: *Database, signal: Signal) !void {
        // Sanity check basic signal invariants. It is prohibitively expensive to
        // check all invariants, especially that timestamps are sorted and unique.
        if (signal.shape == .array) {
            const len = signal.len;
            const payload = signal.payload;
            const bytes_per_sample = signal.type.bytes();
            std.debug.assert(len > 0);
            std.debug.assert(payload.timestamps.len == len);
            std.debug.assert(payload.x0s.len == len * bytes_per_sample);
            std.debug.assert(payload.x1s.len == len * bytes_per_sample);
        }

        try db.signals.ensureUnusedCapacity(db.gpa, 1);
        try db.map.ensureUnusedCapacity(db.gpa, 1);
        // No errors beyond this point.
        errdefer comptime unreachable;

        const len: u32 = @intCast(db.signals.items.len);
        const ref: Ref = @enumFromInt(len);
        db.signals.appendAssumeCapacity(signal);
        db.map.putAssumeCapacity(signal.id, ref);
    }

    /// Query the database for a signal by Id, returning the change samples
    /// between [start, end) timestamps. Currently, these signals are views
    /// into the underlying signal memory and should not be freed by the caller.
    /// FIXME: switch to a streaming strategy.
    pub fn query(db: *const Database, id: Id, start: Timestamp, end: Timestamp) ?Query {
        std.debug.assert(start <= end);

        const ref = db.map.get(id) orelse return null;
        const index = @intFromEnum(ref);
        std.debug.assert(index < db.signals.items.len);
        const signal = db.signals.items[index];

        // Currently, derived signals are not supported.
        std.debug.assert(signal.shape == .array);

        // Calculate the exclusive range of samples to return.
        const timestamps = signal.payload.timestamps;
        const lo = upperBound(timestamps, start) - 1;
        const hi = upperBound(timestamps, end);
        const bytes_per_sample = signal.type.bytes();
        std.debug.assert(hi > lo);
        std.debug.assert(hi <= timestamps.len);

        return .{
            .id = signal.id,
            .type = signal.type,
            .len = hi - lo,
            .timestamps = timestamps[lo..hi],
            .x0s = signal.payload.x0s[lo * bytes_per_sample .. hi * bytes_per_sample],
            .x1s = signal.payload.x1s[lo * bytes_per_sample .. hi * bytes_per_sample],
        };
    }

    /// Find the index of the first timestamp in `timestamps` that is > `target`.
    /// Because timestamps are unique and sorted, this can employ binary search.
    /// Because timestamps are non-negative, this function will never return 0
    /// (assuming the timestamps slice is well-formed with a value at time 0).
    fn upperBound(timestamps: []const Timestamp, target: Timestamp) usize {
        std.debug.assert(timestamps.len > 0);

        var lo: usize = 0;
        var hi: usize = timestamps.len;
        while (hi > lo) {
            const mid = (lo + hi) / 2;
            if (!(target < timestamps[mid])) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }

        std.debug.assert(lo > 0);
        std.debug.assert(lo <= timestamps.len);
        std.debug.assert(lo == timestamps.len or timestamps[lo] > target);
        return lo;
    }
};

test "insert signal" {
    const gpa = std.testing.allocator;
    var db: Database = .init(gpa);
    defer db.deinit();

    // Test inserting a signal.
    // FIXME: Test a round trip through the database.
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
}

fn testQuery(query: Database.Query, id: Id, len: u64, timestamps: []const Timestamp, x0s: []const u8, x1s: []const u8) !void {
    const bytes_per_sample = query.type.bytes();
    std.debug.assert(timestamps.len == len);
    std.debug.assert(x0s.len == len * bytes_per_sample);
    std.debug.assert(x1s.len == len * bytes_per_sample);

    try testing.expectEqual(id, query.id);
    try testing.expectEqual(len, query.len);
    try testing.expectEqualSlices(Timestamp, timestamps, query.timestamps);
    try testing.expectEqualSlices(u8, x0s, query.x0s);
    try testing.expectEqualSlices(u8, x1s, query.x1s);
}

test "query signal" {
    const gpa = std.testing.allocator;
    var db: Database = .init(gpa);
    defer db.deinit();

    // Insert a signal into the database.
    const id: Id = @enumFromInt(100);
    const signal: Signal = .{
        .id = id,
        .type = .{ .kind = .quaternary, .width = 8 },
        .shape = .array,
        .len = 5,
        .payload = .{
            .timestamps = &.{ 0, 10, 30, 50, 70 },
            .x0s = &.{ 0xff, 0x8f, 0x6d, 0x99, 0x8f },
            .x1s = &.{ 0xff, 0x00, 0x00, 0x00, 0x00 },
        },
    };
    try db.insert(signal);

    // Entire range, tight bound.
    try testQuery(
        db.query(id, 0, 70) orelse unreachable,
        id,
        5,
        &.{ 0, 10, 30, 50, 70 },
        &.{ 0xff, 0x8f, 0x6d, 0x99, 0x8f },
        &.{ 0xff, 0x00, 0x00, 0x00, 0x00 },
    );
    // Entire range, loose bound.
    try testQuery(
        db.query(id, 0, 200) orelse unreachable,
        id,
        5,
        &.{ 0, 10, 30, 50, 70 },
        &.{ 0xff, 0x8f, 0x6d, 0x99, 0x8f },
        &.{ 0xff, 0x00, 0x00, 0x00, 0x00 },
    );

    // Time zero (exists).
    try testQuery(
        db.query(id, 0, 0) orelse unreachable,
        id,
        1,
        &.{0},
        &.{0xff},
        &.{0xff},
    );
    // Time 30 (exists).
    try testQuery(
        db.query(id, 30, 30) orelse unreachable,
        id,
        1,
        &.{30},
        &.{0x6d},
        &.{0x00},
    );
    // Time 40 (should round down to 30).
    try testQuery(
        db.query(id, 40, 40) orelse unreachable,
        id,
        1,
        &.{30},
        &.{0x6d},
        &.{0x00},
    );
    // Time 70 (last element).
    try testQuery(
        db.query(id, 70, 70) orelse unreachable,
        id,
        1,
        &.{70},
        &.{0x8f},
        &.{0x00},
    );
    // Time 80 (should round down to last element).
    try testQuery(
        db.query(id, 80, 80) orelse unreachable,
        id,
        1,
        &.{70},
        &.{0x8f},
        &.{0x00},
    );

    // Partial range (inclusive upper).
    try testQuery(
        db.query(id, 0, 50) orelse unreachable,
        id,
        4,
        &.{ 0, 10, 30, 50 },
        &.{ 0xff, 0x8f, 0x6d, 0x99 },
        &.{ 0xff, 0x00, 0x00, 0x00 },
    );
    // Partial range (exclusive upper).
    try testQuery(
        db.query(id, 0, 49) orelse unreachable,
        id,
        3,
        &.{ 0, 10, 30 },
        &.{ 0xff, 0x8f, 0x6d },
        &.{ 0xff, 0x00, 0x00 },
    );
    // Partial range (exclusive both).
    try testQuery(
        db.query(id, 20, 49) orelse unreachable,
        id,
        2,
        &.{ 10, 30 },
        &.{ 0x8f, 0x6d },
        &.{ 0x00, 0x00 },
    );
    // Partial range (only covers single element).
    try testQuery(
        db.query(id, 20, 25) orelse unreachable,
        id,
        1,
        &.{10},
        &.{0x8f},
        &.{0x00},
    );
    // Partial range (out of bounds, should round to last element).
    try testQuery(
        db.query(id, 80, 90) orelse unreachable,
        id,
        1,
        &.{70},
        &.{0x8f},
        &.{0x00},
    );
}
