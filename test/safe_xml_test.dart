import 'package:epub_pro/src/utils/safe_xml.dart';
import 'package:test/test.dart';

void main() {
  group('parseXmlSafe (F-EPUB-008)', () {
    test('accepts well-formed XML', () {
      const xml = '<package version="2.0"><metadata></metadata></package>';
      final doc = parseXmlSafe(xml);
      expect(doc.rootElement.name.local, 'package');
    });

    test('accepts the canonical container.xml shape', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0"
           xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="content.opf"
              media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';
      final doc = parseXmlSafe(xml);
      expect(doc.rootElement.name.local, 'container');
    });

    test('accepts standard EPUB 2 NCX DOCTYPE (NCX 2005-1 spec)', () {
      // Real-world EPUB 2 files like alicesAdventuresUnderGround.epub
      // legitimately include this DOCTYPE per the NCX standard.
      // package:xml does NOT fetch external DTDs, so this is harmless.
      const ncx = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN"
  "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head/>
</ncx>
''';
      final doc = parseXmlSafe(ncx);
      expect(doc.rootElement.name.local, 'ncx');
    });

    test('rejects billion-laughs DOCTYPE + ENTITY combination', () {
      // Note: against today's `package:xml` this attack is not actively
      // exploitable because the parser doesn't register user-declared
      // entities into the decoding map. The guard is defence-in-depth
      // against a future parser bump or a custom XmlEntityMapping.
      const malicious = '''
<?xml version="1.0"?>
<!DOCTYPE ncx [
  <!ENTITY lol "lol">
  <!ENTITY lol2 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">
  <!ENTITY lol3 "&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;">
]>
<ncx><navMap>&lol3;</navMap></ncx>
''';
      expect(
        () => parseXmlSafe(malicious),
        throwsA(isA<UnsafeXmlException>()),
      );
    });

    test('rejects ENTITY declaration without DOCTYPE wrapper', () {
      const bad = '<package><!ENTITY foo "bar"><meta/></package>';
      expect(() => parseXmlSafe(bad), throwsA(isA<UnsafeXmlException>()));
    });

    test('rejects parameter-entity (`<!ENTITY %`) XXE pattern', () {
      // Classic XXE escalation: the parameter entity defines a normal
      // entity that references external system data. `<!ENTITY %`
      // still contains the substring `<!ENTITY`, so the hot-path
      // check catches it.
      const xxePe = '''
<?xml version="1.0"?>
<!DOCTYPE foo [
  <!ENTITY % pe "<!ENTITY xxe SYSTEM 'file:///etc/passwd'>">
  %pe;
]>
<foo>&xxe;</foo>
''';
      expect(() => parseXmlSafe(xxePe), throwsA(isA<UnsafeXmlException>()));
    });

    test('rejects bare external-entity SYSTEM declaration', () {
      const xxe = '''
<?xml version="1.0"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<foo>&xxe;</foo>
''';
      expect(() => parseXmlSafe(xxe), throwsA(isA<UnsafeXmlException>()));
    });

    test(
      'rejects mixed-case <!Entity (defence-in-depth — cold path)',
      () {
        // `package:xml` silently swallows non-conforming variants like
        // `<!Entity` rather than throwing. If a future parser change
        // ever registers them into the entity map this would bypass
        // the case-sensitive hot path.
        const tricky = '<package><!Entity foo "bar"/></package>';
        expect(
          () => parseXmlSafe(tricky),
          throwsA(isA<UnsafeXmlException>()),
        );
        const allLower = '<package><!entity foo "bar"/></package>';
        expect(
          () => parseXmlSafe(allLower),
          throwsA(isA<UnsafeXmlException>()),
        );
      },
    );

    test('UnsafeXmlException message identifies the trigger', () {
      try {
        parseXmlSafe('<package><!ENTITY foo "bar"/></package>');
        fail('Expected UnsafeXmlException');
      } on UnsafeXmlException catch (e) {
        expect(e.toString(), contains('ENTITY'));
        expect(e.offset, isNotNull);
      }
    });
  });
}
