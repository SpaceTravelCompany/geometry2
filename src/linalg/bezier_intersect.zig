//! bezier_intersect.zig — Odin `linalg_ex/bezier_intersect.odin` 1:1 포팅.
//! 베지어 곡선 교차 검사 (빠른 AABB + 느린 Sederberg-Nishita),
//! AABB, 점 포함 판정, parameter-from-point 등.

const std = @import("std");
const linalg = @import("linalg.zig");
const bezier_mod = @import("bezier.zig");
const lines = @import("lines.zig");
const rect_mod = @import("rect.zig");

const Vec2 = linalg.Vec2;
const epsilon = linalg.epsilon;
const subdivLine = lines.subdivLine;
const subdivQuadraticBezier = lines.subdivQuadraticBezier;
const subdivCubicBezier = lines.subdivCubicBezier;
const evalBezier = bezier_mod.evalBezier;
const evalBezierTangent = bezier_mod.evalBezierTangent;
pub const BezierKind = bezier_mod.BezierKind;
const PointInPolygonResult = rect_mod.PointInPolygonResult;
const Rect = rect_mod.Rect;

// ──────────────────────────────────────────────────────────────────────
//  상수
// ──────────────────────────────────────────────────────────────────────

pub const MaxBezierIntersections: usize = 9;
const DEPTH_LIMIT: usize = 20;

// ──────────────────────────────────────────────────────────────────────
//  _rootEps
// ──────────────────────────────────────────────────────────────────────

inline fn _rootEps(comptime T: type) T {
    return switch (T) {
        f64 => 1e-12,
        else => 1e-6,
    };
}

// ──────────────────────────────────────────────────────────────────────
//  _addUnitRoot
// ──────────────────────────────────────────────────────────────────────

fn _addUnitRoot(comptime T: type, roots: *[4]T, count: *usize, root: T) void {
    const eps = _rootEps(T);
    if (root < -eps or root > 1 + eps or count.* >= 4) return;
    const r = std.math.clamp(root, 0, 1);
    for (0..count.*) |i| {
        if (@abs(roots[i] - r) <= eps) return;
    }
    roots[count.*] = r;
    count.* += 1;
}

// ──────────────────────────────────────────────────────────────────────
//  _solveLinearUnit
// ──────────────────────────────────────────────────────────────────────

fn _solveLinearUnit(comptime T: type, roots: *[4]T, count: *usize, b: T, c: T) void {
    const eps = _rootEps(T);
    if (@abs(b) <= eps) return;
    _addUnitRoot(T, roots, count, -c / b);
}

// ──────────────────────────────────────────────────────────────────────
//  _solveQuadraticUnit
// ──────────────────────────────────────────────────────────────────────

fn _solveQuadraticUnit(comptime T: type, roots: *[4]T, count: *usize, a: T, b: T, c: T) void {
    const eps = _rootEps(T);
    if (@abs(a) <= eps) {
        _solveLinearUnit(T, roots, count, b, c);
        return;
    }
    const disc = b * b - 4 * a * c;
    if (disc < -eps) return;
    if (@abs(disc) <= eps) {
        _addUnitRoot(T, roots, count, -b / (2 * a));
        return;
    }
    const s = @sqrt(disc);
    _addUnitRoot(T, roots, count, (-b - s) / (2 * a));
    _addUnitRoot(T, roots, count, (-b + s) / (2 * a));
}

// ──────────────────────────────────────────────────────────────────────
//  _solveCubicUnit
// ──────────────────────────────────────────────────────────────────────

fn _solveCubicUnit(comptime T: type, roots: *[4]T, count: *usize, a: T, b: T, c: T, d: T) void {
    const eps = _rootEps(T);
    if (@abs(a) <= eps) {
        _solveQuadraticUnit(T, roots, count, b, c, d);
        return;
    }

    const aa = b / a;
    const bb = c / a;
    const cc = d / a;
    const p = bb - aa * aa / 3;
    const q = 2 * aa * aa * aa / 27 - aa * bb / 3 + cc;
    const disc = q * q / 4 + p * p * p / 27;
    const shift = aa / 3;

    if (disc > eps) {
        const s = @sqrt(disc);
        const u = std.math.cbrt(-q / 2 + s);
        const v = std.math.cbrt(-q / 2 - s);
        _addUnitRoot(T, roots, count, u + v - shift);
        return;
    }

    if (@abs(disc) <= eps) {
        const u = std.math.cbrt(-q / 2);
        _addUnitRoot(T, roots, count, 2 * u - shift);
        _addUnitRoot(T, roots, count, -u - shift);
        return;
    }

    if (p >= 0) return;
    const r = 2 * @sqrt(-p / 3);
    var arg = (3 * q / (2 * p)) * @sqrt(-3 / p);
    arg = std.math.clamp(arg, -1, 1);
    const theta = std.math.acos(arg) / 3;
    const tau = std.math.tau;
    for (0..3) |k| {
        _addUnitRoot(T, roots, count, r * @cos(theta - tau * @as(T, @floatFromInt(k)) / 3) - shift);
    }
}

// ──────────────────────────────────────────────────────────────────────
//  _lineTForPoint
// ──────────────────────────────────────────────────────────────────────

fn _lineTForPoint(comptime T: type, line: [4]Vec2(T), p: Vec2(T)) T {
    const dx = line[1].x - line[0].x;
    const dy = line[1].y - line[0].y;
    const den = dx * dx + dy * dy;
    if (den <= _rootEps(T)) return 0;
    return ((p.x - line[0].x) * dx + (p.y - line[0].y) * dy) / den;
}

// ──────────────────────────────────────────────────────────────────────
//  _addLineCurveHit
// ──────────────────────────────────────────────────────────────────────

