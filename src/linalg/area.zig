//! area.zig — Area union type 및 AreaMulMatrix, AreaPointIn.
//! Odin의 `Area`, `AreaMulMatrix`, `__PolyMulMatrix`, `AreaPointIn` 대응.

const std = @import("std");
const linalg = @import("linalg.zig");
const Vec2 = linalg.Vec2;
const Vec2f32 = linalg.Vec2f32;
const Vec3f32 = linalg.Vec3f32;
const Vec4f32 = linalg.Vec4f32;
const Mat4x4f32 = linalg.Mat4x4f32;
const rect = @import("rect.zig");
const Rect = rect.Rect;
const Rectf32 = rect.Rectf32;
const checkRect = rect.checkRect;
const rectPointIn = rect.rectPointIn;
const polygon = @import("polygon.zig");
const pointInPolygon = polygon.pointInPolygon;

// ──────────────────────────────────────────────────────────────────────
//  Area(T) — tagged union
// ──────────────────────────────────────────────────────────────────────

pub fn Area(comptime T: type) type {
    return union(enum) {
        rect: Rect(T),
        poly: []Vec2(T),

        const Self = @This();
    };
}

pub const Areaf32 = Area(f32);
pub const Areaf64 = Area(f64);
pub const Areai32 = Area(i32);

// ──────────────────────────────────────────────────────────────────────
//  __PolyMulMatrix (private)
// ──────────────────────────────────────────────────────────────────────

fn __polyMulMatrix(_p: []const Vec2f32, _mat: Mat4x4f32, allocator: std.mem.Allocator) Areaf32 {
    const n = _p.len;
    const res = allocator.alloc(Vec2f32, n) catch @panic("OOM");
    for (0..n) |i| {
        const v = _p[i];
        const r = _mat.mulVec(Vec4f32{ v.x, v.y, 0.0, 1.0 });
        var rx = r[0];
        var ry = r[1];
        if (r[3] != 0) {
            rx /= r[3];
            ry /= r[3];
        }
        res[i] = Vec2f32{ .x = rx, .y = ry };
    }
    return Areaf32{ .poly = res };
}

// ──────────────────────────────────────────────────────────────────────
//  AreaMulMatrix
// ──────────────────────────────────────────────────────────────────────

pub fn areaMulMatrix(_a: Areaf32, _mat: Mat4x4f32, allocator: std.mem.Allocator) Areaf32 {
    switch (_a) {
        .rect => |n| {
            const res = rect.__rectMulMatrix(n, _mat);
            if (checkRect(f32, 4, res)) {
                const minX = @min(res[0][0], res[3][0]);
                const maxX = @max(res[0][0], res[3][0]);
                const minY = @min(res[0][1], res[3][1]);
                const maxY = @max(res[0][1], res[3][1]);
                return Areaf32{ .rect = Rectf32{ .left = minX, .right = maxX, .top = maxY, .bottom = minY } };
            }
            const res2 = allocator.alloc(Vec2f32, 4) catch @panic("OOM");
            res2[0] = Vec2f32{ .x = res[0][0], .y = res[0][1] };
            res2[1] = Vec2f32{ .x = res[1][0], .y = res[1][1] };
            res2[2] = Vec2f32{ .x = res[3][0], .y = res[3][1] };
            res2[3] = Vec2f32{ .x = res[2][0], .y = res[2][1] };
            return Areaf32{ .poly = res2 };
        },
        .poly => |n| {
            return __polyMulMatrix(n, _mat, allocator);
        },
    }
}

// ──────────────────────────────────────────────────────────────────────
//  AreaPointIn
// ──────────────────────────────────────────────────────────────────────

pub inline fn areaPointIn(comptime T: type, area: Area(T), pt: Vec2(T)) bool {
    switch (area) {
        .rect => |r| return rectPointIn(T, r, pt),
        .poly => |p| return pointInPolygon(T, pt, p) != .Outside,
    }
}

test "Area basic" {
    const testing = std.testing;
    try testing.expect(@typeInfo(Areaf32) == .@"union");
    try testing.expect(@typeInfo(Areaf64) == .@"union");
    try testing.expect(@typeInfo(Areai32) == .@"union");
}
