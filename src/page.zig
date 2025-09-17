const std = @import("std");

pub const Page = extern struct {
    header: Header,
    // timestamps_ptr:

    pub const Header = extern struct {
        /// Earliest event time captured in this page (inclusive).
        start_time: u64,
        /// Latest event time captured in this page (inclusive).
        end_time: u64,
        /// Number of events in this page.
        len: u32,
    };
};
