library epubreadertest;

import 'dart:io' as io;

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:epub_pro/epub_pro.dart';

void main() async {
  const fileName = "alicesAdventuresUnderGround.epub";
  String fullPath = path.join(
    io.Directory.current.path,
    "assets",
    fileName,
  );
  final targetFile = io.File(fullPath);

  late EpubBookRef epubRef;

  setUpAll(() async {
    if (!(await targetFile.exists())) {
      throw Exception("Specified epub file not found: $fullPath");
    }

    final bytes = await targetFile.readAsBytes();

    epubRef = await EpubReader.openBook(bytes);
  });

  group('EpubReader', () {
    test("Epub version", () async {
      expect(epubRef.schema?.package?.version, equals(EpubVersion.epub2));
    });

    test("Chapters count and hierarchy", () async {
      var t = epubRef.getChapters();

      // With the subChapter fix, we now get proper hierarchy:
      // - wrap0000.html (orphaned spine item)
      // - Chapter I (with full sub-chapter hierarchy)
      // Note: "ALICE'S ADVENTURES UNDER GROUND" and "Chapter I" reference the same
      // spine file, so spine reconciliation merges them (Chapter I wins as it's
      // processed later in the NavMap)
      expect(t.length, equals(2));

      // First is the orphaned wrap0000.html
      expect(t[0].contentFileName, equals('wrap0000.html'));
      expect(t[0].title, equals('wrap0000'));
      expect(t[0].subChapters.length, equals(0));

      // Second is Chapter I with full hierarchy preserved
      expect(t[1].title, equals("Chapter I"));
      expect(
          t[1].contentFileName,
          equals(
              '@public@vhost@g@gutenberg@html@files@19002@19002-h@19002-h-0.htm.html'));

      // The key fix: subChapters are now populated correctly!
      // Chapter I has 9 sub-chapters in the NavMap
      expect(t[1].subChapters.length, equals(9));

      // Verify some of the sub-chapters
      expect(t[1].subChapters[0].title, equals("Chapter II"));
      expect(t[1].subChapters[1].title, equals("Chapter III"));
      expect(t[1].subChapters[2].title, equals("Chapter IV"));

      // Chapter IV has a nested sub-chapter (THE END.)
      expect(t[1].subChapters[2].subChapters.length, equals(1));
      expect(t[1].subChapters[2].subChapters[0].title, equals("THE END."));
    });

    test("Author and title", () async {
      expect(epubRef.author, equals("Lewis Carroll"));
      expect(
        epubRef.title,
        equals(
            '''Alice's Adventures Under Ground / Being a facsimile of the original Ms. book afterwards developed into "Alice's Adventures in Wonderland"'''),
      );
    });

    test("Cover", () async {
      final cover = await epubRef.readCover();
      expect(cover, isNotNull);
      expect(cover?.width, equals(581));
      expect(cover?.height, equals(1034));
    });
  });
}
