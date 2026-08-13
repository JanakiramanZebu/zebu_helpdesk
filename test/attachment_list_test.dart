import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/widgets/web/attachment_list.dart';

Widget _host(List<ZebuAttachmentSpec> files, {double width = 320}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: ZebuAttachmentList(files: files, onRemove: (_) {}),
        ),
      ),
    );

void main() {
  _emptyTests();
  _tagTests();
  testWidgets('a name too long to fit gets a tooltip with the whole name', (
    tester,
  ) async {
    const name = 'ca72cf893205fa54349ca381c1519cdc_export.pdf';
    await tester.pumpWidget(
      _host(const [ZebuAttachmentSpec(name: name, size: '1.2 MB')], width: 300),
    );
    await tester.pumpAndSettle();

    final tip = tester.widget<Tooltip>(
      find.ancestor(of: find.text(name), matching: find.byType(Tooltip)),
    );
    expect(tip.message, name);
  });

  testWidgets('a name that fits carries no tooltip', (tester) async {
    await tester.pumpWidget(
      _host(const [
        ZebuAttachmentSpec(name: 'a.png', size: '1 KB'),
      ], width: 672),
    );
    await tester.pumpAndSettle();
    expect(
      find.ancestor(of: find.text('a.png'), matching: find.byType(Tooltip)),
      findsNothing,
    );
  });

  testWidgets('short names are not truncated at all', (tester) async {
    await tester.pumpWidget(
      _host(const [ZebuAttachmentSpec(name: 'Trades.csv', size: '442 KB')]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Trades.csv'), findsOneWidget);
  });

  testWidgets('type tag is read from the extension', (tester) async {
    await tester.pumpWidget(
      _host(const [
        ZebuAttachmentSpec(name: 'screenshot-login-error.png', size: '277 KB'),
        ZebuAttachmentSpec(name: 'Trades.csv', size: '442 KB'),
        ZebuAttachmentSpec(name: 'notes', size: ''),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('PNG'), findsOneWidget);
    // Four characters is the cap — nothing wider than DART / JPEG / XLSX.
    for (final tag in tester.widgetList<Text>(find.byType(Text))) {
      expect((tag.data ?? '').length, lessThanOrEqualTo(26));
    }
    expect(find.text('CSV'), findsOneWidget);
    // No extension still gets a label rather than a blank coloured square.
    expect(find.text('FILE'), findsOneWidget);
  });
}

/// The list must pack across, not run one file per line.
void _gridTests() {
  testWidgets('files pack 2 across on a wide dialog', (tester) async {
    await tester.pumpWidget(
      _host(const [
        ZebuAttachmentSpec(name: 'a.png', size: '1 KB'),
        ZebuAttachmentSpec(name: 'b.png', size: '1 KB'),
        ZebuAttachmentSpec(name: 'c.png', size: '1 KB'),
        ZebuAttachmentSpec(name: 'd.png', size: '1 KB'),
      ], width: 672),
    );
    await tester.pumpAndSettle();

    final top = tester.getTopLeft(find.text('a.png')).dy;
    // a and b share a line; c and d drop to the next.
    expect(tester.getTopLeft(find.text('b.png')).dy, top);
    expect(tester.getTopLeft(find.text('c.png')).dy, greaterThan(top));
    expect(
      tester.getTopLeft(find.text('d.png')).dy,
      tester.getTopLeft(find.text('c.png')).dy,
    );
  });

  testWidgets('a short last line keeps its cells the same width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const [
        ZebuAttachmentSpec(name: 'a.png', size: '1 KB'),
        ZebuAttachmentSpec(name: 'b.png', size: '1 KB'),
        ZebuAttachmentSpec(name: 'c.png', size: '1 KB'),
        ZebuAttachmentSpec(name: 'd.png', size: '1 KB'),
      ], width: 672),
    );
    await tester.pumpAndSettle();
    // An odd trailing cell must keep column width, not stretch across.
    expect(
      tester.getTopLeft(find.text('c.png')).dx,
      tester.getTopLeft(find.text('a.png')).dx,
    );
    expect(tester.getSize(find.byType(ZebuAttachmentList)).width, 672);
  });
}

/// A four-letter tag must not fill its container edge to edge.
void _tagTests() {
  testWidgets('tag grows for a long extension and keeps a minimum', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const [
        ZebuAttachmentSpec(name: 'colors.dart', size: '6.4 KB'),
        ZebuAttachmentSpec(name: 'a.pdf', size: '1 KB'),
      ], width: 672),
    );
    await tester.pumpAndSettle();

    final dart = tester.getSize(find.text('DART'));
    final pdf = tester.getSize(find.text('PDF'));
    // The wider label gets a wider tile rather than being squeezed into it.
    expect(dart.width, greaterThan(pdf.width));
  });
}

/// With no files staged the section must still say so.
void _emptyTests() {
  testWidgets('an empty field spans the add button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZebuAttachmentsField(
            files: const [],
            onAdd: () {},
            onRemove: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Attachments'), findsOneWidget);
    // The button is the empty state: it spans the space the list would
    // occupy rather than sitting off in the heading row, and it keeps the
    // inline form's height so the control does not change shape.
    // Same height as the heading-row form, whatever that height is — the
    // point is that the control keeps its shape, not that it is 32 px.
    final size = tester.getSize(find.byType(ZebuAddFilesButton));
    expect(size.width, tester.getSize(find.byType(ZebuAttachmentsField)).width);
    expect(size.height, kZebuAddFilesHeight);
  });

  testWidgets('with files the button moves up to the heading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZebuAttachmentsField(
            files: const [ZebuAttachmentSpec(name: 'a.png', size: '1 KB')],
            onAdd: () {},
            onRemove: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('a.png'), findsOneWidget);
    // With files present the button retreats to the heading row, level with
    // the label rather than centred below it.
    expect(
      tester.getCenter(find.byType(ZebuAddFilesButton)).dy,
      closeTo(tester.getCenter(find.text('Attachments')).dy, 1),
    );
    // Back to sizing to its label, not spanning the row.
    expect(
      tester.getSize(find.byType(ZebuAddFilesButton)).width,
      lessThan(tester.getSize(find.byType(ZebuAttachmentsField)).width / 2),
    );
  });
}
