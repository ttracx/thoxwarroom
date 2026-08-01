import 'package:checks/checks.dart';
import 'package:thoxwarroom/shared/widgets/markdown/markdown_preprocessor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThoxWarRoomMarkdownPreprocessor.normalize', () {
    test('empty string returns empty', () {
      check(ThoxWarRoomMarkdownPreprocessor.normalize('')).equals('');
    });

    test('CRLF is converted to LF', () {
      final result = ThoxWarRoomMarkdownPreprocessor.normalize('hello\r\nworld');
      check(result).not((s) => s.contains('\r'));
      check(result).contains('hello\nworld');
    });

    test('auto-closes unmatched fence (odd count)', () {
      final result = ThoxWarRoomMarkdownPreprocessor.normalize('```python\ncode');
      check(result).endsWith('```');
      // Should have exactly 2 fences now (even)
      final fenceCount = RegExp(r'```').allMatches(result).length;
      check(fenceCount.isEven).isTrue();
    });

    test('dedents indented opening fence', () {
      final result = ThoxWarRoomMarkdownPreprocessor.normalize(
        '    ```python\ncode\n```',
      );
      check(result).contains('```python');
      check(result).not((s) => s.contains('    ```python'));
    });

    test('dedents indented closing fence', () {
      final result = ThoxWarRoomMarkdownPreprocessor.normalize(
        '```python\ncode\n    ```',
      );
      // The closing fence should not be indented.
      check(result).not((s) => s.contains('    ```'));
    });

    test('moves fence after list marker to new line', () {
      final result = ThoxWarRoomMarkdownPreprocessor.normalize(
        '- ```python\ncode\n```',
      );
      // The fence should be on its own line after the list marker.
      check(result).contains('- \n```python');
    });

    test('ensures closing fence on own line', () {
      final result = ThoxWarRoomMarkdownPreprocessor.normalize(
        '```\nsome code```\n',
      );
      // "code```" at EOL should become "code\n```"
      check(result).contains('some code\n```');
    });

    test('fixes numeric heading by inserting ZWNJ after dot', () {
      final result = ThoxWarRoomMarkdownPreprocessor.normalize('### 1. First');
      // Should insert \u200C between the dot and space.
      check(result).contains('1.\u200C');
    });

    test('fixes Setext heading false positive', () {
      final result = ThoxWarRoomMarkdownPreprocessor.normalize('**Bold**\n---');
      // Should add a blank line between the bold text and the dashes.
      check(result).contains('**Bold**\n\n');
    });
  });

  group('ThoxWarRoomMarkdownPreprocessor.sanitize', () {
    test('empty string returns empty', () {
      check(ThoxWarRoomMarkdownPreprocessor.sanitize('')).equals('');
    });

    test('removes <think>...</think> blocks', () {
      final result = ThoxWarRoomMarkdownPreprocessor.sanitize(
        'before<think>internal reasoning</think>after',
      );
      check(result).not((s) => s.contains('think'));
      check(result).not((s) => s.contains('internal'));
      check(result).contains('before');
      check(result).contains('after');
    });

    test('removes <details type="reasoning">...</details> blocks', () {
      final result = ThoxWarRoomMarkdownPreprocessor.sanitize(
        'before<details type="reasoning">hidden</details>after',
      );
      check(result).not((s) => s.contains('hidden'));
      check(result).contains('before');
      check(result).contains('after');
    });

    test('preserves literal reasoning blocks inside code spans and fences', () {
      const input = '''before <think>remove me</think>

``<think>`inline example`</think>``

````
<details type="reasoning">fenced example</details>
````

after''';

      final result = ThoxWarRoomMarkdownPreprocessor.sanitize(input);
      check(result).not((value) => value.contains('remove me'));
      check(result).contains('``<think>`inline example`</think>``');
      check(result).contains(
        '````\n<details type="reasoning">fenced example</details>\n````',
      );
    });

    test('collapses 3+ newlines to double newline', () {
      final result = ThoxWarRoomMarkdownPreprocessor.sanitize('a\n\n\n\nb');
      check(result).equals('a\n\nb');
    });
  });

  group('ThoxWarRoomMarkdownPreprocessor.stripLinkReferenceDefinitions', () {
    test('preserves definitions inside variable-length code delimiters', () {
      const input = '''[remove]: https://example.com/remove

``[inline]: `literal` ``

````
[fenced]: https://example.com/keep
````''';

      final result = ThoxWarRoomMarkdownPreprocessor.stripLinkReferenceDefinitions(
        input,
      );
      check(result).not((value) => value.contains('[remove]'));
      check(result).contains('``[inline]: `literal` ``');
      check(result).contains('````\n[fenced]: https://example.com/keep\n````');
    });
  });

  group('ThoxWarRoomMarkdownPreprocessor.toPlainText', () {
    test('whitespace-only returns empty', () {
      check(ThoxWarRoomMarkdownPreprocessor.toPlainText('   ')).equals('');
    });

    test('removes code blocks, keeps inline code text', () {
      final result = ThoxWarRoomMarkdownPreprocessor.toPlainText(
        '```dart\nvoid main() {}\n```\nUse `print` here',
      );
      check(result).not((s) => s.contains('void main'));
      check(result).contains('print');
    });

    test('removes images ![alt](url)', () {
      final result = ThoxWarRoomMarkdownPreprocessor.toPlainText(
        'See ![photo](http://img.png) here',
      );
      check(result).not((s) => s.contains('photo'));
      check(result).not((s) => s.contains('http'));
    });

    test('keeps link text [text](url)', () {
      final result = ThoxWarRoomMarkdownPreprocessor.toPlainText(
        'Click [here](http://example.com) now',
      );
      check(result).contains('here');
      check(result).not((s) => s.contains('http'));
    });

    test('strips **bold** markers', () {
      final result = ThoxWarRoomMarkdownPreprocessor.toPlainText(
        'This is **bold** text',
      );
      check(result).contains('bold');
      check(result).not((s) => s.contains('**'));
    });

    test('strips ***bold italic*** markers', () {
      final result = ThoxWarRoomMarkdownPreprocessor.toPlainText(
        'This is ***important*** text',
      );
      check(result).contains('important');
      check(result).not((s) => s.contains('***'));
    });

    test('strips ~~strikethrough~~ markers', () {
      final result = ThoxWarRoomMarkdownPreprocessor.toPlainText(
        'This is ~~deleted~~ text',
      );
      check(result).contains('deleted');
      check(result).not((s) => s.contains('~~'));
    });

    test('strips # heading markers', () {
      final result = ThoxWarRoomMarkdownPreprocessor.toPlainText(
        '## My Heading\nParagraph',
      );
      check(result).contains('My Heading');
      check(result).not((s) => s.contains('##'));
    });

    test('strips list markers (-, *, 1.)', () {
      final result = ThoxWarRoomMarkdownPreprocessor.toPlainText(
        '- item one\n* item two\n1. item three',
      );
      check(result).contains('item one');
      check(result).contains('item two');
      check(result).contains('item three');
    });

    test('strips > blockquote markers', () {
      final result = ThoxWarRoomMarkdownPreprocessor.toPlainText('> quoted text');
      check(result).contains('quoted text');
      check(result).not((s) => s.startsWith('>'));
    });

    test('removes HTML tags', () {
      final result = ThoxWarRoomMarkdownPreprocessor.toPlainText(
        'Hello <b>world</b>',
      );
      check(result).contains('world');
      check(result).not((s) => s.contains('<b>'));
    });

    test('removes tool call details from spoken text', () {
      final result = ThoxWarRoomMarkdownPreprocessor.toPlainText(
        'Before <details type="tool_calls" done="true" '
        'name="search"><summary>Tool Executed</summary></details> after',
      );
      check(result).contains('Before');
      check(result).contains('after');
      check(result).not((s) => s.contains('Tool Executed'));
    });

    test('removes extended reasoning blocks from spoken text', () {
      final result = ThoxWarRoomMarkdownPreprocessor.toPlainText(
        'Start <reason>internal chain of thought</reason> '
        '<details><summary>Thinking</summary>private notes</details> end',
      );
      check(result).contains('Start');
      check(result).contains('end');
      check(result).not((s) => s.contains('chain of thought'));
      check(result).not((s) => s.contains('Thinking'));
      check(result).not((s) => s.contains('private notes'));
    });

    test('preserves generic details content in sanitize', () {
      final result = ThoxWarRoomMarkdownPreprocessor.sanitize(
        'before <details><summary>Thinking about dinner</summary>menu</details> after',
      );
      check(result).contains('Thinking about dinner');
      check(result).contains('menu');
    });

    test('normalizes whitespace', () {
      final result = ThoxWarRoomMarkdownPreprocessor.toPlainText(
        'hello   world\n\nnew  paragraph',
      );
      check(result).not((s) => s.contains('  '));
    });
  });

  group('ThoxWarRoomMarkdownPreprocessor.cleanText', () {
    test('whitespace-only returns empty', () {
      check(ThoxWarRoomMarkdownPreprocessor.cleanText('   ')).equals('');
    });

    test('preserves details until caller strips them like OpenWebUI', () {
      final result = ThoxWarRoomMarkdownPreprocessor.cleanText(
        'Before <details><summary>Hidden</summary>tool output</details> after',
      );
      check(result).contains('Before');
      check(result).contains('after');
      check(
        result,
      ).contains('<details><summary>Hidden</summary>tool output</details>');
    });

    test('preserves generic html content to mirror OpenWebUI', () {
      final result = ThoxWarRoomMarkdownPreprocessor.cleanText(
        'Hello <b>world</b>',
      );
      check(result).contains('<b>world</b>');
    });

    test('strips markdown formatting and emojis', () {
      final result = ThoxWarRoomMarkdownPreprocessor.cleanText(
        '## **Hello** 😄\n- item\n`code`',
      );
      check(result).contains('Hello');
      check(result).contains('item');
      check(result).contains('code');
      check(result).not((s) => s.contains('##'));
      check(result).not((s) => s.contains('**'));
      check(result).not((s) => s.contains('😄'));
    });

    test('preserves newline boundaries for downstream splitting', () {
      final result = ThoxWarRoomMarkdownPreprocessor.cleanText(
        'First paragraph\n\nSecond paragraph',
      );
      check(result).equals('First paragraph\nSecond paragraph');
      check(result).contains('\n');
    });
  });

  group('ThoxWarRoomMarkdownPreprocessor.removeAllDetails', () {
    test('removes details outside code spans', () {
      final result = ThoxWarRoomMarkdownPreprocessor.removeAllDetails(
        'keep ```<details>code</details>``` hide <details>x</details>',
      );
      check(result).contains('```<details>code</details>```');
      check(result).not((s) => s.contains(' hide <details>x</details>'));
    });

    test('removes details containing code without splitting the block', () {
      const input = '''before
<details><summary>Hidden</summary>
``inline `secret` ``
````
fenced secret
````
</details>
after''';

      final result = ThoxWarRoomMarkdownPreprocessor.removeAllDetails(input);
      check(result).not((value) => value.contains('Hidden'));
      check(result).not((value) => value.contains('secret'));
      check(result).contains('before');
      check(result).contains('after');
    });
  });

  group('ThoxWarRoomMarkdownPreprocessor.softenInlineCode', () {
    test('short input returned unchanged', () {
      final result = ThoxWarRoomMarkdownPreprocessor.softenInlineCode('short');
      check(result).equals('short');
    });

    test('inserts ZWSP every chunkSize chars for long input', () {
      // Default chunkSize is 24.
      final input = 'a' * 48;
      final result = ThoxWarRoomMarkdownPreprocessor.softenInlineCode(input);
      // Should have ZWSP at positions 24 and 48.
      check(result).contains('\u200B');
      check(result.length).equals(48 + 2);
    });

    test('custom chunkSize works', () {
      final input = 'abcdefghij'; // length 10
      final result = ThoxWarRoomMarkdownPreprocessor.softenInlineCode(
        input,
        chunkSize: 5,
      );
      // ZWSP inserted after position 5 and position 10.
      check(result).equals('abcde\u200Bfghij\u200B');
    });
  });
}
