//! linalg.zig — Odin `core:math/linalg` 대응.
//! Mat4x4, Vec2, lerp, vectorDot, vectorCross, splat 등.

const std = @import("std");

// ──────────────────────────────────────────────────────────────────────
//  2D 벡터 (struct — .x / .y 필드 접근 보존)
// ──────────────────────────────────────────────────────────────────────

pub fn Vec2(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        const Self = @This();
    };
}

pub const Vec2f32 = Vec2(f32);
pub const Vec2f64 = Vec2(f64);

// ──────────────────────────────────────────────────────────────────────
//  3D / 4D SIMD 벡터 (행렬 연산용)
// ──────────────────────────────────────────────────────────────────────

pub const Vec3f32 = @Vector(3, f32);
pub const Vec4f32 = @Vector(4, f32);

// ──────────────────────────────────────────────────────────────────────
//  4×4 행렬 (column‑major: data[col][row])
// ──────────────────────────────────────────────────────────────────────

pub fn Mat4x4(comptime T: type) type {
    return struct {
        data: [4][4]T, // [col][row]

        const Self = @This();

        /// 단위 행렬.
        pub fn identity() Self {
            return Self{ .data = .{
                .{ 1, 0, 0, 0 },
                .{ 0, 1, 0, 0 },
                .{ 0, 0, 1, 0 },
                .{ 0, 0, 0, 1 },
            } };
        }

        /// this * other (matrix multiplication).
        pub fn mul(self: Self, other: Self) Self {
            var result: Self = undefined;
            const a = self.data;
            const b = other.data;
            for (0..4) |col| {
                for (0..4) |row| {
                    var sum: T = 0;
                    for (0..4) |k| {
                        sum += a[k][row] * b[col][k];
                    }
                    result.data[col][row] = sum;
                }
            }
            return result;
        }

        /// this * column vector v.
        pub fn mulVec(self: Self, v: @Vector(4, T)) @Vector(4, T) {
            const d = self.data;
            return @Vector(4, T){
                d[0][0] * v[0] + d[1][0] * v[1] + d[2][0] * v[2] + d[3][0] * v[3],
                d[0][1] * v[0] + d[1][1] * v[1] + d[2][1] * v[2] + d[3][1] * v[3],
                d[0][2] * v[0] + d[1][2] * v[1] + d[2][2] * v[2] + d[3][2] * v[3],
                d[0][3] * v[0] + d[1][3] * v[1] + d[2][3] * v[2] + d[3][3] * v[3],
            };
        }

        /// 역행렬 (adjugate / determinant 방식).
        ///
        /// MESA `gluInvertMatrix` 알고리즘을 column-major flat 인덱스로 정확히
        /// 옮긴다. m[k] = data[k/4][k%4] (column-major), invOut[k]도 같은 규약.
        pub fn inverse(self: Self) Self {
            const d = self.data;

            // adjugate 16개 (MESA gluInvertMatrix 원본 그대로)
            // invOut[k] = invOut[k/4][k%4] (column-major)
            const a0 = d[1][1] * d[2][2] * d[3][3] -
                d[1][1] * d[2][3] * d[3][2] -
                d[2][1] * d[1][2] * d[3][3] +
                d[2][1] * d[1][3] * d[3][2] +
                d[3][1] * d[1][2] * d[2][3] -
                d[3][1] * d[1][3] * d[2][2];

            const a4 = -d[1][0] * d[2][2] * d[3][3] +
                d[1][0] * d[2][3] * d[3][2] +
                d[2][0] * d[1][2] * d[3][3] -
                d[2][0] * d[1][3] * d[3][2] -
                d[3][0] * d[1][2] * d[2][3] +
                d[3][0] * d[1][3] * d[2][2];

            const a8 = d[1][0] * d[2][1] * d[3][3] -
                d[1][0] * d[2][3] * d[3][1] -
                d[2][0] * d[1][1] * d[3][3] +
                d[2][0] * d[1][3] * d[3][1] +
                d[3][0] * d[1][1] * d[2][3] -
                d[3][0] * d[1][3] * d[2][1];

            const a12 = -d[1][0] * d[2][1] * d[3][2] +
                d[1][0] * d[2][2] * d[3][1] +
                d[2][0] * d[1][1] * d[3][2] -
                d[2][0] * d[1][2] * d[3][1] -
                d[3][0] * d[1][1] * d[2][2] +
                d[3][0] * d[1][2] * d[2][1];

            const a1 = -d[0][1] * d[2][2] * d[3][3] +
                d[0][1] * d[2][3] * d[3][2] +
                d[2][1] * d[0][2] * d[3][3] -
                d[2][1] * d[0][3] * d[3][2] -
                d[3][1] * d[0][2] * d[2][3] +
                d[3][1] * d[0][3] * d[2][2];

            const a5 = d[0][0] * d[2][2] * d[3][3] -
                d[0][0] * d[2][3] * d[3][2] -
                d[2][0] * d[0][2] * d[3][3] +
                d[2][0] * d[0][3] * d[3][2] +
                d[3][0] * d[0][2] * d[2][3] -
                d[3][0] * d[0][3] * d[2][2];

            const a9 = -d[0][0] * d[2][1] * d[3][3] +
                d[0][0] * d[2][3] * d[3][1] +
                d[2][0] * d[0][1] * d[3][3] -
                d[2][0] * d[0][3] * d[3][1] -
                d[3][0] * d[0][1] * d[2][3] +
                d[3][0] * d[0][3] * d[2][1];

            const a13 = d[0][0] * d[2][1] * d[3][2] -
                d[0][0] * d[2][2] * d[3][1] -
                d[2][0] * d[0][1] * d[3][2] +
                d[2][0] * d[0][2] * d[3][1] +
                d[3][0] * d[0][1] * d[2][2] -
                d[3][0] * d[0][2] * d[2][1];

            const a2 = d[0][1] * d[1][2] * d[3][3] -
                d[0][1] * d[1][3] * d[3][2] -
                d[1][1] * d[0][2] * d[3][3] +
                d[1][1] * d[0][3] * d[3][2] +
                d[3][1] * d[0][2] * d[1][3] -
                d[3][1] * d[0][3] * d[1][2];

            const a6 = -d[0][0] * d[1][2] * d[3][3] +
                d[0][0] * d[1][3] * d[3][2] +
                d[1][0] * d[0][2] * d[3][3] -
                d[1][0] * d[0][3] * d[3][2] -
                d[3][0] * d[0][2] * d[1][3] +
                d[3][0] * d[0][3] * d[1][2];

            const a10 = d[0][0] * d[1][1] * d[3][3] -
                d[0][0] * d[1][3] * d[3][1] -
                d[1][0] * d[0][1] * d[3][3] +
                d[1][0] * d[0][3] * d[3][1] +
                d[3][0] * d[0][1] * d[1][3] -
                d[3][0] * d[0][3] * d[1][1];

            const a14 = -d[0][0] * d[1][1] * d[3][2] +
                d[0][0] * d[1][2] * d[3][1] +
                d[1][0] * d[0][1] * d[3][2] -
                d[1][0] * d[0][2] * d[3][1] -
                d[3][0] * d[0][1] * d[1][2] +
                d[3][0] * d[0][2] * d[1][1];

            const a3 = -d[0][1] * d[1][2] * d[2][3] +
                d[0][1] * d[1][3] * d[2][2] +
                d[1][1] * d[0][2] * d[2][3] -
                d[1][1] * d[0][3] * d[2][2] -
                d[2][1] * d[0][2] * d[1][3] +
                d[2][1] * d[0][3] * d[1][2];

            const a7 = d[0][0] * d[1][2] * d[2][3] -
                d[0][0] * d[1][3] * d[2][2] -
                d[1][0] * d[0][2] * d[2][3] +
                d[1][0] * d[0][3] * d[2][2] +
                d[2][0] * d[0][2] * d[1][3] -
                d[2][0] * d[0][3] * d[1][2];

            const a11 = -d[0][0] * d[1][1] * d[2][3] +
                d[0][0] * d[1][3] * d[2][1] +
                d[1][0] * d[0][1] * d[2][3] -
                d[1][0] * d[0][3] * d[2][1] -
                d[2][0] * d[0][1] * d[1][3] +
                d[2][0] * d[0][3] * d[1][1];

            const a15 = d[0][0] * d[1][1] * d[2][2] -
                d[0][0] * d[1][2] * d[2][1] -
                d[1][0] * d[0][1] * d[2][2] +
                d[1][0] * d[0][2] * d[2][1] +
                d[2][0] * d[0][1] * d[1][2] -
                d[2][0] * d[0][2] * d[1][1];

            // determinant (MESA): det = m[0]*inv[0] + m[1]*inv[4] + m[2]*inv[8] + m[3]*inv[12]
            // m[0]=d[0][0], inv[0]=a0, m[1]=d[0][1], inv[4]=a4, ...
            const det = d[0][0] * a0 + d[0][1] * a4 + d[0][2] * a8 + d[0][3] * a12;

            // singular matrix: 호출자가 알아서 처리하도록 NaN/inf 가 채워지도록 두지 않고
            // 여기서는 0으로 나누지 않도록 가드. 단, 호출자가 det==0 확인은 별도 책임.
            const inv_det = if (det == 0) 0.0 else 1.0 / det;

            var out: Self = undefined;
            out.data[0][0] = a0 * inv_det;
            out.data[0][1] = a1 * inv_det;
            out.data[0][2] = a2 * inv_det;
            out.data[0][3] = a3 * inv_det;
            out.data[1][0] = a4 * inv_det;
            out.data[1][1] = a5 * inv_det;
            out.data[1][2] = a6 * inv_det;
            out.data[1][3] = a7 * inv_det;
            out.data[2][0] = a8 * inv_det;
            out.data[2][1] = a9 * inv_det;
            out.data[2][2] = a10 * inv_det;
            out.data[2][3] = a11 * inv_det;
            out.data[3][0] = a12 * inv_det;
            out.data[3][1] = a13 * inv_det;
            out.data[3][2] = a14 * inv_det;
            out.data[3][3] = a15 * inv_det;
            return out;
        }

        /// Translation matrix (tx, ty, tz).
        pub fn translate(v: Vec3f32) Self {
            var m = Self.identity();
            m.data[3][0] = v[0];
            m.data[3][1] = v[1];
            m.data[3][2] = v[2];
            return m;
        }

        /// Rotation around Z axis by `angle` radians.
        pub fn rotateZ(angle: f32) Self {
            const c = @cos(angle);
            const s = @sin(angle);
            var m = Self.identity();
            m.data[0][0] = c;
            m.data[1][0] = -s;
            m.data[0][1] = s;
            m.data[1][1] = c;
            return m;
        }

        /// Scale matrix (sx, sy, sz).
        pub fn scale(v: Vec3f32) Self {
            var m = Self.identity();
            m.data[0][0] = v[0];
            m.data[1][1] = v[1];
            m.data[2][2] = v[2];
            return m;
        }
    };
}

