//! matrix2d.zig — 2D 변환 행렬 생성 함수.
//! srtc2dMatrix, srt2dMatrix, st2dMatrix, rt2dMatrix, t2dMatrix,
//! src2dMatrix, sr2dMatrix, s2dMatrix, r2dMatrix, srt2dMatrix2, sr2dMatrix2.
//!
//! 모든 함수는 일반 4×4 곱셈 없이 닫힌 형태의 2D affine 공식을 사용한다.

const linalg = @import("linalg.zig");
const Vec2f32 = linalg.Vec2f32;
const Vec3f32 = linalg.Vec3f32;
const Mat4x4f32 = linalg.Mat4x4f32;

// ──────────────────────────────────────────────────────────────────────
//  srtc2dMatrix — scale + rotate + translate, 중심 pivot
//  닫힌 형태: T * R * S * translate(cp.x, cp.y, 0)
// ──────────────────────────────────────────────────────────────────────

pub fn srtc2dMatrix(t: Vec3f32, s: Vec2f32, r: f32, cp: Vec2f32) Mat4x4f32 {
    const c = @cos(r);
    const sn = @sin(r);
    const sx = s.x;
    const sy = s.y;
    const tx = t[0];
    const ty = t[1];
    const tz = t[2];
    const cpX = cp.x;
    const cpY = cp.y;
    return Mat4x4f32{ .data = .{
        .{ c * sx, sn * sx, 0, 0 },
        .{ -sn * sy, c * sy, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ tx + c * sx * cpX - sn * sy * cpY, ty + sn * sx * cpX + c * sy * cpY, tz, 1 },
    } };
}

// ──────────────────────────────────────────────────────────────────────
//  srt2dMatrix — T * R * S
// ──────────────────────────────────────────────────────────────────────

pub fn srt2dMatrix(t: Vec3f32, s: Vec2f32, r: f32) Mat4x4f32 {
    const c = @cos(r);
    const sn = @sin(r);
    return Mat4x4f32{ .data = .{
        .{ c * s.x, sn * s.x, 0, 0 },
        .{ -sn * s.y, c * s.y, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ t[0], t[1], t[2], 1 },
    } };
}

// ──────────────────────────────────────────────────────────────────────
//  st2dMatrix — T * S (scale 후 translate)
// ──────────────────────────────────────────────────────────────────────

pub fn st2dMatrix(t: Vec3f32, s: Vec2f32) Mat4x4f32 {
    var m = Mat4x4f32.scale(Vec3f32{ s.x, s.y, 1.0 });
    m.data[3][0] = t[0];
    m.data[3][1] = t[1];
    m.data[3][2] = t[2];
    return m;
}

// ──────────────────────────────────────────────────────────────────────
//  rt2dMatrix — T * R (rotate 후 translate)
// ──────────────────────────────────────────────────────────────────────

pub fn rt2dMatrix(t: Vec3f32, r: f32) Mat4x4f32 {
    var m = Mat4x4f32.rotateZ(r);
    m.data[3][0] = t[0];
    m.data[3][1] = t[1];
    m.data[3][2] = t[2];
    return m;
}

// ──────────────────────────────────────────────────────────────────────
//  t2dMatrix
// ──────────────────────────────────────────────────────────────────────

pub fn t2dMatrix(t: Vec3f32) Mat4x4f32 {
    return Mat4x4f32.translate(t);
}

// ──────────────────────────────────────────────────────────────────────
//  src2dMatrix — R * S * translate(cp.x, cp.y, 0)
//  빠른 경로: cp == (0,0) → sr2dMatrix (pivot 계산 생략)
// ──────────────────────────────────────────────────────────────────────

pub fn src2dMatrix(s: Vec2f32, r: f32, cp: Vec2f32) Mat4x4f32 {
    if (cp.x == 0.0 and cp.y == 0.0) return sr2dMatrix(s, r);
    const c = @cos(r);
    const sn = @sin(r);
    const sx = s.x;
    const sy = s.y;
    return Mat4x4f32{ .data = .{
        .{ c * sx, sn * sx, 0, 0 },
        .{ -sn * sy, c * sy, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ c * sx * cp.x - sn * sy * cp.y, sn * sx * cp.x + c * sy * cp.y, 0, 1 },
    } };
}

// ──────────────────────────────────────────────────────────────────────
//  sr2dMatrix — R * S
// ──────────────────────────────────────────────────────────────────────

pub fn sr2dMatrix(s: Vec2f32, r: f32) Mat4x4f32 {
    const c = @cos(r);
    const sn = @sin(r);
    return Mat4x4f32{ .data = .{
        .{ c * s.x, sn * s.x, 0, 0 },
        .{ -sn * s.y, c * s.y, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    } };
}

// ──────────────────────────────────────────────────────────────────────
//  s2dMatrix
// ──────────────────────────────────────────────────────────────────────

pub fn s2dMatrix(s: Vec2f32) Mat4x4f32 {
    return Mat4x4f32.scale(Vec3f32{ s.x, s.y, 1.0 });
}

// ──────────────────────────────────────────────────────────────────────
//  r2dMatrix
// ──────────────────────────────────────────────────────────────────────

pub fn r2dMatrix(r: f32) Mat4x4f32 {
    return Mat4x4f32.rotateZ(r);
}

// ──────────────────────────────────────────────────────────────────────
//  srt2dMatrix2 — 최적화 dispatch (경우별 닫힌 형태 호출)
// ──────────────────────────────────────────────────────────────────────

pub fn srt2dMatrix2(t: Vec3f32, s: Vec2f32, r: f32, cp: Vec2f32) Mat4x4f32 {
    if (cp.x != 0.0 or cp.y != 0.0) {
        return srtc2dMatrix(t, s, r, cp);
    }
    if (r != 0.0) {
        if (s.x != 1.0 or s.y != 1.0) {
            return srt2dMatrix(t, s, r);
        } else {
            return rt2dMatrix(t, r);
        }
    }
    if (s.x != 1.0 or s.y != 1.0) {
        return st2dMatrix(t, s);
    }
    return t2dMatrix(t);
}

// ──────────────────────────────────────────────────────────────────────
//  sr2dMatrix2 — 최적화 dispatch, ?Mat4x4f32 반환
// ──────────────────────────────────────────────────────────────────────

pub fn sr2dMatrix2(s: Vec2f32, r: f32, cp: Vec2f32) ?Mat4x4f32 {
    if (cp.x != 0.0 or cp.y != 0.0) {
        return src2dMatrix(s, r, cp);
    }
    if (r != 0.0) {
        if (s.x != 1.0 or s.y != 1.0) {
            return sr2dMatrix(s, r);
        } else {
            return r2dMatrix(r);
        }
    }
    if (s.x != 1.0 or s.y != 1.0) {
        return s2dMatrix(s);
    }
    return null;
}
