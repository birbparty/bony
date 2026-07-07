// World transform computation: M2 skeleton pose (t=0 setup pose only).
//
// Ports the Nim reference implementation in runtime-nim/src/bony/transform.nim.

import 'dart:math' as math;
import 'deform.dart';
import 'drawbatch_clipping.dart';
import 'ik.dart';
import 'model.dart';
import 'numeric_guards.dart' show distance, lerp, radToDeg;
import 'physics_constraint.dart';
import 'transform_constraint.dart';

part 'transform_math.dart';
part 'helper_geometry.dart';
part 'path_sampling.dart';
part 'constraint_ordering.dart';
part 'constraint_apply.dart';
part 'world_transform.dart';
part 'physics_stage.dart';
part 'draw_batches.dart';
