//! triangle.zig — 삼각형 연산.
//! PointInTriangle (barycentric).

const std = @import("std");
const linalg = @import("linalg.zig");
const Vec2 = linalg.Vec2;

// ──────────────────────────────────────────────────────────────────────
//  PointInTriangle
// ──────────────────────────────────────────────────────────────────────

pub fn pointInTriangle(comptime T: type, p: Vec2(T), a: Vec2(T), b: Vec2(T), c: Vec2(T)) bool {
    const zero: T = 0;
    const x0 = c.x - a.x;
    const y0 = c.y - a.y;
    const x1 = b.x - a.x;
    const y1 = b.y - a.y;
    const x2 = p.x - a.x;
    const y2 = p.y - a.y;

    const dot00 = x0 * x0 + y0 * y0;
    const dot01 = x0 * x1 + y0 * y1;
    const dot02 = x0 * x2 + y0 * y2;
    const dot11 = x1 * x1 + y1 * y1;
    const dot12 = x1 * x2 + y1 * y2;
    const denominator = dot00 * dot11 - dot01 * dot01;
    if (denominator == zero) return false;

    const u = dot11 * dot02 - dot01 * dot12;
    const v = dot00 * dot12 - dot01 * dot02;

    if (denominator > zero) {
        return u > zero and v > zero and (u + v) < denominator;
    }
    return u < zero and v < zero and (u + v) > denominator;
}

test "PointInTriangle" {
    const testing = std.testing;
    const tri_a = Vec2(f32){ .x = 0, .y = 0 };
    const tri_b = Vec2(f32){ .x = 10, .y = 0 };
    const tri_c = Vec2(f32){ .x = 0, .y = 10 };

    try testing.expect(pointInTriangle(f32, Vec2(f32){ .x = 2, .y = 2 }, tri_a, tri_b, tri_c));
    try testing.expect(!pointInTriangle(f32, Vec2(f32){ .x = 20, .y = 20 }, tri_a, tri_b, tri_c));
    try testing.expect(!pointInTriangle(f32, Vec2(f32){ .x = -1, .y = -1 }, tri_a, tri_b, tri_c));
}
