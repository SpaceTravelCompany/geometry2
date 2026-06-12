//! point_in.zig — 점-도형 포함 관계 검사.
//! PointInTriangle과 PolygonOverlapsPolygon을 재노출.

pub const pointInTriangle = @import("triangle.zig").pointInTriangle;
pub const polygonOverlapsPolygon = @import("polygon.zig").polygonOverlapsPolygon;
pub const pointInPolygon = @import("polygon.zig").pointInPolygon;
