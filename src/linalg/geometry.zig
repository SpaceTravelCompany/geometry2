//! geometry.zig — Odin shared/geometry/geometry.odin 1:1 포팅.
//! ShapeNode, Shapes, IsHoleContour, ReverseShapeCloseCurve 등.
//! clipper는 future plan이므로 __ClipperError stub enum만 포함.

const std = @import("std");
const linalg = @import("linalg.zig");
const Vec2 = linalg.Vec2;
const Vec2f32 = linalg.Vec2f32;
const Vec4f32 = linalg.Vec4f32;
const vec2Sub = linalg.vec2Sub;
const vec2Length2 = linalg.vec2Length2;
const rect = @import("rect.zig");
const Rectf32 = rect.Rectf32;
const polygon = @import("polygon.zig");
const pointInPolygon = polygon.pointInPolygon;
const polygonSignedArea = polygon.polygonSignedArea;
const getPolygonOrientation = polygon.getPolygonOrientation;
const lines = @import("lines.zig");
const linesIntersect2 = lines.linesIntersect2;
const linesIntersect3 = lines.linesIntersect3;
const pointLineLeftOrRight = lines.pointLineLeftOrRight;
const subdivQuadraticBezier = lines.subdivQuadraticBezier;
const subdivCubicBezier = lines.subdivCubicBezier;
const triangle = @import("triangle.zig");
const pointInTriangle = triangle.pointInTriangle;
const triangulation = @import("triangulation.zig");
const TrianguateError = triangulation.TrianguateError;
const clipper = @import("clipper.zig");

// ══════════════════════════════════════════════════════════════════════════════
//  Types
// ══════════════════════════════════════════════════════════════════════════════

pub const ShapeVertexFlag = enum(u8) {
    LINE,
    CUBIC,
    QUAD,
};

/// #align(16) — pos(8) + uvw(16) + color(16) = 40 bytes, but align 16.
pub const ShapeVertex2d = struct {
    pos: Vec2f32,
    uvw: Vec4f32,
    color: Vec4f32,
};

pub const RawShape = struct {
    vertices: []ShapeVertex2d,
    indices: []u32,
    rect: Rectf32,
};

pub const CurveType = enum(u8) {
    Line,
    Unknown,
    Serpentine,
    Loop,
    // LoopReverse,
    Cusp,
    Quadratic,
};

/// clipper error set — clipper.ClipperError를 그대로 노출 (별칭).
pub const __ClipperError = clipper.ClipperError;

/// __ShapeError — geometry 자체 오류.
pub const __ShapeError = error{
    IsPointNotLine,
    EmptyPolygon,
    EmptyColor,
    Length_Mismatch,
    Empty_Input,
    First_Point_Is_Curve,
    Consecutive_Anchor_Missing_Control,
    Too_Many_Consecutive_Curves,
    OverFlow,
};

/// ShapeError — 모든 하위 오류를 포함.
pub const ShapeError = __ShapeError || TrianguateError || __ClipperError || std.mem.Allocator.Error;

pub const ShapeNode = struct {
    pts: [][]Vec2f32,
    isCurves: [][]bool,
    color: Vec4f32,
    strokeColor: Vec4f32,
    thickness: f32,
    isClosed: bool,
    clipRect: Rectf32,
};

pub const Shapes = struct {
    nodes: []const ShapeNode,
    clipRect: Rectf32,
};

/// ReverseShapeCloseCurve 반환 타입.
pub const ReverseShapeCloseCurveResult = struct {
    pts: []Vec2f32,
    isCurves: []bool,
};

// ══════════════════════════════════════════════════════════════════════════════
//  FindParentContour (private)
// ══════════════════════════════════════════════════════════════════════════════

/// idx번째 contour를 포함하는 가장 작은 면적의 parent contour를 찾는다.
/// parent가 없으면 -1을 반환한다.
fn findParentContour(idx: usize, ptsIn: []const []const Vec2f32) isize {
    if (idx >= ptsIn.len) return -1;
    if (ptsIn[idx].len < 3) return -1;

    const p = ptsIn[idx][0];

    var parentIdx: isize = -1;
    var parentArea: f32 = 0;

    for (ptsIn, 0..) |other, j| {
        if (j == idx) continue;
        if (other.len < 3) continue;

        if (pointInPolygon(f32, p, other) == .Outside) continue;

        const area = @abs(polygonSignedArea(other));

        if (parentIdx == -1 or area < parentArea) {
            parentIdx = @intCast(j);
            parentArea = area;
        }
    }

    return parentIdx;
}

// ══════════════════════════════════════════════════════════════════════════════
//  IsHoleContour
// ══════════════════════════════════════════════════════════════════════════════

/// idx번째 contour가 hole(구멍)인지 여부를 반환한다.
/// FindParentContour로 parent를 찾고, parent가 outer면 hole, parent가 hole이면 outer.
pub fn isHoleContour(idx: usize, ptsIn: []const []const Vec2f32) bool {
    if (idx >= ptsIn.len) return false;
    if (ptsIn[idx].len < 3) return false;

    const parent = findParentContour(idx, ptsIn);
    if (parent == -1) return false;

    return !isHoleContour(@intCast(parent), ptsIn);
}

// ══════════════════════════════════════════════════════════════════════════════
//  ReverseShapeCloseCurve
// ══════════════════════════════════════════════════════════════════════════════

/// 닫힌 contour의 정점/커브 플래그를 reverse(역순)로 재배열한다.
/// geometry.shapesComputePolygon이 anchor-first를 요구하므로 사용.
///
/// algo:
///   anchor(비-커브) 사이의 control point 개수를 검사한 뒤,
///   reverse된 순서로 세그먼트를 재배치한다.
pub fn reverseShapeCloseCurve(
    pts: []const Vec2f32,
    isCurves: []const bool,
    allocator: std.mem.Allocator,
) ShapeError!ReverseShapeCloseCurveResult {
    // overflow check (64-bit only — int > max(u32) 인 경우)
    if (@sizeOf(usize) > 4) {
        if (pts.len > std.math.maxInt(u32) or isCurves.len > std.math.maxInt(u32)) {
            return error.OverFlow;
        }
    }

    const n: u32 = @intCast(pts.len);

    if (n != @as(u32, @intCast(isCurves.len))) return error.Length_Mismatch;
    if (n == 0) return error.Empty_Input;
    if (isCurves[0]) return error.First_Point_Is_Curve;

    // anchor(비-커브) 인덱스 수집
    var anchorIndices: std.array_list.Aligned(u32, null) = .empty;
    defer anchorIndices.deinit(allocator);
    for (0..n) |i| {
        if (!isCurves[i]) {
            try anchorIndices.append(allocator, @intCast(i));
        }
    }

    if (anchorIndices.items.len == 0) return error.First_Point_Is_Curve;

    const m = anchorIndices.items.len;

    // 각 anchor 사이 control 개수 검사
    for (0..m) |a| {
        const start = anchorIndices.items[a];
        const next = anchorIndices.items[(a + 1) % m];

        var curveCount: u32 = 0;
        var i: u32 = (start +% 1) % n;
        while (i != next) {
            if (!isCurves[i]) return error.Consecutive_Anchor_Missing_Control;
            curveCount += 1;
            i = (i +% 1) % n;
        }
        if (curveCount == 0) return error.Consecutive_Anchor_Missing_Control;
        if (curveCount > 2) return error.Too_Many_Consecutive_Curves;
    }

    // 출력 버퍼 할당
    var outPts = try allocator.alloc(Vec2f32, n);
    var outCurves = try allocator.alloc(bool, n);
    errdefer allocator.free(outPts);
    errdefer allocator.free(outCurves);

    outPts[0] = pts[0];
    outCurves[0] = false;
    var outI: u32 = 1;

    // reverse된 순서대로 세그먼트 처리
    for (0..m) |step| {
        const endAnchorPos = (m - step) % m;
        const startAnchorPos = (endAnchorPos + m - 1) % m;

        const a0 = anchorIndices.items[startAnchorPos];
        const a1 = anchorIndices.items[endAnchorPos];

        var controls: [2]u32 = undefined;
        var curveCount: u32 = 0;

        var i: u32 = (a0 +% 1) % n;
        while (i != a1) {
            controls[curveCount] = i;
            curveCount += 1;
            i = (i +% 1) % n;
        }

        switch (curveCount) {
            1 => {
                outPts[outI] = pts[controls[0]];
                outCurves[outI] = true;
                outI += 1;
            },
            2 => {
                outPts[outI] = pts[controls[1]];
                outCurves[outI] = true;
                outI += 1;

                outPts[outI] = pts[controls[0]];
                outCurves[outI] = true;
                outI += 1;
            },
            else => return error.Too_Many_Consecutive_Curves,
        }

        // 마지막 세그먼트는 first anchor로 닫히므로 anchor 0은 다시 쓰지 않음
        if (a0 != 0) {
            outPts[outI] = pts[a0];
            outCurves[outI] = false;
            outI += 1;
        }
    }

    if (outI != n) return error.EmptyPolygon;

    return ReverseShapeCloseCurveResult{
        .pts = outPts,
        .isCurves = outCurves,
    };
}

