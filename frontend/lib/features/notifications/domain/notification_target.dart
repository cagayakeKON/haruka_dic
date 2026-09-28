import '../../library/domain/material_summary.dart';
import 'notification_record.dart';

LearningMaterialType? notificationMaterialType(String route) => switch (route) {
  'novel' => LearningMaterialType.novel,
  'textbook' => LearningMaterialType.textbook,
  'examPrep' => LearningMaterialType.exam,
  _ => null,
};

/// A notification is a pointer, never evidence of current source access.
bool notificationTargetMatches(NotificationRecord item, MaterialSummary material) {
  final type = notificationMaterialType(item.route);
  if (type == null ||
      item.resourceId == null ||
      item.resourceRevision == null ||
      item.resourceId != material.id ||
      item.resourceRevision != material.revision ||
      type != material.type) {
    return false;
  }
  return switch (type) {
    LearningMaterialType.novel || LearningMaterialType.textbook => material.status == 'readable',
    LearningMaterialType.exam => material.status == 'needs_review' || material.status == 'readable',
  };
}
