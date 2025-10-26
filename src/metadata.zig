const std = @import("std");

const testing = std.testing;
const Allocator = std.mem.Allocator;

/// Records the type of a single signal in the database.
pub const Type = struct {
    kind: Kind,
    width: Width,

    pub const Kind = enum(u8) {
        /// Verilog compatible 4-state datatype storing 0, 1, x, z.
        quaternary,
    };

    pub const Width = u32;

    pub fn quaternary(width: Width) Type {
        std.debug.assert(width > 0);
        return .{ .kind = .quaternary, .width = width };
    }

    pub fn bytes(ty: Type) usize {
        return (ty.width + 7) / 8;
    }
};

/// Signals are the primitive data stored in the database. Operations on signals
/// go through `Signal.Id` opaque handles. This struct is currently used as the
/// backing store but will be removed eventually once file backed streaming queries
/// are implemented.
pub const Signal = struct {
    /// The public facing opaque handle for a signal, effectively
    /// serving as a primary key. It is user defined.
    id: Id,
    /// The structural type of this signal. This does not necessarily
    /// define the internal storage format.
    type: Type,
    /// The backing storage format for this signal.
    shape: Shape,
    /// The number of recorded samples for this signal. This is a constant
    /// since signals are immutable once created.
    len: u64,
    /// Payload data for this signal. The interpretation depends on the
    /// type and shape.
    payload: Payload,

    /// Ids are opaque 64 bit handles to a signal.
    pub const Id = enum(u64) { _ };

    // Refs are used internally to track handles to signals without holding
    // onto pointers. Unlike Ids, they are internally allocated and only
    // valid for the lifetime of the database instance, not the underlying data.
    pub const Ref = enum(u64) { _ };

    /// Timestamps are stored as opaque 64 bit integrals, where the unit delta
    /// represents the minimum granularity recorded by the application. The
    /// mapping to a unit quantity of real "time" is left to the application.
    pub const Timestamp = u64;

    /// The underlying storage format for a signal.
    pub const Shape = enum(u8) {
        /// Materialized array of timestamps and change values, stored
        /// flat as a columnar array (struct of arrays). Since signals
        /// are encoded as change values, this accomodates efficient
        /// constants (single sample) as well.
        array,
        /// Derived signal computed lazily via an expression evaluation.
        /// These are currently not materialized.
        derived,
    };

    pub const Payload = struct {
        timestamps: []const u64,
        x0s: []const u8,
        x1s: []const u8,
    };

    // TODO: This will be removed once we have central buffer management.
    pub fn deinit(self: *const Signal, gpa: Allocator) void {
        gpa.free(self.payload.timestamps);
        gpa.free(self.payload.x0s);
        gpa.free(self.payload.x1s);
    }
};

