import 'package:flutter/cupertino.dart';

import '../library_sort.dart';
import 'cupertino_settings.dart';

typedef LibrarySortSelection = ({LibrarySort sort, bool descending});

Future<LibrarySortSelection?> showLibrarySort(
  BuildContext context, {
  required LibrarySort sort,
  required bool descending,
}) => showSettingsPopup<LibrarySortSelection>(
  context: context,
  builder: (_) => _SortDialog(sort: sort, descending: descending),
);

class _SortDialog extends StatefulWidget {
  const _SortDialog({required this.sort, required this.descending});
  final LibrarySort sort;
  final bool descending;
  @override
  State<_SortDialog> createState() => _SortDialogState();
}

class _SortDialogState extends State<_SortDialog> {
  late LibrarySort _sort = widget.sort;
  late bool _descending = widget.descending;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '列表排序',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            SettingsIconButton(
              tooltip: '关闭列表排序',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(CupertinoIcons.xmark_circle_fill),
            ),
          ],
        ),
        CupertinoListSection.insetGrouped(
          margin: const EdgeInsets.symmetric(vertical: 16),
          children: [
            for (final sort in LibrarySort.values)
              CupertinoListTile(
                key: Key('sort-${sort.name}'),
                title: Text(sort.label),
                trailing: _sort == sort
                    ? const Icon(CupertinoIcons.checkmark, size: 20)
                    : null,
                onTap: () => setState(() {
                  if (_sort != sort) {
                    _sort = sort;
                    _descending = sort == LibrarySort.playCount;
                  }
                }),
              ),
          ],
        ),
        if (_sort != LibrarySort.original) ...[
          CupertinoSlidingSegmentedControl<bool>(
            groupValue: _descending,
            onValueChanged: (value) {
              if (value != null) setState(() => _descending = value);
            },
            children: {
              false: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(_sort == LibrarySort.playCount ? '从少到多' : '升序'),
              ),
              true: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(_sort == LibrarySort.playCount ? '从多到少' : '降序'),
              ),
            },
          ),
          const SizedBox(height: 16),
        ],
        CupertinoButton.filled(
          key: const Key('apply-library-sort'),
          onPressed: () =>
              Navigator.pop(context, (sort: _sort, descending: _descending)),
          child: const Text('应用'),
        ),
      ],
    ),
  );
}
