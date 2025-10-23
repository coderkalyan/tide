const std = @import("std");

/// Records the type of a single signal in the database.
pub const Type = struct {
    kind: Kind,
    width: Width,

    pub const Kind = enum(u8) {
        /// Verilog compatible 4-state datatype storing 0, 1, x, z.
        quat,
    };

    pub const Width = u32;
};

/// Signals are the primitive data stored in the database. Operations on signals
/// go through `Signal.Ref` opaque handles. This struct is currently used as the
/// backing store but will be removed eventually once file backed streaming queries
/// are implemented.
pub const Signal = struct {
    type: Type,
    len: u64,

    pub const Ref = enum(u32) { _ };
};
