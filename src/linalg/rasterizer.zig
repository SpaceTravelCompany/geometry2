//! rasterizer.zig — Odin shared/geometry/rasterizer/rasterizer.odin 1:1 포팅.
//! plutovg 라이브러리를 통해 Shape → 픽셀 래스터라이즈.

const std = @import("std");
const linalg = @import("linalg.zig");
const Vec2f32 = linalg.Vec2f32;
const Vec4f32 = linalg.Vec4f32;
const geometry = @import("geometry.zig");
const ShapeNode = geometry.ShapeNode;
const Shapes = geometry.Shapes;

// ══════════════════════════════════════════════════════════════════════════════
//  plutovg C-ABI 선언
// ══════════════════════════════════════════════════════════════════════════════

/// plutovg 불투명 타입 선언 (opaque).
const plutovg_surface_t = opaque {};
const plutovg_canvas_t = opaque {};

const plutovg_color_t = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

const plutovg_fill_rule_t = c_int;
const PLUTOVG_FILL_RULE_NON_ZERO: plutovg_fill_rule_t = 0;

extern "c" fn plutovg_surface_create(width: c_int, height: c_int) ?*plutovg_surface_t;
extern "c" fn plutovg_surface_destroy(surface: ?*plutovg_surface_t) void;
extern "c" fn plutovg_surface_clear(surface: ?*plutovg_surface_t, color: *const plutovg_color_t) void;
extern "c" fn plutovg_surface_get_stride(surface: ?*plutovg_surface_t) c_int;
extern "c" fn plutovg_surface_get_data(surface: ?*plutovg_surface_t) [*]u8;

extern "c" fn plutovg_canvas_create(surface: ?*plutovg_surface_t) ?*plutovg_canvas_t;
extern "c" fn plutovg_canvas_destroy(canvas: ?*plutovg_canvas_t) void;
extern "c" fn plutovg_canvas_set_fill_rule(canvas: ?*plutovg_canvas_t, rule: plutovg_fill_rule_t) void;
extern "c" fn plutovg_canvas_set_rgba(canvas: ?*plutovg_canvas_t, r: f32, g: f32, b: f32, a: f32) void;
extern "c" fn plutovg_canvas_set_line_width(canvas: ?*plutovg_canvas_t, width: f32) void;
extern "c" fn plutovg_canvas_new_path(canvas: ?*plutovg_canvas_t) void;
extern "c" fn plutovg_canvas_move_to(canvas: ?*plutovg_canvas_t, x: f32, y: f32) void;
extern "c" fn plutovg_canvas_line_to(canvas: ?*plutovg_canvas_t, x: f32, y: f32) void;
extern "c" fn plutovg_canvas_quad_to(canvas: ?*plutovg_canvas_t, x1: f32, y1: f32, x2: f32, y2: f32) void;
extern "c" fn plutovg_canvas_cubic_to(canvas: ?*plutovg_canvas_t, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) void;
extern "c" fn plutovg_canvas_close_path(canvas: ?*plutovg_canvas_t) void;
extern "c" fn plutovg_canvas_fill(canvas: ?*plutovg_canvas_t) void;
extern "c" fn plutovg_canvas_fill_preserve(canvas: ?*plutovg_canvas_t) void;
extern "c" fn plutovg_canvas_stroke(canvas: ?*plutovg_canvas_t) void;
extern "c" fn plutovg_canvas_scale(canvas: ?*plutovg_canvas_t, sx: f32, sy: f32) void;

// ══════════════════════════════════════════════════════════════════════════════
//  Error
// ══════════════════════════════════════════════════════════════════════════════

pub const __RasterizerError = error{
    INVALID_SIZE,
    SURFACE_CREATE_FAILED,
    CANVAS_CREATE_FAILED,
};

pub const RasterizerError = __RasterizerError || std.mem.Allocator.Error;

// ══════════════════════════════════════════════════════════════════════════════
//  PixelFormat
// ══════════════════════════════════════════════════════════════════════════════

pub const PixelFormat = enum(u8) {
    ARGB8_PREMULTIPLIED,
};

// ══════════════════════════════════════════════════════════════════════════════
//  RasterizedPixels
// ══════════════════════════════════════════════════════════════════════════════

pub const RasterizedPixels = struct {
    width: usize,
    height: usize,
    stride: usize,
    format: PixelFormat,
    pixels: []u8,
    allocator: std.mem.Allocator,
};

pub fn rasterizedPixelsFree(self: *RasterizedPixels) void {
    if (self.pixels.len > 0) {
        self.allocator.free(self.pixels);
    }
    self.* = undefined;
}

