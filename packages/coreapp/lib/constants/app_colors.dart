import 'package:flutter/material.dart';

/// Shared palette. Screens and widgets should use these tokens instead of
/// raw hex / [Colors] so the host app and every game plugin stay in sync.
abstract final class AppColors {
  /// Main app background (`#19194D`).
  static const background = Color(0xFF19194D);

  /// Text / icons on [background].
  static const onBackground = Color(0xFFFFFFFF);
  static const white = Color(0xFFFFFFFF);

  static const hint = Color(0x99FFFFFF);
  static const grey = Color(0xFFE4E0E0);

  /// Overlay dim used by [BaseLoader] and [ConnectionLoader].
  static const scrim = Color(0x80000000);

  /// Connection-loader card (`#6E45E2`).
  static const connectionCard = Color(0xFF6E45E2);

  /// Destructive / exit text (`#FF5959`).
  static const error = Color(0xFFFF5959);

  /// Lobby cards (`#15143E`).
  static const card = Color(0xFF15143E);

  /// Timer / highlight (`#FFCF4D`).
  static const yellow = Color(0xFFFFCF4D);

  /// Report / accent (`#62AAF3`).
  static const blue = Color(0xFF62AAF3);

  /// Pass button (`#50AAF2`).
  static const button = Color(0xFF50AAF2);

  /// Selected answer / purple stroke (`#6E45E2`).
  static const purple = Color(0xFF6E45E2);

  /// Inactive strike (`#433D6C`).
  static const strikeInactive = Color(0xFF433D6C);

  /// Image / block skeleton base.
  static const skeleton = Color(0xFF121138);

  /// Image / block skeleton shimmer highlight.
  static const skeletonHighlight = Color(0x8115143E);

  /// Unselected answer chip fill (`#121138`).
  static const answerChip = Color(0xFF121138);

  /// Score / attempts (`#2DDB9C`).
  static const green = Color(0xFF2DDB9C);

  /// Stat-pill stroke (`#DF5CFA`).
  static const statStroke = Color(0xFFDF5CFA);

  /// Light divider (`#7EECEAEA`).
  static const divider = Color(0x7EECEAEA);
}
