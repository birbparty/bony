import 'package:bony/bony.dart';
import 'package:test/test.dart';

void main() {
  group('validateBonyData', () {
    test('accepts constructed data using loader validation rules', () {
      final data = SkeletonData(
        header: const SkeletonHeader(name: 'constructed', version: '1.0.0'),
        bones: const [
          BoneData(
            name: 'root',
            parent: '',
            x: 0,
            y: 0,
            rotation: 0,
            scaleX: 1,
            scaleY: 1,
            shearX: 0,
            shearY: 0,
            inheritRotation: true,
            inheritScale: true,
            inheritReflection: true,
            transformMode: 'normal',
          ),
        ],
        slots: const [],
        regions: const [],
        paths: const [],
        pathAttachments: const [],
      );

      expect(() => validateBonyData(data), returnsNormally);
    });

    test('rejects constructed data with the same errors as loaders', () {
      final duplicateBones = SkeletonData(
        header: const SkeletonHeader(name: 'constructed', version: '1.0.0'),
        bones: const [
          BoneData(
            name: 'root',
            parent: '',
            x: 0,
            y: 0,
            rotation: 0,
            scaleX: 1,
            scaleY: 1,
            shearX: 0,
            shearY: 0,
            inheritRotation: true,
            inheritScale: true,
            inheritReflection: true,
            transformMode: 'normal',
          ),
          BoneData(
            name: 'root',
            parent: '',
            x: 1,
            y: 0,
            rotation: 0,
            scaleX: 1,
            scaleY: 1,
            shearX: 0,
            shearY: 0,
            inheritRotation: true,
            inheritScale: true,
            inheritReflection: true,
            transformMode: 'normal',
          ),
        ],
        slots: const [],
        regions: const [],
        paths: const [],
        pathAttachments: const [],
      );

      expect(() => validateBonyData(duplicateBones), throwsFormatException);
    });
  });

  group('SkeletonData.copyWith', () {
    test('replaces one field and preserves every other constructor field', () {
      final data = _fullyPopulatedSkeletonData();
      const replacementHeader =
          SkeletonHeader(name: 'replacement', version: '1.0.1');

      final copy = data.copyWith(header: replacementHeader);

      expect(copy.header, same(replacementHeader));
      expect(copy.bones, same(data.bones));
      expect(copy.slots, same(data.slots));
      expect(copy.regions, same(data.regions));
      expect(copy.paths, same(data.paths));
      expect(copy.pathAttachments, same(data.pathAttachments));
      expect(copy.pointAttachments, same(data.pointAttachments));
      expect(copy.boundingBoxAttachments, same(data.boundingBoxAttachments));
      expect(copy.nestedRigAttachments, same(data.nestedRigAttachments));
      expect(copy.clippingAttachments, same(data.clippingAttachments));
      expect(copy.meshAttachments, same(data.meshAttachments));
      expect(copy.ikConstraints, same(data.ikConstraints));
      expect(copy.transformConstraints, same(data.transformConstraints));
      expect(copy.physicsConstraints, same(data.physicsConstraints));
      expect(copy.skins, same(data.skins));
      expect(copy.animations, same(data.animations));
      expect(copy.parameters, same(data.parameters));
      expect(copy.deformers, same(data.deformers));
      expect(copy.stateMachines, same(data.stateMachines));
      expect(copy.deformOverrides, same(data.deformOverrides));
    });

    test('can replace multiple list fields in one call', () {
      final data = _fullyPopulatedSkeletonData();
      final newRegions = const [
        RegionAttachment(name: 'replacement-region', width: 8, height: 9),
      ];
      final newOverrides = const [
        DeformOverride(
          slot: 'slot',
          attachment: 'mesh',
          deltas: [MeshDelta(x: 3, y: 4)],
        ),
      ];

      final copy = data.copyWith(
        regions: newRegions,
        deformOverrides: newOverrides,
      );

      expect(copy.regions, same(newRegions));
      expect(copy.deformOverrides, same(newOverrides));
      expect(copy.header, same(data.header));
      expect(copy.bones, same(data.bones));
      expect(copy.slots, same(data.slots));
      expect(copy.meshAttachments, same(data.meshAttachments));
    });
  });
}