pub const Mat4x4f32 = Mat4x4(f32);

// ──────────────────────────────────────────────────────────────────────
//  2D 벡터 연산 헬퍼 (Odin linalg.vector_* / lerp / splat 대응)
// ──────────────────────────────────────────────────────────────────────

/// a + b
pub inline fn vec2Add(comptime T: type, a: Vec2(T), b: Vec2(T)) Vec2(T) {
    return .{ .x = a.x + b.x, .y = a.y + b.y };
}

/// a - b
pub inline fn vec2Sub(comptime T: type, a: Vec2(T), b: Vec2(T)) Vec2(T) {
    return .{ .x = a.x - b.x, .y = a.y - b.y };
}

/// a * b (element-wise)
pub inline fn vec2Mul(comptime T: type, a: Vec2(T), b: Vec2(T)) Vec2(T) {
    return .{ .x = a.x * b.x, .y = a.y * b.y };
}

/// a * s (scalar)
pub inline fn vec2Scale(comptime T: type, a: Vec2(T), s: T) Vec2(T) {
    return .{ .x = a.x * s, .y = a.y * s };
}

/// {s, s}
pub inline fn vec2Splat(comptime T: type, s: T) Vec2(T) {
    return .{ .x = s, .y = s };
}

/// Dot product.
pub inline fn vec2Dot(comptime T: type, a: Vec2(T), b: Vec2(T)) T {
    return a.x * b.x + a.y * b.y;
}

