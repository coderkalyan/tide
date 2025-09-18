const std = @import("std");

pub const StringPool = struct {
    /// Backing store for string interning.
    bytes: std.ArrayListUnmanaged(u8),
    /// Probing table for interning strings in the `bytes` backing store.
    string_table: std.HashMapUnmanaged(Ref, void, IndexContext, std.hash_map.default_max_load_percentage),

    pub const Ref = enum(u32) { _ };

    const IndexContext = struct {
        bytes: *std.ArrayListUnmanaged(u8),

        pub fn eql(_: IndexContext, a: Ref, b: Ref) bool {
            return a == b;
        }

        pub fn hash(self: IndexContext, index: Ref) u64 {
            const x: u32 = @intFromEnum(index);
            const str = std.mem.span(@as([*:0]const u8, @ptrCast(self.bytes.items.ptr)) + x);
            return std.hash_map.hashString(str);
        }
    };

    const SliceAdapter = struct {
        bytes: *std.ArrayListUnmanaged(u8),

        pub fn eql(self: SliceAdapter, a_str: []const u8, b: u32) bool {
            const b_str = std.mem.span(@as([*:0]const u8, @ptrCast(self.bytes.items.ptr)) + b);
            return std.mem.eql(u8, a_str, b_str);
        }

        pub fn hash(self: SliceAdapter, str: []const u8) u64 {
            _ = self;
            return std.hash_map.hashString(str);
        }
    };

    pub fn put(pool: *StringPool, str: []const u8) !Ref {
        const ref: Ref = @enumFromInt(@as(u32, @intCast(pool.bytes.items.len)));

        try pool.bytes.ensureUnusedCapacity(pool.gpa, str.len + 1);
        pool.bytes.appendSliceAssumeCapacity(str);
        pool.bytes.appendAssumeCapacity('\x00');

        const index_context: IndexContext = .{ .bytes = &pool.bytes };
        try pool.string_table.putContext(pool.gpa, ref, {}, index_context);

        return ref;
    }

    pub fn get(pool: *const StringPool, ref: Ref) []const u8 {
        const offset: u32 = @intFromEnum(ref);
        return std.mem.span(@as([*:0]const u8, @ptrCast(pool.bytes.items.ptr)) + offset);
    }
};

pub const Signal = struct {
    /// Interned name of the signal, not including parent scope names. To resolve the name
    /// as a string, call the `name` function and pass the string pool.
    name_ref: StringPool.Ref,
    /// Width of the signal, in bits.
    width: u32,

    pub const Ref = enum(u32) { _ };

    pub fn name(self: *const Signal, pool: *const StringPool) []const u8 {
        return pool.get(self.name_ref);
    }
};

pub const Scope = struct {
    /// Interned name of the scope, not including parent scope names. To resolve the name
    /// as a string, call the `name` function and pass the string pool.
    name_ref: StringPool.Ref,
    /// Scope kind (signal, module, function, etc).
    tag: Tag,
    /// Tag specific payload. Examples include child scopes or signal data.
    payload: Payload,

    pub const Tag = enum(u8) {
        variable,
        verilog_begin,
        verilog_fork,
        verilog_function,
        verilog_module,
        verilog_task,
    };

    pub const Payload = union {
        /// Reference to an array of child scopes.
        child_refs: ChildRefs,
        /// Reference to the signal underlying a variable.
        variable: Signal.Ref,

        pub const ChildRefs = struct {
            /// Index into Hierarchy.children where the child refs
            /// for this scope start.
            start: u32,
            /// Index into Hierarchy.children where the child refs
            /// for this scope end (exclusive).
            end: u32,
        };
    };

    pub const Ref = enum(u32) { _ };

    pub fn name(self: *const Signal, pool: *const StringPool) []const u8 {
        return pool.get(self.name_ref);
    }
};

pub const Hierarchy = struct {
    /// Flat list of nodes in the hierarchy. The hierarchy forms a tree
    /// where leaf nodes are variables and internal nodes are nested scopes.
    scopes: []const Scope,
    /// List of edges in the hierarchy tree.
    children: []const Scope.Ref,
};
