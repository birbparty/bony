import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../src/model.dart';

BlendMode _toFlutterBlend(String blendMode) {
  switch (blendMode) {
    case 'additive':
      return BlendMode.plus;
    case 'multiply':
      return BlendMode.multiply;
    case 'screen':
      return BlendMode.screen;
    default:
      assert(blendMode == 'normal',
          'Unknown bony blendMode "$blendMode" — falling back to srcOver');
      return BlendMode.srcOver;
  }
}

/// Flutter [CustomPainter] that renders a bony [DrawBatch] list onto a [Canvas].
///
/// Accepts an optional [textures] map from [DrawBatch.texturePage] name to a
/// [ui.Image]. When a texture is found for a batch it is applied via an
/// [ImageShader] and the vertex colours modulate it; otherwise the batch is
/// rendered with vertex colours only.
///
/// The painter does not manage texture loading — callers own the [ui.Image]
/// lifecycle and must supply them via [textures].
///
/// **Repaint contract**: [shouldRepaint] uses reference equality on [batches]
/// and [textures]. Callers must supply a new list or map instance each frame;
/// in-place mutation of an existing list will not trigger a repaint.
///
/// **Index range**: each [DrawBatch.indices] value must fit in a [Uint16List]
/// (i.e. be in [0, 65535]). Meshes with more than 65 536 vertices must be
/// split before being passed to [BonyPainter].
class BonyPainter extends CustomPainter {
  const BonyPainter({
    required this.batches,
    this.textures = const {},
  });

  final List<DrawBatch> batches;
  final Map<String, ui.Image> textures;

  @override
  void paint(Canvas canvas, Size size) {
    for (final batch in batches) {
      _paintBatch(canvas, batch);
    }
  }

  void _paintBatch(Canvas canvas, DrawBatch batch) {
    final verts = batch.vertices;
    if (verts.isEmpty || batch.indices.isEmpty) return;

    assert(
      verts.length <= 0xFFFF,
      'BonyPainter: batch "${batch.slot}" has ${verts.length} vertices '
      '(max 65535 for Uint16List indices). Split the mesh before rendering.',
    );

    final positions = Float32List(verts.length * 2);
    final colors = Int32List(verts.length);
    final texCoords = Float32List(verts.length * 2);

    for (var i = 0; i < verts.length; i++) {
      final v = verts[i];
      positions[i * 2] = v.x;
      positions[i * 2 + 1] = v.y;
      // Flutter Color is ARGB32 packed as int.
      final a = (v.a.clamp(0.0, 1.0) * 255).round() & 0xFF;
      final r = (v.r.clamp(0.0, 1.0) * 255).round() & 0xFF;
      final g = (v.g.clamp(0.0, 1.0) * 255).round() & 0xFF;
      final b = (v.b.clamp(0.0, 1.0) * 255).round() & 0xFF;
      colors[i] = (a << 24) | (r << 16) | (g << 8) | b;
      texCoords[i * 2] = v.u;
      texCoords[i * 2 + 1] = v.v;
    }

    final indices = Uint16List.fromList(batch.indices);
    // Empty texturePage means untextured; look up only a non-empty key.
    final image =
        batch.texturePage.isEmpty ? null : textures[batch.texturePage];
    final canvasBlend = _toFlutterBlend(batch.blendMode);

    if (image != null) {
      // Textured path: map bony UV [0,1] to pixel space via scale matrix.
      // ui.ImageShader matrix is a column-major 4×4 that transforms UVs to
      // pixel coordinates — scale each axis by image dimensions.
      final mat = Float64List(16);
      mat[0] = image.width.toDouble();
      mat[5] = image.height.toDouble();
      mat[10] = 1.0;
      mat[15] = 1.0;
      final shader = ui.ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        mat,
      );
      try {
        final paint = Paint()
          ..shader = shader
          ..blendMode = canvasBlend;
        final vertices = ui.Vertices.raw(
          ui.VertexMode.triangles,
          positions,
          textureCoordinates: texCoords,
          colors: colors,
          indices: indices,
        );
        // BlendMode.modulate: fragment = texture_pixel × vertex_color.
        canvas.drawVertices(vertices, BlendMode.modulate, paint);
      } finally {
        shader.dispose();
      }
    } else {
      // Untextured path: vertex-coloured fill only.
      final paint = Paint()..blendMode = canvasBlend;
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
        indices: indices,
      );
      // BlendMode.src: use interpolated vertex colours as-is.
      canvas.drawVertices(vertices, BlendMode.src, paint);
    }
  }

  @override
  bool shouldRepaint(BonyPainter oldDelegate) =>
      !identical(batches, oldDelegate.batches) ||
      !identical(textures, oldDelegate.textures);
}

/// Convenience [Widget] that wraps [BonyPainter] in a [CustomPaint].
///
/// Repaints whenever [batches] or [textures] changes by reference. Pass a new
/// list or map each frame — in-place mutation does not trigger repaints.
class BonyWidget extends StatelessWidget {
  const BonyWidget({
    super.key,
    required this.batches,
    this.textures = const {},
    this.size = Size.infinite,
  });

  final List<DrawBatch> batches;

  /// Optional texture atlas pages keyed by [DrawBatch.texturePage].
  final Map<String, ui.Image> textures;

  /// Hint size for the [CustomPaint]; defaults to [Size.infinite] so the widget
  /// expands to fill its parent.
  final Size size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: BonyPainter(batches: batches, textures: textures),
      size: size,
    );
  }
}
