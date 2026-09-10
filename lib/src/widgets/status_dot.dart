/// Small status indicator dot (green/red/amber/grey).
library;

import 'package:flutter/material.dart';

enum StatusSeverity { ok, error, busy, idle }

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.severity, this.size = 10});

  final StatusSeverity severity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = switch (severity) {
      StatusSeverity.ok => Colors.green,
      StatusSeverity.error => Colors.red,
      StatusSeverity.busy => Colors.amber.shade700,
      StatusSeverity.idle => Colors.grey,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