fn _addLineCurveHit(
    comptime T: type,
    line: [4]Vec2(T),
    curveKind: BezierKind,
    curve: [4]Vec2(T),
    tCurve: T,
    count: *usize,
    ips: *[MaxBezierIntersections]Vec2(T),
    tLineOut: *[MaxBezierIntersections]T,
    tCurveOut: *[MaxBezierIntersections]T,
) void {
    if (count.* >= MaxBezierIntersections) return;
    const eps = _rootEps(T);
    const p = evalBezier(T, curveKind, curve, std.math.clamp(tCurve, 0, 1));
    const tLine = _lineTForPoint(T, line, p);
    if (tLine < -eps or tLine > 1 + eps) return;
    const tLineClamped = std.math.clamp(tLine, 0, 1);
    const tCurveClamped = std.math.clamp(tCurve, 0, 1);
    for (0..count.*) |i| {
        if (@abs(tLineOut[i] - tLineClamped) <= eps and @abs(tCurveOut[i] - tCurveClamped) <= eps) return;
    }
    ips[count.*] = p;
    tLineOut[count.*] = tLineClamped;
    tCurveOut[count.*] = tCurveClamped;
    count.* += 1;
}

// ──────────────────────────────────────────────────────────────────────
//  _lineCurveIntersections
// ──────────────────────────────────────────────────────────────────────

fn _lineCurveIntersections(
    comptime T: type,
    line: [4]Vec2(T),
    curveKind: BezierKind,
    curve: [4]Vec2(T),
) struct { usize, [MaxBezierIntersections]Vec2(T), [MaxBezierIntersections]T, [MaxBezierIntersections]T } {
    var count: usize = 0;
    var ips: [MaxBezierIntersections]Vec2(T) = undefined;
    var tLineOut: [MaxBezierIntersections]T = undefined;
    var tCurveOut: [MaxBezierIntersections]T = undefined;

    const dx = line[1].x - line[0].x;
    const dy = line[1].y - line[0].y;
    if (@abs(dx) <= _rootEps(T) and @abs(dy) <= _rootEps(T)) return .{ count, ips, tLineOut, tCurveOut };

    var dist: [4]T = undefined;
    const n = bezierOrder(curveKind) - 1;
    for (0..n + 1) |i| {
        dist[i] = (curve[i].x - line[0].x) * dy - (curve[i].y - line[0].y) * dx;
    }

    var roots: [4]T = undefined;
    var rootCount: usize = 0;
    switch (curveKind) {
        .Line => {
            _solveLinearUnit(T, &roots, &rootCount, dist[1] - dist[0], dist[0]);
        },
        .Quad => {
            const a = dist[0] - 2 * dist[1] + dist[2];
            const b = 2 * (dist[1] - dist[0]);
            const c = dist[0];
            _solveQuadraticUnit(T, &roots, &rootCount, a, b, c);
        },
        .Cubic => {
            const a = -dist[0] + 3 * dist[1] - 3 * dist[2] + dist[3];
            const b = 3 * dist[0] - 6 * dist[1] + 3 * dist[2];
            const c = -3 * dist[0] + 3 * dist[1];
            const d = dist[0];
            _solveCubicUnit(T, &roots, &rootCount, a, b, c, d);
        },
    }

    for (0..rootCount) |i| {
        _addLineCurveHit(T, line, curveKind, curve, roots[i], &count, &ips, &tLineOut, &tCurveOut);
    }
    return .{ count, ips, tLineOut, tCurveOut };
}

// ──────────────────────────────────────────────────────────────────────
//  bezierOrder
// ──────────────────────────────────────────────────────────────────────

pub fn bezierOrder(kind: BezierKind) usize {
    return switch (kind) {
        .Line => 2,
        .Quad => 3,
        .Cubic => 4,
    };
}

// ──────────────────────────────────────────────────────────────────────
//  _splitHalf
// ──────────────────────────────────────────────────────────────────────

fn _splitHalf(comptime T: type, kind: BezierKind, pts: [4]Vec2(T)) struct { [4]Vec2(T), [4]Vec2(T) } {
    const half: T = 0.5;
    const zero = Vec2(T){ .x = 0, .y = 0 };
    switch (kind) {
        .Line => {
            const mid = subdivLine(T, .{ pts[0], pts[1] }, half);
            return .{
                .{ pts[0], mid, zero, zero },
                .{ mid, pts[1], zero, zero },
            };
        },
        .Quad => {
            const p01, const m, const p12 = subdivQuadraticBezier(T, .{ pts[0], pts[1], pts[2] }, half);
            return .{
                .{ pts[0], p01, m, zero },
                .{ m, p12, pts[2], zero },
            };
        },
        .Cubic => {
            const c0, const c1, const m, const d0, const d1 = subdivCubicBezier(T, pts, half);
            return .{
                .{ pts[0], c0, c1, m },
                .{ m, d0, d1, pts[3] },
            };
        },
    }
}

// ──────────────────────────────────────────────────────────────────────
//  _distToBaseline
// ──────────────────────────────────────────────────────────────────────

inline fn _distToBaseline(comptime T: type, px: T, py: T, ax: T, ay: T, dx: T, dy: T) T {
    return (px - ax) * dy - (py - ay) * dx;
}

// ──────────────────────────────────────────────────────────────────────
//  _clipHull
// ──────────────────────────────────────────────────────────────────────