SkeletonData _fullyPopulatedSkeletonData() {
  const bones = [
    BoneData(
      name: 'root',
      parent: '',
      x: 0,
      y: 0,
      rotation: 0,
      scaleX: 1,
      scaleY: 1,
      shearX: 0,
      shearY: 0,
      inheritRotation: true,
      inheritScale: true,
      inheritReflection: true,
      transformMode: 'normal',
    ),
    BoneData(
      name: 'child',
      parent: 'root',
      x: 1,
      y: 2,
      rotation: 3,
      scaleX: 1,
      scaleY: 1,
      shearX: 0,
      shearY: 0,
      inheritRotation: true,
      inheritScale: true,
      inheritReflection: true,
      transformMode: 'normal',
    ),
  ];
  const slots = [
    SlotData(name: 'slot', bone: 'root', attachment: 'region'),
  ];
  const regions = [
    RegionAttachment(name: 'region', width: 10, height: 20),
  ];
  const paths = [
    PathConstraintData(
      name: 'path-constraint',
      bone: 'root',
      target: 'child',
      path: 'path-attachment',
      order: 0,
    ),
  ];
  const pathAttachments = [
    PathAttachment(
      name: 'path-attachment',
      p0x: 0,
      p0y: 0,
      p1x: 1,
      p1y: 0,
      p2x: 1,
      p2y: 1,
      p3x: 2,
      p3y: 1,
    ),
  ];
  const pointAttachments = [
    PointAttachment(name: 'point', x: 1, y: 2, rotation: 3),
  ];
  const boundingBoxAttachments = [
    BoundingBoxAttachment(name: 'box', vertices: [0, 0, 1, 0, 0, 1]),
  ];
  const nestedRigAttachments = [
    NestedRigAttachment(name: 'nested', skeleton: 'child-rig'),
  ];
  const clippingAttachments = [
    ClippingAttachment(
      name: 'clip',
      vertices: [0, 0, 1, 0, 0, 1],
      untilSlot: 'slot',
    ),
  ];
  const meshAttachments = [
    MeshAttachment(
      name: 'mesh',
      weighted: false,
      vertices: [MeshVertex.unweighted(0, 0)],
      uvs: [MeshUv(0, 0)],
      triangles: [0, 0, 0],
    ),
  ];
  const ikConstraints = [
    IkConstraintData(name: 'ik', bones: ['child'], target: 'root', order: 0),
  ];
  const transformConstraints = [
    TransformConstraintData(
      name: 'transform',
      bone: 'child',
      target: 'root',
      order: 0,
    ),
  ];
  const physicsConstraints = [
    PhysicsConstraintData(
      name: 'physics',
      bone: 'child',
      channels: {PhysicsChannel.x},
    ),
  ];
  const skins = [
    SkinData(
      name: 'default',
      entries: [
        SkinEntryData(slot: 'slot', attachment: 'region', target: 'region'),
      ],
      bones: ['root'],
      ikConstraints: ['ik'],
      transformConstraints: ['transform'],
      pathConstraints: ['path-constraint'],
      physicsConstraints: ['physics'],
    ),
  ];
  const animations = [
    AnimationClip(
      name: 'idle',
      duration: 1,
      boneTimelines: [
        BoneTimeline(
          bone: 'root',
          kind: BoneTimelineKind.rotate,
          scalarKeys: [ScalarKeyframe(time: 0, value: 0)],
        ),
      ],
    ),
  ];
  const parameters = [
    ParameterAxis(name: 'blend', minValue: 0, maxValue: 1),
  ];
  const deformers = [
    DeformerRecord(
      deformer: WarpDeformer(
        id: 'warp',
        order: 0,
        warp: WarpLattice(
          rows: 2,
          cols: 2,
          minX: 0,
          minY: 0,
          maxX: 1,
          maxY: 1,
          controlPoints: [
            DeformerPoint(x: 0, y: 0),
            DeformerPoint(x: 1, y: 0),
            DeformerPoint(x: 0, y: 1),
            DeformerPoint(x: 1, y: 1),
          ],
        ),
      ),
      keyformBlend: KeyformBlend(),
    ),
  ];
  const stateMachines = [
    StateMachineData(
      name: 'machine',
      layers: [
        StateMachineLayer(
          name: 'base',
          states: [
            StateMachineState(
              name: 'idle',
              kind: StateMachineStateKind.clip,
              clipName: 'idle',
            ),
          ],
          initialState: 'idle',
        ),
      ],
    ),
  ];
  const deformOverrides = [
    DeformOverride(
      slot: 'slot',
      attachment: 'mesh',
      deltas: [MeshDelta(x: 1, y: 2)],
    ),
  ];

  return const SkeletonData(
    header: SkeletonHeader(name: 'full', version: '1.0.0'),
    bones: bones,
    slots: slots,
    regions: regions,
    paths: paths,
    pathAttachments: pathAttachments,
    pointAttachments: pointAttachments,
    boundingBoxAttachments: boundingBoxAttachments,
    nestedRigAttachments: nestedRigAttachments,
    clippingAttachments: clippingAttachments,
    meshAttachments: meshAttachments,
    ikConstraints: ikConstraints,
    transformConstraints: transformConstraints,
    physicsConstraints: physicsConstraints,
    skins: skins,
    animations: animations,
    parameters: parameters,
    deformers: deformers,
    stateMachines: stateMachines,
    deformOverrides: deformOverrides,
  );
}
