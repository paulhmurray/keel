import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:xml/xml.dart';

/// Extracts plain text content from document files.
///
/// Supported formats:
/// - .txt / .md  — read directly with dart:io
/// - .docx       — unzip + parse word/document.xml
/// - .pptx       — unzip + parse ppt/slides/slide*.xml
/// - .xlsx       — unzip + parse xl/sharedStrings.xml + xl/worksheets/sheet*.xml
class DocumentProcessor {
  const DocumentProcessor();

  Future<String> extractText(String filePath, String fileType) async {
    final type = fileType.toLowerCase().replaceFirst(RegExp(r'^\.'), '');

    switch (type) {
      case 'txt':
      case 'md':
        return _readTextFile(filePath);
      case 'docx':
        return _extractDocx(filePath);
      case 'pptx':
        return _extractPptx(filePath);
      case 'xlsx':
        return _extractXlsx(filePath);
      case 'pdf':
        return 'PDF text extraction is not supported in this version.\n\n'
            'To add this document\'s content:\n'
            '• Open the PDF in your PDF viewer\n'
            '• Copy the text you want to capture\n'
            '• Use the "Paste text" option when uploading, or add it as a '
            'Context Entry manually.';
      default:
        return 'Unsupported file type: .$type\n\n'
            'Supported formats: .txt, .md, .docx, .pptx, .xlsx';
    }
  }

  // ---------------------------------------------------------------------------
  // Text file
  // ---------------------------------------------------------------------------