fn _clipHull(comptime T: type, d: [4]T, n: usize, dMin: T, dMax: T) struct { T, T } {
    const one: T = 1;
    const zero: T = 0;
    var tLo: T = one;
    var tHi: T = zero;

    for (0..n + 1) |i| {
        if (d[i] >= dMin and d[i] <= dMax) {
            const ti = @as(T, @floatFromInt(i)) / @as(T, @floatFromInt(n));
            if (ti < tLo) tLo = ti;
            if (ti > tHi) tHi = ti;
        }
    }

    for (0..n) |i| {
        for (i + 1..n + 1) |j| {
            const ti = @as(T, @floatFromInt(i)) / @as(T, @floatFromInt(n));
            const tj = @as(T, @floatFromInt(j)) / @as(T, @floatFromInt(n));
            const dd = d[j] - d[i];
            if (dd == zero) continue;
            const dt = tj - ti;

            if ((d[i] < dMin) != (d[j] < dMin)) {
                const tc = ti + (dMin - d[i]) / dd * dt;
                if (tc >= zero and tc <= one) {
                    if (tc < tLo) tLo = tc;
                    if (tc > tHi) tHi = tc;
                }
            }
            if ((d[i] > dMax) != (d[j] > dMax)) {
                const tc = ti + (dMax - d[i]) / dd * dt;
                if (tc >= zero and tc <= one) {
                    if (tc < tLo) tLo = tc;
                    if (tc > tHi) tHi = tc;
                }
            }
        }
    }

    return .{ tLo, tHi };
}

// ──────────────────────────────────────────────────────────────────────
//  _BezClipWork
// ──────────────────────────────────────────────────────────────────────

fn _BezClipWorkType(comptime T: type) type {
    return struct {
        a: [4]Vec2(T),
        b: [4]Vec2(T),
        kindA: BezierKind,
        kindB: BezierKind,
        aLo: T,
        aHi: T,
        bLo: T,
        bHi: T,
        swapped: bool,
    };
}

// ──────────────────────────────────────────────────────────────────────
//  _extractSub
// ──────────────────────────────────────────────────────────────────────

fn _extractSub(comptime T: type, kind: BezierKind, pts: [4]Vec2(T), tLo: T, tHi: T) [4]Vec2(T) {
    const one: T = 1;
    const zero: T = 0;
    const zero_v = Vec2(T){ .x = 0, .y = 0 };
    var result = pts;

    if (tLo > zero) {
        switch (kind) {
            .Line => {
                const p = subdivLine(T, .{ pts[0], pts[1] }, tLo);
                result = .{ p, pts[1], zero_v, zero_v };
            },
            .Quad => {
                const _x0, const m, const p12 = subdivQuadraticBezier(T, .{ pts[0], pts[1], pts[2] }, tLo);
                _ = _x0;
                result = .{ m, p12, pts[2], zero_v };
            },
            .Cubic => {
                const _x0, const _x1, const m, const d0, const d1 = subdivCubicBezier(T, pts, tLo);
                _ = .{ _x0, _x1 };
                result = .{ m, d0, d1, pts[3] };
            },
        }
    }

    const denom = one - tLo;
    if (denom <= zero) return result;
    const tAdj = (tHi - tLo) / denom;
    if (tAdj >= one) return result;

    switch (kind) {
        .Line => {
            const p = subdivLine(T, .{ result[0], result[1] }, tAdj);
            result[1] = p;
        },
        .Quad => {
            const p01, const m, const _discard = subdivQuadraticBezier(T, .{ result[0], result[1], result[2] }, tAdj);
            _ = _discard;
            result = .{ result[0], p01, m, zero_v };
        },
        .Cubic => {
            const c0, const c1, const m, const _discard0, const _discard1 = subdivCubicBezier(T, result, tAdj);
            _ = .{ _discard0, _discard1 };
            result = .{ result[0], c0, c1, m };
        },
    }
    return result;
}

// ──────────────────────────────────────────────────────────────────────
//  _linesFromBezier
// ──────────────────────────────────────────────────────────────────────

fn _linesFromBezier(comptime T: type, kind: BezierKind, pts: [4]Vec2(T)) struct { Vec2(T), Vec2(T) } {
    const o = bezierOrder(kind);
    return .{ pts[0], pts[o - 1] };
}

// ──────────────────────────────────────────────────────────────────────
//  _controlPointAABB
// ──────────────────────────────────────────────────────────────────────

fn _controlPointAABB(comptime T: type, kind: BezierKind, pts: [4]Vec2(T)) struct { T, T, T, T } {
    const n = bezierOrder(kind);
    var minX: T = pts[0].x;
    var maxX: T = pts[0].x;
    var minY: T = pts[0].y;
    var maxY: T = pts[0].y;
    for (1..n) |i| {
        if (pts[i].x < minX) minX = pts[i].x;
        if (pts[i].x > maxX) maxX = pts[i].x;
        if (pts[i].y < minY) minY = pts[i].y;
        if (pts[i].y > maxY) maxY = pts[i].y;
    }
    return .{ minX, minY, maxX, maxY };
}

// ──────────────────────────────────────────────────────────────────────
//  _segIntersectParams
// ──────────────────────────────────────────────────────────────────────

fn _segIntersectParams(comptime T: type, a0: Vec2(T), a1: Vec2(T), b0: Vec2(T), b1: Vec2(T)) struct { T, T, Vec2(T), bool } {
    const den = (b1.y - b0.y) * (a1.x - a0.x) - (b1.x - b0.x) * (a1.y - a0.y);
    if (den == 0) return .{ 0, 0, Vec2(T){ .x = 0, .y = 0 }, false };
    const ua = ((b1.x - b0.x) * (a0.y - b0.y) - (b1.y - b0.y) * (a0.x - b0.x)) / den;
    const ub = ((a1.x - a0.x) * (a0.y - b0.y) - (a1.y - a0.y) * (a0.x - b0.x)) / den;
    if (ua < 0 or ua > 1 or ub < 0 or ub > 1) return .{ 0, 0, Vec2(T){ .x = 0, .y = 0 }, false };
    return .{ ua, ub, Vec2(T){ .x = a0.x + ua * (a1.x - a0.x), .y = a0.y + ua * (a1.y - a0.y) }, true };
}

// ──────────────────────────────────────────────────────────────────────
//  _lineLineIntersection
// ──────────────────────────────────────────────────────────────────────

