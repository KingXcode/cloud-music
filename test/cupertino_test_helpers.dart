import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';

/// The public root widget of each Cupertino popup route, independent of whether
/// its content is an action sheet or a bounded settings page.
Finder get cupertinoPopup => find.byElementPredicate((element) {
  if (element.widget is! CupertinoPageScaffold &&
      element.widget is! CupertinoActionSheet) {
    return false;
  }
  final route = ModalRoute.of(element);
  if (route is! CupertinoModalPopupRoute) return false;
  return element.widget is CupertinoPageScaffold ||
      element.widget is CupertinoActionSheet;
});

/// Checks the live tree, including routes kept offstage by the navigator.
void expectNoMaterialWidgets() {
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is material.MaterialApp ||
          widget is material.Material ||
          widget is material.Scaffold ||
          widget is material.AppBar ||
          widget is material.BottomSheet ||
          widget is material.AlertDialog ||
          widget is material.SimpleDialog ||
          widget is material.InkWell ||
          widget is material.IconButton ||
          widget is material.TextButton ||
          widget is material.FilledButton ||
          widget is material.ElevatedButton ||
          widget is material.OutlinedButton ||
          widget is material.TextField ||
          widget is material.Switch ||
          widget is material.Slider ||
          widget is material.NavigationBar ||
          widget is material.BottomNavigationBar ||
          widget is material.ListTile ||
          widget is material.Chip ||
          widget is material.Checkbox ||
          widget is material.CircularProgressIndicator ||
          widget is material.LinearProgressIndicator,
      skipOffstage: false,
    ),
    findsNothing,
    reason: 'Every application route and modal must remain Cupertino-only.',
  );
}
