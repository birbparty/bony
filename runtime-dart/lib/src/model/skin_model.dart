import 'animation_model.dart';
import 'attachment_model.dart';
import 'bone_slot_model.dart';
import 'constraint_model.dart';
import 'deformer_model.dart';
import 'state_machine_model.dart';

class SkinEntryData {
  const SkinEntryData({
    required this.slot,
    required this.attachment,
    required this.target,
  });

  final String slot;
  final String attachment;
  final String target;
}

class SkinData {
  const SkinData({
    required this.name,
    this.entries = const [],
    this.bones = const [],
    this.ikConstraints = const [],
    this.transformConstraints = const [],
    this.pathConstraints = const [],
    this.physicsConstraints = const [],
  });

  final String name;
  final List<SkinEntryData> entries;
  final List<String> bones;
  final List<String> ikConstraints;
  final List<String> transformConstraints;
  final List<String> pathConstraints;
  final List<String> physicsConstraints;
}

class SkeletonData {
  const SkeletonData({
    required this.header,
    required this.bones,
    required this.slots,
    required this.regions,
    required this.paths,
    required this.pathAttachments,
    this.pointAttachments = const [],
    this.boundingBoxAttachments = const [],
    this.nestedRigAttachments = const [],
    this.clippingAttachments = const [],
    this.meshAttachments = const [],
    this.ikConstraints = const [],
    this.transformConstraints = const [],
    this.physicsConstraints = const [],
    this.skins = const [],
    this.animations = const [],
    this.parameters = const [],
    this.deformers = const [],
    this.stateMachines = const [],
    this.deformOverrides = const [],
  });

  final SkeletonHeader header;
  final List<BoneData> bones;
  final List<SlotData> slots;
  final List<RegionAttachment> regions;
  final List<PathConstraintData> paths;
  final List<PathAttachment> pathAttachments;
  final List<PointAttachment> pointAttachments;
  final List<BoundingBoxAttachment> boundingBoxAttachments;
  final List<NestedRigAttachment> nestedRigAttachments;
  final List<ClippingAttachment> clippingAttachments;
  final List<MeshAttachment> meshAttachments;
  final List<IkConstraintData> ikConstraints;
  final List<TransformConstraintData> transformConstraints;
  final List<PhysicsConstraintData> physicsConstraints;
  final List<SkinData> skins;
  final List<AnimationClip> animations;
  final List<ParameterAxis> parameters;
  final List<DeformerRecord> deformers;
  final List<StateMachineData> stateMachines;

  /// Transient per-slot/attachment deform-timeline override staged by
  /// `applyPose` and applied to skinned mesh vertices in `buildDrawBatches`.
  /// Non-serialized: excluded from any `.bony`/`.bnb` round-trip, mirroring the
  /// Nim reference seam (docs/deform-timeline-contract.md).
  final List<DeformOverride> deformOverrides;

  /// All concrete attachment records. Loader validation keeps slot-visible
  /// attachment names unambiguous across render/helper/clip/nested families;
  /// callers that key this iterable by name rely on that invariant. Path
  /// attachments are included for family exhaustiveness, not slot visibility.
  Iterable<Attachment> get allAttachments sync* {
    yield* regions;
    yield* pathAttachments;
    yield* pointAttachments;
    yield* boundingBoxAttachments;
    yield* nestedRigAttachments;
    yield* clippingAttachments;
    yield* meshAttachments;
  }
}

class ActiveSkinMembership {
  const ActiveSkinMembership({
    required this.activeSkin,
    required this.bones,
    required this.ikConstraints,
    required this.transformConstraints,
    required this.pathConstraints,
    required this.physicsConstraints,
  });

  final String activeSkin;
  final List<bool> bones;
  final List<bool> ikConstraints;
  final List<bool> transformConstraints;
  final List<bool> pathConstraints;
  final List<bool> physicsConstraints;
}

extension SkinResolution on SkeletonData {
  bool hasSkin(String skinName) {
    if (skins.isEmpty) return skinName == 'default';
    for (final skin in skins) {
      if (skin.name == skinName) return true;
    }
    return false;
  }

  String resolveSkinAttachmentTarget(
    String activeSkin,
    String slotName,
    String attachmentName,
  ) {
    if (attachmentName.isEmpty) return '';
    if (skins.isEmpty) return attachmentName;
    for (final skin in skins) {
      if (skin.name == activeSkin) {
        for (final entry in skin.entries) {
          if (entry.slot == slotName && entry.attachment == attachmentName) {
            return entry.target;
          }
        }
        break;
      }
    }
    if (activeSkin != 'default') {
      for (final skin in skins) {
        if (skin.name == 'default') {
          for (final entry in skin.entries) {
            if (entry.slot == slotName && entry.attachment == attachmentName) {
              return entry.target;
            }
          }
          break;
        }
      }
    }
    return '';
  }