fn _lineLineIntersection(comptime T: type, a: [4]Vec2(T), b: [4]Vec2(T)) struct { usize, [MaxBezierIntersections]Vec2(T), [MaxBezierIntersections]T, [MaxBezierIntersections]T } {
    var count: usize = 0;
    var ips: [MaxBezierIntersections]Vec2(T) = undefined;
    var tAs: [MaxBezierIntersections]T = undefined;
    var tBs: [MaxBezierIntersections]T = undefined;

    const tA, const tB, const p, const hit = _segIntersectParams(T, a[0], a[1], b[0], b[1]);
    if (!hit) return .{ count, ips, tAs, tBs };
    ips[0] = p;
    tAs[0] = tA;
    tBs[0] = tB;
    count = 1;
    return .{ count, ips, tAs, tBs };
}

// ──────────────────────────────────────────────────────────────────────
//  _isFlat
// ──────────────────────────────────────────────────────────────────────

fn _isFlat(comptime T: type, kind: BezierKind, pts: [4]Vec2(T), tol2: T) bool {
    if (kind == .Line) return true;
    const n = bezierOrder(kind);
    const a = pts[0];
    const b = pts[n - 1];
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len2 = dx * dx + dy * dy;
    if (len2 <= tol2) return true;
    for (1..n - 1) |i| {
        const px = pts[i].x - a.x;
        const py = pts[i].y - a.y;
        const cr = px * dy - py * dx;
        if (cr * cr > tol2 * len2) return false;
        const dot = px * dx + py * dy;
        if (dot < 0 or dot > len2) return false;
    }
    return true;
}

// ──────────────────────────────────────────────────────────────────────
//  _addCurveHit
// ──────────────────────────────────────────────────────────────────────

fn _addCurveHit(
    comptime T: type,
    count: *usize,
    ips: *[MaxBezierIntersections]Vec2(T),
    tAs: *[MaxBezierIntersections]T,
    tBs: *[MaxBezierIntersections]T,
    p: Vec2(T),
    tA: T,
    tB: T,
) void {
    const dedupEps: T = 1e-4;
    for (0..count.*) |i| {
        if (@abs(tAs[i] - tA) <= dedupEps and @abs(tBs[i] - tB) <= dedupEps) return;
    }
    if (count.* >= MaxBezierIntersections) return;
    ips[count.*] = p;
    tAs[count.*] = tA;
    tBs[count.*] = tB;
    count.* += 1;
}

// ──────────────────────────────────────────────────────────────────────
//  _intersectRecursive
// ──────────────────────────────────────────────────────────────────────

fn _intersectRecursive(
    comptime T: type,
    kindA: BezierKind, aIn: [4]Vec2(T), aLo: T, aHi: T,
    kindB: BezierKind, bIn: [4]Vec2(T), bLo: T, bHi: T,
    flatTol2: T,
    count: *usize, ips: *[MaxBezierIntersections]Vec2(T), tAs: *[MaxBezierIntersections]T, tBs: *[MaxBezierIntersections]T,
    depth: usize,
) void {
    if (count.* >= MaxBezierIntersections) return;

    // AABB overlap 체크
    const aMinX, const aMinY, const aMaxX, const aMaxY = _controlPointAABB(T, kindA, aIn);
    const bMinX, const bMinY, const bMaxX, const bMaxY = _controlPointAABB(T, kindB, bIn);
    if (aMaxX < bMinX or bMaxX < aMinX or aMaxY < bMinY or bMaxY < aMinY) return;

    // 양쪽 모두 충분히 평탄하면 chord-chord 교차로 종료
    if (depth >= DEPTH_LIMIT or (_isFlat(T, kindA, aIn, flatTol2) and _isFlat(T, kindB, bIn, flatTol2))) {
        const la0, const la1 = _linesFromBezier(T, kindA, aIn);
        const lb0, const lb1 = _linesFromBezier(T, kindB, bIn);
        const tA, const tB, const p, const hit = _segIntersectParams(T, la0, la1, lb0, lb1);
        if (hit) {
            _addCurveHit(T, count, ips, tAs, tBs, p, aLo + tA * (aHi - aLo), bLo + tB * (bHi - bLo));
        }
        return;
    }

    // 더 큰 AABB 쪽을 subdivision
    const aDiag = (aMaxX - aMinX) * (aMaxX - aMinX) + (aMaxY - aMinY) * (aMaxY - aMinY);
    const bDiag = (bMaxX - bMinX) * (bMaxX - bMinX) + (bMaxY - bMinY) * (bMaxY - bMinY);
    if (bDiag > aDiag) {
        const bLeft, const bRight = _splitHalf(T, kindB, bIn);
        const bMid = (bLo + bHi) / 2;
        _intersectRecursive(T, kindA, aIn, aLo, aHi, kindB, bLeft, bLo, bMid, flatTol2, count, ips, tAs, tBs, depth + 1);
        _intersectRecursive(T, kindA, aIn, aLo, aHi, kindB, bRight, bMid, bHi, flatTol2, count, ips, tAs, tBs, depth + 1);
    } else {
        const aLeft, const aRight = _splitHalf(T, kindA, aIn);
        const aMid = (aLo + aHi) / 2;
        _intersectRecursive(T, kindA, aLeft, aLo, aMid, kindB, bIn, bLo, bHi, flatTol2, count, ips, tAs, tBs, depth + 1);
        _intersectRecursive(T, kindA, aRight, aMid, aHi, kindB, bIn, bLo, bHi, flatTol2, count, ips, tAs, tBs, depth + 1);
    }
}

// ──────────────────────────────────────────────────────────────────────
//  GetBezierIntersectPt (빠른 버전)
// ──────────────────────────────────────────────────────────────────────

