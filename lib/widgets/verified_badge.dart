import 'package:flutter/material.dart';

/// Renders authentic verification badge from lib/verif/verif.png
Widget buildVerifiedBadge({double size = 16}) {
  return Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Image.asset(
      'lib/verif/verif.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Icon(
          Icons.verified_rounded,
          size: size,
          color: const Color(0xFF3390EC),
        );
      },
    ),
  );
}
