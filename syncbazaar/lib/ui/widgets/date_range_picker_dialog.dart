import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/motion.dart';

/// A centred, dimmed-barrier calendar for picking a start and end date.
///
/// Replaces Flutter's `showDateRangePicker`, which opens as a full-screen
/// route on narrow windows and brings its own Material 2 chrome — a different
/// visual language from every other surface in this app, and no control over
/// spacing.
///
/// Interaction follows the pattern people already know from booking sites
/// (Jakob's law): the first tap sets the start, the second sets the end, and a
/// third starts over. Tapping a date *before* the current start doesn't error —
/// it just becomes the new start, because that's what someone correcting
/// themselves means.
Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialRange,
  String title = 'Select dates',
}) {
  return showDialog<DateTimeRange>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) => _DateRangePickerDialog(
      firstDate: _dateOnly(firstDate),
      lastDate: _dateOnly(lastDate),
      initialRange: initialRange,
      title: title,
    ),
  );
}

/// Picks one day, in the same calendar as [showAppDateRangePicker].
///
/// The range picker needs two taps even for a single day, which is wrong for a
/// birthday or a hire date. Here one tap selects and Apply confirms. Returns
/// null when dismissed.
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? initialDate,
  String title = 'Select date',
}) async {
  final picked = await showDialog<DateTimeRange>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) => _DateRangePickerDialog(
      firstDate: _dateOnly(firstDate),
      lastDate: _dateOnly(lastDate),
      initialRange: initialDate == null
          ? null
          : DateTimeRange(
              start: _dateOnly(initialDate),
              end: _dateOnly(initialDate),
            ),
      title: title,
      singleDate: true,
    ),
  );
  return picked?.start;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _DateRangePickerDialog extends StatefulWidget {
  const _DateRangePickerDialog({
    required this.firstDate,
    required this.lastDate,
    required this.initialRange,
    required this.title,
    this.singleDate = false,
  });

  /// One day instead of a span: a tap selects it outright.
  final bool singleDate;

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange? initialRange;
  final String title;

  @override
  State<_DateRangePickerDialog> createState() => _DateRangePickerDialogState();
}

/// What the calendar body is showing. Picking goes year, then month, then day:
/// a far-off date (a hire date years back) is three taps instead of hundreds
/// on the previous-month arrow.
enum _PickerView { days, months, years }

class _DateRangePickerDialogState extends State<_DateRangePickerDialog> {
  late DateTime _visibleMonth;
  DateTime? _start;
  DateTime? _end;
  _PickerView _view = _PickerView.days;
  ScrollController? _yearScroll;

  /// Height of the year and month views, so the dialog does not jump in size
  /// when switching to and from a five- or six-row month.
  static const _kPanelHeight = 264.0;
  static const _kYearRowHeight = 48.0;

  @override
  void dispose() {
    _yearScroll?.dispose();
    super.dispose();
  }

  void _openYears() {
    _yearScroll?.dispose();
    final index = _visibleMonth.year - widget.firstDate.year;
    // Three to a row. Scrolled so the current year lands a row or two down
    // rather than flush against the top edge.
    final offset = ((index ~/ 3) - 1) * _kYearRowHeight;
    _yearScroll = ScrollController(
      initialScrollOffset: offset < 0 ? 0 : offset,
    );
    setState(() => _view = _PickerView.years);
  }

  void _pickYear(int year) {
    setState(() {
      // Kept inside the allowed range: picking the newest year while the
      // visible month is past the last allowed one would open a dead month.
      var month = _visibleMonth.month;
      if (year == widget.firstDate.year && month < widget.firstDate.month) {
        month = widget.firstDate.month;
      }
      if (year == widget.lastDate.year && month > widget.lastDate.month) {
        month = widget.lastDate.month;
      }
      _visibleMonth = DateTime(year, month);
      _view = _PickerView.months;
    });
  }

