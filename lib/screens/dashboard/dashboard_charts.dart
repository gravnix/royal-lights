import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import 'dashboard_ui.dart';

/// Chart primitives for the dashboard.
///
/// Two rules drive the choices here:
/// * **One measure per plot.** Orders and new customers are separate charts
///   stacked as small multiples, never two y-scales on one frame.
/// * **Severity bands are sequential, not categorical.** Ordered bands use one
///   hue stepped light→dark ([severityRamp]); green/amber/red cannot be told
///   apart under protanopia, so it is not used for adjacent fills. Every band
///   carries a visible label and count, so identity is never colour alone.

/// Brand-gold sequential ramp, light→dark. Luminance is monotonically
/// decreasing (0.586 → 0.267 → 0.113), so it reads as an ordered scale in
/// greyscale and under any colour-vision deficiency.
const List<Color> severityRamp = [
  Color(0xFFE3C77A),
  Color(0xFFA88A2E),
  Color(0xFF735C00), // == AppTheme.secondary
];

/// Steps for a scale of [count] segments drawn from [severityRamp].
List<Color> rampSteps(int count) {
  if (count <= 1) return [severityRamp.last];
  if (count <= 3) {
    return List.generate(
      count,
      (i) => severityRamp[(i * (severityRamp.length - 1) ~/ (count - 1))],
    );
  }
  // Interpolate for longer scales (the 8-stage order pipeline).
  return List.generate(count, (i) {
    final t = i / (count - 1) * (severityRamp.length - 1);
    final low = t.floor().clamp(0, severityRamp.length - 1);
    final high = t.ceil().clamp(0, severityRamp.length - 1);
    return Color.lerp(severityRamp[low], severityRamp[high], t - low)!;
  });
}

// ─────────────────────────────────────────────────────────────────
// Single-series bar chart
// ─────────────────────────────────────────────────────────────────

class BarDatum {
  final String label;
  final String tooltip;
  final num value;

  const BarDatum({
    required this.label,
    required this.tooltip,
    required this.value,
  });
}

/// One measure over time. Direct-labels only the peak — a number on every bar
/// is noise; the rest are available on hover.
class TrendBarChart extends StatelessWidget {
  final List<BarDatum> data;
  final Color color;
  final double height;

  /// Show only every Nth x label when the axis would otherwise collide.
  final int labelStride;

  /// Stacked small multiples share one x axis — only the lowest plot labels it.
  final bool showLabels;

  const TrendBarChart({
    super.key,
    required this.data,
    required this.color,
    this.height = 96,
    this.labelStride = 1,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return SizedBox(height: height);

    final maxValue = data.fold<num>(0, (m, d) => d.value > m ? d.value : m);
    final peakIndex = maxValue == 0
        ? -1
        : data.indexWhere((d) => d.value == maxValue);

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < data.length; i++)
            Expanded(
              child: Padding(
                // 2px surface gap between adjacent fills.
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: _Bar(
                  datum: data[i],
                  maxValue: maxValue,
                  color: color,
                  showValue: i == peakIndex,
                  showLabel: showLabels && i % labelStride == 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final BarDatum datum;
  final num maxValue;
  final Color color;
  final bool showValue;
  final bool showLabel;

  const _Bar({
    required this.datum,
    required this.maxValue,
    required this.color,
    required this.showValue,
    required this.showLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isZero = datum.value <= 0;
    // Keep a hairline for empty buckets so the axis stays legible.
    final factor = maxValue == 0
        ? 0.02
        : (datum.value / maxValue).clamp(0.02, 1.0).toDouble();

    return Tooltip(
      message: datum.tooltip,
      textStyle: GoogleFonts.assistant(
        color: AppTheme.onPrimary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 14,
            child: showValue
                ? FittedBox(
                    child: Text(
                      count(datum.value),
                      style: GoogleFonts.assistant(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onSurface,
                      ),
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: factor,
                widthFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: isZero
                        ? AppTheme.outlineVariant.withValues(alpha: 0.5)
                        : color,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 14,
            child: showLabel
                ? FittedBox(
                    child: Text(
                      datum.label,
                      style: GoogleFonts.assistant(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Segmented proportion bar
// ─────────────────────────────────────────────────────────────────

class BarSegment {
  final String label;
  final int count;
  final Color color;

  /// Optional secondary figure (a ₪ total) shown in the legend.
  final String? detail;

  const BarSegment({
    required this.label,
    required this.count,
    required this.color,
    this.detail,
  });
}

/// Horizontal composition bar plus a legend. The bar carries proportion; the
/// legend carries identity and the exact numbers, so nothing depends on colour
/// alone. Follows text direction, so in Hebrew it reads right-to-left.
class SegmentedProportionBar extends StatelessWidget {
  final List<BarSegment> segments;
  final VoidCallback? onTap;

  /// Legend layout: a row of columns (wide cards) or stacked rows (narrow).
  final bool stackedLegend;

  const SegmentedProportionBar({
    super.key,
    required this.segments,
    this.onTap,
    this.stackedLegend = false,
  });

  @override
  Widget build(BuildContext context) {
    final visible = segments.where((s) => s.count > 0).toList();
    final total = visible.fold<int>(0, (sum, s) => sum + s.count);

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 12,
        child: total == 0
            ? Container(
                color: AppTheme.surfaceContainerHighest.withValues(alpha: 0.6),
              )
            : Row(
                children: [
                  for (var i = 0; i < visible.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: visible[i].count,
                      child: Container(color: visible[i].color),
                    ),
                  ],
                ],
              ),
      ),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar,
        const SizedBox(height: 14),
        if (stackedLegend)
          Column(
            children: [
              for (final s in segments) ...[
                _LegendRow(segment: s, total: total),
                const SizedBox(height: 8),
              ],
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: _LegendColumn(segment: segments[i])),
              ],
            ],
          ),
      ],
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: content,
    );
  }
}

class _LegendColumn extends StatelessWidget {
  final BarSegment segment;

  const _LegendColumn({required this.segment});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: segment.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                segment.label,
                style: GoogleFonts.assistant(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          count(segment.count),
          style: GoogleFonts.assistant(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppTheme.onSurface,
            height: 1.1,
          ),
        ),
        if (segment.detail != null)
          Text(
            segment.detail!,
            style: GoogleFonts.assistant(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  final BarSegment segment;
  final int total;

  const _LegendRow({required this.segment, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: segment.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            segment.label,
            style: GoogleFonts.assistant(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        if (segment.detail != null) ...[
          Text(
            segment.detail!,
            style: GoogleFonts.assistant(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
        ],
        Text(
          count(segment.count),
          style: GoogleFonts.assistant(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppTheme.onSurface,
          ),
        ),
      ],
    );
  }
}
