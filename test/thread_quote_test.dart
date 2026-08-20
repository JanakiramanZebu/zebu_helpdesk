import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/features/tickets/widgets/thread_entry_tile.dart';
import 'package:zebu_helpdesk/models/common.dart';

ThreadEntry _entry(String poster, String body) =>
    ThreadEntry(id: 1, type: 'M', poster: poster, body: body, bodyHtml: body);

void main() {
  group('splitLeadingQuote', () {
    test('peels the composer\'s own quote off a reply', () {
      final html =
          '${quoteReplyHtml(_entry('Sowmiya Ramesh', 'Testing'))}'
          '<p>Reply test check</p>';
      final q = splitLeadingQuote(html);
      expect(q, isNotNull);
      expect(q!.poster, 'Sowmiya Ramesh');
      expect(q.excerpt, 'Testing');
      // The empty separator paragraph is dropped, leaving just the reply.
      expect(q.rest, '<p>Reply test check</p>');
    });

    test('returns null for a plain message', () {
      expect(splitLeadingQuote('<p>Just a message</p>'), isNull);
    });

    test('leaves nested (forwarded) quotes to the HTML renderer', () {
      expect(
        splitLeadingQuote(
          '<blockquote>outer<blockquote>inner</blockquote></blockquote><p>hi</p>',
        ),
        isNull,
      );
    });

    test('handles a quote with no attribution', () {
      final q = splitLeadingQuote('<blockquote>bare text</blockquote><p>ok</p>');
      expect(q!.poster, isNull);
      expect(q.excerpt, 'bare text');
      expect(q.rest, '<p>ok</p>');
    });

    test('keeps the quote when nothing was typed after it', () {
      final q = splitLeadingQuote(quoteReplyHtml(_entry('Ann', 'Hello')));
      expect(q!.poster, 'Ann');
      expect(q.excerpt, 'Hello');
      expect(q.rest, '');
    });

    test('round-trips entities the quote builder escaped', () {
      final q = splitLeadingQuote(
        quoteReplyHtml(_entry('A & B', '<b>bold</b> & <i>italic</i>')),
      );
      expect(q!.poster, 'A & B');
      // The quote carries a plain-text excerpt: markup is flattened by
      // quoteReplyHtml, and the entities it escaped come back out intact.
      expect(q.excerpt, 'bold & italic');
    });
  });
}