// ══════════════════════════════════════════════════════════════════════════════
//  CurveStructFloat — GetCubicCurveType/SubdivCurve 등에 사용
// ══════════════════════════════════════════════════════════════════════════════

/// CurveStructFloat — 부동소수점 좌표용 커브 구조체 (CurveStructFixed와 동일 레이아웃).
pub fn CurveStructFloat(comptime F: type) type {
    return struct {
        start: Vec2(F),
        ctl0: Vec2(F),
        ctl1: Vec2(F),
        end: Vec2(F),
        type: CurveType,
        curveReverse: bool,
    };
}

// ══════════════════════════════════════════════════════════════════════════════
//  Internal array helpers (Odin utils_private 대응)
// ══════════════════════════════════════════════════════════════════════════════

/// Odin non_zero_resize_dynamic_array 대응. list의 길이를 n으로 설정한다 (zero-initialize 없음).
fn resizeNonZero(
    comptime T: type,
    list: *std.array_list.Aligned(T, null),
    n: usize,
    allocator: std.mem.Allocator,
) !void {
    try list.ensureTotalCapacity(allocator, n);
    list.items.len = n;
}

/// Odin non_zero_resize_fixed_capacity_dynamic_array 대응. 길이를 0으로 설정한다.
fn clearRetaining(comptime T: type, list: *std.array_list.Aligned(T, null)) void {
    list.clearRetainingCapacity();
}

// ══════════════════════════════════════════════════════════════════════════════
//  rawShapeFree
// ══════════════════════════════════════════════════════════════════════════════

/// RawShape의 vertices/indices 메모리를 해제한다.
pub fn rawShapeFree(self: *RawShape, allocator: std.mem.Allocator) void {
    allocator.free(self.vertices);
    allocator.free(self.indices);
    self.vertices = &.{};
    self.indices = &.{};
}

// ══════════════════════════════════════════════════════════════════════════════
//  rawShapeComputeRect
// ══════════════════════════════════════════════════════════════════════════════

/// RawShape의 모든 vertex를 순회하여 bounding rect를 계산한다.
pub fn rawShapeComputeRect(self: RawShape) Rectf32 {
    if (self.vertices.len == 0) return Rectf32{ .left = 0, .right = 0, .top = 0, .bottom = 0 };
    var left = self.vertices[0].pos.x;
    var right = self.vertices[0].pos.x;
    var bottom = self.vertices[0].pos.y;
    var top = self.vertices[0].pos.y;
    for (self.vertices[1..]) |v| {
        left = @min(left, v.pos.x);
        right = @max(right, v.pos.x);
        bottom = @min(bottom, v.pos.y);
        top = @max(top, v.pos.y);
    }
    return Rectf32{ .left = left, .right = right, .top = top, .bottom = bottom };
}

// ══════════════════════════════════════════════════════════════════════════════
//  rawShapeUpdateRect
// ══════════════════════════════════════════════════════════════════════════════

/// RawShape의 rect 필드를 다시 계산하여 갱신한다.
pub fn rawShapeUpdateRect(self: *RawShape) void {
    self.rect = rawShapeComputeRect(self.*);
}

// ══════════════════════════════════════════════════════════════════════════════
//  rawShapeClone
// ══════════════════════════════════════════════════════════════════════════════

/// RawShape를 deep clone한다.
pub fn rawShapeClone(self: *const RawShape, allocator: std.mem.Allocator) (std.mem.Allocator.Error)!*RawShape {
    const res = try allocator.create(RawShape);
    errdefer allocator.destroy(res);

    res.vertices = try allocator.alloc(ShapeVertex2d, self.vertices.len);
    errdefer allocator.free(res.vertices);

    res.indices = try allocator.alloc(u32, self.indices.len);

    @memcpy(res.vertices, self.vertices);
    @memcpy(res.indices, self.indices);
    res.rect = self.rect;

    return res;
}

// ══════════════════════════════════════════════════════════════════════════════
//  getCubicCurveType
// ══════════════════════════════════════════════════════════════════════════════

/// cubic 베지어 곡선의 종류(Serpentine/Loop/Cusp/Quadratic/Line)를 판정한다.
/// Odin geometry.GetCubicCurveType 1:1.
pub fn getCubicCurveType(comptime T: type, start: Vec2(T), control0: Vec2(T), control1: Vec2(T), end: Vec2(T)) ShapeError!struct { curveType: CurveType, d0: T, d1: T, d2: T } {
    if (start.x == control0.x and start.y == control0.y and
        control0.x == control1.x and control0.y == control1.y and
        control1.x == end.x and control1.y == end.y)
    {
        return error.IsPointNotLine;
    }

    const sx: f64 = @as(f64, @floatCast(start.x));
    const sy: f64 = @as(f64, @floatCast(start.y));
    const c0x: f64 = @as(f64, @floatCast(control0.x));
    const c0y: f64 = @as(f64, @floatCast(control0.y));
    const c1x: f64 = @as(f64, @floatCast(control1.x));
    const c1y: f64 = @as(f64, @floatCast(control1.y));
    const ex: f64 = @as(f64, @floatCast(end.x));
    const ey: f64 = @as(f64, @floatCast(end.y));

    const cross1 = [3]f64{ ey - c1y, c1x - ex, ex * c1y - ey * c1x };
    const cross2 = [3]f64{ sy - ey, ex - sx, sx * ey - sy * ex };
    const cross3 = [3]f64{ c0y - sy, sx - c0x, c0x * sy - c0y * sx };

    const a1 = sx * cross1[0] + sy * cross1[1] + cross1[2];
    const a2 = c0x * cross2[0] + c0y * cross2[1] + cross2[2];
    const a3 = c1x * cross3[0] + c1y * cross3[1] + cross3[2];

    const d0_ = a1 - 2.0 * a2 + 3.0 * a3;
    const d1_ = -a2 + 3.0 * a3;
    const d2_ = 3.0 * a3;

    const D = 3.0 * d1_ * d1_ - 4.0 * d2_ * d0_;
    const discr = d0_ * d0_ * D;

    const EP: f64 = 1e-12;

    const curveType: CurveType = if (@abs(discr) <= EP) blk: {
        if (d0_ == 0.0 and d1_ == 0.0) {
            if (d2_ == 0.0) break :blk .Line;
            break :blk .Quadratic;
        }
        break :blk .Cusp;
    } else if (discr > 0.0) blk: {
        break :blk .Serpentine;
    } else blk: {
        break :blk .Loop;
    };

    return .{
        .curveType = curveType,
        .d0 = @as(T, @floatCast(d0_)),
        .d1 = @as(T, @floatCast(d1_)),
        .d2 = @as(T, @floatCast(d2_)),
    };
}

// ══════════════════════════════════════════════════════════════════════════════
//  _ShapesComputeLine (file-private)
// ══════════════════════════════════════════════════════════════════════════════

/// `reverseOrientation` — F 행렬의 방향을 반전시킨다.
fn reverseOrientation(F: [4][3]f32) [4][3]f32 {
    return .{
        .{ -F[0][0], -F[0][1], F[0][2] },
        .{ -F[1][0], -F[1][1], F[1][2] },
        .{ -F[2][0], -F[2][1], F[2][2] },
        .{ -F[3][0], -F[3][1], F[3][2] },
    };
}

