import 'package:xml/xml.dart';

/// Thrown when EPUB structural XML (OPF / NCX / Navigation Document /
/// container.xml) contains an `<!ENTITY` declaration.
///
/// This is a **defense-in-depth** guard. `package:xml` 6.x currently
/// parses `<!ENTITY>` declarations into the DTD model but does NOT
/// register them in the entity-decoding map (the default mapping only
/// knows `amp/apos/gt/lt/quot`), so billion-laughs expansion is not
/// actively exploitable against today's parser. The guard exists for
/// future-bump scenarios and for the small theoretical risk of a
/// downstream caller swapping in a custom `XmlEntityMapping`.
class UnsafeXmlException implements Exception {
  /// 1-based character offset (in [text]) where the offending marker
  /// was found, for diagnostic logging. Never the marker contents.
  const UnsafeXmlException(this.message, {this.offset});

  final String message;
  final int? offset;

  @override
  String toString() =>
      'UnsafeXmlException: $message${offset == null ? '' : ' (at offset $offset)'}';
}

// XML 1.0 §2.8 specifies the literal token `<!ENTITY` is case-sensitive
// — lowercase `<!entity` is not a conforming entity declaration.
// `String.contains` uses a fast Boyer-Moore-ish substring search (no
// regex JIT, no per-character class machinery), keeping the pre-scan
// cost negligible on multi-KB NCX / OPF / nav-doc payloads.
const _entityMarker = '<!ENTITY';

// Cold-path catch for non-conforming mixed-case variants like
// `<!Entity` or `<!EnTITY`. The current `package:xml` parser would
// silently swallow such declarations rather than throwing, so a future
// behaviour change to register them into the entity map could bypass
// the hot-path uppercase check.
final RegExp _entityMarkerInsensitive =
    RegExp('<!entity', caseSensitive: false);

/// Parses [text] as XML after rejecting any `<!ENTITY` declarations.
///
/// **Why only `<!ENTITY` and not `<!DOCTYPE`:** legitimate EPUB 2 NCX
/// files require a `<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN"
/// "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">` declaration per
/// the NCX 2005-1 spec. `package:xml` doesn't fetch external DTDs (no
/// HTTP code in the library), so a bare DOCTYPE without internal-subset
/// entity definitions is harmless. The attack vector is `<!ENTITY`
/// (internal entity expansion → billion-laughs); banning that
/// independently of the DOCTYPE wrapper catches both forms:
///   - `<!DOCTYPE foo [<!ENTITY ...>]>` — internal-subset attack
///   - `<!DOCTYPE foo [<!ENTITY % pe SYSTEM "...">]>` — parameter-entity
///     XXE via the DTD parser
///   - `<!ENTITY external SYSTEM "file:///etc/passwd">` — XXE via
///     external entity reference
///
/// **Known limitation (acceptable for the EPUB metadata files this
/// guards):** the substring scan also rejects `<!ENTITY` appearing
/// inside XML comments or CDATA sections. Real OPF / NCX / container /
/// nav-doc payloads don't carry comment-wrapped or CDATA-wrapped
/// markup-declaration text, so this trade-off is practically free.
///
/// Throws [UnsafeXmlException] if a forbidden declaration is found;
/// otherwise returns the parsed [XmlDocument]. Defends against
/// F-EPUB-008 (entity-expansion DoS / XXE) across all OPF, NCX,
/// container, and EPUB3 Navigation Document parse sites in `epub_pro`.
XmlDocument parseXmlSafe(String text) {
  // Hot path: case-sensitive substring search catches the only
  // XML-spec-conforming form (uppercase `<!ENTITY`). Cheap on
  // 100KB-class payloads.
  var idx = text.indexOf(_entityMarker);
  if (idx >= 0) {
    throw UnsafeXmlException(
      'XML contains an ENTITY declaration. Structural EPUB metadata '
      'must not declare internal entities (billion-laughs / XXE).',
      offset: idx,
    );
  }
  // Cold path: catch non-conforming mixed-case variants like
  // `<!Entity ...>` that today's `package:xml` parser silently
  // swallows rather than rejecting (so the "package:xml rejects
  // lowercase upstream of me" assumption from the hot-path check
  // doesn't fully hold). Defence-in-depth.
  final m = _entityMarkerInsensitive.firstMatch(text);
  if (m != null) {
    throw UnsafeXmlException(
      'XML contains a non-conforming `<!Entity` variant. Markup '
      'declarations are case-sensitive (XML 1.0 §2.8) but the parser '
      'may silently accept the misformed declaration.',
      offset: m.start,
    );
  }
  return XmlDocument.parse(text);
}
