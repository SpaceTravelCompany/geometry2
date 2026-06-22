# geometry2

Odin `Odin/shared/geometry`의 1:1 Zig 0.16 포팅. `linalg`, `triangulation`, `geometry`, `svg`, `rasterizer` 모듈을 노출하며, `linalg`는 18개 서브모듈을 re-export.

**마지막 업데이트**: 2026-06-23 | **모듈 상태**: 17/17 단위 테스트 통과

---

## 빌드

```bash
zig build              # 컴파일 체크
zig build test         # linalg 단위 테스트 + geometry2_test 실행 파일
zig build check        # alias for zig build test
```

`zig build test`는 통합 테스트 명령이다. 두 가지를 차례로 실행한다:
- `linalg` 모듈의 단위 테스트 (`src/linalg` 내 `test {}` 블록 17개). 파일별 내역:
  - `bezier_intersect.zig` (6): 2quadCurves, lineLineIntersect, lineQuadIntersect, bezierExtremaT, bezierAABBQuad, pointInCurvedPolygonSquare
  - `path_template.zig` (5): rectLineInit, circleCubicInit, ellipseCubicInit, roundRectLineInit (2)
  - `triangulation.zig` (3): triangulationSquare, triangulationTwoSquares, triangulationTriangle
  - `area.zig` (1): Area basic
  - `triangle.zig` (1): PointInTriangle
  - `mod.zig` (1): 모듈 참조 smoke test
- `src/test/main.zig` 기반 `geometry2_test` 실행 파일. 주요 검증 영역:
  - 기하 기본 연산 (rect, pointInTriangle, rectAnd, linesIntersect2, pointInPolygon, polygonSignedArea, crossProductSign, inCircleTest, xyMirrorPoint, bezier eval)
  - 행렬 정확성 (srt2dMatrix, inverse, matrix2d shortcut 최적화 table-driven)
  - path_template (circleCubicInit, rectLineInit, roundRectLineInit, ellipseCubicInit)
  - polyTransformMatrix, shapesComputePolygon
  - geometry aggregator (getCubicCurveType, reverseShapeCloseCurve)
  - SVG 파싱 (Q→CUBIC 변환, isCurves 보존, Y-flip)
  - Rasterizer end-to-end (SVG → shapes → pixels non-zero 확인)

---

## 모듈

`geometry2`는 linalg 모듈을 노출하며, 그 안에서 다음 18개 서브모듈을 re-export:

| 서브모듈 | 줄 수 | 설명 |
|---|---:|---|
| linalg.zig | 348 | Vec2/Vec3/Vec4/Mat4x4 기본 타입 + epsilon + vec2Lerp 등 |
| rect.zig | 234 | Rect(T) + 12개 Rect 연산 (rectAnd, rectOr 등) |
| area.zig | 101 | Area(T) + AreaMulMatrix + AreaPointIn |
| polygon.zig | 154 | PointInPolygon, PolygonSignedArea, LineInPolygon, PolygonOverlapsPolygon |
| lines.zig | 290 | LinesIntersect2/3, GetAngle, InCircleTest, SubdivLine/Quadratic/Cubic |
| circle.zig | 19 | Circle(T) |
| bezier.zig | 144 | BezierKind, evalBezier, evalBezierTangent, evalBezierSegment, CvtQuadraticToCubic |
| matrix2d.zig | 140 | srtc2dMatrix, srt2dMatrix, sr2dMatrix, t2dMatrix, srt2dMatrix2 등 11개 함수 |
| triangle.zig | 47 | pointInTriangle |
| mirror.zig | 28 | xyMirrorPoint, oppPolyOrientation |
| point_in.zig | 6 | polygon + triangle + rect + circle re-export aggregator |
| path_template.zig | 217 | CircleCubicInit, RectLineInit, RoundRectLineInit, EllipseCubicInit |
| bezier_intersect.zig | 1095 | GetBezierIntersectPt, GetBezierIntersectPtSlow, GetBezierTFromPoint, BezierAABB, PointInCurvedPolygon + 6개 테스트 |
| triangulation.zig | 299 | C-ABI libtess2 래퍼. TrianguatePolygons + __TrianguateError / TrianguateError |
| clipper.zig | 4268 | ClipperBase / ClipperOffset / Boolean / RectClip / inflatePaths. __ClipperError + ClipperError |
| geometry.zig | 1534 | ShapeNode/Shapes/IsHoleContour/ReverseShapeCloseCurve/ShapesComputePolygon/getCubicCurveType/polyTransformMatrix + offsetShapeNode / clipShapeNodeRect / booleanShapeNodes |
| svg.zig | 613 | SvgParser + initParse/deinit + plutovg c-abi + zig-xml streaming pull parser |
| rasterizer.zig | 220 | shapesToPixels + rasterizedPixelsFree (메서드) + plutovg c-abi |

`geometry2` 최상위 진입점(`src/root.zig`)은 `linalg`, `triangulation`, `geometry`, `svg`, `rasterizer`를 재노출한다.

---

## 사용 예시

```zig
const std = @import("std");
const linalg = @import("geometry2").linalg;
const triangulation = @import("geometry2").triangulation;

// Rect
const r = linalg.rectInit(f32, 0, 100, 0, 100);

// PointInPolygon
const poly = [_]linalg.Vec2(f32){
    .{ .x = 0, .y = 0 },
    .{ .x = 10, .y = 0 },
    .{ .x = 10, .y = 10 },
    .{ .x = 0, .y = 10 },
};
const inside = linalg.pointInPolygon(f32, .{ .x = 5, .y = 5 }, &poly);

// 삼각 측량
const allocator = std.heap.page_allocator;
const polys = [_][]const linalg.Vec2(f32){ &poly };
const indices = try triangulation.trianguatePolygons(&polys, allocator, 0);

// SVG 파싱
const svg_text = "<svg>...</svg>";
var parser = try linalg.svg.initParse(svg_text, allocator);
defer parser.deinit();

// 래스터화
var pixels = try linalg.rasterizer.shapesToPixels(parser.shapes, 100, 100, allocator);
defer pixels.rasterizedPixelsFree();
```