  void _pickMonth(int month) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, month);
      _view = _PickerView.days;
    });
  }

  @override
  void initState() {
    super.initState();
    _start = widget.initialRange?.start;
    _end = widget.initialRange?.end;
    // With nothing chosen, open on today, held inside the allowed range. It
    // used to open on the earliest allowed day, which for a hire date meant
    // January 1990.
    final now = DateTime.now();
    var today = DateTime(now.year, now.month, now.day);
    if (today.isBefore(widget.firstDate)) today = widget.firstDate;
    if (today.isAfter(widget.lastDate)) today = widget.lastDate;
    final anchor = _start ?? today;
    _visibleMonth = DateTime(anchor.year, anchor.month);
  }

  bool get _canGoBack {
    final previous = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    return !previous.isBefore(
      DateTime(widget.firstDate.year, widget.firstDate.month),
    );
  }

  bool get _canGoForward {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    return !next.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month));
  }

  void _selectDay(DateTime day) {
    if (widget.singleDate) {
      setState(() {
        _start = day;
        _end = day;
      });
      return;
    }
    setState(() {
      final hasCompleteRange = _start != null && _end != null;
      // A third tap starts a new range, and a tap before the current start
      // becomes the new start rather than being rejected — correcting yourself
      // shouldn't need a Clear button first.
      if (hasCompleteRange || _start == null || day.isBefore(_start!)) {
        _start = day;
        _end = null;
        return;
      }
      _end = day;
    });
  }

  bool _isInRange(DateTime day) {
    if (_start == null || _end == null) return false;
    return day.isAfter(_start!) && day.isBefore(_end!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canApply = _start != null && _end != null;

    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.97, end: 1),
        duration: AppMotion.entrance,
        curve: AppMotion.easeOut,
        builder: (context, value, child) => Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0, 1), child: child),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context, theme),
              const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  children: [
                    _buildMonthNav(theme),
                    const SizedBox(height: 14),
                    if (_view == _PickerView.days) ...[
                      _buildWeekdayHeader(theme),
                      const SizedBox(height: 6),
                      _buildMonthGrid(theme),
                    ] else if (_view == _PickerView.months)
                      _buildMonthPicker(theme)
                    else
                      _buildYearPicker(theme),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              _buildFooter(context, canApply),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    final format = DateFormat('MMM d, y');
    // The header doubles as the readout: it always states the current
    // selection, so the result of a tap is confirmed without looking away
    // from the grid.
    final String summary;
    if (widget.singleDate) {
      summary = _start == null
          ? 'Tap a day to select it'
          : format.format(_start!);
    } else if (_start == null) {
      summary = 'Tap a day to set the start date';
    } else if (_end == null) {
      summary = '${format.format(_start!)} — now pick the end date';
    } else {
      final days = _end!.difference(_start!).inDays + 1;
      summary =
          '${format.format(_start!)} – ${format.format(_end!)}  ·  '
          '$days ${days == 1 ? 'day' : 'days'}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 10, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _start != null && _end != null
                        ? AppColors.primary
                        : Colors.black45,
                    fontSize: 12,
                    fontWeight: _start != null && _end != null
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            splashRadius: 18,
            tooltip: 'Close',
            icon: const Icon(
              Icons.close_rounded,
              size: 17,
              color: Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthNav(ThemeData theme) {
    final inYears = _view == _PickerView.years;
    final inMonths = _view == _PickerView.months;

    // The arrows step what the view is showing: months on the day grid, years
    // on the month grid. The year list scrolls, so it has none.
    final step = inMonths ? 12 : 1;
    final canBack = inMonths
        ? _visibleMonth.year > widget.firstDate.year
        : _canGoBack;
    final canForward = inMonths
        ? _visibleMonth.year < widget.lastDate.year
        : _canGoForward;

    final title = inYears
        ? 'Select year'
        : inMonths
        ? '${_visibleMonth.year}'
        : DateFormat('MMMM y').format(_visibleMonth);

    return Row(
      children: [
        if (inYears)
          const SizedBox(width: 40)
        else
          _NavButton(
            icon: Icons.chevron_left_rounded,
            tooltip: inMonths ? 'Previous year' : 'Previous month',
            onPressed: canBack
                ? () => setState(() {
                    _visibleMonth = DateTime(
                      _visibleMonth.year,
                      _visibleMonth.month - step,
                    );
                  })
                : null,
          ),
        Expanded(
          // The title is the way in to the year list, and says so with a
          // chevron: an unmarked heading is not read as a control.
          child: Center(
            child: InkWell(
              onTap: inYears
                  ? () => setState(() => _view = _PickerView.days)
                  : _openYears,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      inYears
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (inYears)
          const SizedBox(width: 40)
        else
          _NavButton(
            icon: Icons.chevron_right_rounded,
            tooltip: inMonths ? 'Next year' : 'Next month',
            onPressed: canForward
                ? () => setState(() {
                    _visibleMonth = DateTime(
                      _visibleMonth.year,
                      _visibleMonth.month + step,
                    );
                  })
                : null,
          ),
      ],
    );
  }

  Widget _buildYearPicker(ThemeData theme) {
    final first = widget.firstDate.year;
    final last = widget.lastDate.year;
    final count = last - first + 1;
    final selected = _start?.year;

    return SizedBox(
      height: _kPanelHeight,
      child: GridView.builder(
        controller: _yearScroll,
        itemCount: count,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisExtent: _kYearRowHeight,
          mainAxisSpacing: 0,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, i) {
          final year = first + i;
          return _PeriodCell(
            label: '$year',
            isSelected: year == _visibleMonth.year,
            // The year of the chosen date, when it is not the one in view, is
            // ringed so it can be found again in a long list.
            isMarked: selected == year && year != _visibleMonth.year,
            onTap: () => _pickYear(year),
          );
        },
      ),
    );
  }

  Widget _buildMonthPicker(ThemeData theme) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
    ];
    final year = _visibleMonth.year;

    bool outOfRange(int month) {
      final value = DateTime(year, month);
      return value.isBefore(
            DateTime(widget.firstDate.year, widget.firstDate.month),
          ) ||
          value.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month));
    }

    return SizedBox(
      height: _kPanelHeight,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 12,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisExtent: 62,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, i) {
          final month = i + 1;
          return _PeriodCell(
            label: names[i],
            isSelected: month == _visibleMonth.month,
            isDisabled: outOfRange(month),
            onTap: () => _pickMonth(month),
          );
        },
      ),
    );
  }

  Widget _buildWeekdayHeader(ThemeData theme) {
    const labels = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: SizedBox(
              height: 24,
              child: Center(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black38,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMonthGrid(ThemeData theme) {
    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month);
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    // DateTime.weekday is 1=Mon..7=Sun; this grid starts on Sunday.
    final leadingBlanks = firstOfMonth.weekday % 7;
    final cells = leadingBlanks + daysInMonth;
    final rows = (cells / 7).ceil();

    return Column(
      children: [
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _buildCell(theme, row * 7 + col - leadingBlanks + 1),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildCell(ThemeData theme, int dayNumber) {
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 40);
    }

    final day = DateTime(_visibleMonth.year, _visibleMonth.month, dayNumber);
    final isDisabled =
        day.isBefore(widget.firstDate) || day.isAfter(widget.lastDate);
    final isStart = _start != null && _isSameDay(day, _start!);
    final isEnd = _end != null && _isSameDay(day, _end!);
    final isEndpoint = isStart || isEnd;
    final inRange = _isInRange(day);

    // The connecting band is drawn on the cell behind the endpoint circles, so
    // a selected range reads as one continuous shape instead of separate dots.
    BorderRadius? bandRadius;
    if (widget.singleDate) {
      bandRadius = null;
    } else if (isStart && _end != null) {
      bandRadius = const BorderRadius.horizontal(left: Radius.circular(20));
    } else if (isEnd && _start != null) {
      bandRadius = const BorderRadius.horizontal(right: Radius.circular(20));
    } else if (inRange) {
      bandRadius = BorderRadius.zero;
    }

    return SizedBox(
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (bandRadius != null)
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: bandRadius,
                ),
              ),
            ),
          Center(
            child: InkWell(
              onTap: isDisabled ? null : () => _selectDay(day),
              customBorder: const CircleBorder(),
              child: AnimatedContainer(
                duration: AppMotion.feedback,
                curve: AppMotion.easeOut,
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isEndpoint ? AppColors.primary : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$dayNumber',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDisabled
                        ? Colors.black26
                        : isEndpoint
                        ? Colors.white
                        : AppColors.text,
                    fontWeight: isEndpoint || inRange
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, bool canApply) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          TextButton(
            onPressed: _start == null && _end == null
                ? null
                : () => setState(() {
                    _start = null;
                    _end = null;
                  }),
            style: TextButton.styleFrom(
              foregroundColor: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            child: const Text('Clear'),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: canApply
                ? () => Navigator.pop(
                    context,
                    DateTimeRange(start: _start!, end: _end!),
                  )
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary.withValues(
                alpha: 0.35,
              ),
              disabledForegroundColor: Colors.white70,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}

/// One year or month in the picker's list: a roomy, flat target, filled when it
/// is the one in view.
class _PeriodCell extends StatelessWidget {
  const _PeriodCell({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isDisabled = false,
    this.isMarked = false,
  });

  final String label;
  final bool isSelected;
  final bool isDisabled;
  final bool isMarked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: AppMotion.feedback,
          curve: AppMotion.easeOut,
          height: 40,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isMarked
                ? Border.all(color: AppColors.primary, width: 1.5)
                : null,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDisabled
                  ? Colors.black26
                  : isSelected
                  ? Colors.white
                  : AppColors.text,
              fontWeight: isSelected || isMarked
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onPressed == null ? Colors.transparent : AppColors.inputFill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 19,
            color: onPressed == null ? Colors.black26 : Colors.black54,
          ),
        ),
      ),
    );
  }
}
