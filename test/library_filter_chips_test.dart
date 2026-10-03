import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/features/library/presentation/widgets/library_filter_chips.dart';

const Color _accent = Color(0xFF7C4DFF);

class _HubHarness extends StatefulWidget {
  const _HubHarness();

  @override
  State<_HubHarness> createState() => _HubHarnessState();
}

class _HubHarnessState extends State<_HubHarness>
    with SingleTickerProviderStateMixin {
  static const int _filterCount = 6;

  static const List<String> _labels = [
    'Songs',
    'Playlists',
    'Recently played',
    'Downloads',
    'Favourites',
    'Local music',
  ];

  late final TabController controller;
  int filterIndex = 0;

  @override
  void initState() {
    super.initState();
    controller = TabController(length: _filterCount, vsync: this)
      ..addListener(() {
        if (!controller.indexIsChanging) {
          setState(() => filterIndex = controller.index);
        }
      });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void selectFilter(int index) {
    controller.animateTo(index);
    setState(() => filterIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LibraryFilterChips(
              labels: _labels,
              selectedIndex: filterIndex,
              onSelected: selectFilter,
              isDarkMode: false,
              accentColor: _accent,
            ),
            Expanded(
              child: TabBarView(
                controller: controller,
                physics: const BouncingScrollPhysics(),
                children: [
                  for (var index = 0; index < _filterCount; index++)
                    Center(
                      key: ValueKey('page-$index'),
                      child: Text('page $index'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double _screenWidth(WidgetTester tester) =>
    tester.view.physicalSize.width / tester.view.devicePixelRatio;

void _usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

_HubHarnessState _state(WidgetTester tester) =>
    tester.state<_HubHarnessState>(find.byType(_HubHarness));

Color _chipColor(WidgetTester tester, String label) {
  final container = tester.widget<AnimatedContainer>(
    find.ancestor(
      of: find.text(label),
      matching: find.byType(AnimatedContainer),
    ),
  );

  return (container.decoration as BoxDecoration).color!;
}

double _pageCenterX(WidgetTester tester, int index) =>
    tester.getCenter(find.byKey(ValueKey('page-$index'))).dx;

bool _isOnScreen(WidgetTester tester, String label) {
  final rect = tester.getRect(find.text(label));

  return rect.left >= 0 && rect.right <= _screenWidth(tester);
}

void _expectShows(WidgetTester tester, int index) {
  expect(_state(tester).filterIndex, index);
  expect(_state(tester).controller.index, index);
  expect(
    _pageCenterX(tester, index),
    closeTo(_screenWidth(tester) / 2, 1.0),
    reason: 'page $index should be the visible page',
  );
  expect(_chipColor(tester, _HubHarnessState._labels[index]), _accent);
  expect(tester.takeException(), isNull);
}

/// Scrolls the pill row until [label] sits fully inside the viewport.
Future<void> _revealChip(WidgetTester tester, String label) async {
  for (var attempt = 0; attempt < 6; attempt++) {
    if (_isOnScreen(tester, label)) {
      return;
    }

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-140, 0),
    );
    await tester.pumpAndSettle();
  }

  expect(
    _isOnScreen(tester, label),
    isTrue,
    reason: 'could not scroll "$label" into view',
  );
}

Future<void> _tapChip(WidgetTester tester, String label) async {
  await _revealChip(tester, label);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the filters sit on a single row', (tester) async {
    _usePhoneSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: _HubHarness()));
    await tester.pumpAndSettle();

    final scroller = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );

    expect(scroller.scrollDirection, Axis.horizontal);

    final firstCenterY = tester
        .getCenter(find.text(_HubHarnessState._labels[0]))
        .dy;

    for (final label in _HubHarnessState._labels) {
      expect(
        tester.getCenter(find.text(label)).dy,
        closeTo(firstCenterY, 1.0),
        reason: '"$label" is not on the same row as the first filter',
      );
    }
  });

  testWidgets('the row scrolls because the pills do not all fit', (
    tester,
  ) async {
    _usePhoneSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: _HubHarness()));
    await tester.pumpAndSettle();

    expect(
      _HubHarnessState._labels.any((label) => !_isOnScreen(tester, label)),
      isTrue,
      reason: 'the pills are expected to overflow a 360dp screen',
    );
  });

  testWidgets('the selected pill is scrolled back into view', (tester) async {
    _usePhoneSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: _HubHarness()));
    await tester.pumpAndSettle();

    expect(_isOnScreen(tester, 'Songs'), isTrue);
    expect(_isOnScreen(tester, 'Local music'), isFalse);

    _state(tester).selectFilter(5);
    await tester.pumpAndSettle();

    expect(_isOnScreen(tester, 'Local music'), isTrue);
    expect(_chipColor(tester, 'Local music'), _accent);
  });

  testWidgets('tapping a chip selects it, repaints it and shows its page', (
    tester,
  ) async {
    _usePhoneSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: _HubHarness()));
    await tester.pumpAndSettle();

    _expectShows(tester, 0);

    await _tapChip(tester, 'Recently played');
    _expectShows(tester, 2);
    expect(_chipColor(tester, 'Songs'), isNot(_accent));

    await _tapChip(tester, 'Downloads');
    _expectShows(tester, 3);
    expect(_chipColor(tester, 'Recently played'), isNot(_accent));
  });

  testWidgets('chips stay in sync when selected out of order', (tester) async {
    _usePhoneSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: _HubHarness()));
    await tester.pumpAndSettle();

    await _tapChip(tester, 'Songs');
    _expectShows(tester, 0);

    await _tapChip(tester, 'Playlists');
    _expectShows(tester, 1);

    await _tapChip(tester, 'Songs');
    _expectShows(tester, 0);

    await _tapChip(tester, 'Playlists');
    _expectShows(tester, 1);
  });

  testWidgets('each of the six filters drives the page in turn', (
    tester,
  ) async {
    _usePhoneSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: _HubHarness()));
    await tester.pumpAndSettle();

    for (var index = 0; index < _HubHarnessState._filterCount; index++) {
      await _tapChip(tester, _HubHarnessState._labels[index]);
      _expectShows(tester, index);
    }
  });
}