pub fn getBezierIntersectPt(
    comptime T: type,
    kindA: BezierKind,
    aIn: [4]Vec2(T),
    kindB: BezierKind,
    bIn: [4]Vec2(T),
) struct { usize, [MaxBezierIntersections]Vec2(T), [MaxBezierIntersections]T, [MaxBezierIntersections]T } {
    var count: usize = 0;
    var ips: [MaxBezierIntersections]Vec2(T) = undefined;
    var tAs: [MaxBezierIntersections]T = undefined;
    var tBs: [MaxBezierIntersections]T = undefined;

    if (kindA == .Line) {
        if (kindB == .Line) return _lineLineIntersection(T, aIn, bIn);
        return _lineCurveIntersections(T, aIn, kindB, bIn);
    }
    if (kindB == .Line) {
        const c, const ips2, const tLine, const tCurve = _lineCurveIntersections(T, bIn, kindA, aIn);
        count = c;
        ips = ips2;
        tAs = tCurve;
        tBs = tLine;
        return .{ count, ips, tAs, tBs };
    }

    // flatness 허용 오차: 입력 스케일 대비 상대값
    const aMinX, const aMinY, const aMaxX, const aMaxY = _controlPointAABB(T, kindA, aIn);
    const bMinX, const bMinY, const bMaxX, const bMaxY = _controlPointAABB(T, kindB, bIn);
    const scale = @max(@max(@max(aMaxX - aMinX, aMaxY - aMinY), bMaxX - bMinX), bMaxY - bMinY);
    const flatTol = scale * @as(T, 1e-6);
    _intersectRecursive(T, kindA, aIn, 0, 1, kindB, bIn, 0, 1, flatTol * flatTol, &count, &ips, &tAs, &tBs, 0);
    return .{ count, ips, tAs, tBs };
}

// ──────────────────────────────────────────────────────────────────────
//  GetBezierIntersectPtSlow (Sederberg-Nishita Bézier Clipping)
// ──────────────────────────────────────────────────────────────────────

pub fn getBezierIntersectPtSlow(
    comptime T: type,
    kindA: BezierKind,
    aIn: [4]Vec2(T),
    kindB: BezierKind,
    bIn: [4]Vec2(T),
) struct { usize, [MaxBezierIntersections]Vec2(T), [MaxBezierIntersections]T, [MaxBezierIntersections]T } {
    var count: usize = 0;
    var ips: [MaxBezierIntersections]Vec2(T) = undefined;
    var tAs: [MaxBezierIntersections]T = undefined;
    var tBs: [MaxBezierIntersections]T = undefined;

    if (kindA == .Line) {
        const c, const ips2, const tL, const tC = _lineCurveIntersections(T, aIn, kindB, bIn);
        count = c;
        ips = ips2;
        tAs = tL;
        tBs = tC;
        return .{ count, ips, tAs, tBs };
    }
    if (kindB == .Line) {
        const c, const ips2, const tL, const tC = _lineCurveIntersections(T, bIn, kindA, aIn);
        count = c;
        ips = ips2;
        tAs = tC;
        tBs = tL;
        return .{ count, ips, tAs, tBs };
    }

    const one: T = 1;
    const zero: T = 0;
    const eps = epsilon(T);
    const epsHit = eps * 10;
    const fourFifth: T = 0.8;

    const Work = _BezClipWorkType(T);
    const stack_allocator = std.heap.page_allocator;
    var stack: std.ArrayList(Work) = .empty;
    defer stack.deinit(stack_allocator);

    stack.append(stack_allocator, Work{
        .a = aIn,
        .b = bIn,
        .kindA = kindA,
        .kindB = kindB,
        .aLo = zero,
        .aHi = one,
        .bLo = zero,
        .bHi = one,
        .swapped = false,
    }) catch unreachable;

    while (stack.items.len > 0) {
        // `while` 불변식 (`stack.items.len > 0`)에 의해 `pop()`은 절대 `null`을
        // 반환하지 않으므로 `orelse unreachable`로 안전하게 unwrap한다.
        const w = stack.pop() orelse unreachable;

        const aRange = w.aHi - w.aLo;
        const bRange = w.bHi - w.bLo;

        if (aRange <= eps and bRange <= eps) {
            const na = bezierOrder(w.kindA) - 1;
            const ip = Vec2(T){
                .x = (w.a[0].x + w.a[na].x) * 0.5,
                .y = (w.a[0].y + w.a[na].y) * 0.5,
            };
            const tA: T = if (!w.swapped)
                (w.aLo + w.aHi) * 0.5
            else
                (w.bLo + w.bHi) * 0.5;
            const tB: T = if (!w.swapped)
                (w.bLo + w.bHi) * 0.5
            else
                (w.aLo + w.aHi) * 0.5;

            var isDup = false;
            for (0..count) |i| {
                if (@abs(tAs[i] - tA) <= epsHit and @abs(tBs[i] - tB) <= epsHit) {
                    isDup = true;
                    break;
                }
            }
            if (!isDup and count < MaxBezierIntersections) {
                ips[count] = ip;
                tAs[count] = tA;
                tBs[count] = tB;
                count += 1;
            }
            continue;
        }

        const na = bezierOrder(w.kindA) - 1;
        const ax = w.a[0].x;
        const ay = w.a[0].y;
        const dx = w.a[na].x - ax;
        const dy = w.a[na].y - ay;

        if (dx == zero and dy == zero) continue;

        var dMin: T = zero;
        var dMax: T = zero;
        for (1..na) |i| {
            const d = (w.a[i].x - ax) * dy - (w.a[i].y - ay) * dx;
            if (d < dMin) dMin = d;
            if (d > dMax) dMax = d;
        }

        const nb = bezierOrder(w.kindB) - 1;
        var db: [4]T = undefined;
        for (0..nb + 1) |i| {
            db[i] = (w.b[i].x - ax) * dy - (w.b[i].y - ay) * dx;
        }

        const clipLo, const clipHi = _clipHull(T, db, nb, dMin, dMax);
        if (clipLo > clipHi) continue;

        const clipLoClamped: T = if (clipLo < zero) zero else clipLo;
        const clipHiClamped: T = if (clipHi > one) one else clipHi;

        const bSpan = w.bHi - w.bLo;
        const newBLo = w.bLo + clipLoClamped * bSpan;
        const newBHi = w.bLo + clipHiClamped * bSpan;
        const bClipped = _extractSub(T, w.kindB, w.b, clipLoClamped, clipHiClamped);

        const clipRange = clipHiClamped - clipLoClamped;

        if (clipRange > fourFifth) {
            if (aRange >= bRange) {
                const aLeft, const aRight = _splitHalf(T, w.kindA, w.a);
                const aMid = (w.aLo + w.aHi) * 0.5;
                stack.append(stack_allocator, Work{
                    .a = bClipped,
                    .b = aLeft,
                    .kindA = w.kindB,
                    .kindB = w.kindA,
                    .aLo = newBLo,
                    .aHi = newBHi,
                    .bLo = w.aLo,
                    .bHi = aMid,
                    .swapped = !w.swapped,
                }) catch unreachable;
                stack.append(stack_allocator, Work{
                    .a = bClipped,
                    .b = aRight,
                    .kindA = w.kindB,
                    .kindB = w.kindA,
                    .aLo = newBLo,
                    .aHi = newBHi,
                    .bLo = aMid,
                    .bHi = w.aHi,
                    .swapped = !w.swapped,
                }) catch unreachable;
            } else {
                const bLeft, const bRight = _splitHalf(T, w.kindB, bClipped);
                const bMid = (newBLo + newBHi) * 0.5;
                stack.append(stack_allocator, Work{
                    .a = bLeft,
                    .b = w.a,
                    .kindA = w.kindB,
                    .kindB = w.kindA,
                    .aLo = newBLo,
                    .aHi = bMid,
                    .bLo = w.aLo,
                    .bHi = w.aHi,
                    .swapped = !w.swapped,
                }) catch unreachable;
                stack.append(stack_allocator, Work{
                    .a = bRight,
                    .b = w.a,
                    .kindA = w.kindB,
                    .kindB = w.kindA,
                    .aLo = bMid,
                    .aHi = newBHi,
                    .bLo = w.aLo,
                    .bHi = w.aHi,
                    .swapped = !w.swapped,
                }) catch unreachable;
            }
        } else {
            stack.append(stack_allocator, Work{
                .a = bClipped,
                .b = w.a,
                .kindA = w.kindB,
                .kindB = w.kindA,
                .aLo = newBLo,
                .aHi = newBHi,
                .bLo = w.aLo,
                .bHi = w.aHi,
                .swapped = !w.swapped,
            }) catch unreachable;
        }
    }

    return .{ count, ips, tAs, tBs };
}