/// Cross product (2D: a.x*b.y - a.y*b.x).
pub inline fn vec2Cross(comptime T: type, a: Vec2(T), b: Vec2(T)) T {
    return a.x * b.y - a.y * b.x;
}

/// Linear interpolation: a + (b - a) * t  (scalar).
pub inline fn lerp(a: anytype, b: @TypeOf(a), t: @TypeOf(a)) @TypeOf(a) {
    return a + (b - a) * t;
}

/// Linear interpolation for Vec2(T).
pub inline fn vec2Lerp(comptime T: type, a: Vec2(T), b: Vec2(T), t: T) Vec2(T) {
    return .{
        .x = a.x + (b.x - a.x) * t,
        .y = a.y + (b.y - a.y) * t,
    };
}

/// Length squared of a Vec2.
pub inline fn vec2Length2(comptime T: type, a: Vec2(T)) T {
    return a.x * a.x + a.y * a.y;
}

// ──────────────────────────────────────────────────────────────────────
//  Vec3/Vec4 → Vec2 변환
// ──────────────────────────────────────────────────────────────────────

pub inline fn vec3ToVec2(v: Vec3f32) Vec2f32 {
    return .{ .x = v[0], .y = v[1] };
}

pub inline fn vec4ToVec2(v: Vec4f32) Vec2f32 {
    return .{ .x = v[0], .y = v[1] };
}

pub inline fn vec2ToVec3(v: Vec2f32, z: f32) Vec3f32 {
    return .{ v.x, v.y, z };
}

pub inline fn vec2ToVec4(v: Vec2f32, z: f32, w: f32) Vec4f32 {
    return .{ v.x, v.y, z, w };
}

// ──────────────────────────────────────────────────────────────────────
//  epsilon (Odin `math.F32_EPSILON` 등 대응)
// ──────────────────────────────────────────────────────────────────────

pub inline fn epsilon(comptime T: type) T {
    return switch (T) {
        f16 => std.math.floatEps(f16),
        f32 => std.math.floatEps(f32),
        f64 => std.math.floatEps(f64),
        else => @compileError("unsupported float type: " ++ @typeName(T)),
    };
}
