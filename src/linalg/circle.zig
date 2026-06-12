//! circle.zig — Circle 타입.

const std = @import("std");
const linalg = @import("linalg.zig");
const Vec2 = linalg.Vec2;

// ──────────────────────────────────────────────────────────────────────
//  Circle(T)
// ──────────────────────────────────────────────────────────────────────

pub fn Circle(comptime T: type) type {
    return struct {
        p: Vec2(T),
        rectRadius: T,
    };
}

pub const Circlef32 = Circle(f32);
pub const Circlef64 = Circle(f64);
