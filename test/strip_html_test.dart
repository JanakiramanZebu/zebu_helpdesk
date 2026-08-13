import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/format.dart';

/// `Fmt.stripHtml` turns an osTicket body into the plain text the composer,
/// the clipboard and every preview show.
void main() {
  test('lines padded with &nbsp; do not arrive indented', () {
    // What the canned-response editor actually stores: a leading `&nbsp;` on
    // each line after the first. It is still an entity while the tags are
    // stripped, so it used to survive as a space and push every line right.
    const html =
        '<p>I hope you are doing well.</p>\n'
        '<p>&nbsp;As per your request, the link has been attached.</p>\n'
        '<p>&nbsp;Step 1: Please log in.</p>';

    // The blank line between paragraphs is pre-existing behaviour and stays —
    // `</p>` becomes a newline and the newline between the tags survives. The
    // fix is the missing leading space, nothing else.
    expect(
      Fmt.stripHtml(html),
      'I hope you are doing well.\n'
      '\n'
      'As per your request, the link has been attached.\n'
      '\n'
      'Step 1: Please log in.',
    );
  });

  test('the real osTicket shape: <p>A</p> <p>B</p>, separated by a space', () {
    // Copied from the /canned?page=1&limit=50 response. The tags are divided
    // by a single space, not a newline — so nothing in the source supplies the
    // paragraph break, and it has to come from `</p>` itself.
    const html =
        '<p>I hope you are doing well.</p> '
        '<p>Please find the requested documents attached.</p> '
        '<p>Step 1: Please log in using this link.</p>';

    expect(
      Fmt.stripHtml(html),
      'I hope you are doing well.\n'
      '\n'
      'Please find the requested documents attached.\n'
      '\n'
      'Step 1: Please log in using this link.',
    );
  });

  test('a body opening with an empty <p><br/></p> does not start blank', () {
    // Also from the API — id 14 begins with one.
    const html = '<p><br /></p> <p>The document attached cannot be used.</p>';
    expect(Fmt.stripHtml(html), 'The document attached cannot be used.');
  });

  test('runs of blank lines collapse to one', () {
    const html = '<p>First</p>\n\n\n<p>Second</p>';
    expect(Fmt.stripHtml(html), 'First\n\nSecond');
  });

  test('br becomes a newline and tags are dropped', () {
    const html = 'Line one<br/>Line two<br />Line three<b>!</b>';
    expect(Fmt.stripHtml(html), 'Line one\nLine two\nLine three!');
  });

  test('div and li end a line the way p does', () {
    // These used to be stripped to nothing, running every line into the one
    // before it — the other half of the "not properly aligned" report.
    expect(
      Fmt.stripHtml('<div>One</div><div>Two</div><div>Three</div>'),
      'One\nTwo\nThree',
    );
    expect(
      Fmt.stripHtml('<ul><li>Step 1</li><li>Step 2</li></ul>'),
      'Step 1\nStep 2',
    );
    // A heading is a paragraph break, so it earns the blank line that `<div>`
    // and `<li>` do not.
    expect(Fmt.stripHtml('<h2>Title</h2><p>Body</p>'), 'Title\n\nBody');
  });

  test('entities decode', () {
    const html = '<p>Tom &amp; Jerry said &quot;hi&quot; &rarr; 5 &lt; 6</p>';
    expect(Fmt.stripHtml(html), 'Tom & Jerry said "hi" → 5 < 6');
  });

  test('empty and null are empty', () {
    expect(Fmt.stripHtml(null), '');
    expect(Fmt.stripHtml(''), '');
    expect(Fmt.stripHtml('<p>&nbsp;</p>'), '');
  });

  test('trailing blank lines are dropped', () {
    expect(Fmt.stripHtml('<p>Only</p>\n<p>&nbsp;</p>'), 'Only');
  });
}