pub const Builder = struct {
    id: Id,
    type: Type,
    timestamps: std.ArrayListUnmanaged(Timestamp),
    x0s: std.ArrayListUnmanaged(u8),
    x1s: std.ArrayListUnmanaged(u8),

    const Id = Signal.Id;
    const Timestamp = Signal.Timestamp;

    /// Initialize a new signal builder state with a specified unique id
    /// and signal type.
    pub fn init(id: Id, ty: Type) Builder {
        return .{
            .id = id,
            .type = ty,
            .timestamps = .empty,
            .x0s = .empty,
            .x1s = .empty,
        };
    }

    /// Deallocates internal buffers and drops the builder state.
    /// Designed to clean up in the error path, but is safe to call
    /// after a successful build as well.
    pub fn deinit(builder: *Builder, gpa: Allocator) void {
        builder.timestamps.deinit(gpa);
        builder.x0s.deinit(gpa);
        builder.x1s.deinit(gpa);
    }

    /// Reserve capacity for at least `count` additional samples.
    pub fn ensureUnusedCapacity(builder: *Builder, gpa: Allocator, count: usize) !void {
        try builder.timestamps.ensureUnusedCapacity(gpa, count);
        const bytes_per_sample = builder.type.bytes();
        try builder.x0s.ensureUnusedCapacity(gpa, bytes_per_sample * count);
        try builder.x1s.ensureUnusedCapacity(gpa, bytes_per_sample * count);
    }

    pub fn appendSliceAssumeCapacity(builder: *Builder, timestamps: []const Timestamp, x0s: []const u8, x1s: []const u8) void {
        const count = timestamps.len;
        const bytes_per_sample = builder.type.bytes();
        std.debug.assert(x0s.len == count * bytes_per_sample);
        std.debug.assert(x1s.len == count * bytes_per_sample);

        builder.timestamps.appendSliceAssumeCapacity(timestamps);
        builder.x0s.appendSliceAssumeCapacity(x0s);
        builder.x1s.appendSliceAssumeCapacity(x1s);
    }

    pub fn appendAssumeCapacity(builder: *Builder, timestamp: Timestamp, x0: []const u8, x1: []const u8) void {
        const bytes_per_sample = builder.type.bytes();
        std.debug.assert(x0.len == bytes_per_sample);
        std.debug.assert(x1.len == bytes_per_sample);

        builder.appendSliceAssumeCapacity(&.{timestamp}, x0, x1);
    }

    pub fn append(builder: *Builder, gpa: Allocator, timestamp: Timestamp, x0: []const u8, x1: []const u8) !void {
        try builder.ensureUnusedCapacity(gpa, 1);
        // No errors beyond this point.
        errdefer comptime unreachable;

        builder.appendAssumeCapacity(timestamp, x0, x1);
    }

    pub fn build(builder: *Builder, gpa: Allocator) !Signal {
        // Sanity check lengths.
        const len = builder.timestamps.items.len;
        const bytes_per_sample = builder.type.bytes();
        std.debug.assert(builder.x0s.items.len == len * bytes_per_sample);
        std.debug.assert(builder.x1s.items.len == len * bytes_per_sample);

        const timestamps = try builder.timestamps.toOwnedSlice(gpa);
        const x0s = try builder.x0s.toOwnedSlice(gpa);
        const x1s = try builder.x1s.toOwnedSlice(gpa);

        // No errors beyond this point.
        errdefer comptime unreachable;

        return .{
            .id = builder.id,
            .type = builder.type,
            .shape = .array,
            .len = len,
            .payload = .{
                .timestamps = timestamps,
                .x0s = x0s,
                .x1s = x1s,
            },
        };
    }
};

test "type bytes" {
    try testing.expectEqual(1, Type.quaternary(1).bytes());
    try testing.expectEqual(1, Type.quaternary(2).bytes());
    try testing.expectEqual(1, Type.quaternary(7).bytes());
    try testing.expectEqual(1, Type.quaternary(8).bytes());
    try testing.expectEqual(2, Type.quaternary(16).bytes());
    try testing.expectEqual(4, Type.quaternary(31).bytes());
    try testing.expectEqual(8, Type.quaternary(64).bytes());
}

test "build signal" {
    const gpa = std.testing.allocator;

    const id: Signal.Id = @enumFromInt(100);
    const ty: Type = .{ .kind = .quaternary, .width = 8 };
    var builder: Builder = .init(id, ty);
    defer builder.deinit(gpa);

    // Insert a few samples into the builder.
    try builder.append(gpa, 0, &.{0xff}, &.{0xff});
    try builder.ensureUnusedCapacity(gpa, 2);
    builder.appendAssumeCapacity(5, &.{0x00}, &.{0xff});
    builder.appendAssumeCapacity(10, &.{0x00}, &.{0x8f});

    // Insert a slice of samples.
    try builder.ensureUnusedCapacity(gpa, 3);
    builder.appendSliceAssumeCapacity(&.{ 30, 50, 70 }, &.{ 0x6d, 0x99, 0x8f }, &.{ 0x00, 0x00, 0x00 });

    // Finalize the signal and verify contents.
    const signal = try builder.build(gpa);
    defer signal.deinit(gpa);
    try testing.expectEqual(id, signal.id);
    try testing.expectEqual(ty, signal.type);
    try testing.expectEqual(.array, signal.shape);

    const timestamps: []const u64 = &.{ 0, 5, 10, 30, 50, 70 };
    const x0s: []const u8 = &.{ 0xff, 0x00, 0x00, 0x6d, 0x99, 0x8f };
    const x1s: []const u8 = &.{ 0xff, 0xff, 0x8f, 0x00, 0x00, 0x00 };
    try testing.expectEqual(6, signal.len);
    try testing.expectEqualSlices(u64, timestamps, signal.payload.timestamps);
    try testing.expectEqualSlices(u8, x0s, signal.payload.x0s);
    try testing.expectEqualSlices(u8, x1s, signal.payload.x1s);
}

test "builder fail" {}