/// Odin geometry._ShapesComputeLine 1:1. cubic/quadratic 곡선을 삼각형 strip으로 분할.
fn shapesComputeLine(
    vertList: *std.array_list.Aligned(ShapeVertex2d, null),
    indList: *std.array_list.Aligned(u32, null),
    color: Vec4f32,
    pts: *CurveStructFloat(f32),
    allocator: std.mem.Allocator,
) ShapeError!void {
    var curveType = pts.type;

    // loop_reverse 처리 (Odin 주석 처리됨)
    pts.curveReverse = false;
    var reverse = false;
    var d0: f32 = undefined;
    var d1: f32 = undefined;
    var d2: f32 = undefined;

    if (curveType != .Line and curveType != .Quadratic) {
        const result = try getCubicCurveType(f32, pts.start, pts.ctl0, pts.ctl1, pts.end);
        curveType = result.curveType;
        d0 = result.d0;
        d1 = result.d1;
        d2 = result.d2;
    } else if (curveType == .Quadratic) {
        const vlen: u32 = @intCast(vertList.items.len);
        const quadTri = [3]Vec2f32{ pts.start, pts.ctl0, pts.end };
        const quadSign: f32 = if (getPolygonOrientation(f32, &quadTri) == .CounterClockwise) -1.0 else 1.0;
        if (quadSign < 0) pts.curveReverse = true;

        try vertList.append(allocator, .{
            .uvw = .{ 0.0, 0.0, quadSign, @floatFromInt(@intFromEnum(ShapeVertexFlag.QUAD)) },
            .pos = .{ .x = pts.start.x, .y = pts.start.y },
            .color = color,
        });
        try vertList.append(allocator, .{
            .uvw = .{ 0.5, 0.0, quadSign, @floatFromInt(@intFromEnum(ShapeVertexFlag.QUAD)) },
            .pos = .{ .x = pts.ctl0.x, .y = pts.ctl0.y },
            .color = color,
        });
        try vertList.append(allocator, .{
            .uvw = .{ 1.0, 1.0, quadSign, @floatFromInt(@intFromEnum(ShapeVertexFlag.QUAD)) },
            .pos = .{ .x = pts.end.x, .y = pts.end.y },
            .color = color,
        });
        try indList.appendSlice(allocator, &.{ vlen, vlen + 1, vlen + 2 });
        return;
    }

    var F: [4][3]f32 = undefined;

    switch (curveType) {
        .Serpentine => {
            const t1 = @sqrt(9 * d1 * d1 - 12 * d0 * d2);
            const ls = 3 * d1 - t1;
            const lt = 6 * d0;
            const ms = 3 * d1 + t1;
            const mt = lt;
            const ltMinusLs = lt - ls;
            const mtMinusMs = mt - ms;

            F = .{
                .{ ls * ms, ls * ls * ls, ms * ms * ms },
                .{ (1.0 / 3.0) * (3.0 * ls * ms - ls * mt - lt * ms), ls * ls * (ls - lt), ms * ms * (ms - mt) },
                .{ (1.0 / 3.0) * (lt * (mt - 2.0 * ms) + ls * (3.0 * ms - 2.0 * mt)), ltMinusLs * ltMinusLs * ls, mtMinusMs * mtMinusMs * ms },
                .{ ltMinusLs * mtMinusMs, -(ltMinusLs * ltMinusLs * ltMinusLs), -(mtMinusMs * mtMinusMs * mtMinusMs) },
            };

            if (d0 < 0) reverse = true;
        },
        .Loop => {
            const t1 = @sqrt(4 * d0 * d2 - 3 * d1 * d1);
            const ls = d1 - t1;
            const lt = 2 * d0;
            const ms = d1 + t1;
            const mt = lt;
            const ltMinusLs = lt - ls;
            const mtMinusMs = mt - ms;

            F = .{
                .{ ls * ms, ls * ls * ms, ls * ms * ms },
                .{ (1.0 / 3.0) * (-ls * mt - lt * ms + 3.0 * ls * ms), -(1.0 / 3.0) * ls * (ls * (mt - 3.0 * ms) + 2.0 * lt * ms), -(1.0 / 3.0) * ms * (ls * (2.0 * mt - 3.0 * ms) + lt * ms) },
                .{ (1.0 / 3.0) * (lt * (mt - 2.0 * ms) + ls * (3.0 * ms - 2.0 * mt)), (1.0 / 3.0) * ltMinusLs * (ls * (2.0 * mt - 3.0 * ms) + lt * ms), (1.0 / 3.0) * mtMinusMs * (ls * (mt - 3.0 * ms) + 2.0 * lt * ms) },
                .{ ltMinusLs * mtMinusMs, -(ltMinusLs * ltMinusLs) * mtMinusMs, -ltMinusLs * mtMinusMs * mtMinusMs },
            };

            reverse = (d0 > 0 and F[1][0] < 0.0) or (d0 < 0 and F[1][0] > 0.0);
        },
        .Cusp => {
            const ls = d2;
            const lt = 3.0 * d1;
            const lsMinusLt = ls - lt;
            F = .{
                .{ ls, ls * ls * ls, 1.0 },
                .{ ls - (1.0 / 3.0) * lt, ls * ls * lsMinusLt, 1.0 },
                .{ ls - (2.0 / 3.0) * lt, lsMinusLt * lsMinusLt * ls, 1.0 },
                .{ lsMinusLt, lsMinusLt * lsMinusLt * lsMinusLt, 1.0 },
            };
        },
        .Quadratic => {
            F = .{
                .{ 0.0, 0.0, 0.0 },
                .{ 1.0 / 3.0, 0.0, 1.0 / 3.0 },
                .{ 2.0 / 3.0, 1.0 / 3.0, 2.0 / 3.0 },
                .{ 1.0, 1.0, 1.0 },
            };
            if (d2 < 0) reverse = true;
        },
        .Line => return,
        .Unknown => {},
    }

    pts.curveReverse = reverse;
    if (reverse) {
        F = reverseOrientation(F);
    }

    try appendComputeLine(vertList, indList, color, pts.*, F, allocator);
}

