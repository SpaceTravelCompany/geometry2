//! geometry2 — 최상위 진입점.
//! linalg, triangulation, geometry, svg, rasterizer 모듈을 재노출한다.

const std = @import("std");
const linalg_mod = @import("linalg");

pub const linalg = linalg_mod;
pub const triangulation = linalg_mod.triangulation;
pub const geometry = linalg_mod.geometry;
pub const svg = linalg_mod.svg;
pub const rasterizer = linalg_mod.rasterizer;
