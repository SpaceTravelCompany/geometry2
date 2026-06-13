//! rect.zig — Rect_ type 및 Rect 연산.
//! Odin linalg_ex의 RectInit, CheckRect, RectMulMatrix, RectDivMatrix,
//! RectLeftTop, RectRightBottom, RectAnd, RectOr, RectPointIn, RectMove 대응.

const std = @import("std");
const linalg = @import("linalg.zig");
const Vec2 = linalg.Vec2;
const Vec2f32 = linalg.Vec2f32;
const Vec3f32 = linalg.Vec3f32;
const Vec4f32 = linalg.Vec4f32;
const Mat4x4f32 = linalg.Mat4x4f32;

// ──────────────────────────────────────────────────────────────────────
//  enum
// ──────────────────────────────────────────────────────────────────────

/// 중심/모서리 위치 지정용. 현재 일부 함수에서 사용.
pub const CenterPtPos = enum {
    Center,
    Left,
    Right,
    TopLeft,
    Top,
    TopRight,
    BottomLeft,
    Bottom,
    BottomRight,
};

/// 점-폴리곤 관계 결과.
pub const PointInPolygonResult = enum(u8) {
    On,
    Outside,
    Inside,
};

// ──────────────────────────────────────────────────────────────────────
//  Rect(T) 타입
// ──────────────────────────────────────────────────────────────────────

pub fn Rect(comptime T: type) type {
    return struct {
        left: T,
        right: T,
        top: T,
        bottom: T,
    };
}

pub const Rectf32 = Rect(f32);
pub const Recti32 = Rect(i32);
pub const Rectu32 = Rect(u32);

// ──────────────────────────────────────────────────────────────────────
//  RectInit
// ──────────────────────────────────────────────────────────────────────

pub inline fn rectInit(comptime T: type, left: T, right: T, top: T, bottom: T) Rect(T) {
    return Rect(T){ .left = left, .right = right, .top = top, .bottom = bottom };
}

// ──────────────────────────────────────────────────────────────────────
//  CheckRect — 네 점이 axis-aligned rectangle을 이루는지 검사
// ──────────────────────────────────────────────────────────────────────

pub inline fn checkRect(comptime T: type, comptime N: usize, _pts: [4][N]T) bool {
    return _pts[0][1] == _pts[1][1] and
        _pts[2][1] == _pts[3][1] and
        _pts[0][0] == _pts[2][0] and
        _pts[1][0] == _pts[3][0];
}

// ──────────────────────────────────────────────────────────────────────
//  __RectMulMatrix (내부 공개 — area.zig에서 사용)
// ──────────────────────────────────────────────────────────────────────

pub fn __rectMulMatrix(_r: Rectf32, _mat: Mat4x4f32) [4]Vec4f32 {
    const x0 = _r.left;
    const y0 = _r.top;
    const x1 = _r.right;
    const y1 = _r.bottom;

    const p0 = Vec4f32{ x0, y0, 0, 1 };
    const p1 = Vec4f32{ x1, y0, 0, 1 };
    const p2 = Vec4f32{ x0, y1, 0, 1 };
    const p3 = Vec4f32{ x1, y1, 0, 1 };

    const t0 = _mat.mulVec(p0);
    const t1 = _mat.mulVec(p1);
    const t2 = _mat.mulVec(p2);
    const t3 = _mat.mulVec(p3);

    // homogeneous divide
    var r0 = t0;
    var r1 = t1;
    var r2 = t2;
    var r3 = t3;
    if (r0[3] != 0) {
        r0[0] /= r0[3];
        r0[1] /= r0[3];
    }
    if (r1[3] != 0) {
        r1[0] /= r1[3];
        r1[1] /= r1[3];
    }
    if (r2[3] != 0) {
        r2[0] /= r2[3];
        r2[1] /= r2[3];
    }
    if (r3[3] != 0) {
        r3[0] /= r3[3];
        r3[1] /= r3[3];
    }

    return .{ r0, r1, r2, r3 };
}

// ──────────────────────────────────────────────────────────────────────
//  RectMulMatrix — Rectf32 × Mat4x4f32 → (Rectf32, bool)
// ──────────────────────────────────────────────────────────────────────

pub fn rectMulMatrix(_r: Rectf32, _mat: Mat4x4f32) struct { Rectf32, bool } {
    const tps = __rectMulMatrix(_r, _mat);

    if (checkRect(f32, 4, tps)) return .{ undefined, false };

    return .{
        Rectf32{ .left = tps[0][0], .right = tps[3][0], .top = tps[0][1], .bottom = tps[3][1] },
        true,
    };
}