/// shapesComputeLine의 appendLine 단계. 4개 정점과 삼각형 인덱스를 생성한다.
fn appendComputeLine(
    vertList: *std.array_list.Aligned(ShapeVertex2d, null),
    indList: *std.array_list.Aligned(u32, null),
    color: Vec4f32,
    pts: CurveStructFloat(f32),
    F: [4][3]f32,
    allocator: std.mem.Allocator,
) ShapeError!void {
    const start: u32 = @intCast(vertList.items.len);

    try vertList.append(allocator, .{ .uvw = .{ F[0][0], F[0][1], F[0][2], @floatFromInt(@intFromEnum(ShapeVertexFlag.CUBIC)) }, .color = color, .pos = .{ .x = 0, .y = 0 } });
    try vertList.append(allocator, .{ .uvw = .{ F[1][0], F[1][1], F[1][2], @floatFromInt(@intFromEnum(ShapeVertexFlag.CUBIC)) }, .color = color, .pos = .{ .x = 0, .y = 0 } });
    try vertList.append(allocator, .{ .uvw = .{ F[2][0], F[2][1], F[2][2], @floatFromInt(@intFromEnum(ShapeVertexFlag.CUBIC)) }, .color = color, .pos = .{ .x = 0, .y = 0 } });
    try vertList.append(allocator, .{ .uvw = .{ F[3][0], F[3][1], F[3][2], @floatFromInt(@intFromEnum(ShapeVertexFlag.CUBIC)) }, .color = color, .pos = .{ .x = 0, .y = 0 } });

    // Set positions
    vertList.items[start].pos = .{ .x = pts.start.x, .y = pts.start.y };
    vertList.items[start + 1].pos = .{ .x = pts.ctl0.x, .y = pts.ctl0.y };
    vertList.items[start + 2].pos = .{ .x = pts.ctl1.x, .y = pts.ctl1.y };
    vertList.items[start + 3].pos = .{ .x = pts.end.x, .y = pts.end.y };

    // triangulate the 4 control points
    const vts = [4]Vec2f32{
        vertList.items[start].pos,
        vertList.items[start + 1].pos,
        vertList.items[start + 2].pos,
        vertList.items[start + 3].pos,
    };

    // Check for duplicate vertices → triangle fan
    for (0..4) |ii| {
        for (ii + 1..4) |jj| {
            if (vts[ii].x == vts[jj].x and vts[ii].y == vts[jj].y) {
                var indices: [3]u32 = .{ start, start, start };
                var idx: u32 = 0;
                for (0..4) |kk| {
                    if (kk != jj) {
                        indices[idx] = start + @as(u32, @intCast(kk));
                        idx += 1;
                    }
                }
                try indList.appendSlice(allocator, &.{ indices[0], indices[1], indices[2] });
                return;
            }
        }
    }

    // Check interior point → fan from interior
    for (0..4) |ii| {
        var indices: [3]u32 = .{ start, start, start };
        var idx: u32 = 0;
        for (0..4) |jj| {
            if (jj != ii) {
                indices[idx] = start + @as(u32, @intCast(jj));
                idx += 1;
            }
        }
        // remap to 0..3 for pointInTriangle
        const tri0 = vertList.items[indices[0]].pos;
        const tri1 = vertList.items[indices[1]].pos;
        const tri2 = vertList.items[indices[2]].pos;
        if (pointInTriangle(f32, vts[ii], tri0, tri1, tri2)) {
            try indList.appendSlice(allocator, &.{ indices[0], indices[1], indices[2] });
            try indList.appendSlice(allocator, &.{ indices[1], indices[2], start + @as(u32, @intCast(ii)) });
            try indList.appendSlice(allocator, &.{ indices[2], indices[0], start + @as(u32, @intCast(ii)) });
            return;
        }
    }

    // Split along the shorter diagonal
    const b = linesIntersect3(f32, vts[0], vts[2], vts[1], vts[3], false);
    if (b == .intersect) {
        if (vec2Length2(f32, vec2Sub(f32, vts[2], vts[0])) < vec2Length2(f32, vec2Sub(f32, vts[3], vts[1]))) {
            try indList.appendSlice(allocator, &.{ start, start + 1, start + 2, start, start + 2, start + 3 });
        } else {
            try indList.appendSlice(allocator, &.{ start, start + 1, start + 3, start, start + 2, start + 3 });
        }
        return;
    }
    const b2 = linesIntersect3(f32, vts[0], vts[3], vts[1], vts[2], false);
    if (b2 == .intersect) {
        if (vec2Length2(f32, vec2Sub(f32, vts[3], vts[0])) < vec2Length2(f32, vec2Sub(f32, vts[2], vts[1]))) {
            try indList.appendSlice(allocator, &.{ start, start + 1, start + 3, start, start + 3, start + 2 });
        } else {
            try indList.appendSlice(allocator, &.{ start, start + 1, start + 2, start, start + 2, start + 3 });
        }
        return;
    }
    if (vec2Length2(f32, vec2Sub(f32, vts[1], vts[0])) < vec2Length2(f32, vec2Sub(f32, vts[3], vts[2]))) {
        try indList.appendSlice(allocator, &.{ start, start + 2, start + 1, start, start + 1, start + 3 });
    } else {
        try indList.appendSlice(allocator, &.{ start, start + 2, start + 3, start, start + 3, start + 1 });
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SubdivCurveAndInjectAt (file-private)
// ══════════════════════════════════════════════════════════════════════════════

/// 곡선 src를 t에서 분할하고, 분할 결과를 curvesN[insertIdx]에 주입한다.
fn subdivCurveAndInjectAt(
    curvesN: *std.array_list.Aligned(CurveStructFloat(f32), null),
    insertIdx: usize,
    cur: *CurveStructFloat(f32),
    src: CurveStructFloat(f32),
    t: f32,
    allocator: std.mem.Allocator,
) ShapeError!struct { mid: Vec2f32, c0: Vec2f32, c1: Vec2f32 } {
    if (src.type == .Quadratic) {
        const p0_p1_p2 = subdivQuadraticBezier(f32, .{ src.start, src.ctl0, src.end }, t);
        cur.ctl0 = p0_p1_p2[0];
        cur.end = p0_p1_p2[1];
        const mid = p0_p1_p2[1];
        const c0 = p0_p1_p2[2];
        try curvesN.insert(allocator, insertIdx, .{
            .start = p0_p1_p2[1],
            .ctl0 = p0_p1_p2[2],
            .ctl1 = Vec2f32{ .x = 0, .y = 0 },
            .end = src.end,
            .type = .Quadratic,
            .curveReverse = false,
        });
        return .{ .mid = mid, .c0 = c0, .c1 = Vec2f32{ .x = 0, .y = 0 } };
    } else {
        const p0_p1_p2_p3_p4 = subdivCubicBezier(f32, .{ src.start, src.ctl0, src.ctl1, src.end }, t);
        cur.ctl0 = p0_p1_p2_p3_p4[0];
        cur.ctl1 = p0_p1_p2_p3_p4[1];
        cur.end = p0_p1_p2_p3_p4[2];
        const mid = p0_p1_p2_p3_p4[2];
        const c0 = p0_p1_p2_p3_p4[3];
        const c1 = p0_p1_p2_p3_p4[4];
        try curvesN.insert(allocator, insertIdx, .{
            .start = p0_p1_p2_p3_p4[2],
            .ctl0 = p0_p1_p2_p3_p4[3],
            .ctl1 = p0_p1_p2_p3_p4[4],
            .end = src.end,
            .type = .Unknown,
            .curveReverse = false,
        });
        return .{ .mid = mid, .c0 = c0, .c1 = c1 };
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SubdivCurveAt (file-private)
// ══════════════════════════════════════════════════════════════════════════════

/// 곡선 src를 t에서 분할하여 좌/우 부분 곡선을 반환한다.
fn subdivCurveAt(src: CurveStructFloat(f32), t: f32) struct { CurveStructFloat(f32), CurveStructFloat(f32) } {
    if (src.type == .Quadratic) {
        const p0_p1_p2 = subdivQuadraticBezier(f32, .{ src.start, src.ctl0, src.end }, t);
        const left = CurveStructFloat(f32){
            .start = src.start,
            .ctl0 = p0_p1_p2[0],
            .ctl1 = Vec2f32{ .x = 0, .y = 0 },
            .end = p0_p1_p2[1],
            .type = .Quadratic,
            .curveReverse = false,
        };
        const right = CurveStructFloat(f32){
            .start = p0_p1_p2[1],
            .ctl0 = p0_p1_p2[2],
            .ctl1 = Vec2f32{ .x = 0, .y = 0 },
            .end = src.end,
            .type = .Quadratic,
            .curveReverse = false,
        };
        return .{ left, right };
    } else {
        const p0_p1_p2_p3_p4 = subdivCubicBezier(f32, .{ src.start, src.ctl0, src.ctl1, src.end }, t);
        const left = CurveStructFloat(f32){
            .start = src.start,
            .ctl0 = p0_p1_p2_p3_p4[0],
            .ctl1 = p0_p1_p2_p3_p4[1],
            .end = p0_p1_p2_p3_p4[2],
            .type = .Unknown,
            .curveReverse = false,
        };
        const right = CurveStructFloat(f32){
            .start = p0_p1_p2_p3_p4[2],
            .ctl0 = p0_p1_p2_p3_p4[3],
            .ctl1 = p0_p1_p2_p3_p4[4],
            .end = src.end,
            .type = .Unknown,
            .curveReverse = false,
        };
        return .{ left, right };
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  CurveChordOverlaps (file-private)
// ══════════════════════════════════════════════════════════════════════════════

/// 두 곡선의 chord(시작-끝 직선)가 교차하는지 검사.
fn curveChordOverlaps(src: CurveStructFloat(f32), cur: CurveStructFloat(f32)) bool {
    if (src.type == .Line and cur.type == .Line) return false;

    if (src.type == .Line or cur.type == .Line) {
        const k = linesIntersect2(f32, src.start, src.end, cur.start, cur.end, true);
        return k[0] == .intersect;
    }

    const k1 = linesIntersect2(f32, src.start, src.end, cur.start, cur.ctl0, true);
    if (k1[0] == .intersect) return true;

    const curEndPt = if (cur.type == .Quadratic) cur.ctl0 else cur.ctl1;
    const k2 = linesIntersect2(f32, src.start, src.end, curEndPt, cur.end, true);
    return k2[0] == .intersect;
}

// ══════════════════════════════════════════════════════════════════════════════
//  CurveChordOverlapsAny (file-private)
// ══════════════════════════════════════════════════════════════════════════════

/// srcs 중 하나라도 curs 중 하나와 chord 교차하면 true.
fn curveChordOverlapsAny(srcs: []const CurveStructFloat(f32), curs: []const CurveStructFloat(f32)) bool {
    for (srcs) |src| {
        for (curs) |cur| {
            if (curveChordOverlaps(src, cur)) return true;
        }
    }
    return false;
}

// ══════════════════════════════════════════════════════════════════════════════
//  SubdivCurveSegmentsAtHalf (file-private)
// ══════════════════════════════════════════════════════════════════════════════

/// 각 곡선을 0.5에서 분할하여 dst에 저장 (len(dst) == len(srcs)*2).
fn subdivCurveSegmentsAtHalf(srcs: []const CurveStructFloat(f32), dst: []CurveStructFloat(f32)) void {
    for (srcs, 0..) |src, idx| {
        const halves = subdivCurveAt(src, 0.5);
        dst[2 * idx] = halves[0];
        dst[2 * idx + 1] = halves[1];
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  InjectSubdivCurveSegments (file-private)
// ══════════════════════════════════════════════════════════════════════════════

/// curvesN[atIdx]를 segs로 대체하고, 추가 segs를 atIdx 이후에 삽입한다.
fn injectSubdivCurveSegments(
    curvesN: *std.array_list.Aligned(CurveStructFloat(f32), null),
    splitFlagsN: *std.array_list.Aligned(bool, null),
    atIdx: usize,
    segs: []const CurveStructFloat(f32),
    allocator: std.mem.Allocator,
) ShapeError!usize {
    if (segs.len == 0) return 0;

    curvesN.items[atIdx] = segs[0];
    splitFlagsN.items[atIdx] = true;
    var added: usize = 0;
    if (segs.len > 1) {
        try curvesN.insertSlice(allocator, atIdx + 1, segs[1..]);
        var k: usize = 1;
        while (k < segs.len) : (k += 1) {
            try splitFlagsN.insert(allocator, atIdx + k, true);
        }
        added = segs.len - 1;
    }
    return added;
}

// ══════════════════════════════════════════════════════════════════════════════
//  ProcessCurveOverlapPair (file-private)
// ══════════════════════════════════════════════════════════════════════════════

/// curvesA[i]와 curvesB[j] 사이의 겹침을 처리하고 분할을 수행한다.
fn processCurveOverlapPair(
    curvesA: *std.array_list.Aligned(CurveStructFloat(f32), null),
    splitFlagsA: *std.array_list.Aligned(bool, null),
    i: usize,
    curvesB: *std.array_list.Aligned(CurveStructFloat(f32), null),
    splitFlagsB: *std.array_list.Aligned(bool, null),
    j: usize,
    sameContour: bool,
    allocator: std.mem.Allocator,
) ShapeError!struct { curAdded: usize, srcAdded: usize, overlapped: bool } {
    const src = curvesB.items[j];
    const cur = curvesA.items[i];

    const srcIsLine = src.type == .Line;
    const curIsLine = cur.type == .Line;
    if (srcIsLine and curIsLine) return .{ .curAdded = 0, .srcAdded = 0, .overlapped = false };
    if (!curveChordOverlaps(src, cur)) return .{ .curAdded = 0, .srcAdded = 0, .overlapped = false };

    // curve-vs-line: split only the curve side.
    if (srcIsLine or curIsLine) {
        if (srcIsLine) {
            const curHalf0_1 = subdivCurveAt(cur, 0.5);
            var curSegs2 = [2]CurveStructFloat(f32){ curHalf0_1[0], curHalf0_1[1] };
            var curSegs4: [4]CurveStructFloat(f32) = undefined;
            var curSegs8: [8]CurveStructFloat(f32) = undefined;
            var curSegs: []const CurveStructFloat(f32) = curSegs2[0..];
            const lineProbe = [1]CurveStructFloat(f32){src};

            if (curveChordOverlapsAny(lineProbe[0..], curSegs)) {
                subdivCurveSegmentsAtHalf(curSegs, curSegs4[0..]);
                curSegs = curSegs4[0..];
                if (curveChordOverlapsAny(lineProbe[0..], curSegs)) {
                    subdivCurveSegmentsAtHalf(curSegs, curSegs8[0..]);
                    curSegs = curSegs8[0..];
                }
            }
            const curAdded = try injectSubdivCurveSegments(curvesA, splitFlagsA, i, curSegs, allocator);
            return .{ .curAdded = curAdded, .srcAdded = 0, .overlapped = true };
        } else {
            const srcHalf0_1 = subdivCurveAt(src, 0.5);
            var srcSegs2 = [2]CurveStructFloat(f32){ srcHalf0_1[0], srcHalf0_1[1] };
            var srcSegs4: [4]CurveStructFloat(f32) = undefined;
            var srcSegs8: [8]CurveStructFloat(f32) = undefined;
            var srcSegs: []const CurveStructFloat(f32) = srcSegs2[0..];
            const lineProbe = [1]CurveStructFloat(f32){cur};

            if (curveChordOverlapsAny(srcSegs, lineProbe[0..])) {
                subdivCurveSegmentsAtHalf(srcSegs, srcSegs4[0..]);
                srcSegs = srcSegs4[0..];
                if (curveChordOverlapsAny(srcSegs, lineProbe[0..])) {
                    subdivCurveSegmentsAtHalf(srcSegs, srcSegs8[0..]);
                    srcSegs = srcSegs8[0..];
                }
            }

            const srcAdded = if (sameContour)
                try injectSubdivCurveSegments(curvesA, splitFlagsA, j, srcSegs, allocator)
            else
                try injectSubdivCurveSegments(curvesB, splitFlagsB, j, srcSegs, allocator);
            return .{ .curAdded = 0, .srcAdded = srcAdded, .overlapped = true };
        }
    }

    const srcHalf0_1 = subdivCurveAt(src, 0.5);
    const curHalf0_1 = subdivCurveAt(cur, 0.5);
    var srcSegs2 = [2]CurveStructFloat(f32){ srcHalf0_1[0], srcHalf0_1[1] };
    var curSegs2_arr = [2]CurveStructFloat(f32){ curHalf0_1[0], curHalf0_1[1] };
    var curSegs1_arr = [1]CurveStructFloat(f32){cur};
    var srcSegs4: [4]CurveStructFloat(f32) = undefined;
    var srcSegs8: [8]CurveStructFloat(f32) = undefined;
    var curSegs4: [4]CurveStructFloat(f32) = undefined;
    var curSegs8: [8]CurveStructFloat(f32) = undefined;
    var srcSegs: []const CurveStructFloat(f32) = srcSegs2[0..];
    var curSegs: []const CurveStructFloat(f32) = curSegs1_arr[0..];

    // refine one side at a time
    if (curveChordOverlapsAny(srcSegs, curSegs)) {
        curSegs = curSegs2_arr[0..];

        if (curveChordOverlapsAny(srcSegs, curSegs)) {
            subdivCurveSegmentsAtHalf(srcSegs, srcSegs4[0..]);
            srcSegs = srcSegs4[0..];

            if (curveChordOverlapsAny(srcSegs, curSegs)) {
                subdivCurveSegmentsAtHalf(curSegs, curSegs4[0..]);
                curSegs = curSegs4[0..];

                if (curveChordOverlapsAny(srcSegs, curSegs)) {
                    subdivCurveSegmentsAtHalf(srcSegs, srcSegs8[0..]);
                    srcSegs = srcSegs8[0..];

                    if (curveChordOverlapsAny(srcSegs, curSegs)) {
                        subdivCurveSegmentsAtHalf(curSegs, curSegs8[0..]);
                        curSegs = curSegs8[0..];
                    }
                }
            }
        }
    }

    var curAdded: usize = 0;
    var srcAdded: usize = 0;

    if (sameContour) {
        if (srcSegs.len > 1 and curSegs.len > 1) {
            if (j > i) {
                srcAdded = try injectSubdivCurveSegments(curvesA, splitFlagsA, j, srcSegs, allocator);
                curAdded = try injectSubdivCurveSegments(curvesA, splitFlagsA, i, curSegs, allocator);
            } else {
                curAdded = try injectSubdivCurveSegments(curvesA, splitFlagsA, i, curSegs, allocator);
                srcAdded = try injectSubdivCurveSegments(curvesA, splitFlagsA, j, srcSegs, allocator);
            }
        } else if (srcSegs.len > 1) {
            srcAdded = try injectSubdivCurveSegments(curvesA, splitFlagsA, j, srcSegs, allocator);
        } else if (curSegs.len > 1) {
            curAdded = try injectSubdivCurveSegments(curvesA, splitFlagsA, i, curSegs, allocator);
        }
    } else {
        srcAdded = try injectSubdivCurveSegments(curvesB, splitFlagsB, j, srcSegs, allocator);
        if (curSegs.len > 1) {
            curAdded = try injectSubdivCurveSegments(curvesA, splitFlagsA, i, curSegs, allocator);
        }
    }

    return .{ .curAdded = curAdded, .srcAdded = srcAdded, .overlapped = true };
}

// ══════════════════════════════════════════════════════════════════════════════
//  shapesComputePolygon
// ══════════════════════════════════════════════════════════════════════════════

/// Shapes(다중 contour + curve flag)를 RawShape(vertices + indices + rect)로 변환한다.
/// Odin geometry.shapesComputePolygon 1:1.
pub fn shapesComputePolygon(
    poly: Shapes,
    allocator: std.mem.Allocator,
) ShapeError!RawShape {
    var vertList: std.array_list.Aligned(ShapeVertex2d, null) = .empty;
    var indList: std.array_list.Aligned(u32, null) = .empty;

    // ── clipper 전처리: clipRect + 외곽선(stroke) ──
    var procNodes: std.array_list.Aligned(ShapeNode, null) = .empty;
    defer procNodes.deinit(allocator);

    for (poly.nodes) |node| {
        if (node.color[3] <= 0) continue;

        // 1. clipRect 클리핑
        const clipValid = node.clipRect.left != node.clipRect.right and
            node.clipRect.top != node.clipRect.bottom;
        var clipped = node;
        if (clipValid) {
            const clippedResult = clipShapeNodeRect(&node, node.clipRect, allocator) catch {
                try procNodes.append(allocator, node);
                continue;
            };
            clipped = clippedResult;
        }

        // 2. 외곽선(stroke) — thickness>0이고 strokeColor 불투명이면 별도 노드로 추가
        if (node.thickness > 0 and node.strokeColor[3] > 0) {
            if (offsetShapeNode(&node, @floatCast(node.thickness), .Round, .Polygon, allocator)) |*outline| {
                var s = outline.*;
                s.color = node.strokeColor;
                s.strokeColor = .{ 0, 0, 0, 0 };
                s.thickness = 0;
                try procNodes.append(allocator, s);
            } else |_| {}
        }

        // 3. 원본(채움) 노드 추가
        try procNodes.append(allocator, clipped);
    }

    const procPoly = Shapes{ .nodes = try procNodes.toOwnedSlice(allocator), .clipRect = poly.clipRect };
    try shapesComputePolygonIn(&vertList, &indList, procPoly, allocator);

    const res = RawShape{
        .vertices = try allocator.dupe(ShapeVertex2d, vertList.items),
        .indices = try allocator.dupe(u32, indList.items),
        .rect = .{ .left = 0, .right = 0, .top = 0, .bottom = 0 },
    };
    rawShapeUpdateRect(@constCast(&res));
    return res;
}

// ══════════════════════════════════════════════════════════════════════════════
//  shapesComputePolygonIn (private) — shapesComputePolygon 내부 처리
// ══════════════════════════════════════════════════════════════════════════════

/// Odin shapesComputePolygon의 내부 proc에 대응.
fn shapesComputePolygonIn(
    vertList: *std.array_list.Aligned(ShapeVertex2d, null),
    indList: *std.array_list.Aligned(u32, null),
    poly: Shapes,
    allocator: std.mem.Allocator,
) ShapeError!void {
    const ta = allocator; // temp allocator (Odin context.temp_allocator)

    var nonCurves: std.array_list.Aligned([]const Vec2f32, null) = .empty;
    var nonCurves2: std.array_list.Aligned(std.array_list.Aligned(Vec2f32, null), null) = .empty;
    var curves2: std.array_list.Aligned(std.array_list.Aligned(CurveStructFloat(f32), null), null) = .empty;
    var overlapSkip2: std.array_list.Aligned(std.array_list.Aligned(bool, null), null) = .empty;

    for (poly.nodes, 0..) |node, nidx| {
        _ = nidx;
        if (node.color[3] > 0) {
            // clipper clipRect 처리 — TODO: clipper 안정화 후 활성화
            // 현재는 clipRect를 무시하고 모든 contour 처리

            // resize per-contour arrays
            try resizeNonZero(std.array_list.Aligned(Vec2f32, null), &nonCurves2, node.pts.len, ta);
            try resizeNonZero(std.array_list.Aligned(CurveStructFloat(f32), null), &curves2, node.pts.len, ta);
            try resizeNonZero(std.array_list.Aligned(bool, null), &overlapSkip2, node.pts.len, ta);

            for (0..node.pts.len) |npi| {
                // 각 ArrayList 요소를 명시적으로 초기화 (raw 메모리는 uninitialized 상태).
                nonCurves2.items[npi] = .empty;
                curves2.items[npi] = .empty;
                overlapSkip2.items[npi] = .empty;
            }

            for (node.pts, 0..) |np, npi| {
                const curveFlags: ?[]const bool = if (npi < node.isCurves.len) node.isCurves[npi] else null;

                if (np.len == 0) continue;

                const last = np.len - 1;
                var ii: usize = 0;
                while (true) {
                    if (!node.isClosed and ii >= last) break;

                    const next = if (node.isClosed) (ii + 1) % np.len else ii + 1;
                    if (next >= np.len) break;

                    if (curveFlags != null and next < curveFlags.?.len and curveFlags.?[next]) {
                        const next2 = if (node.isClosed) (next + 1) % np.len else next + 1;
                        if (next2 >= np.len) break;

                        if (curveFlags != null and next2 < curveFlags.?.len and curveFlags.?[next2]) {
                            const next3 = if (node.isClosed) (next2 + 1) % np.len else next2 + 1;
                            if (next3 >= np.len) break;

                            try curves2.items[npi].append(ta, .{
                                .start = np[ii],
                                .ctl0 = np[next],
                                .ctl1 = np[next2],
                                .end = np[next3],
                                .type = .Unknown,
                                .curveReverse = false,
                            });
                            ii = next3;
                        } else {
                            try curves2.items[npi].append(ta, .{
                                .start = np[ii],
                                .ctl0 = np[next],
                                .ctl1 = Vec2f32{ .x = 0, .y = 0 },
                                .end = np[next2],
                                .type = .Quadratic,
                                .curveReverse = false,
                            });
                            ii = next2;
                        }
                    } else {
                        try curves2.items[npi].append(ta, .{
                            .start = np[ii],
                            .end = np[next],
                            .type = .Line,
                            .curveReverse = false,
                            .ctl0 = Vec2f32{ .x = 0, .y = 0 },
                            .ctl1 = Vec2f32{ .x = 0, .y = 0 },
                        });
                        ii = next;
                    }

                    if (node.isClosed and ii == 0) break;
                }
            }

            // Loop subdivision
            for (0..curves2.items.len) |npi| {
                var i: usize = 0;
                while (i < curves2.items[npi].items.len) : (i += 1) {
                    const c = curves2.items[npi].items[i];
                    if (c.type != .Quadratic and c.type != .Line) {
                        const result = try getCubicCurveType(f32, c.start, c.ctl0, c.ctl1, c.end);
                        if (result.curveType == .Loop) {
                            const disc = 4 * result.d0 * result.d2 - 3 * result.d1 * result.d1;
                            const t1 = @sqrt(disc);
                            const ls = result.d1 - t1;
                            const lt = 2 * result.d0;
                            const ms = result.d1 + t1;
                            const mt = lt;

                            const ql = ls / lt;
                            const qm = ms / mt;

                            const subdivAt: f32 = if (0.0 < ql and ql < 1.0) ql else if (0.0 < qm and qm < 1.0) qm else {
                                continue;
                            };

                            const result2 = try subdivCurveAndInjectAt(
                                &curves2.items[npi],
                                i + 1,
                                &curves2.items[npi].items[i],
                                c,
                                subdivAt,
                                ta,
                            );
                            _ = result2;
                            i += 1;
                        }
                    }
                }
            }

            // Initialize overlapSkip (false by default)
            for (0..curves2.items.len) |npi| {
                try resizeNonZero(bool, &overlapSkip2.items[npi], curves2.items[npi].items.len, ta);
            }

            // Overlap check — scan all contour pairs
            var npiA: usize = 0;
            while (npiA < curves2.items.len) : (npiA += 1) {
                const curvesA = &curves2.items[npiA];
                const skipA = &overlapSkip2.items[npiA];

                var npiB: usize = 0;
                while (npiB < curves2.items.len) : (npiB += 1) {
                    const curvesB = &curves2.items[npiB];
                    const skipB = &overlapSkip2.items[npiB];
                    const sameContour = npiA == npiB;

                    var ii: usize = 0;
                    while (ii < curvesA.items.len) : (ii += 1) {
                        if (skipA.items[ii]) continue;

                        var jj: usize = 0;
                        while (jj < curvesB.items.len) : (jj += 1) {
                            if (ii >= curvesA.items.len) break;
                            if (skipA.items[ii]) break;
                            if (skipB.items[jj]) continue;
                            if (sameContour and ii == jj) continue;

                            const origI = ii;
                            const origJ = jj;
                            const overlapResult = try processCurveOverlapPair(
                                curvesA, skipA, ii,
                                curvesB, skipB, jj,
                                sameContour,
                                ta,
                            );
                            if (!overlapResult.overlapped) continue;

                            if (sameContour) {
                                if (overlapResult.srcAdded > 0 and origJ < origI) ii += overlapResult.srcAdded;
                                if (overlapResult.curAdded > 0 and origI < origJ) jj += overlapResult.curAdded;
                            }

                            ii += overlapResult.curAdded;
                            jj += overlapResult.srcAdded;
                            if (ii >= curvesA.items.len) break;
                        }
                    }
                }
            }

            // Build non-curves polygon boundaries
            for (0..node.pts.len) |npi| {
                const nonCurvesNpi = &nonCurves2.items[npi];
                const curvesNpi = curves2.items[npi].items;

                nonCurvesNpi.clearRetainingCapacity();
                if (curvesNpi.len == 0) continue;

                try nonCurvesNpi.append(ta, curvesNpi[0].start);
                for (curvesNpi, 0..) |c, ci| {
                    if (node.isClosed and ci == curvesNpi.len - 1 and
                        @abs(c.end.x - curvesNpi[0].start.x) <= std.math.floatEps(f32) and
                        @abs(c.end.y - curvesNpi[0].start.y) <= std.math.floatEps(f32))
                    {
                        continue;
                    }
                    try nonCurvesNpi.append(ta, c.end);
                }
            }

            // Generate compute line vertices/indices for each curve
            for (0..curves2.items.len) |ci| {
                const cc = &curves2.items[ci];
                for (0..cc.items.len) |cj| {
                    try shapesComputeLine(vertList, indList, node.color, &cc.items[cj], ta);
                }
            }

            // Insert curve control points into polygon boundaries
            for (0..node.pts.len) |npi| {
                const nonCurvesNpi = &nonCurves2.items[npi];
                const curvesNpi = curves2.items[npi].items;

                for (curvesNpi) |c| {
                    if (c.type != .Line) {
                        var insertAr: std.array_list.Aligned(Vec2f32, null) = .empty;
                        defer insertAr.deinit(ta);

                        if (c.type != .Quadratic) {
                            if (pointLineLeftOrRight(f32, c.ctl0, c.start, c.end) > 0) {
                                try insertAr.append(ta, c.ctl0);
                            }
                            if (pointLineLeftOrRight(f32, c.ctl1, c.start, c.end) > 0) {
                                try insertAr.append(ta, c.ctl1);
                            }
                        } else {
                            if (pointLineLeftOrRight(f32, c.ctl0, c.start, c.end) > 0) {
                                try insertAr.append(ta, c.ctl0);
                            }
                        }

                        if (insertAr.items.len > 0) {
                            var insertIdx: isize = -1;
                            for (nonCurvesNpi.items, 0..) |pt, idx| {
                                const next = if (node.isClosed) (idx + 1) % nonCurvesNpi.items.len else idx + 1;
                                if (next >= nonCurvesNpi.items.len) break;

                                if (@abs(pt.x - c.start.x) <= std.math.floatEps(f32) and
                                    @abs(pt.y - c.start.y) <= std.math.floatEps(f32) and
                                    @abs(nonCurvesNpi.items[next].x - c.end.x) <= std.math.floatEps(f32) and
                                    @abs(nonCurvesNpi.items[next].y - c.end.y) <= std.math.floatEps(f32))
                                {
                                    insertIdx = @intCast(next);
                                    break;
                                }
                            }
                            if (insertIdx < 0) continue;
                            try nonCurvesNpi.insertSlice(ta, @intCast(insertIdx), insertAr.items);
                        }
                    }
                }
            }

            // Build flat nonCurves list
            try resizeNonZero([]const Vec2f32, &nonCurves, nonCurves2.items.len, ta);
            for (nonCurves2.items, 0..) |nc, npi| {
                nonCurves.items[npi] = nc.items;
            }

            // Triangulate
            const indices = try triangulation.trianguatePolygons(
                Vec2f32,
                nonCurves.items,
                ta,
                @intCast(vertList.items.len),
            );
            defer ta.free(indices);

            // Append triangulated vertices
            for (nonCurves.items) |n| {
                for (n) |nn| {
                    try vertList.append(ta, .{
                        .pos = nn,
                        .color = node.color,
                        .uvw = .{ 0, 0, 0, 0 },
                    });
                }
            }
            try indList.appendSlice(ta, indices);
        }
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  polyTransformMatrix
// ══════════════════════════════════════════════════════════════════════════════

/// Shapes의 모든 정점에 4x4 행렬 변환을 적용한다.
pub fn polyTransformMatrix(inoutPoly: *Shapes, F: linalg.Mat4x4f32) void {
    for (inoutPoly.nodes) |*node| {
        for (node.pts) |pts_slice| {
            for (pts_slice) |*pt| {
                const out = F.mulVec(.{ pt.x, pt.y, 0.0, 1.0 });
                pt.x = out[0] / out[3];
                pt.y = out[1] / out[3];
            }
        }
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Clipper 통합 — 곡선 재조립 + Offset + RectClip + Boolean (Stage 7)
// ══════════════════════════════════════════════════════════════════════════════

/// Curved segment metadata for t-parameter tracking during flattening
pub const FlattenedSegment = struct { pt: linalg.Vec2f32, orig_curve_idx: usize, t_start: f32, t_end: f32, is_curve: bool };

/// Exact De Casteljau extraction of cubic bezier [t_min, t_max]
pub fn reconstructCubicFromTRange(orig: [4]linalg.Vec2f32, t_min: f32, t_max: f32) [4]linalg.Vec2f32 {
    const r1 = lines.subdivCubicBezier(f32, orig, t_min);
    const right: [4]linalg.Vec2f32 = .{ r1[2], r1[3], r1[4], orig[3] };
    const tn = if (t_max >= 1.0) 1.0 else (t_max - t_min) / (1.0 - t_min);
    const r2 = lines.subdivCubicBezier(f32, right, tn);
    return .{ right[0], r2[0], r2[1], r2[2] };
}

/// Exact De Casteljau extraction of quadratic bezier [t_min, t_max]
pub fn reconstructQuadraticFromTRange(orig: [3]linalg.Vec2f32, t_min: f32, t_max: f32) [3]linalg.Vec2f32 {
    const r1 = lines.subdivQuadraticBezier(f32, orig, t_min);
    const right: [3]linalg.Vec2f32 = .{ r1[1], r1[2], orig[2] };
    const tn = if (t_max >= 1.0) 1.0 else (t_max - t_min) / (1.0 - t_min);
    const r2 = lines.subdivQuadraticBezier(f32, right, tn);
    return .{ right[0], r2[0], r2[1] };
}

// ── Polyline → Bezier curve fitting (Loop Blinn compatible) ──

fn fitBezierToPolyline(poly: []const Vec2f32, isClosed: bool, allocator: std.mem.Allocator) std.mem.Allocator.Error!struct { pts: []Vec2f32, isCurves: []bool } {
    if (poly.len <= 2) {
        const p = try allocator.dupe(Vec2f32, poly);
        const c = try allocator.alloc(bool, poly.len);
        for (0..poly.len) |i| c[i] = false;
        return .{ .pts = p, .isCurves = c };
    }
    var outP: std.array_list.Aligned(Vec2f32, null) = .empty;
    var outC: std.array_list.Aligned(bool, null) = .empty;
    defer {
        outP.deinit(allocator);
        outC.deinit(allocator);
    }
    var i: usize = 0;
    while (i < poly.len) : (i += 1) {
        const r = poly.len - i - 1;
        _ = try outP.append(allocator, poly[i]); _ = try outC.append(allocator, false);
        if (r >= 3) { _ = try outC.append(allocator, true); _ = try outP.append(allocator, poly[i + 1]); _ = try outC.append(allocator, true); _ = try outP.append(allocator, poly[i + 2]); _ = try outC.append(allocator, false); _ = try outP.append(allocator, poly[i + 3]); i += 3; }
        else if (r >= 2) { _ = try outC.append(allocator, true); _ = try outP.append(allocator, poly[i + 1]); _ = try outC.append(allocator, false); _ = try outP.append(allocator, poly[i + 2]); i += 2; }
        else if (r >= 1) { _ = try outC.append(allocator, false); _ = try outP.append(allocator, poly[i + 1]); i += 1; }
        if (isClosed and i >= poly.len - 1) break;
    }
    if (isClosed and outP.items.len > 0 and outP.items[0].x == outP.items[outP.items.len - 1].x and outP.items[0].y == outP.items[outP.items.len - 1].y) { _ = outP.pop(); _ = outC.pop(); }
    return .{ .pts = try outP.toOwnedSlice(allocator), .isCurves = try outC.toOwnedSlice(allocator) };
}

// ── Offset (inflate) ──

pub fn offsetShapeNode(node: *const ShapeNode, delta: f32, jt: clipper.JoinType, et: clipper.EndType, allocator: std.mem.Allocator) (std.mem.Allocator.Error || ShapeError)!ShapeNode {
    if (node.pts.len == 0) return error.Empty_Input;
    var allP: std.array_list.Aligned([]clipper.Point, null) = .empty;
    defer {
        for (allP.items) |p| allocator.free(p);
        allP.deinit(allocator);
    }
    for (node.pts) |c| {
        if (c.len == 0) continue;
        var cp = try allocator.alloc(clipper.Point, c.len);
        for (c, 0..) |pt, j| cp[j] = .{ .x = @floatCast(pt.x), .y = @floatCast(pt.y) };
        try allP.append(allocator, cp);
    }
    const inflated = clipper.inflatePaths(allP.items, @floatCast(delta), jt, et, 2.0, 0.0, true, allocator);
    if (inflated.err != null) return mapClipperErr(inflated.err.?);

    var newP: std.array_list.Aligned([]Vec2f32, null) = .empty;
    var newC: std.array_list.Aligned([]bool, null) = .empty;
    defer {
        for (newP.items) |p| allocator.free(p);
        for (newC.items) |c| allocator.free(c);
        newP.deinit(allocator);
        newC.deinit(allocator);
    }
    for (inflated.res) |poly| {
        if (poly.len == 0) continue;
        var vp = try allocator.alloc(Vec2f32, poly.len);
        defer allocator.free(vp);
        for (poly, 0..) |pt, j| vp[j] = .{ .x = @floatCast(pt.x), .y = @floatCast(pt.y) };
        const fit = try fitBezierToPolyline(vp, node.isClosed, allocator);
        try newP.append(allocator, fit.pts); try newC.append(allocator, fit.isCurves);
    }
    return ShapeNode{ .pts = try newP.toOwnedSlice(allocator), .isCurves = try newC.toOwnedSlice(allocator), .color = node.color, .strokeColor = node.strokeColor, .thickness = node.thickness, .isClosed = node.isClosed, .clipRect = node.clipRect };
}

// ── RectClip ──

pub fn clipShapeNodeRect(node: *const ShapeNode, clipRect: Rectf32, allocator: std.mem.Allocator) (std.mem.Allocator.Error || ShapeError)!ShapeNode {
    if (node.pts.len == 0) return error.Empty_Input;
    var cp: std.array_list.Aligned([]clipper.Point, null) = .empty;
    defer {
        for (cp.items) |p| allocator.free(p);
        cp.deinit(allocator);
    }
    for (node.pts) |c| {
        if (c.len < 3) continue;
        var pp = try allocator.alloc(clipper.Point, c.len);
        for (c, 0..) |pt, j| pp[j] = .{ .x = @floatCast(pt.x), .y = @floatCast(pt.y) };
        try cp.append(allocator, pp);
    }
    const r: clipper.RectF64 = .{ .left = @floatCast(clipRect.left), .top = @floatCast(clipRect.top), .right = @floatCast(clipRect.right), .bottom = @floatCast(clipRect.bottom) };
    const rc = clipper.rectClip(r, cp.items, &.{}, allocator);
    if (rc.err != null) return mapClipperErr(rc.err.?);

    var newP: std.array_list.Aligned([]Vec2f32, null) = .empty;
    var newC: std.array_list.Aligned([]bool, null) = .empty;
    defer {
        for (newP.items) |p| allocator.free(p);
        for (newC.items) |c| allocator.free(c);
        newP.deinit(allocator);
        newC.deinit(allocator);
    }
    for (rc.closed) |poly| {
        if (poly.len < 3) continue;
        var vp = try allocator.alloc(Vec2f32, poly.len);
        defer allocator.free(vp);
        for (poly, 0..) |pt, j| vp[j] = .{ .x = @floatCast(pt.x), .y = @floatCast(pt.y) };
        const fit = try fitBezierToPolyline(vp, node.isClosed, allocator);
        try newP.append(allocator, fit.pts); try newC.append(allocator, fit.isCurves);
    }
    return ShapeNode{ .pts = try newP.toOwnedSlice(allocator), .isCurves = try newC.toOwnedSlice(allocator), .color = node.color, .strokeColor = node.strokeColor, .thickness = node.thickness, .isClosed = node.isClosed, .clipRect = clipRect };
}

// ── Boolean ──

pub fn booleanShapeNodes(ct: clipper.ClipType, subj: *const ShapeNode, clip: *const ShapeNode, allocator: std.mem.Allocator) (std.mem.Allocator.Error || ShapeError)!ShapeNode {
    if (subj.pts.len == 0) return error.Empty_Input;
    // subject → clipper.Point
    var sp: std.array_list.Aligned([]clipper.Point, null) = .empty;
    defer {
        for (sp.items) |p| allocator.free(p);
        sp.deinit(allocator);
    }
    for (subj.pts) |c| { if (c.len < 3) continue; var pp = try allocator.alloc(clipper.Point, c.len); for (c, 0..) |pt, j| pp[j] = .{ .x = @floatCast(pt.x), .y = @floatCast(pt.y) }; try sp.append(allocator, pp); }
    // clip → clipper.Point
    var clp: std.array_list.Aligned([]clipper.Point, null) = .empty;
    defer {
        for (clp.items) |p| allocator.free(p);
        clp.deinit(allocator);
    }
    for (clip.pts) |c| { if (c.len < 3) continue; var pp = try allocator.alloc(clipper.Point, c.len); for (c, 0..) |pt, j| pp[j] = .{ .x = @floatCast(pt.x), .y = @floatCast(pt.y) }; try clp.append(allocator, pp); }
    const br = clipper.booleanOp(ct, sp.items, clp.items, &.{}, .NonZero, allocator);
    if (br.err != null) return mapClipperErr(br.err.?);

    var newP: std.array_list.Aligned([]Vec2f32, null) = .empty;
    var newC: std.array_list.Aligned([]bool, null) = .empty;
    defer {
        for (newP.items) |p| allocator.free(p);
        for (newC.items) |c| allocator.free(c);
        newP.deinit(allocator);
        newC.deinit(allocator);
    }
    for (br.res.items) |poly| {
        if (poly.len < 3) continue;
        var vp = try allocator.alloc(Vec2f32, poly.len);
        defer allocator.free(vp);
        for (poly, 0..) |pt, j| vp[j] = .{ .x = @floatCast(pt.x), .y = @floatCast(pt.y) };
        const fit = try fitBezierToPolyline(vp, subj.isClosed, allocator);
        try newP.append(allocator, fit.pts); try newC.append(allocator, fit.isCurves);
    }
    return ShapeNode{ .pts = try newP.toOwnedSlice(allocator), .isCurves = try newC.toOwnedSlice(allocator), .color = subj.color, .strokeColor = subj.strokeColor, .thickness = subj.thickness, .isClosed = subj.isClosed, .clipRect = subj.clipRect };
}

// ── Error mapping helper ──

fn mapClipperErr(err: clipper.ClipperError) ShapeError {
    if (err == error.Failed) return error.Failed;
    if (err == error.TooSmall) return error.TooSmall;
    if (err == error.LengthMismatch) return error.Length_Mismatch;
    if (err == error.OutOfMemory) return error.OutOfMemory;
    unreachable;
}
