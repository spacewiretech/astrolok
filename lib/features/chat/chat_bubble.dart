import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_typography.dart';
import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../widgets/audio_bars.dart';
import 'chat_copy.dart';
import 'chat_palette.dart';

/// Where a message the person sent has got to, as WhatsApp's ticks say it.
enum BubbleStatus {
  /// Astro's messages carry no ticks.
  none,

  /// Still leaving the phone — a clock.
  pending,

  /// Sent — one grey tick.
  sent,

  /// Read — two blue ticks. Astro reads before it types, so they turn blue as "typing…" starts.
  read,
}

/// The chat's text style: WhatsApp's size and line height, in the app's body face.
TextStyle chatTextStyle() =>
    AppText.body.copyWith(fontSize: 15.5, height: 1.35, color: ChatPalette.text);

TextStyle _metaStyle() =>
    AppText.body.copyWith(fontSize: 11.5, height: 1, color: ChatPalette.meta);

/// "10:42 PM" — by hand, because the app carries no `intl`.
String formatBubbleTime(DateTime at) {
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final minute = at.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${at.hour < 12 ? 'AM' : 'PM'}';
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// The day chip over a run of messages: "Today", "Yesterday", a weekday within the week, else the
/// date — WhatsApp's own rule. Takes [now] so it can be tested across midnight.
String dayLabel(DateTime day, DateTime now) {
  final a = DateTime(day.year, day.month, day.day);
  final b = DateTime(now.year, now.month, now.day);
  final days = b.difference(a).inDays;
  if (days <= 0) return ChatCopy.ageToday;
  if (days == 1) return ChatCopy.ageYesterday;
  if (days < 7) return _weekdays[a.weekday - 1];
  return '${a.day} ${_months[a.month - 1]} ${a.year}';
}

/// The numbers a care reply carries — Tele-MANAS, iCall, 112 — made tappable to call.
final _phone = RegExp(r'(?<!\d)(?:1800-89-14416|14416|9152987821|112)(?!\d)');

/// One message.
///
/// Drawn rather than decorated, because the tail is the whole point: WhatsApp's pointed corner on
/// the first message of a run is what makes a column of boxes read as a conversation. The time and
/// the ticks sit inside, bottom right, on the last line when it has room — the invisible copy of
/// them at the end of the text is what reserves that room.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.outgoing,
    required this.time,
    this.tail = false,
    this.status = BubbleStatus.none,
    this.linkPhones = false,
    this.onSpeak,
    this.speaking = false,
  });

  final String text;

  /// The person's own message: green, on the right.
  final bool outgoing;

  final DateTime time;

  /// The first message of a run from one side, which gets the pointed corner.
  final bool tail;

  final BubbleStatus status;

  /// Care replies: the helpline numbers in them can be tapped to call.
  final bool linkPhones;

  /// The listen control, on the last of Astro's messages in a run. Null to leave it out.
  final VoidCallback? onSpeak;
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    final meta = _metaStyle();
    final clock = formatBubbleTime(time);

    // What the time and ticks will occupy, spelled out invisibly at the end of the text so the
    // last line leaves room for them — or wraps them onto a line of their own when it cannot.
    final reserve = '   $clock${outgoing ? '    ' : ''}'
        '${onSpeak != null ? '     ' : ''}';

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: CustomPaint(
          painter: ChatBubbleShape(
            color: outgoing ? ChatPalette.outgoing : ChatPalette.incoming,
            outgoing: outgoing,
            tail: tail,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              outgoing ? 9 : ChatBubbleShape.tailWidth + 9,
              6,
              outgoing ? ChatBubbleShape.tailWidth + 9 : 9,
              7,
            ),
            child: Stack(
              children: [
                Text.rich(
                  TextSpan(
                    style: chatTextStyle(),
                    children: [
                      ..._spans(context, text),
                      TextSpan(
                        text: reserve,
                        style: meta.copyWith(color: Colors.transparent),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onSpeak != null) ...[
                        _Listen(speaking: speaking, onTap: onSpeak!),
                        const SizedBox(width: 4),
                      ],
                      Text(clock, style: meta),
                      if (status != BubbleStatus.none) ...[
                        const SizedBox(width: 3),
                        _Ticks(status: status),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<InlineSpan> _spans(BuildContext context, String text) {
    if (!linkPhones) return [TextSpan(text: text)];

    final spans = <InlineSpan>[];
    var at = 0;
    for (final match in _phone.allMatches(text)) {
      if (match.start > at) spans.add(TextSpan(text: text.substring(at, match.start)));
      final number = match.group(0)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Semantics(
            link: true,
            label: '${ChatCopy.call} $number',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () {
                analytics.track(Ev.elementTapped, {P.elementId: 'chat_helpline_call'});
                launchUrl(Uri(scheme: 'tel', path: number.replaceAll('-', '')));
              },
              child: Text(
                number,
                style: chatTextStyle().copyWith(
                  color: ChatPalette.button,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
      );
      at = match.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return spans;
  }
}

/// WhatsApp's bubble: a rounded box, with a pointed corner at the top on the speaker's side when
/// it opens a run. Shared with the typing indicator, which is drawn as one of Astro's messages.
class ChatBubbleShape extends CustomPainter {
  const ChatBubbleShape({required this.color, required this.outgoing, required this.tail});

  final Color color;
  final bool outgoing;
  final bool tail;

  /// Room left on the speaker's side for the tail, whether or not this bubble draws one — so a
  /// run of bubbles lines up as one column.
  static const tailWidth = 7.0;
  static const _radius = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    const t = tailWidth;
    const r = Radius.circular(_radius);
    final body = RRect.fromLTRBAndCorners(
      outgoing ? 0 : t,
      0,
      outgoing ? size.width - t : size.width,
      size.height,
      topLeft: !outgoing && tail ? Radius.zero : r,
      topRight: outgoing && tail ? Radius.zero : r,
      bottomLeft: r,
      bottomRight: r,
    );

    final path = Path()..addRRect(body);
    if (tail) {
      final pointer = Path();
      if (outgoing) {
        pointer
          ..moveTo(size.width - t - 1, 0)
          ..lineTo(size.width, 0)
          ..quadraticBezierTo(size.width - 2, 2, size.width - t, t + 3)
          ..close();
      } else {
        pointer
          ..moveTo(t + 1, 0)
          ..lineTo(0, 0)
          ..quadraticBezierTo(2, 2, t, t + 3)
          ..close();
      }
      path.addPath(pointer, Offset.zero);
    }

    canvas.drawPath(
      path.shift(const Offset(0, 0.7)),
      Paint()
        ..color = ChatPalette.shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6),
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(ChatBubbleShape old) =>
      old.color != color || old.outgoing != outgoing || old.tail != tail;
}

class _Ticks extends StatelessWidget {
  const _Ticks({required this.status});

  final BubbleStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      BubbleStatus.pending => const Icon(Icons.schedule_rounded, size: 13, color: ChatPalette.meta),
      BubbleStatus.sent => const Icon(Icons.done_rounded, size: 16, color: ChatPalette.meta),
      // `none` never gets here — the bubble leaves the ticks out — but the switch must say.
      BubbleStatus.read || BubbleStatus.none =>
        const Icon(Icons.done_all_rounded, size: 16, color: ChatPalette.tick),
    };
  }
}

class _Listen extends StatelessWidget {
  const _Listen({required this.speaking, required this.onTap});

  final bool speaking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: speaking ? ChatCopy.stopListening : ChatCopy.listen,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: speaking
              ? const AudioBars(speaking: true, color: ChatPalette.button, size: 13)
              : const Icon(Icons.volume_up_rounded, size: 15, color: ChatPalette.meta),
        ),
      ),
    );
  }
}

/// The day, centred over the messages sent on it.
class ChatDateChip extends StatelessWidget {
  const ChatDateChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: ChatPalette.chip,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: ChatPalette.shadow, blurRadius: 1, offset: Offset(0, 1))],
        ),
        child: Text(label, style: _metaStyle().copyWith(fontSize: 12.5, color: ChatPalette.onChip)),
      ),
    );
  }
}

/// The yellow line at the top of a conversation: what Astro reads from, and that it is private.
class ChatNotice extends StatelessWidget {
  const ChatNotice({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.fromLTRB(28, 4, 28, 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: ChatPalette.notice,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: _metaStyle().copyWith(fontSize: 12.5, height: 1.35, color: ChatPalette.onNotice),
        ),
      ),
    );
  }
}

/// WhatsApp's reply buttons: what they might tap next, attached under Astro's newest message.
class ChatReplyButtons extends StatelessWidget {
  const ChatReplyButtons({super.key, required this.options, required this.onPick});

  /// Label and what tapping it does, in order.
  final List<(String, VoidCallback)> options;

  final void Function(int index)? onPick;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Padding(
          padding: const EdgeInsets.only(left: ChatBubbleShape.tailWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, (label, onTap)) in options.indexed)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Material(
                    color: ChatPalette.incoming,
                    borderRadius: BorderRadius.circular(8),
                    elevation: 0.6,
                    shadowColor: ChatPalette.shadow,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        onPick?.call(index);
                        onTap();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: chatTextStyle().copyWith(
                            fontSize: 15,
                            color: ChatPalette.button,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
