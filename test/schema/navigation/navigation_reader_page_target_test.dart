import 'package:epub_pro/src/readers/navigation_reader.dart';
import 'package:epub_pro/src/schema/navigation/epub_navigation_page_list.dart';
import 'package:epub_pro/src/schema/navigation/epub_navigation_page_target.dart';
import 'package:epub_pro/src/schema/navigation/epub_navigation_page_target_type.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart' as xml;

xml.XmlElement _parseElement(String source) {
  return xml.XmlDocument.parse(source).rootElement;
}

void main() {
  group('NavigationReader.readNavigationPageTarget — regression for F-EPUB-002',
      () {
    test(
      'preserves the type attribute (was always null due to inner-var shadow)',
      () {
        final element = _parseElement('''
          <pageTarget id="pt-1" value="42" type="normal" playOrder="3">
            <navLabel><text>Page 42</text></navLabel>
            <content src="chapter_03.xhtml#p42"/>
          </pageTarget>
        ''');

        final target = NavigationReader.readNavigationPageTarget(element);

        expect(target.type, equals(EpubNavigationPageTargetType.normal));
      },
    );

    test(
      'preserves the content child (was always null due to inner-var shadow)',
      () {
        final element = _parseElement('''
          <pageTarget id="pt-2" value="7" type="front" playOrder="1">
            <navLabel><text>Foreword</text></navLabel>
            <content src="front_matter/foreword.xhtml#start"/>
          </pageTarget>
        ''');

        final target = NavigationReader.readNavigationPageTarget(element);

        expect(target.content, isNotNull);
        expect(target.content!.source, equals('front_matter/foreword.xhtml#start'));
      },
    );

    test('preserves type across every defined enum value', () {
      const cases = <String, EpubNavigationPageTargetType>{
        'normal': EpubNavigationPageTargetType.normal,
        'front': EpubNavigationPageTargetType.front,
        'special': EpubNavigationPageTargetType.special,
      };
      cases.forEach((rawType, expected) {
        final element = _parseElement('''
          <pageTarget id="pt" value="1" type="$rawType" playOrder="1">
            <navLabel><text>page</text></navLabel>
            <content src="page.xhtml"/>
          </pageTarget>
        ''');
        final target = NavigationReader.readNavigationPageTarget(element);
        expect(
          target.type,
          equals(expected),
          reason: 'type="$rawType" should map to $expected',
        );
      });
    });

    test('treats type attribute case-insensitively', () {
      final element = _parseElement('''
        <pageTarget id="pt" value="1" type="NORMAL" playOrder="1">
          <navLabel><text>page</text></navLabel>
          <content src="page.xhtml"/>
        </pageTarget>
      ''');
      final target = NavigationReader.readNavigationPageTarget(element);
      expect(target.type, equals(EpubNavigationPageTargetType.normal));
    });

    test('leaves type null when the type attribute is absent', () {
      final element = _parseElement('''
        <pageTarget id="pt" value="1" playOrder="1">
          <navLabel><text>page</text></navLabel>
          <content src="page.xhtml"/>
        </pageTarget>
      ''');
      final target = NavigationReader.readNavigationPageTarget(element);
      expect(target.type, isNull);
    });

    test('throws when type attribute is literally "undefined"', () {
      final element = _parseElement('''
        <pageTarget id="pt" value="1" type="undefined" playOrder="1">
          <navLabel><text>page</text></navLabel>
          <content src="page.xhtml"/>
        </pageTarget>
      ''');
      expect(
        () => NavigationReader.readNavigationPageTarget(element),
        throwsA(isA<Exception>()),
      );
    });

    test('preserves type and content together inside a full pageList',
        () {
      final element = _parseElement('''
        <pageList>
          <pageTarget id="pt-a" value="1" type="front" playOrder="1">
            <navLabel><text>Title page</text></navLabel>
            <content src="front.xhtml"/>
          </pageTarget>
          <pageTarget id="pt-b" value="2" type="normal" playOrder="2">
            <navLabel><text>Page 2</text></navLabel>
            <content src="ch1.xhtml#p2"/>
          </pageTarget>
        </pageList>
      ''');

      final EpubNavigationPageList pageList =
          NavigationReader.readNavigationPageList(element);

      expect(pageList.targets, hasLength(2));

      final EpubNavigationPageTarget first = pageList.targets[0];
      expect(first.type, equals(EpubNavigationPageTargetType.front));
      expect(first.content, isNotNull);
      expect(first.content!.source, equals('front.xhtml'));

      final EpubNavigationPageTarget second = pageList.targets[1];
      expect(second.type, equals(EpubNavigationPageTargetType.normal));
      expect(second.content, isNotNull);
      expect(second.content!.source, equals('ch1.xhtml#p2'));
    });
  });
}