// ──────────────────────────────────────────────────────────────────────
//  RectDivMatrix — Rectf32 / Mat4x4f32 = Rectf32 * inverse(M)
// ──────────────────────────────────────────────────────────────────────

pub fn rectDivMatrix(_r: Rectf32, _mat: Mat4x4f32) struct { Rectf32, bool } {
    return rectMulMatrix(_r, _mat.inverse());
}

// ──────────────────────────────────────────────────────────────────────
//  RectLeftTop, RectRightBottom
// ──────────────────────────────────────────────────────────────────────

pub inline fn rectLeftTop(comptime T: type, _r: Rect(T)) Vec2(T) {
    return Vec2(T){ .x = _r.left, .y = _r.top };
}

pub inline fn rectRightBottom(comptime T: type, _r: Rect(T)) Vec2(T) {
    return Vec2(T){ .x = _r.right, .y = _r.bottom };
}

// ──────────────────────────────────────────────────────────────────────
//  RectAnd — intersection
// ──────────────────────────────────────────────────────────────────────

pub inline fn rectAnd(comptime T: type, _r1: Rect(T), _r2: Rect(T)) Rect(T) {
    var res: Rect(T) = undefined;
    res.left = if (_r1.left > _r2.left) _r1.left else _r2.left;
    res.right = if (_r1.right < _r2.right) _r1.right else _r2.right;
    // Odin `return {}` 는 zero-initialized Rect 와 동등. Zig 도 동일하게 처리.
    if (res.right < res.left) return Rect(T){ .left = 0, .right = 0, .top = 0, .bottom = 0 };

    const r1Top: T = if (_r1.top > _r1.bottom) _r1.top else _r1.bottom;
    const r1Bottom: T = if (_r1.top < _r1.bottom) _r1.top else _r1.bottom;
    const r2Top: T = if (_r2.top > _r2.bottom) _r2.top else _r2.bottom;
    const r2Bottom: T = if (_r2.top < _r2.bottom) _r2.top else _r2.bottom;

    const yTop: T = if (r1Top < r2Top) r1Top else r2Top;
    const yBottom: T = if (r1Bottom > r2Bottom) r1Bottom else r2Bottom;

    if (_r1.top >= _r1.bottom) {
        res.top = yTop;
        res.bottom = yBottom;
    } else {
        res.top = yBottom;
        res.bottom = yTop;
    }
    return res;
}

// ──────────────────────────────────────────────────────────────────────
//  RectOr — union
// ──────────────────────────────────────────────────────────────────────

pub inline fn rectOr(comptime T: type, _r1: Rect(T), _r2: Rect(T)) Rect(T) {
    var res: Rect(T) = undefined;
    res.left = if (_r1.left < _r2.left) _r1.left else _r2.left;
    res.right = if (_r1.right > _r2.right) _r1.right else _r2.right;

    const r1Top: T = if (_r1.top > _r1.bottom) _r1.top else _r1.bottom;
    const r1Bottom: T = if (_r1.top < _r1.bottom) _r1.top else _r1.bottom;
    const r2Top: T = if (_r2.top > _r2.bottom) _r2.top else _r2.bottom;
    const r2Bottom: T = if (_r2.top < _r2.bottom) _r2.top else _r2.bottom;

    const yTop: T = if (r1Top > r2Top) r1Top else r2Top;
    const yBottom: T = if (r1Bottom < r2Bottom) r1Bottom else r2Bottom;

    if (_r1.top >= _r1.bottom) {
        res.top = yTop;
        res.bottom = yBottom;
    } else {
        res.top = yBottom;
        res.bottom = yTop;
    }

    return res;
}

// ──────────────────────────────────────────────────────────────────────
//  RectPointIn
// ──────────────────────────────────────────────────────────────────────

pub inline fn rectPointIn(comptime T: type, _r: Rect(T), p: Vec2(T)) bool {
    const inX = p.x >= _r.left and p.x <= _r.right;
    const inY = if (_r.top > _r.bottom)
        p.y <= _r.top and p.y >= _r.bottom
    else
        p.y >= _r.top and p.y <= _r.bottom;
    return inX and inY;
}

// ──────────────────────────────────────────────────────────────────────
//  RectMove
// ──────────────────────────────────────────────────────────────────────

pub inline fn rectMove(comptime T: type, _r: Rect(T), p: Vec2(T)) Rect(T) {
    return Rect(T){
        .left = _r.left + p.x,
        .top = _r.top + p.y,
        .right = _r.right + p.x,
        .bottom = _r.bottom + p.y,
    };
}
