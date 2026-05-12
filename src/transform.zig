//! Public surface of the transform engine.
//!
//! Re-exports the pipeline entry point and the `Level` enum. Rule
//! implementations live under `transform/rules/` and are wired together by
//! `pipeline.zig`.

const pipeline = @import("transform/pipeline.zig");

pub const Level = pipeline.Level;
pub const transform = pipeline.transform;

test {
    _ = pipeline;
}