// ══════════════════════════════════════════════════════════════════════════════
//  _appendContourPath (private)
// ══════════════════════════════════════════════════════════════════════════════

fn appendContourPath(canvas: ?*plutovg_canvas_t, pts: []const Vec2f32, curveFlags: []const bool, isClosed: bool) void {
    if (canvas == null or pts.len == 0) return;

    plutovg_canvas_move_to(canvas, pts[0].x, pts[0].y);

    const last = pts.len - 1;
    if (last <= 0) {
        if (isClosed) plutovg_canvas_close_path(canvas);
        return;
    }

    var i: usize = 0;
    while (true) {
        if (!isClosed and i >= last) break;

        const next = if (isClosed) (i + 1) % pts.len else i + 1;
        if (next >= pts.len) break;

        if (next < curveFlags.len and curveFlags[next]) {
            const next2 = if (isClosed) (next + 1) % pts.len else next + 1;
            if (next2 >= pts.len) break;

            if (next2 < curveFlags.len and curveFlags[next2]) {
                const next3 = if (isClosed) (next2 + 1) % pts.len else next2 + 1;
                if (next3 >= pts.len) break;

                plutovg_canvas_cubic_to(
                    canvas,
                    pts[next].x, pts[next].y,
                    pts[next2].x, pts[next2].y,
                    pts[next3].x, pts[next3].y,
                );
                i = next3;
            } else {
                plutovg_canvas_quad_to(
                    canvas,
                    pts[next].x, pts[next].y,
                    pts[next2].x, pts[next2].y,
                );
                i = next2;
            }
        } else {
            plutovg_canvas_line_to(canvas, pts[next].x, pts[next].y);
            i = next;
        }

        if (isClosed and i == 0) break;
    }

    if (isClosed) plutovg_canvas_close_path(canvas);
}

// ══════════════════════════════════════════════════════════════════════════════
//  shapesToPixels
// ══════════════════════════════════════════════════════════════════════════════

pub fn shapesToPixels(
    src: Shapes,
    width: usize,
    height: usize,
    allocator: std.mem.Allocator,
) RasterizerError!RasterizedPixels {
    if (width == 0 or height == 0) return error.INVALID_SIZE;

    const surface = plutovg_surface_create(@intCast(width), @intCast(height)) orelse return error.SURFACE_CREATE_FAILED;
    defer plutovg_surface_destroy(surface);

    const canvas = plutovg_canvas_create(surface) orelse return error.CANVAS_CREATE_FAILED;
    defer plutovg_canvas_destroy(canvas);

    const clear_color = plutovg_color_t{
        .r = 0.0,
        .g = 0.0,
        .b = 0.0,
        .a = 0.0,
    };
    plutovg_surface_clear(surface, &clear_color);
    plutovg_canvas_set_fill_rule(canvas, PLUTOVG_FILL_RULE_NON_ZERO);

    // geometry 좌표계 (Y-up) → plutovg canvas 좌표계 (Y-down) 변환
    plutovg_canvas_scale(canvas, 1, -1);

    for (src.nodes) |node| {
        if (node.pts.len == 0) continue;

        plutovg_canvas_new_path(canvas);
        for (node.pts, 0..) |contour, cidx| {
            const curveFlags: []const bool = if (cidx < node.isCurves.len) node.isCurves[cidx] else &.{};
            appendContourPath(canvas, contour, curveFlags, node.isClosed);
        }

        const hasFill = node.color[3] > 0.0;
        const hasStroke = node.strokeColor[3] > 0.0 and node.thickness > 0.0;

        if (hasFill) {
            plutovg_canvas_set_rgba(canvas, node.color[0], node.color[1], node.color[2], node.color[3]);
            if (hasStroke) {
                plutovg_canvas_fill_preserve(canvas);
            } else {
                plutovg_canvas_fill(canvas);
            }
        }

        if (hasStroke) {
            plutovg_canvas_set_rgba(canvas, node.strokeColor[0], node.strokeColor[1], node.strokeColor[2], node.strokeColor[3]);
            plutovg_canvas_set_line_width(canvas, node.thickness);
            plutovg_canvas_stroke(canvas);
        }
    }

    const stride: usize = @intCast(plutovg_surface_get_stride(surface));
    const pixelBytes = stride * height;

    const pixels = try allocator.alloc(u8, pixelBytes);
    @memcpy(pixels, plutovg_surface_get_data(surface)[0..pixelBytes]);

    return RasterizedPixels{
        .width = width,
        .height = height,
        .stride = stride,
        .format = .ARGB8_PREMULTIPLIED,
        .pixels = pixels,
        .allocator = allocator,
    };
}
