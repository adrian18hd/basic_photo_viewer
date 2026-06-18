import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basic_photo_viewer/main.dart';

void main() {
  testWidgets('Photo viewer shows empty state when no image loaded',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PhotoViewerApp());

    expect(find.text('No image loaded'), findsOneWidget);
    expect(find.text('Drop an image here or use "Open with" from Finder'),
        findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets('Photo viewer has correct theme configuration',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PhotoViewerApp());

    final MaterialApp app = tester.widget(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme, isNotNull);
    expect(app.darkTheme, isNotNull);
  });

  testWidgets('Photo viewer shows toolbar with disabled buttons when no image',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PhotoViewerApp());

    expect(find.byIcon(Icons.rotate_left), findsOneWidget);
    expect(find.byIcon(Icons.rotate_right), findsOneWidget);
    expect(find.byIcon(Icons.zoom_in), findsOneWidget);
    expect(find.byIcon(Icons.zoom_out), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);

    // Buttons should be disabled when no image is loaded
    final rotateLeftButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.rotate_left),
    );
    expect(rotateLeftButton.onPressed, isNull);
  });
}