// ──────────────────────────────────────────────────────────────────────
//  GetBezierTFromPoint
// ──────────────────────────────────────────────────────────────────────

pub fn getBezierTFromPoint(comptime T: type, kind: BezierKind, pts: [4]Vec2(T), point: Vec2(T)) struct { T, bool } {
    const zero: T = 0;
    const one: T = 1;
    var lo: T = zero;
    var hi: T = one;

    const eps = epsilon(T) * 16;
    for (0..64) |_| {
        const mid = (lo + hi) / 2;
        const p = evalBezier(T, kind, pts, mid);
        const diffX = p.x - point.x;
        const diffY = p.y - point.y;
        if (@abs(diffX) <= eps and @abs(diffY) <= eps) {
            return .{ mid, true };
        }

        // Use tangent direction to choose the next half interval.
        const tangent = evalBezierTangent(T, kind, pts, mid);
        if (tangent.x * diffX + tangent.y * diffY > zero) {
            hi = mid;
        } else {
            lo = mid;
        }
    }

    const mid = (lo + hi) / 2;
    const p = evalBezier(T, kind, pts, mid);
    const diffX = p.x - point.x;
    const diffY = p.y - point.y;
    if (@abs(diffX) <= eps and @abs(diffY) <= eps) {
        return .{ mid, true };
    }

    return .{ zero, false };
}

// ──────────────────────────────────────────────────────────────────────
//  EvalBezier — bezier.zig의 evalBezier에 위임 (재구현 금지)
// ──────────────────────────────────────────────────────────────────────

pub const EvalBezier = evalBezier;

// ──────────────────────────────────────────────────────────────────────
//  EvalBezierTangent — bezier.zig의 evalBezierTangent에 위임 (재구현 금지)
// ──────────────────────────────────────────────────────────────────────

pub const EvalBezierTangent = evalBezierTangent;

// ──────────────────────────────────────────────────────────────────────
//  GetBezierTForXMonotone
// ──────────────────────────────────────────────────────────────────────

pub fn getBezierTForXMonotone(comptime T: type, kind: BezierKind, pts: [4]T) struct { T, T } {
    if (kind == .Quad) {
        const x0 = pts[0];
        const x1 = pts[1];
        const x2 = pts[2];
        const A = 2 * (x1 - x0);
        const B = 2 * (x0 - 2 * x1 + x2);
        if (B == 0) return .{ -1, -1 };
        return .{ -A / B, -1 };
    } else if (kind == .Cubic) {
        const two: T = 2;
        const three: T = 3;
        const four: T = 4;
        const six: T = 6;
        const x0 = pts[0];
        const x1 = pts[1];
        const x2 = pts[2];
        const x3 = pts[3];
        const coefA = three * (three * x1 - x0 + x3 - three * x2);
        const coefB = six * (x0 - two * x1 + x2);
        const coefC = three * (x1 - x0);
        const zero: T = 0;
        const twoA = two * coefA;

        if (coefA == zero) {
            if (coefB == zero) return .{ -1, -1 };
            return .{ -coefC / coefB, -1 };
        }

        const D = coefB * coefB - four * coefA * coefC;
        if (D < zero) {
            return .{ -1, -1 };
        } else if (D == zero) {
            return .{ -coefB / twoA, -1 };
        }

        const sqrtD = @sqrt(D);
        const r0 = (-coefB - sqrtD) / twoA;
        const r1 = (-coefB + sqrtD) / twoA;
        return .{ @min(r0, r1), @max(r0, r1) };
    }
    return .{ -1, -1 };
}

