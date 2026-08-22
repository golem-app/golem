import 'package:flutter/widgets.dart';

/// The width [text] takes on one line in [style] as [context] would paint
/// it — the ambient default style, text scale and direction included — for
/// layouts that reserve room for a figure's widest value.
double textWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
