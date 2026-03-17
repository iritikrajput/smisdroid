import 'package:flutter/material.dart';
import '../../core/utils/extensions.dart';

class RiskBadge extends StatelessWidget {
  final String riskLevel;
  final bool large;

  const RiskBadge({
    super.key,
    required this.riskLevel,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 16 : 10,
        vertical: large ? 8 : 4,
      ),
      decoration: BoxDecoration(
        color: riskLevel.riskBackgroundColor,
        borderRadius: BorderRadius.circular(large ? 20 : 12),
        border: Border.all(
          color: riskLevel.riskColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            riskLevel.riskIcon,
            size: large ? 18 : 14,
            color: riskLevel.riskColor,
          ),
          const SizedBox(width: 4),
          Text(
            riskLevel,
            style: TextStyle(
              color: riskLevel.riskColor,
              fontWeight: FontWeight.bold,
              fontSize: large ? 14 : 11,
            ),
          ),
        ],
      ),
    );
  }
}