---

## engine2 통합

`engine2`는 geometry2를 Zig 패키지 의존성으로 사용한다.

```zon
// engine2/build.zig.zon
.dependencies = .{
    .geometry2 = .{
        .path = "../geometry2",
    },
},
```

```zig
// engine2/build.zig
const geometry2_dep = b.dependency("geometry2", .{
    .target = target,
    .optimize = optimize,
});
const geometry_mod = geometry2_dep.module("geometry2");
engine_mod.addImport("geometry", geometry_mod);
```

```zig
// engine2 외부 사용자
const engine2 = @import("engine2");
const linalg = engine2.geometry.linalg;
const triangulation = engine2.geometry.triangulation;
const svg = engine2.geometry.svg;
const rasterizer = engine2.geometry.rasterizer;
```

---

## 외부 의존성

| 의존성 | 종류 | 버전 | 위치 |
|---|---|---|---|
| libtess2 (memononen) | C 라이브러리 | v1.0.2-34-g8dbd648 | `deps/libtess2/` (submodule) |
| plutovg (sammycage) | C 라이브러리 | v1.3.3-12-gdd73459 | `deps/plutovg/` (submodule) |
| zig-xml (ianprime0509) | Zig 0.16 패키지 | 0.2.0 | `build.zig.zon` `.dependencies.xml` |

**zig-xml 선택 이유**: `nektro/zig-xml` 원본은 zigmod 기반이라 nio/tracer/extras 의존성 때문에 Zig 표준 패키지 시스템과 직접 호환되지 않는다. `ianprime0509/zig-xml`은 Zig 0.16 호환 fork로 외부 의존성 없이 standalone 사용 가능.

빌드 시 C 소스는 `addCSourceFiles`로 포함되며, `addIncludePath`는 `b.path(...)`로 절대 경로 변환 필수 (dependency로 사용될 때 상대 경로가 깨지는 문제 방지).

---

## clipper

`Odin/shared/geometry/clipper/clipper.odin` (4214줄) 1:1 포팅. `src/linalg/clipper.zig` (4268줄)에 다음 API 제공:

- `ClipperBase`, `ClipperOffset`, `Point`, `RectF64`, `FillRule` (NonZero / EvenOdd), `ClipType`, `JoinType`, `EndType`
- `inflatePaths`, `booleanOp`, `rectClip` + `InflateResult` / `BooleanResult` / `RectClipResult`

### Error set 분리 패턴

Odin의 `union #shared_nil { __ClipperError, runtime.Allocator_Error }` 패턴은 Zig의 merge된 error set으로 표현한다. `clipper.zig`, `triangulation.zig`, `geometry.zig` 모두 동일한 구조를 따른다:

```zig
// 도메인 고유 오류 — Odin `__XxxError` 1:1 대응
pub const __ClipperError = error{ Failed, TooSmall, LengthMismatch };

// 도메인 + allocator 오류 합집합 — Odin `XxxError` 1:1 대응
pub const ClipperError = __ClipperError || std.mem.Allocator.Error;
```

`triangulation.zig`도 동일하게 `__TrianguateError = error{ Failed, TooFewPoints }`, `TrianguateError = __TrianguateError || std.mem.Allocator.Error`.

`geometry.zig`의 `ShapeError`는 이들을 모두 합친 최상위 union:

```zig
pub const ShapeError = __ShapeError || __TrianguateError || __ClipperError || std.mem.Allocator.Error;
```

따라서 `offsetShapeNode` / `clipShapeNodeRect` / `booleanShapeNodes`는 `ShapeError!ShapeNode` 한 가지로 깔끔히 표현된다. `mapClipperErr`는 `clipper.ClipperError` → `ShapeError` 변환 helper:

```zig
fn mapClipperErr(err: clipper.ClipperError) ShapeError {
    return switch (err) {
        error.Failed => error.Failed,
        error.TooSmall => error.TooSmall,
        error.LengthMismatch => error.Length_Mismatch,
        error.OutOfMemory => error.OutOfMemory,
    };
}
```

---

## 명세

- **1:1 포팅 표** (70개 항목 + 38개 bezier_intersect + triangulation/trianguatePolygons + geometry aggregator + svg + rasterizer): `engine2/ENGINE_REFERENCE.md`의 섹션 3 참조.
- **의미 변경 요약** (Odin union → Zig error set, ArrayList API, Y-flip 등): 동 문서 섹션 6 참조.
- **빌드 그래프** (모듈 의존성, C 소스 포함 관계): 동 문서 섹션 8 참조.

---

## 라이선스 / 저작권

geometry2는 다음 라이브러리를 통합하며, 각각의 라이선스를 따른다:

- **[libtess2](https://github.com/memononen/libtess2)** (memononen) — SGI FREE SOFTWARE LICENSE B Version 2.0
- **[plutovg](https://github.com/sammycage/plutovg)** (sammycage) — MIT
- **[zig-xml](https://github.com/ianprime0509/zig-xml)** (ianprime0509) — MPL-2.0
- **[Odin geometry](https://github.com/SpaceTravelCompany/geometry)** (SpaceTravelCompany) — Boost Software License 1.0

geometry2 자체는 Zig 포팅(+기능 추가)으로, 원본 라이선스를 따른다.
