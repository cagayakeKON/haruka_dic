enum LayoutSize { compact, medium, expanded }

abstract final class AdaptivePolicy {
  static LayoutSize forWidth(double width) {
    if (width < 600) return LayoutSize.compact;
    if (width < 1024) return LayoutSize.medium;
    return LayoutSize.expanded;
  }
}