// ──────────────────────────────────────────────────────────────────────
//  BezierAABB
// ──────────────────────────────────────────────────────────────────────

pub fn bezierAABB(comptime T: type, kind: BezierKind, pts: [4]Vec2(T)) Rect(T) {
    const n = bezierOrder(kind);
    const p0 = pts[0];
    const p1 = pts[n - 1];

    var minX: T = @min(p0.x, p1.x);
    var maxX: T = @max(p0.x, p1.x);
    var minY: T = @min(p0.y, p1.y);
    var maxY: T = @max(p0.y, p1.y);

    if (kind != .Line) {
        const xCoords = [_]T{ pts[0].x, pts[1].x, pts[2].x, pts[3].x };
        const yCoords = [_]T{ pts[0].y, pts[1].y, pts[2].y, pts[3].y };
        const tx0, const tx1 = getBezierTForXMonotone(T, kind, xCoords);
        const ty0, const ty1 = getBezierTForXMonotone(T, kind, yCoords);
        const t_vals = [_]T{ tx0, tx1, ty0, ty1 };
        for (t_vals) |t| {
            if (t <= 0 or t >= 1) continue;
            const pt = evalBezier(T, kind, pts, t);
            minX = @min(minX, pt.x);
            maxX = @max(maxX, pt.x);
            minY = @min(minY, pt.y);
            maxY = @max(maxY, pt.y);
        }
    }

    return Rect(T){ .left = minX, .right = maxX, .top = maxY, .bottom = minY };
}

// ──────────────────────────────────────────────────────────────────────
//  PointInCurvedPolygon
// ──────────────────────────────────────────────────────────────────────

pub fn pointInCurvedPolygon(
    comptime T: type,
    p: Vec2(T),
    edges: []const [4]Vec2(T),
    kinds: []const BezierKind,
) PointInPolygonResult {
    const n = edges.len;
    if (n < 3) return .Outside;

    const eps = _rootEps(T);

    const allocator = std.heap.page_allocator;
    const bboxes = allocator.alloc(Rect(T), n) catch {
        return .Outside;
    };
    defer allocator.free(bboxes);

    var maxRight: T = p.x;
    for (0..n) |i| {
        bboxes[i] = bezierAABB(T, kinds[i], edges[i]);
        if (bboxes[i].right > maxRight) maxRight = bboxes[i].right;
    }
    const FAR = maxRight + 100;

    const ray: [4]Vec2(T) = .{ p, Vec2(T){ .x = FAR, .y = p.y }, Vec2(T){ .x = 0, .y = 0 }, Vec2(T){ .x = 0, .y = 0 } };

    var crossing: usize = 0;
    for (0..n) |i| {
        const bbox = bboxes[i];
        if (p.y < bbox.bottom - eps or p.y > bbox.top + eps) continue;
        if (p.x > bbox.right) continue;

        const count, const ips, _, _ = getBezierIntersectPt(T, .Line, ray, kinds[i], edges[i]);

        for (0..count) |j| {
            const pt = ips[j];
            if (@abs(pt.x - p.x) <= eps and @abs(pt.y - p.y) <= eps) {
                return .On;
            }
            if (pt.x >= p.x) {
                crossing += 1;
            }
        }
    }

    return if (crossing % 2 == 1) .Inside else .Outside;
}

// ══════════════════════════════════════════════════════════════════════
//  테스트 (Odin 6개 1:1 변환)
// ══════════════════════════════════════════════════════════════════════

test "2quadCurves" {
    const pt0: [4]Vec2(f32) = .{
        Vec2(f32){ .x = 0.0, .y = 0.0 },
        Vec2(f32){ .x = 1.0, .y = 0.0 },
        Vec2(f32){ .x = 1.0, .y = -1.0 },
        Vec2(f32){ .x = 0.0, .y = 0.0 },
    };
    const pt1: [4]Vec2(f32) = .{
        Vec2(f32){ .x = 1.0, .y = 0.0 },
        Vec2(f32){ .x = 0.0, .y = 0.0 },
        Vec2(f32){ .x = 0.0, .y = -1.0 },
        Vec2(f32){ .x = 0.0, .y = 0.0 },
    };

    const count, const ips, const tAs, const tBs = getBezierIntersectPt(f32, .Quad, pt0, .Quad, pt1);

    try std.testing.expectEqual(@as(usize, 1), count);
    // Mirrored curves cross at x = 0.5 with t = 1 - sqrt(2)/2 on both.
    const expectedT: f32 = @floatCast(1.0 - std.math.sqrt2 / 2.0);
    try std.testing.expect(@abs(ips[0].x - 0.5) < 1e-4);
    try std.testing.expect(@abs(tAs[0] - expectedT) < 1e-3);
    try std.testing.expect(@abs(tAs[0] - tBs[0]) < 1e-4);
}

