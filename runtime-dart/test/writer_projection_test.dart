import 'package:bony/src/model.dart';
import 'package:bony/src/physics_constraint.dart';
import 'package:bony/src/writer.dart';
import 'package:test/test.dart';

void main() {
  group('canonical writer projections', () {
    test('reconstruct mesh payloads as structured JSON', () {
      expect(
        bonyCanonicalMeshVerticesJson(
          const [
            MeshVertex.unweighted(1.0, -0.0),
            MeshVertex.weighted([
              MeshInfluence(bone: 'root', bindX: 2.5, bindY: 3.0, weight: 0.75),
              MeshInfluence(bone: 'tip', bindX: -1.0, bindY: 0.5, weight: 0.25),
            ]),
          ],
          indent: 3,
        ),
        '[\n'
        '        {"x": 1, "y": 0},\n'
        '        {"influences": [{"bone": "root", "bindX": 2.5, '
        '"bindY": 3, "weight": 0.75}, {"bone": "tip", "bindX": -1, '
        '"bindY": 0.5, "weight": 0.25}]}\n'
        '      ]',
      );
      expect(
        bonyCanonicalMeshUvsJson(const [MeshUv(0.0, 1.0), MeshUv(0.5, 0.25)]),
        '[0, 1, 0.5, 0.25]',
      );
      expect(bonyCanonicalIntArrayJson([2, 1, 0]), '[2, 1, 0]');
    });

    test('orders skins, membership, and entries like Nim canonical JSON', () {
      final data = _fixtureSkeleton(
        skins: const [
          SkinData(name: 'alt'),
          SkinData(
            name: 'default',
            bones: ['tip', 'root'],
            ikConstraints: ['ik'],
            transformConstraints: ['tc'],
            pathConstraints: ['path'],
            physicsConstraints: ['phys'],
            entries: [
              SkinEntryData(slot: 'front', attachment: 'z', target: 'mesh_z'),
              SkinEntryData(slot: 'back', attachment: 'b', target: 'mesh_b'),
              SkinEntryData(slot: 'back', attachment: 'a', target: 'mesh_a'),
            ],
          ),
        ],
      );

      expect(bonyCanonicalOrderedSkins(data).map((s) => s.name),
          ['default', 'alt']);
      expect(
        bonyCanonicalSkinJson(data, data.skins[1], indent: 1),
        '{\n'
        '    "name": "default",\n'
        '    "bones": ["root", "tip"],\n'
        '    "ikConstraints": ["ik"],\n'
        '    "transformConstraints": ["tc"],\n'
        '    "pathConstraints": ["path"],\n'
        '    "physicsConstraints": ["phys"],\n'
        '    "entries": [\n'
        '      {\n'
        '        "slot": "back",\n'
        '        "attachment": "a",\n'
        '        "target": "mesh_a"\n'
        '      },\n'
        '      {\n'
        '        "slot": "back",\n'
        '        "attachment": "b",\n'
        '        "target": "mesh_b"\n'
        '      },\n'
        '      {\n'
        '        "slot": "front",\n'
        '        "attachment": "z",\n'
        '        "target": "mesh_z"\n'
        '      }\n'
        '    ]\n'
        '  }',
      );
    });

    test('projects deformer payloads and keyform names', () {
      final json = bonyCanonicalDeformerRecordJson(
        const DeformerRecord(
          deformer: WarpDeformer(
            id: 'warp',
            parent: 'parent',
            order: 2,
            warp: WarpLattice(
              rows: 2,
              cols: 2,
              minX: -10,
              minY: -5,
              maxX: 10,
              maxY: 5,
              controlPoints: [
                DeformerPoint(x: -10, y: -5),
                DeformerPoint(x: 10, y: 5),
              ],
            ),
          ),
          keyformBlend: KeyformBlend(
            axes: [ParameterAxis(name: 'smile', minValue: 0, maxValue: 1)],
            valueCount: 2,
            keyforms: [
              Keyform(
                coordinates: [ParameterSample(name: 'smile', value: 1)],
                values: [0.25, 0.75],
              ),
            ],
          ),
        ),
      );

      expect(json, contains('"id": "warp"'));
      expect(json, contains('"parent": "parent"'));
      expect(
          json,
          contains('"controlPoints": [{"x": -10, "y": -5}, '
              '{"x": 10, "y": 5}]'));
      expect(json, contains('"axes": ["smile"]'));
      expect(json, contains('"coordinates": {"smile": 1}'));
      expect(json, contains('"values": [0.25, 0.75]'));
    });

    test('projects packed animation timeline families', () {
      final clip = AnimationClip(
        name: 'act',
        duration: 1,
        boneTimelines: const [
          BoneTimeline(
            bone: 'root',
            kind: BoneTimelineKind.translate,
            vectorKeys: [
              Vector2Keyframe(time: 0, x: 1, y: 2),
            ],
          ),
        ],
        slotTimelines: const [
          SlotTimeline(
            slot: 'front',
            kind: SlotTimelineKind.sequence,
            sequenceKeys: [
              SequenceKeyframe(
                time: 0.5,
                index: 3,
                delay: 0.125,
                mode: SequenceMode.loop,
              ),
            ],
          ),
        ],
        drawOrderTimeline: const DrawOrderTimeline(
          keys: [
            DrawOrderKeyframe(
              time: 0.25,
              offsets: [
                DrawOrderOffset(slot: 'front', offset: -1),
                DrawOrderOffset(slot: 'back', offset: 1),
              ],
            ),
          ],
        ),
        deformTimelines: const [
          DeformTimeline(
            skin: 'default',
            slot: 'front',
            attachment: 'cloth',
            vertexCount: 2,
            keys: [
              DeformKeyframe(
                time: 0.75,
                offset: 1,
                deltas: [MeshDelta(x: 3, y: 4)],
              ),
            ],
          ),
        ],
        eventTimelines: const [
          EventTimeline(
            keys: [
              EventKeyframe(
                time: 1,
                event: EventData(name: 'hit', intValue: 2, volume: 0.5),
              ),
            ],
          ),
        ],
      );

      final json = bonyCanonicalAnimationClipJson(
        clip,
        setupSlots: const [
          SlotData(name: 'back', bone: 'root', attachment: ''),
          SlotData(name: 'front', bone: 'tip', attachment: ''),
        ],
      );

      expect(json, contains('"property": "translate"'));
      expect(json, contains('"curveX": "linear"'));
      expect(json, contains('"property": "sequence"'));
      expect(json, contains('"mode": "loop"'));
      expect(
        bonyCanonicalDrawOrderOffsets(
          clip.drawOrderTimeline!.keys.single,
          const [
            SlotData(name: 'back', bone: 'root', attachment: ''),
            SlotData(name: 'front', bone: 'tip', attachment: ''),
          ],
        ).map((o) => o.slot),
        ['back', 'front'],
      );
      expect(json, contains('"deformTimelines"'));
      expect(json, contains('"attachment": "cloth"'));
      expect(json, contains('"eventTimelines"'));
      expect(json, contains('"name": "hit"'));
      expect(json, isNot(contains('deformKeys')));
      expect(json, isNot(contains('timelineKeys')));
    });

    test('projects state machines using name references', () {
      final machine = StateMachineData(
        name: 'sm',
        inputs: const [
          StateMachineInput(name: 'pressed', kind: StateMachineInputKind.bool_),
          StateMachineInput(
            name: 'speed',
            kind: StateMachineInputKind.number,
            defaultNumber: 1,
          ),
        ],
        layers: const [
          StateMachineLayer(
            name: 'base',
            initialState: 'idle',
            states: [
              StateMachineState(
                name: 'idle',
                kind: StateMachineStateKind.clip,
                clipName: 'idle_clip',
              ),
              StateMachineState(
                name: 'move',
                kind: StateMachineStateKind.blend1d,
                blendInput: 'speed',
                blendClips: [
                  StateMachineBlendClip(clipName: 'walk', value: 0),
                  StateMachineBlendClip(clipName: 'run', value: 1, loop: true),
                ],
              ),
            ],
            transitions: [
              StateMachineTransition(
                fromState: 'idle',
                toState: 'move',
                conditions: [
                  StateMachineCondition(
                    input: 'pressed',
                    kind: StateMachineConditionKind.boolEquals,
                    boolValue: true,
                  ),
                  StateMachineCondition(
                    input: 'speed',
                    kind: StateMachineConditionKind.numberGreater,
                    numberValue: 0.5,
                  ),
                ],
              ),
            ],
          ),
        ],
        listeners: const [
          StateMachineListener(
            name: 'down',
            kind: StateMachineListenerKind.pointerDown,
            slot: 'front',
            targetKind: PointerHelperTargetKind.point,
            target: 'hit',
            hitRadius: 6,
            input: 'pressed',
            boolValue: true,
          ),
        ],
      );

      final json = bonyCanonicalStateMachineJson(machine);

      expect(json, contains('"clip": "idle_clip"'));
      expect(json, contains('"blendInput": "speed"'));
      expect(json, contains('"clip": "run"'));
      expect(json, contains('"fromState": "idle"'));
      expect(json, contains('"toState": "move"'));
      expect(json, contains('"kind": "boolEquals"\n'));
      expect(json, isNot(contains('"value": true,\n')));
      expect(
          json,
          contains('"kind": "numberGreater",\n'
              '              "value": 0.5'));
      expect(json, contains('"targetKind": "point"'));
      expect(json, isNot(contains('"state": 0')));
      expect(json, isNot(contains('"clipIndex"')));
    });
  });
}

SkeletonData _fixtureSkeleton({List<SkinData> skins = const []}) {
  return SkeletonData(
    header: const SkeletonHeader(name: 'fixture', version: '1'),
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
        name: 'tip',
        parent: 'root',
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
    slots: const [
      SlotData(name: 'back', bone: 'root', attachment: ''),
      SlotData(name: 'front', bone: 'tip', attachment: ''),
    ],
    regions: const [],
    paths: const [
      PathConstraintData(
        name: 'path',
        bone: 'root',
        target: 'tip',
        path: 'curve',
        order: 0,
      ),
    ],
    pathAttachments: const [],
    ikConstraints: const [
      IkConstraintData(
          name: 'ik', bones: ['root', 'tip'], target: 'tip', order: 0),
    ],
    transformConstraints: const [
      TransformConstraintData(
          name: 'tc', bone: 'tip', target: 'root', order: 0),
    ],
    physicsConstraints: const [
      PhysicsConstraintData(
        name: 'phys',
        bone: 'tip',
        channels: {PhysicsChannel.x},
      ),
    ],
    skins: skins,
  );
}
