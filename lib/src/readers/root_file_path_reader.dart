import 'dart:async';

import 'package:archive/archive.dart';
import 'dart:convert' as convert;
import 'package:collection/collection.dart' show IterableExtension;
import 'package:xml/xml.dart' as xml;

import '../utils/safe_xml.dart';
import '../zip/lazy_archive_file.dart';

class RootFilePathReader {
  static Future<String?> getRootFilePath(Archive epubArchive) async {
    const epubContainerFilePath = 'META-INF/container.xml';

    var containerFileEntry = epubArchive.files.firstWhereOrNull(
        (ArchiveFile file) => file.name == epubContainerFilePath);
    if (containerFileEntry == null) {
      throw Exception(
          'EPUB parsing error: $epubContainerFilePath file not found in archive.');
    }

    String containerContent;
    if (containerFileEntry is LazyArchiveFile) {
      containerContent = await containerFileEntry.readContentAsString();
    } else {
      containerContent = convert.utf8.decode(containerFileEntry.content);
    }

    // F-EPUB-008: pre-scan rejects DOCTYPE/ENTITY before parsing —
    // `package:xml` has no built-in entity-expansion cap.
    var containerDocument = parseXmlSafe(containerContent);
    var packageElement = containerDocument
        .findAllElements('container',
            namespace: 'urn:oasis:names:tc:opendocument:xmlns:container')
        .firstOrNull;
    if (packageElement == null) {
      throw Exception('EPUB parsing error: Invalid epub container');
    }

    var rootFileElement = packageElement.descendants.firstWhereOrNull(
        (xml.XmlNode testElem) =>
            (testElem is xml.XmlElement) &&
            'rootfile' == testElem.name.local) as xml.XmlElement;

    return rootFileElement.getAttribute('full-path');
  }
}