test "lineLineIntersect" {
    const a: [4]Vec2(f32) = .{
        Vec2(f32){ .x = 0, .y = 0 },
        Vec2(f32){ .x = 2, .y = 2 },
        Vec2(f32){ .x = 0, .y = 0 },
        Vec2(f32){ .x = 0, .y = 0 },
    };
    const b: [4]Vec2(f32) = .{
        Vec2(f32){ .x = 0, .y = 2 },
        Vec2(f32){ .x = 2, .y = 0 },
        Vec2(f32){ .x = 0, .y = 0 },
        Vec2(f32){ .x = 0, .y = 0 },
    };

    const count, const ips, const tAs, const tBs = getBezierIntersectPt(f32, .Line, a, .Line, b);

    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expect(@abs(ips[0].x - 1) < 1e-6);
    try std.testing.expect(@abs(ips[0].y - 1) < 1e-6);
    try std.testing.expect(@abs(tAs[0] - 0.5) < 1e-6);
    try std.testing.expect(@abs(tBs[0] - 0.5) < 1e-6);
}

test "lineQuadIntersect" {
    // y(t) = 4t(1-t), peaks at 1; line y = 0.5 crosses twice.
    const q: [4]Vec2(f32) = .{
        Vec2(f32){ .x = 0, .y = 0 },
        Vec2(f32){ .x = 1, .y = 2 },
        Vec2(f32){ .x = 2, .y = 0 },
        Vec2(f32){ .x = 0, .y = 0 },
    };
    const l: [4]Vec2(f32) = .{
        Vec2(f32){ .x = -1, .y = 0.5 },
        Vec2(f32){ .x = 3, .y = 0.5 },
        Vec2(f32){ .x = 0, .y = 0 },
        Vec2(f32){ .x = 0, .y = 0 },
    };

    const count, const ips, _, const tBs = getBezierIntersectPt(f32, .Line, l, .Quad, q);

    try std.testing.expectEqual(@as(usize, 2), count);
    for (0..count) |i| {
        try std.testing.expect(@abs(ips[i].y - 0.5) < 1e-5);
        // roots of 4t(1-t) = 0.5
        const r0: f32 = @floatCast(0.5 - std.math.sqrt2 / 4.0);
        const r1: f32 = @floatCast(0.5 + std.math.sqrt2 / 4.0);
        try std.testing.expect(@abs(tBs[i] - r0) < 1e-4 or @abs(tBs[i] - r1) < 1e-4);
    }
}

test "bezierExtremaT" {
    // Quad: x(t) extremum of {0, 2, 0} at t = 0.5
    const qt0, const qt1 = getBezierTForXMonotone(f32, .Quad, [_]f32{ 0, 2, 0, 0 });
    try std.testing.expect(@abs(qt0 - 0.5) < 1e-6);
    try std.testing.expectEqual(@as(f32, -1), qt1);

    // Cubic: x'(t) = 30t² - 30t + 6, roots 0.5 ± sqrt(180)/60
    const ct0, const ct1 = getBezierTForXMonotone(f32, .Cubic, [_]f32{ 0, 2, -1, 1 });
    try std.testing.expect(@abs(ct0 - 0.276393) < 1e-4);
    try std.testing.expect(@abs(ct1 - 0.723607) < 1e-4);

    // Cubic degenerating to quadratic derivative (coefA == 0): x(t) = 3t(1-t)
    const lt0, const lt1 = getBezierTForXMonotone(f32, .Cubic, [_]f32{ 0, 1, 1, 0 });
    try std.testing.expect(@abs(lt0 - 0.5) < 1e-6);
    try std.testing.expectEqual(@as(f32, -1), lt1);
}

test "bezierAABBQuad" {
    // Curve max y is 1 (control point at 2 lies outside the curve).
    const q: [4]Vec2(f32) = .{
        Vec2(f32){ .x = 0, .y = 0 },
        Vec2(f32){ .x = 1, .y = 2 },
        Vec2(f32){ .x = 2, .y = 0 },
        Vec2(f32){ .x = 0, .y = 0 },
    };
    const bbox = bezierAABB(f32, .Quad, q);
    try std.testing.expect(@abs(bbox.left - 0) < 1e-6);
    try std.testing.expect(@abs(bbox.right - 2) < 1e-6);
    try std.testing.expect(@abs(bbox.top - 1) < 1e-6);
    try std.testing.expect(@abs(bbox.bottom - 0) < 1e-6);
}

test "pointInCurvedPolygonSquare" {
    const edges = [_][4]Vec2(f32){
        .{ Vec2(f32){ .x = 0, .y = 0 }, Vec2(f32){ .x = 2, .y = 0 }, Vec2(f32){ .x = 0, .y = 0 }, Vec2(f32){ .x = 0, .y = 0 } },
        .{ Vec2(f32){ .x = 2, .y = 0 }, Vec2(f32){ .x = 2, .y = 2 }, Vec2(f32){ .x = 0, .y = 0 }, Vec2(f32){ .x = 0, .y = 0 } },
        .{ Vec2(f32){ .x = 2, .y = 2 }, Vec2(f32){ .x = 0, .y = 2 }, Vec2(f32){ .x = 0, .y = 0 }, Vec2(f32){ .x = 0, .y = 0 } },
        .{ Vec2(f32){ .x = 0, .y = 2 }, Vec2(f32){ .x = 0, .y = 0 }, Vec2(f32){ .x = 0, .y = 0 }, Vec2(f32){ .x = 0, .y = 0 } },
    };
    const kinds = [_]BezierKind{ .Line, .Line, .Line, .Line };

    try std.testing.expectEqual(PointInPolygonResult.Inside, pointInCurvedPolygon(f32, Vec2(f32){ .x = 1, .y = 1 }, &edges, &kinds));
    try std.testing.expectEqual(PointInPolygonResult.Outside, pointInCurvedPolygon(f32, Vec2(f32){ .x = 3, .y = 1 }, &edges, &kinds));
    try std.testing.expectEqual(PointInPolygonResult.On, pointInCurvedPolygon(f32, Vec2(f32){ .x = 2, .y = 1 }, &edges, &kinds));
}
