import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/features/admin/presentation/admin_pages.dart';

void main() {
  test('admin login lands on the first published section in projection order', () {
    expect(firstLiveAdminSection(['overview', 'users', 'audit']), 'overview');
    expect(firstLiveAdminSection(['audit', 'users']), 'audit');
    expect(firstLiveAdminSection(['/settings', 'library']), 'security');
    expect(firstLiveAdminSection(const []), 'security');
  });
}
