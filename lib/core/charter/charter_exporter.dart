import '../database/database.dart';
import '../platform/web_download.dart';

class CharterExporter {
  static Future<String> export({
    required String projectName,
    required ProjectCharter charter,
    required String format, // 'md' | 'html'
  }) async {
    final slug =
        projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final date = DateTime.now().toIso8601String().substring(0, 10);

    switch (format) {
      case 'md':
        final md = _buildMarkdown(projectName: projectName, charter: charter);
        return saveTextAndOpen('charter-$slug-$date.md', md);
      case 'html':
      default:
        final html = _buildHtml(projectName: projectName, charter: charter);
        return saveTextAndOpen('charter-$slug-$date.html', html);
    }
  }

  static String _buildMarkdown({
    required String projectName,
    required ProjectCharter charter,
  }) {
    final sb = StringBuffer();
    sb.writeln('# Programme Charter — $projectName');
    sb.writeln();
    sb.writeln(
        '_Exported ${DateTime.now().toIso8601String().substring(0, 10)}_');
    sb.writeln();
    _mdSection(sb, 'Vision', charter.vision);
    _mdSection(sb, 'Objectives', charter.objectives);
    _mdSection(sb, 'Scope — In Scope', charter.scopeIn);
    _mdSection(sb, 'Scope — Out of Scope', charter.scopeOut);
    _mdSection(sb, 'Delivery Approach', charter.deliveryApproach);
    _mdSection(sb, 'Success Criteria', charter.successCriteria);
    _mdSection(sb, 'Key Constraints', charter.keyConstraints);
    _mdSection(sb, 'Assumptions', charter.assumptions);
    return sb.toString();
  }

  static void _mdSection(StringBuffer sb, String title, String? value) {
    sb.writeln('## $title');
    sb.writeln();
    sb.writeln(value?.isNotEmpty == true ? value! : '_Not yet defined._');
    sb.writeln();
  }

  static String _buildHtml({
    required String projectName,
    required ProjectCharter charter,
  }) {
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final sb = StringBuffer();
    sb.writeln('''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Charter — $projectName</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: #1a1f2e; color: #e2e8f0; font-family: 'Segoe UI', system-ui, sans-serif;
         font-size: 14px; padding: 40px; max-width: 860px; margin: 0 auto; }
  h1 { font-size: 20px; font-weight: 700; color: #e2e8f0; margin-bottom: 4px; }
  .meta { color: #8a9faf; font-size: 11px; margin-bottom: 40px; }
  .section { margin-bottom: 32px; }
  .section-header { display: flex; align-items: center; gap: 12px; margin-bottom: 12px; }
  .section-label { font-size: 9px; font-weight: 700; letter-spacing: 0.15em;
                   color: #8a9faf; text-transform: uppercase; white-space: nowrap; }
  .section-rule { flex: 1; height: 1px; background: #2e3446; }
  .prose { color: #e2e8f0; font-size: 14px; line-height: 1.7; white-space: pre-wrap; }
  .empty { color: #4a5568; font-style: italic; }
</style>
</head>
<body>
<h1>Programme Charter — ${_esc(projectName)}</h1>
<p class="meta">Exported $date</p>
''');

    void section(String label, String? value) {
      sb.writeln('<div class="section">');
      sb.writeln('<div class="section-header">');
      sb.writeln(
          '<span class="section-label">${_esc(label)}</span><span class="section-rule"></span>');
      sb.writeln('</div>');
      if (value != null && value.isNotEmpty) {
        sb.writeln('<p class="prose">${_esc(value)}</p>');
      } else {
        sb.writeln('<p class="empty">Not yet defined.</p>');
      }
      sb.writeln('</div>');
    }

    section('Vision', charter.vision);
    section('Objectives', charter.objectives);
    section('Scope — In scope', charter.scopeIn);
    section('Scope — Out of scope', charter.scopeOut);
    section('Delivery Approach', charter.deliveryApproach);
    section('Success Criteria', charter.successCriteria);
    section('Key Constraints', charter.keyConstraints);
    section('Assumptions', charter.assumptions);

    sb.writeln('</body></html>');
    return sb.toString();
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
