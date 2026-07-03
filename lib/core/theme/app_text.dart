import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized text helpers, mirroring the **Mynt Plus** `global_state_text.dart`
/// (`TextWidget`) pattern so font family, size and weight are handled the same
/// way across the app.
///
/// Every builder returns a ready-to-use [Text] widget on the Inter typeface with
/// a fixed size from the shared ladder:
///
/// | Builder        | Size |
/// |----------------|------|
/// | [heroText]     | 20   |
/// | [headText]     | 18   |
/// | [titleText]    | 16   |
/// | [subText]      | 14   |
/// | [paraText]     | 12   |
/// | [captionText]  | 10   |
/// | [overlineText] | 8    |
/// | [custmText]    | any  |
///
/// Weight is chosen with the same `fw` integer convention as Mynt Plus:
///
/// | `fw` | Weight            |
/// |------|-------------------|
/// | 2    | bold (w700)       |
/// | 1    | semiBold (w600)   |
/// | 0    | medium (w500)     |
/// | 3    | regular (w400)    |
/// | null | normal (w400)     |
///
/// Unlike Mynt Plus (which takes a `theme` bool and reads a global color
/// singleton), colors here default to the ambient [ColorScheme]: the primary
/// text tone `onSurface`, and the muted `onSurfaceVariant` for [paraText] /
/// [captionText] / [overlineText]. Pass [color] to override. Because the color
/// comes from the theme, these builders need a [BuildContext].
class AppText {
  AppText._();

  /// Translate the Mynt Plus `fw` integer into a [FontWeight].
  static FontWeight weight(int? fw) => switch (fw) {
    2 => FontWeight.w700,
    1 => FontWeight.w600,
    0 => FontWeight.w500,
    3 => FontWeight.w400,
    _ => FontWeight.normal,
  };

  static Color _primary(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color _muted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static Widget _text(
    String text, {
    required double fontSize,
    required Color color,
    int? fw,
    int? maxLines,
    TextAlign? align,
    TextOverflow? overflow,
    double? letterSpacing,
    double? height,
    bool? softWrap,
    TextDecoration? decoration,
    Key? key,
  }) {
    return Text(
      text,
      key: key,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: align,
      softWrap: softWrap,
      style: GoogleFonts.inter(
        textStyle: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: weight(fw),
          letterSpacing: letterSpacing,
          height: height,
          decoration: decoration,
        ),
      ),
    );
  }

  /// 20px — hero titles / the most prominent on-screen text.
  static Widget heroText(
    BuildContext context,
    String text, {
    Color? color,
    int? fw,
    int? maxLines,
    TextAlign? align,
    TextOverflow? overflow,
  }) => _text(
    text,
    fontSize: 20,
    color: color ?? _primary(context),
    fw: fw,
    maxLines: maxLines,
    align: align,
    overflow: overflow,
  );

  /// 18px — screen / page headers.
  static Widget headText(
    BuildContext context,
    String text, {
    Color? color,
    int? fw,
    int? maxLines,
    TextAlign? align,
    TextOverflow? overflow,
  }) => _text(
    text,
    fontSize: 18,
    color: color ?? _primary(context),
    fw: fw,
    maxLines: maxLines,
    align: align,
    overflow: overflow,
  );

  /// 16px — card / list-item titles.
  static Widget titleText(
    BuildContext context,
    String text, {
    Color? color,
    int? fw,
    int? maxLines,
    TextAlign? align,
    TextOverflow? overflow,
  }) => _text(
    text,
    fontSize: 16,
    color: color ?? _primary(context),
    fw: fw,
    maxLines: maxLines,
    align: align,
    overflow: overflow,
  );

  /// 14px — primary body / description text.
  static Widget subText(
    BuildContext context,
    String text, {
    Color? color,
    int? fw,
    int? maxLines,
    TextAlign? align,
    TextOverflow? overflow,
    double? letterSpacing,
    double? lineHeight,
    bool? softWrap,
    TextDecoration? decoration,
    Key? key,
  }) => _text(
    text,
    fontSize: 14,
    color: color ?? _primary(context),
    fw: fw,
    maxLines: maxLines,
    align: align,
    overflow: overflow,
    letterSpacing: letterSpacing,
    height: lineHeight,
    softWrap: softWrap,
    decoration: decoration,
    key: key,
  );

  /// 12px — secondary / muted paragraph text.
  static Widget paraText(
    BuildContext context,
    String text, {
    Color? color,
    int? fw,
    int? maxLines,
    double? height,
    TextAlign? align,
    TextOverflow? overflow,
    double? letterSpacing,
    TextDecoration? decoration,
  }) => _text(
    text,
    fontSize: 12,
    color: color ?? _muted(context),
    fw: fw,
    maxLines: maxLines,
    height: height,
    align: align,
    overflow: overflow,
    letterSpacing: letterSpacing,
    decoration: decoration,
  );

  /// 10px — captions, metadata, timestamps (muted by default).
  static Widget captionText(
    BuildContext context,
    String text, {
    Color? color,
    int? fw,
    int? maxLines,
    TextAlign? align,
    TextOverflow? overflow,
  }) => _text(
    text,
    fontSize: 10,
    color: color ?? _muted(context),
    fw: fw,
    maxLines: maxLines,
    align: align,
    overflow: overflow,
  );

  /// 8px — overline / smallest labels (muted by default).
  static Widget overlineText(
    BuildContext context,
    String text, {
    Color? color,
    int? fw,
    int? maxLines,
    TextAlign? align,
    TextOverflow? overflow,
  }) => _text(
    text,
    fontSize: 8,
    color: color ?? _muted(context),
    fw: fw,
    maxLines: maxLines,
    align: align,
    overflow: overflow,
  );

  /// Arbitrary [fs] size when the ladder doesn't fit.
  static Widget custmText(
    BuildContext context,
    String text, {
    required double fs,
    Color? color,
    int? fw,
    int? maxLines,
    TextAlign? align,
    TextOverflow? overflow,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) => _text(
    text,
    fontSize: fs,
    color: color ?? _primary(context),
    fw: fw,
    maxLines: maxLines,
    align: align,
    overflow: overflow,
    letterSpacing: letterSpacing,
    height: height,
    decoration: decoration,
  );

  /// Bare [TextStyle] (no [Text] widget) for cases that need to feed a style
  /// into an existing widget — buttons, inputs, `TextSpan`, etc.
  static TextStyle style(
    BuildContext context, {
    required double fontSize,
    Color? color,
    int? fw,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
  }) => GoogleFonts.inter(
    textStyle: TextStyle(
      fontSize: fontSize,
      color: color ?? _primary(context),
      fontWeight: weight(fw),
      height: height,
      letterSpacing: letterSpacing,
      decoration: decoration,
    ),
  );
}