  Future<String> _readTextFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return 'Error: File not found at path: $filePath';
      }
      final content = await file.readAsString();
      if (content.isEmpty) return '(File is empty)';
      return content;
    } catch (e) {
      return 'Error reading file: $e';
    }
  }

  // ---------------------------------------------------------------------------
  // DOCX — word/document.xml  (<w:t> elements)
  // ---------------------------------------------------------------------------

  Future<String> _extractDocx(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final docXml = _archiveFile(archive, 'word/document.xml');
      if (docXml == null) return 'Could not find document content in DOCX file.';

      final xmlStr = String.fromCharCodes(docXml.content as List<int>);
      final doc = XmlDocument.parse(xmlStr);

      final buffer = StringBuffer();
      String? lastPara;

      for (final el in doc.descendants.whereType<XmlElement>()) {
        // <w:p> — paragraph break
        if (el.qualifiedName == 'w:p') {
          final paraText = el.descendants
              .whereType<XmlElement>()
              .where((e) => e.qualifiedName == 'w:t')
              .map((e) => e.innerText)
              .join();
          if (paraText.trim().isNotEmpty || lastPara?.isNotEmpty == true) {
            buffer.writeln(paraText);
          }
          lastPara = paraText;
        }
      }

      final result = buffer.toString().trim();
      return result.isEmpty ? '(No text content found in document)' : result;
    } catch (e) {
      return 'Error extracting DOCX: $e';
    }
  }

  // ---------------------------------------------------------------------------
  // PPTX — ppt/slides/slide*.xml  (<a:t> elements)
  // ---------------------------------------------------------------------------

  Future<String> _extractPptx(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Collect slide files in order
      final slideFiles = archive.files
          .where((f) =>
              f.name.startsWith('ppt/slides/slide') &&
              f.name.endsWith('.xml') &&
              !f.name.contains('_rels'))
          .toList()
        ..sort((a, b) => _slideNumber(a.name).compareTo(_slideNumber(b.name)));

      if (slideFiles.isEmpty) return 'No slides found in PPTX file.';

      final buffer = StringBuffer();
      var slideNum = 1;

      for (final slideFile in slideFiles) {
        final xmlStr = String.fromCharCodes(slideFile.content as List<int>);
        final doc = XmlDocument.parse(xmlStr);

        final texts = doc.descendants
            .whereType<XmlElement>()
            .where((e) => e.qualifiedName == 'a:t')
            .map((e) => e.innerText.trim())
            .where((t) => t.isNotEmpty)
            .toList();

        if (texts.isNotEmpty) {
          buffer.writeln('--- Slide $slideNum ---');
          buffer.writeln(texts.join(' '));
          buffer.writeln();
          slideNum++;
        }
      }

      final result = buffer.toString().trim();
      return result.isEmpty ? '(No text content found in presentation)' : result;
    } catch (e) {
      return 'Error extracting PPTX: $e';
    }
  }

  int _slideNumber(String name) {
    final match = RegExp(r'slide(\d+)\.xml$').firstMatch(name);
    return match != null ? int.tryParse(match.group(1)!) ?? 999 : 999;
  }

  // ---------------------------------------------------------------------------
  // XLSX — xl/sharedStrings.xml + xl/worksheets/sheet*.xml
  // ---------------------------------------------------------------------------

  Future<String> _extractXlsx(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Load shared strings table (strings are referenced by index in cells)
      final sharedStrings = _loadXlsxSharedStrings(archive);

      // Find and sort sheet files
      final sheetFiles = archive.files
          .where((f) =>
              f.name.startsWith('xl/worksheets/sheet') &&
              f.name.endsWith('.xml'))
          .toList()
        ..sort((a, b) => _sheetNumber(a.name).compareTo(_sheetNumber(b.name)));

      if (sheetFiles.isEmpty) return 'No worksheets found in XLSX file.';

      final buffer = StringBuffer();

      for (final sheetFile in sheetFiles) {
        final xmlStr = String.fromCharCodes(sheetFile.content as List<int>);
        final doc = XmlDocument.parse(xmlStr);

        final rows = doc.descendants
            .whereType<XmlElement>()
            .where((e) => e.localName == 'row');

        final rowTexts = <String>[];
        for (final row in rows) {
          final cells = row.childElements
              .where((e) => e.localName == 'c');

          final cellValues = <String>[];
          for (final cell in cells) {
            final t = cell.getAttribute('t'); // type attribute
            final v = cell.descendants
                .whereType<XmlElement>()
                .firstWhere((e) => e.localName == 'v',
                    orElse: () => XmlElement(XmlName('_empty')));
            final vText = v.innerText.trim();
            if (vText.isEmpty) continue;

            if (t == 's') {
              // Shared string index
              final idx = int.tryParse(vText);
              if (idx != null && idx < sharedStrings.length) {
                cellValues.add(sharedStrings[idx]);
              }
            } else if (t == 'inlineStr') {
              final is_ = cell.descendants
                  .whereType<XmlElement>()
                  .firstWhere((e) => e.localName == 't',
                      orElse: () => XmlElement(XmlName('_empty')));
              final text = is_.innerText.trim();
              if (text.isNotEmpty) cellValues.add(text);
            } else {
              // Numeric / date / boolean — use raw value
              cellValues.add(vText);
            }
          }

          if (cellValues.isNotEmpty) {
            rowTexts.add(cellValues.join('\t'));
          }
        }

        if (rowTexts.isNotEmpty) {
          buffer.writeln(rowTexts.join('\n'));
          buffer.writeln();
        }
      }

      final result = buffer.toString().trim();
      return result.isEmpty ? '(No text content found in spreadsheet)' : result;
    } catch (e) {
      return 'Error extracting XLSX: $e';
    }
  }

  List<String> _loadXlsxSharedStrings(Archive archive) {
    final ssFile = _archiveFile(archive, 'xl/sharedStrings.xml');
    if (ssFile == null) return [];
    try {
      final xmlStr = String.fromCharCodes(ssFile.content as List<int>);
      final doc = XmlDocument.parse(xmlStr);
      return doc.descendants
          .whereType<XmlElement>()
          .where((e) => e.localName == 'si')
          .map((si) {
            // Concatenate all <t> children within the <si>
            return si.descendants
                .whereType<XmlElement>()
                .where((e) => e.localName == 't')
                .map((t) => t.innerText)
                .join();
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  int _sheetNumber(String name) {
    final match = RegExp(r'sheet(\d+)\.xml$').firstMatch(name);
    return match != null ? int.tryParse(match.group(1)!) ?? 999 : 999;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  ArchiveFile? _archiveFile(Archive archive, String name) {
    try {
      return archive.files.firstWhere((f) => f.name == name);
    } catch (_) {
      return null;
    }
  }
}