  ({
    Set<String> bones,
    Set<String> ikConstraints,
    Set<String> transformConstraints,
    Set<String> pathConstraints,
    Set<String> physicsConstraints,
  }) _runtimeSkinMembership(String activeSkin) {
    final bones = <String>{};
    final ikConstraints = <String>{};
    final transformConstraints = <String>{};
    final pathConstraints = <String>{};
    final physicsConstraints = <String>{};

    if (skins.isEmpty) {
      if (activeSkin != 'default') {
        throw FormatException('unknown active skin: $activeSkin');
      }
      return (
        bones: bones,
        ikConstraints: ikConstraints,
        transformConstraints: transformConstraints,
        pathConstraints: pathConstraints,
        physicsConstraints: physicsConstraints,
      );
    }

    var foundDefault = false;
    var foundActive = activeSkin == 'default';
    for (final skin in skins) {
      if (skin.name == 'default') {
        bones.addAll(skin.bones);
        ikConstraints.addAll(skin.ikConstraints);
        transformConstraints.addAll(skin.transformConstraints);
        pathConstraints.addAll(skin.pathConstraints);
        physicsConstraints.addAll(skin.physicsConstraints);
        foundDefault = true;
        break;
      }
    }
    if (!foundDefault) {
      throw const FormatException('skins must contain default skin');
    }

    if (activeSkin != 'default') {
      for (final skin in skins) {
        if (skin.name == activeSkin) {
          bones.addAll(skin.bones);
          ikConstraints.addAll(skin.ikConstraints);
          transformConstraints.addAll(skin.transformConstraints);
          pathConstraints.addAll(skin.pathConstraints);
          physicsConstraints.addAll(skin.physicsConstraints);
          foundActive = true;
          break;
        }
      }
    }
    if (!foundActive) {
      throw FormatException('unknown active skin: $activeSkin');
    }

    return (
      bones: bones,
      ikConstraints: ikConstraints,
      transformConstraints: transformConstraints,
      pathConstraints: pathConstraints,
      physicsConstraints: physicsConstraints,
    );
  }

  ActiveSkinMembership activeSkinMembership([String activeSkin = 'default']) {
    final membership = _runtimeSkinMembership(activeSkin);
    final boneByName = <String, int>{};
    final activeBones = List<bool>.filled(bones.length, false);

    for (var index = 0; index < bones.length; index++) {
      final bone = bones[index];
      boneByName[bone.name] = index;
      final directlyActive =
          !bone.skinRequired || membership.bones.contains(bone.name);
      final parentActive = bone.parent.isEmpty ||
          (boneByName.containsKey(bone.parent) &&
              activeBones[boneByName[bone.parent]!]);
      activeBones[index] = directlyActive && parentActive;
    }

    bool isBoneActive(String name) {
      final index = boneByName[name];
      return index != null && activeBones[index];
    }

    final activeIk = List<bool>.filled(ikConstraints.length, false);
    for (var index = 0; index < ikConstraints.length; index++) {
      final ik = ikConstraints[index];
      var depsActive = isBoneActive(ik.target);
      for (final boneName in ik.bones) {
        depsActive = depsActive && isBoneActive(boneName);
      }
      activeIk[index] =
          (!ik.skinRequired || membership.ikConstraints.contains(ik.name)) &&
              depsActive;
    }

    final activeTransform =
        List<bool>.filled(transformConstraints.length, false);
    for (var index = 0; index < transformConstraints.length; index++) {
      final tc = transformConstraints[index];
      activeTransform[index] = (!tc.skinRequired ||
              membership.transformConstraints.contains(tc.name)) &&
          isBoneActive(tc.bone) &&
          isBoneActive(tc.target);
    }

    final activePath = List<bool>.filled(paths.length, false);
    for (var index = 0; index < paths.length; index++) {
      final path = paths[index];
      activePath[index] = (!path.skinRequired ||
              membership.pathConstraints.contains(path.name)) &&
          isBoneActive(path.bone) &&
          isBoneActive(path.target);
    }

    final activePhysics = List<bool>.filled(physicsConstraints.length, false);
    for (var index = 0; index < physicsConstraints.length; index++) {
      final pc = physicsConstraints[index];
      activePhysics[index] = (!pc.skinRequired ||
              membership.physicsConstraints.contains(pc.name)) &&
          isBoneActive(pc.bone);
    }

    return ActiveSkinMembership(
      activeSkin: activeSkin,
      bones: activeBones,
      ikConstraints: activeIk,
      transformConstraints: activeTransform,
      pathConstraints: activePath,
      physicsConstraints: activePhysics,
    );
  }
}
