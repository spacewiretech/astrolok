import 'package:astrolok/app/theme/app_colors.dart';
import 'package:astrolok/widgets/otp_field.dart';
import 'package:astrolok/widgets/phone_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Focus has gone wrong twice on these sheets, both times in the same way and both times only
/// visible by running the app: a field arrives without the keyboard, and its border does not
/// react to being focused.
///
/// The cause is the `AnimatedSwitcher` that swaps the onboarding sheets. It keeps the outgoing
/// sheet mounted through the transition, so its field still holds focus when the incoming one
/// asks for it — and `autofocus` alone loses that race.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  /// The border colour the field is currently drawing.
  Color borderOf(WidgetTester tester, Finder field) {
    final container = tester.widget<Container>(
      find.ancestor(of: field, matching: find.byType(Container)).first,
    );
    final decoration = container.decoration! as BoxDecoration;
    return decoration.border!.top.color;
  }

  testWidgets('a phone field takes focus on its own and rings gold', (tester) async {
    await tester.pumpWidget(wrap(PhoneField(controller: TextEditingController())));
    await tester.pumpAndSettle();

    expect(tester.testTextInput.isVisible, isTrue, reason: 'the keyboard should be up');
    expect(borderOf(tester, find.byType(TextField)), AppColors.gold);
  });

  testWidgets('a name field takes focus on its own and rings gold', (tester) async {
    // This one used to hardcode `focused: false`, so it stayed grey however the user tapped.
    await tester.pumpWidget(wrap(
      TextFieldBox(controller: TextEditingController(), hint: 'Enter your name'),
    ));
    await tester.pumpAndSettle();

    expect(tester.testTextInput.isVisible, isTrue);
    expect(borderOf(tester, find.byType(TextField)), AppColors.gold);
  });

  testWidgets('a field opted out of autofocus stays grey and closed', (tester) async {
    await tester.pumpWidget(wrap(
      TextFieldBox(
        controller: TextEditingController(),
        hint: 'Enter your name',
        autofocus: false,
      ),
    ));
    await tester.pumpAndSettle();

    expect(borderOf(tester, find.byType(TextField)), AppColors.fieldBorder);
  });

  testWidgets('a field swapped in behind another still wins focus', (tester) async {
    // The real failure, reproduced: an AnimatedSwitcher holds the outgoing field for the length
    // of the transition. Without the post-frame request the incoming field never gets focus.
    Widget sheet(bool showName) => wrap(
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(
              key: ValueKey(showName),
              child: showName
                  ? TextFieldBox(controller: TextEditingController(), hint: 'name')
                  : PhoneField(controller: TextEditingController()),
            ),
          ),
        );

    await tester.pumpWidget(sheet(false));
    await tester.pumpAndSettle();

    await tester.pumpWidget(sheet(true));
    await tester.pumpAndSettle();

    expect(find.text('name'), findsOneWidget, reason: 'the name sheet should be showing');
    expect(
      borderOf(tester, find.widgetWithText(TextField, 'name')),
      AppColors.gold,
      reason: 'the incoming field lost the focus race to the outgoing one',
    );
  });

  testWidgets('the OTP field takes focus on arrival', (tester) async {
    await tester.pumpWidget(wrap(OtpField(length: 6, onChanged: (_) {})));
    await tester.pumpAndSettle();

    expect(tester.testTextInput.isVisible, isTrue);
  });
}
