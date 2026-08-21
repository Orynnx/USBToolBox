import 'package:flutter_test/flutter_test.dart';
import 'package:hyperusb_ui/hid/keyboard_text_encoder.dart';

void main() {
  group('KeyboardTextEncoder tests', () {
    test('encodes lowercase letters without modifiers', () {
      expect(KeyboardTextEncoder.encodeChar('a'), const KeyStroke(key: 'A'));
      expect(KeyboardTextEncoder.encodeChar('z'), const KeyStroke(key: 'Z'));
    });

    test('encodes uppercase letters with SHIFT modifier', () {
      expect(
        KeyboardTextEncoder.encodeChar('A'),
        const KeyStroke(modifiers: ['SHIFT'], key: 'A'),
      );
      expect(
        KeyboardTextEncoder.encodeChar('Z'),
        const KeyStroke(modifiers: ['SHIFT'], key: 'Z'),
      );
    });

    test('encodes digits without modifiers', () {
      expect(KeyboardTextEncoder.encodeChar('0'), const KeyStroke(key: '0'));
      expect(KeyboardTextEncoder.encodeChar('9'), const KeyStroke(key: '9'));
    });

    test('encodes shift-numbers to corresponding shifted digit keys', () {
      expect(
        KeyboardTextEncoder.encodeChar('!'),
        const KeyStroke(modifiers: ['SHIFT'], key: '1'),
      );
      expect(
        KeyboardTextEncoder.encodeChar('@'),
        const KeyStroke(modifiers: ['SHIFT'], key: '2'),
      );
      expect(
        KeyboardTextEncoder.encodeChar('#'),
        const KeyStroke(modifiers: ['SHIFT'], key: '3'),
      );
      expect(
        KeyboardTextEncoder.encodeChar(r'$'),
        const KeyStroke(modifiers: ['SHIFT'], key: '4'),
      );
      expect(
        KeyboardTextEncoder.encodeChar('%'),
        const KeyStroke(modifiers: ['SHIFT'], key: '5'),
      );
      expect(
        KeyboardTextEncoder.encodeChar('^'),
        const KeyStroke(modifiers: ['SHIFT'], key: '6'),
      );
      expect(
        KeyboardTextEncoder.encodeChar('&'),
        const KeyStroke(modifiers: ['SHIFT'], key: '7'),
      );
      expect(
        KeyboardTextEncoder.encodeChar('*'),
        const KeyStroke(modifiers: ['SHIFT'], key: '8'),
      );
      expect(
        KeyboardTextEncoder.encodeChar('('),
        const KeyStroke(modifiers: ['SHIFT'], key: '9'),
      );
      expect(
        KeyboardTextEncoder.encodeChar(')'),
        const KeyStroke(modifiers: ['SHIFT'], key: '0'),
      );
    });

    test('encodes whitespace and control characters', () {
      expect(KeyboardTextEncoder.encodeChar(' '), const KeyStroke(key: 'SPACE'));
      expect(KeyboardTextEncoder.encodeChar('\n'), const KeyStroke(key: 'ENTER'));
      expect(KeyboardTextEncoder.encodeChar('\t'), const KeyStroke(key: 'TAB'));
    });

    test('encodes punctuation symbols with and without shift', () {
      expect(KeyboardTextEncoder.encodeChar('-'), const KeyStroke(key: 'MINUS'));
      expect(
        KeyboardTextEncoder.encodeChar('_'),
        const KeyStroke(modifiers: ['SHIFT'], key: 'MINUS'),
      );
      expect(KeyboardTextEncoder.encodeChar('='), const KeyStroke(key: 'EQUAL'));
      expect(
        KeyboardTextEncoder.encodeChar('+'),
        const KeyStroke(modifiers: ['SHIFT'], key: 'EQUAL'),
      );
      expect(KeyboardTextEncoder.encodeChar('['), const KeyStroke(key: 'LEFTBRACKET'));
      expect(
        KeyboardTextEncoder.encodeChar('{'),
        const KeyStroke(modifiers: ['SHIFT'], key: 'LEFTBRACKET'),
      );
      expect(KeyboardTextEncoder.encodeChar(']'), const KeyStroke(key: 'RIGHTBRACKET'));
      expect(
        KeyboardTextEncoder.encodeChar('}'),
        const KeyStroke(modifiers: ['SHIFT'], key: 'RIGHTBRACKET'),
      );
      expect(KeyboardTextEncoder.encodeChar(r'\'), const KeyStroke(key: 'BACKSLASH'));
      expect(
        KeyboardTextEncoder.encodeChar('|'),
        const KeyStroke(modifiers: ['SHIFT'], key: 'BACKSLASH'),
      );
      expect(KeyboardTextEncoder.encodeChar(';'), const KeyStroke(key: 'SEMICOLON'));
      expect(
        KeyboardTextEncoder.encodeChar(':'),
        const KeyStroke(modifiers: ['SHIFT'], key: 'SEMICOLON'),
      );
      expect(KeyboardTextEncoder.encodeChar("'"), const KeyStroke(key: 'QUOTE'));
      expect(
        KeyboardTextEncoder.encodeChar('"'),
        const KeyStroke(modifiers: ['SHIFT'], key: 'QUOTE'),
      );
      expect(KeyboardTextEncoder.encodeChar('`'), const KeyStroke(key: 'GRAVE'));
      expect(
        KeyboardTextEncoder.encodeChar('~'),
        const KeyStroke(modifiers: ['SHIFT'], key: 'GRAVE'),
      );
      expect(KeyboardTextEncoder.encodeChar(','), const KeyStroke(key: 'COMMA'));
      expect(
        KeyboardTextEncoder.encodeChar('<'),
        const KeyStroke(modifiers: ['SHIFT'], key: 'COMMA'),
      );
      expect(KeyboardTextEncoder.encodeChar('.'), const KeyStroke(key: 'DOT'));
      expect(
        KeyboardTextEncoder.encodeChar('>'),
        const KeyStroke(modifiers: ['SHIFT'], key: 'DOT'),
      );
      expect(KeyboardTextEncoder.encodeChar('/'), const KeyStroke(key: 'SLASH'));
      expect(
        KeyboardTextEncoder.encodeChar('?'),
        const KeyStroke(modifiers: ['SHIFT'], key: 'SLASH'),
      );
    });

    test('throws KeyboardEncodingException for unsupported characters', () {
      expect(
        () => KeyboardTextEncoder.encodeChar('你'),
        throwsA(isA<KeyboardEncodingException>()),
      );
      expect(
        () => KeyboardTextEncoder.encodeChar('🚀'),
        throwsA(isA<KeyboardEncodingException>()),
      );
    });

    test('encodeText encodes sequential sequence correctly', () {
      final strokes = KeyboardTextEncoder.encodeText('Ab1!');
      expect(strokes, [
        const KeyStroke(modifiers: ['SHIFT'], key: 'A'),
        const KeyStroke(key: 'B'),
        const KeyStroke(key: '1'),
        const KeyStroke(modifiers: ['SHIFT'], key: '1'),
      ]);
    });
  });
}
