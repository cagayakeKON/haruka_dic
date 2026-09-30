import 'package:flutter/material.dart';

/// Icon keys are restricted by the server's published navigation catalogue.
IconData publishedNavigationIcon(String? key, IconData fallback) => switch (key) {
  'grid' => Icons.grid_view_outlined,
  'person' => Icons.person_outline,
  'shield' => Icons.shield_outlined,
  'layers' => Icons.layers_outlined,
  'settings' => Icons.settings_outlined,
  'schedule' => Icons.schedule,
  'book' => Icons.menu_book_outlined,
  'spark' => Icons.auto_awesome_outlined,
  'library' => Icons.library_books_outlined,
  'notebooks' => Icons.bookmarks_outlined,
  'query' => Icons.search,
  'exercise' => Icons.edit_note_outlined,
  _ => fallback,
};
