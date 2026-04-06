import 'dart:io';

/// Extracts text content from document files.
///
/// Supported formats:
/// - .txt / .md  — read directly with dart:io
/// - .pdf / .docx — returns a helpful placeholder (proper extraction
///   requires native plugins; add in a future phase)
class DocumentProcessor {
  const DocumentProcessor();

  /// Extracts text from a document file.
  ///
  /// [filePath] — absolute path to the file.
  /// [fileType] — lowercase extension hint, e.g. 'pdf', 'docx', 'txt', 'md'.
  ///
  /// Returns extracted plain text, or a human-readable message for
  /// unsupported formats.
  Future<String> extractText(String filePath, String fileType) async {
    final type = fileType.toLowerCase().replaceFirst(RegExp(r'^\.'), '');

    switch (type) {
      case 'txt':
      case 'md':
        return _readTextFile(filePath);
      case 'pdf':
        return 'PDF text extraction is not yet supported in this version.\n\n'
            'To add this document\'s content:\n'
            '• Open the PDF in your PDF viewer\n'
            '• Copy the text you want to capture\n'
            '• Use the "Paste text" option when uploading, or add it as a '
            'Context Entry manually.';
      case 'docx':
        return 'DOCX text extraction is not yet supported in this version.\n\n'
            'To add this document\'s content:\n'
            '• Open the file in Word or LibreOffice\n'
            '• Copy the relevant text\n'
            '• Use the "Paste text" option when uploading, or add it as a '
            'Context Entry manually.';
      default:
        return 'Unsupported file type: .$type\n\n'
            'Supported formats for automatic extraction: .txt, .md\n'
            'For other formats, paste the text content manually.';
    }
  }

  Future<String> _readTextFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return 'Error: File not found at path: $filePath';
      }
      final content = await file.readAsString();
      if (content.isEmpty) {
        return '(File is empty)';
      }
      return content;
    } catch (e) {
      return 'Error reading file: $e';
    }
  }
}
