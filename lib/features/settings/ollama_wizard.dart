import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../core/llm/ollama_client.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';

// ---------------------------------------------------------------------------
// Recommended models catalogue
// ---------------------------------------------------------------------------

class _OllamaModel {
  final String id;
  final String label;
  final String description;
  final String size;
  final bool recommended;

  const _OllamaModel({
    required this.id,
    required this.label,
    required this.description,
    required this.size,
    this.recommended = false,
  });
}

const _kModels = [
  _OllamaModel(
    id: 'llama3.2:3b',
    label: 'Llama 3.2 3B',
    description: 'Fast · Great for most tasks',
    size: '2 GB',
    recommended: true,
  ),
  _OllamaModel(
    id: 'phi4-mini',
    label: 'Phi-4 Mini',
    description: 'Microsoft · Very efficient',
    size: '2.5 GB',
  ),
  _OllamaModel(
    id: 'gemma3:4b',
    label: 'Gemma 3 4B',
    description: 'Google · Strong reasoning',
    size: '3 GB',
  ),
  _OllamaModel(
    id: 'mistral:7b',
    label: 'Mistral 7B',
    description: 'Balanced quality',
    size: '4 GB',
  ),
  _OllamaModel(
    id: 'llama3.1:8b',
    label: 'Llama 3.1 8B',
    description: 'Most capable free model',
    size: '5 GB',
  ),
];

// ---------------------------------------------------------------------------
// Wizard entry point
// ---------------------------------------------------------------------------

void showOllamaWizard(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const OllamaWizardDialog(),
  );
}

// ---------------------------------------------------------------------------
// Wizard dialog
// ---------------------------------------------------------------------------

enum _WizardStep { detecting, settingUp, selectModel, downloading, ready }

class OllamaWizardDialog extends StatefulWidget {
  const OllamaWizardDialog({super.key});

  @override
  State<OllamaWizardDialog> createState() => _OllamaWizardDialogState();
}

class _OllamaWizardDialogState extends State<OllamaWizardDialog> {
  _WizardStep _step = _WizardStep.detecting;

  // Resolved path to the ollama binary (system PATH or our local install)
  String _ollamaExe = 'ollama';
  bool _ollamaRunning = false;
  List<String> _installedModels = [];

  // Binary download (setting up)
  double _setupProgress = 0; // 0–1
  String _setupStatus = '';
  bool _setupFailed = false;
  http.Client? _httpClient;

  // Model selection
  String _selectedModelId = 'llama3.2:3b';
  final _customCtrl = TextEditingController();
  bool _useCustom = false;

  // Model download
  final List<String> _pullLog = [];
  double _pullProgress = 0; // 0–1
  String _pullStatus = '';
  bool _pullFailed = false;
  bool _pullComplete = false;
  Process? _pullProcess;

  static const _baseUrl = 'http://localhost:11434';

  // ---------------------------------------------------------------------------
  // Local install paths
  // ---------------------------------------------------------------------------

  String get _localBinDir {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '';
    if (Platform.isWindows) {
      return '${Platform.environment['LOCALAPPDATA']}\\Keel\\bin';
    }
    return '$home/.local/share/keel/bin';
  }

  String get _localOllamaExe {
    if (Platform.isWindows) return '$_localBinDir\\ollama.exe';
    return '$_localBinDir/ollama';
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _detect();
  }

  @override
  void dispose() {
    _pullProcess?.kill();
    _httpClient?.close();
    _customCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Step 1: Detection — auto-triggers setup if Ollama not found
  // ---------------------------------------------------------------------------

  Future<void> _detect() async {
    setState(() => _step = _WizardStep.detecting);

    // 1. Check system PATH
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        ['ollama'],
      );
      if (result.exitCode == 0) {
        _ollamaExe = 'ollama';
        await _checkRunningAndProceed();
        return;
      }
    } catch (_) {}

    // 2. Check our own local install
    final localExe = File(_localOllamaExe);
    if (await localExe.exists()) {
      _ollamaExe = _localOllamaExe;
      await _checkRunningAndProceed();
      return;
    }

    // 3. Not found anywhere — silently download the binary
    _downloadBinary();
  }

  Future<void> _checkRunningAndProceed() async {
    _ollamaRunning = await OllamaClient.isRunning(_baseUrl);
    if (_ollamaRunning) {
      _installedModels = await OllamaClient.getAvailableModels(_baseUrl);
    }
    if (mounted) setState(() => _step = _WizardStep.selectModel);
  }

  // ---------------------------------------------------------------------------
  // Step 2: Silent binary download — no sudo, no shell scripts
  // ---------------------------------------------------------------------------

  Future<void> _downloadBinary() async {
    setState(() {
      _step = _WizardStep.settingUp;
      _setupProgress = 0;
      _setupFailed = false;
      _setupStatus = 'Preparing download...';
    });

    Directory? tmpDir;
    try {
      // Detect architecture on Linux
      String arch = 'amd64';
      if (Platform.isLinux) {
        try {
          final r = await Process.run('uname', ['-m']);
          final m = r.stdout.toString().trim();
          if (m == 'aarch64' || m == 'arm64') arch = 'arm64';
        } catch (_) {}
      }

      // Platform-specific download URL and archive type
      final String url;
      final String archiveType; // 'tar.zst' | 'zip' | 'exe'
      if (Platform.isWindows) {
        url = 'https://ollama.com/download/OllamaSetup.exe';
        archiveType = 'exe';
      } else if (Platform.isMacOS) {
        url = 'https://ollama.com/download/Ollama-darwin.zip';
        archiveType = 'zip';
      } else {
        url = 'https://ollama.com/download/ollama-linux-$arch.tar.zst';
        archiveType = 'tar.zst';
      }

      if (mounted) setState(() => _setupStatus = 'Connecting...');

      // Ensure local bin dir exists
      final binDir = Directory(_localBinDir);
      if (!await binDir.exists()) await binDir.create(recursive: true);

      // Temp dir for download + extraction
      tmpDir = await Directory.systemTemp.createTemp('keel_ollama_');
      final tmpFile = File('${tmpDir.path}/ollama.$archiveType');

      // Download
      _httpClient?.close();
      _httpClient = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await _httpClient!
          .send(request)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw 'Server returned HTTP ${response.statusCode}';
      }

      final totalBytes = response.contentLength ?? 0;
      var receivedBytes = 0;
      final sink = tmpFile.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (mounted) {
          setState(() {
            if (totalBytes > 0) {
              _setupProgress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
              final mb = (receivedBytes / 1024 / 1024).toStringAsFixed(0);
              final total = (totalBytes / 1024 / 1024).toStringAsFixed(0);
              _setupStatus = '$mb MB / $total MB';
            } else {
              _setupStatus =
                  '${(receivedBytes / 1024 / 1024).toStringAsFixed(0)} MB downloaded...';
            }
          });
        }
      }
      await sink.close();

      if (mounted) setState(() => _setupStatus = 'Extracting...');

      if (archiveType == 'tar.zst') {
        // Extract bin/ollama from the archive into tmpDir
        final result = await Process.run('tar', [
          '--zstd', '-xf', tmpFile.path, '-C', tmpDir!.path, 'bin/ollama',
        ]);
        if (result.exitCode != 0) throw 'Extraction failed: ${result.stderr}';
        final extracted = File('${tmpDir.path}/bin/ollama');
        if (!await extracted.exists()) throw 'Binary not found in archive';
        await extracted.copy(_localOllamaExe);
        await Process.run('chmod', ['+x', _localOllamaExe]);
        _ollamaExe = _localOllamaExe;
      } else if (archiveType == 'zip') {
        // macOS: unzip then locate the ollama CLI binary
        await Process.run('unzip', ['-o', tmpFile.path, '-d', tmpDir!.path]);
        final binary = await _findBinaryInDir(tmpDir, 'ollama');
        if (binary == null) throw 'Could not find ollama binary in zip';
        await binary.copy(_localOllamaExe);
        await Process.run('chmod', ['+x', _localOllamaExe]);
        _ollamaExe = _localOllamaExe;
      } else {
        // Windows: run NSIS silent installer
        if (mounted) setState(() => _setupStatus = 'Installing...');
        final result = await Process.run(tmpFile.path, ['/S']);
        if (result.exitCode != 0) throw 'Installer exited with ${result.exitCode}';
        _ollamaExe = 'ollama'; // installer adds to system PATH
      }

      if (mounted) setState(() => _setupStatus = 'Starting service...');
      await Process.start(_ollamaExe, ['serve'],
          mode: ProcessStartMode.detached);
      await Future.delayed(const Duration(seconds: 2));
      _ollamaRunning = await OllamaClient.isRunning(_baseUrl);
      if (_ollamaRunning) {
        _installedModels = await OllamaClient.getAvailableModels(_baseUrl);
      }

      if (mounted) setState(() => _step = _WizardStep.selectModel);
    } catch (e) {
      if (mounted) {
        setState(() {
          _setupFailed = true;
          _setupStatus = e.toString();
        });
      }
    } finally {
      try { await tmpDir?.delete(recursive: true); } catch (_) {}
    }
  }

  /// Recursively finds the first file named [name] inside [dir].
  Future<File?> _findBinaryInDir(Directory dir, String name) async {
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.uri.pathSegments.last == name) {
        return entity;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Step 3: Model download
  // ---------------------------------------------------------------------------

  String get _targetModel =>
      _useCustom ? _customCtrl.text.trim() : _selectedModelId;

  Future<void> _pullModel() async {
    final model = _targetModel;
    if (model.isEmpty) return;

    setState(() {
      _step = _WizardStep.downloading;
      _pullLog.clear();
      _pullProgress = 0;
      _pullStatus = 'Starting download...';
      _pullFailed = false;
      _pullComplete = false;
    });

    try {
      // Ensure service is running
      if (!_ollamaRunning) {
        await Process.start(_ollamaExe, ['serve'],
            mode: ProcessStartMode.detached);
        await Future.delayed(const Duration(seconds: 2));
        _ollamaRunning = await OllamaClient.isRunning(_baseUrl);
      }

      _pullProcess = await Process.start(_ollamaExe, ['pull', model]);

      _pullProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onPullLine);

      _pullProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty && mounted) {
          setState(() => _pullLog.add(line));
        }
      });

      final exitCode = await _pullProcess!.exitCode;
      if (!mounted) return;

      if (exitCode == 0) {
        setState(() {
          _pullComplete = true;
          _pullProgress = 1.0;
          _pullStatus = 'Download complete.';
        });
        await Future.delayed(const Duration(milliseconds: 500));
        _finalise();
      } else {
        setState(() {
          _pullFailed = true;
          _pullStatus = 'Download failed (exit code $exitCode).';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pullFailed = true;
          _pullStatus = 'Error: $e';
        });
      }
    }
  }

  void _onPullLine(String line) {
    if (!mounted) return;
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final status = json['status'] as String? ?? '';
      final total = (json['total'] as num?)?.toDouble() ?? 0;
      final completed = (json['completed'] as num?)?.toDouble() ?? 0;

      setState(() {
        _pullStatus = status;
        if (total > 0) {
          _pullProgress = (completed / total).clamp(0.0, 1.0);
        }
        _pullLog.add(_formatPullStatus(status, total, completed));
        if (_pullLog.length > 8) _pullLog.removeAt(0);
      });
    } catch (_) {
      if (line.trim().isNotEmpty) {
        setState(() {
          _pullLog.add(line);
          if (_pullLog.length > 8) _pullLog.removeAt(0);
        });
      }
    }
  }

  String _formatPullStatus(String status, double total, double completed) {
    if (total > 0) {
      final pct = (completed / total * 100).toStringAsFixed(0);
      final mbDone = (completed / 1024 / 1024).toStringAsFixed(0);
      final mbTotal = (total / 1024 / 1024).toStringAsFixed(0);
      return '$status — $pct% ($mbDone / $mbTotal MB)';
    }
    return status;
  }

  void _finalise() async {
    _installedModels = await OllamaClient.getAvailableModels(_baseUrl);
    if (!mounted) return;
    setState(() => _step = _WizardStep.ready);
  }

  // ---------------------------------------------------------------------------
  // Switch to Ollama
  // ---------------------------------------------------------------------------

  Future<void> _switchToOllama() async {
    final sp = context.read<SettingsProvider>();
    await sp.save(sp.settings.copyWith(
      llmProvider: LLMProvider.ollama,
      ollamaModel: _targetModel,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: KColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: KColors.border2),
      ),
      child: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildStepIndicator(),
            const Divider(color: KColors.border, height: 1),
            Flexible(child: SingleChildScrollView(child: _buildBody())),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final busy = (_step == _WizardStep.detecting ||
            _step == _WizardStep.settingUp ||
            _step == _WizardStep.downloading) &&
        !_setupFailed &&
        !_pullFailed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.computer_outlined, size: 18, color: KColors.amber),
          const SizedBox(width: 10),
          const Text(
            'LOCAL AI SETUP',
            style: TextStyle(
              color: KColors.amber,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08,
            ),
          ),
          const Spacer(),
          if (!busy)
            InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(3),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: KColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    const steps = ['Setup', 'Choose', 'Download', 'Ready'];
    int currentStep;
    switch (_step) {
      case _WizardStep.detecting:
      case _WizardStep.settingUp:
        currentStep = 0;
      case _WizardStep.selectModel:
        currentStep = 1;
      case _WizardStep.downloading:
        currentStep = 2;
      case _WizardStep.ready:
        currentStep = 3;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: steps.asMap().entries.map((e) {
          final i = e.key;
          final label = e.value;
          final isDone = i < currentStep;
          final isActive = i == currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isDone
                              ? KColors.phosDim
                              : isActive
                                  ? KColors.amberDim
                                  : KColors.surface2,
                          border: Border.all(
                            color: isDone
                                ? KColors.phosphor
                                : isActive
                                    ? KColors.amber
                                    : KColors.border,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: isDone
                              ? const Icon(Icons.check,
                                  size: 12, color: KColors.phosphor)
                              : Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    color: isActive
                                        ? KColors.amber
                                        : KColors.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          color:
                              isActive ? KColors.amber : KColors.textMuted,
                          fontSize: 10,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < steps.length - 1)
                  Container(
                    width: 24,
                    height: 1,
                    color: isDone ? KColors.phosphor : KColors.border,
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _WizardStep.detecting:
        return _buildDetecting();
      case _WizardStep.settingUp:
        return _buildSettingUp();
      case _WizardStep.selectModel:
        return _buildSelectModel();
      case _WizardStep.downloading:
        return _buildDownloading();
      case _WizardStep.ready:
        return _buildReady();
    }
  }

  // ---------------------------------------------------------------------------
  // Step bodies
  // ---------------------------------------------------------------------------

  Widget _buildDetecting() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        children: [
          CircularProgressIndicator(color: KColors.amber, strokeWidth: 2),
          SizedBox(height: 20),
          Text(
            'Checking your system...',
            style: TextStyle(color: KColors.textDim, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingUp() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!_setupFailed)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: KColors.amber),
                )
              else
                const Icon(Icons.error_outline, size: 14, color: KColors.red),
              const SizedBox(width: 10),
              Text(
                _setupFailed ? 'Setup failed' : 'Setting up local AI engine',
                style: TextStyle(
                  color: _setupFailed ? KColors.red : KColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (!_setupFailed) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _setupProgress > 0 ? _setupProgress : null,
                backgroundColor: KColors.surface2,
                color: KColors.amber,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _setupStatus,
              style: const TextStyle(color: KColors.textDim, fontSize: 11),
            ),
            const SizedBox(height: 24),
            const Text(
              'This is a one-time setup. The AI engine runs entirely on your '
              'computer — no data is sent anywhere.',
              style: TextStyle(
                  color: KColors.textMuted, fontSize: 11, height: 1.5),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              _setupStatus,
              style: const TextStyle(
                  color: KColors.textMuted, fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _downloadBinary,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Try Again'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectModel() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service status
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color:
                  _ollamaRunning ? KColors.phosDim : KColors.amberDim,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _ollamaRunning
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                  size: 13,
                  color:
                      _ollamaRunning ? KColors.phosphor : KColors.amber,
                ),
                const SizedBox(width: 6),
                Text(
                  _ollamaRunning
                      ? 'AI engine ready · ${_installedModels.length} model${_installedModels.length == 1 ? '' : 's'} installed'
                      : 'AI engine installed — will start when you download a model',
                  style: TextStyle(
                    color: _ollamaRunning
                        ? KColors.phosphor
                        : KColors.amber,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Choose a model to download',
            style: TextStyle(
              color: KColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Larger models produce better results but require more RAM and storage.',
            style: TextStyle(color: KColors.textDim, fontSize: 11),
          ),
          const SizedBox(height: 16),

          // Model list
          ..._kModels.map((m) {
            final isInstalled = _installedModels.any(
                (installed) => installed.startsWith(m.id.split(':').first));
            final isSelected = !_useCustom && _selectedModelId == m.id;
            return _ModelOption(
              model: m,
              isSelected: isSelected,
              isInstalled: isInstalled,
              onTap: () => setState(() {
                _selectedModelId = m.id;
                _useCustom = false;
              }),
            );
          }),

          const SizedBox(height: 8),
          // Custom model
          InkWell(
            onTap: () => setState(() => _useCustom = true),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _useCustom
                    ? KColors.amberDim
                    : Colors.transparent,
                border: Border.all(
                  color: _useCustom
                      ? KColors.amber.withValues(alpha: 0.4)
                      : KColors.border,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    _useCustom
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 14,
                    color: _useCustom ? KColors.amber : KColors.textDim,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _useCustom
                        ? TextField(
                            controller: _customCtrl,
                            autofocus: true,
                            style: const TextStyle(
                                color: KColors.text, fontSize: 12),
                            decoration: const InputDecoration(
                              hintText: 'e.g. codellama:7b',
                              hintStyle: TextStyle(
                                  color: KColors.textMuted, fontSize: 12),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          )
                        : const Text(
                            'Custom model',
                            style: TextStyle(
                                color: KColors.textDim, fontSize: 12),
                          ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed:
                    _targetModel.isNotEmpty ? _pullModel : null,
                icon: const Icon(Icons.download_outlined, size: 14),
                label: Text(
                    'Download ${_useCustom ? (_customCtrl.text.trim().isEmpty ? "model" : _customCtrl.text.trim()) : _selectedModelId}'),
              ),
              if (_installedModels.isNotEmpty) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      if (!_installedModels.contains(_selectedModelId)) {
                        _selectedModelId = _installedModels.first;
                      }
                      _step = _WizardStep.ready;
                    });
                  },
                  child: const Text('Use existing model'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDownloading() {
    final pct = (_pullProgress * 100).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!_pullFailed && !_pullComplete)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: KColors.amber),
                )
              else if (_pullComplete)
                const Icon(Icons.check_circle,
                    size: 14, color: KColors.phosphor)
              else
                const Icon(Icons.error_outline,
                    size: 14, color: KColors.red),
              const SizedBox(width: 8),
              Text(
                _pullFailed
                    ? 'Download failed'
                    : _pullComplete
                        ? 'Download complete'
                        : 'Downloading $_targetModel',
                style: TextStyle(
                  color: _pullFailed
                      ? KColors.red
                      : _pullComplete
                          ? KColors.phosphor
                          : KColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!_pullFailed && !_pullComplete) ...[
                const Spacer(),
                Text(
                  '$pct%',
                  style: const TextStyle(
                    color: KColors.amber,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _pullProgress > 0 ? _pullProgress : null,
              backgroundColor: KColors.surface2,
              color: _pullFailed ? KColors.red : KColors.amber,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _pullStatus,
            style: const TextStyle(color: KColors.textDim, fontSize: 11),
          ),
          const SizedBox(height: 12),

          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 140),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: KColors.bg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: KColors.border),
            ),
            child: SingleChildScrollView(
              reverse: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _pullLog
                    .map((l) => Text(
                          l,
                          style: const TextStyle(
                            color: KColors.textDim,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),

          if (_pullFailed) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _pullModel,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Retry'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () =>
                      setState(() => _step = _WizardStep.selectModel),
                  child: const Text('Back'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReady() {
    final model = _targetModel.isNotEmpty
        ? _targetModel
        : (_installedModels.isNotEmpty ? _installedModels.first : 'unknown');

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, size: 20, color: KColors.phosphor),
              SizedBox(width: 10),
              Text(
                'Local AI is ready',
                style: TextStyle(
                  color: KColors.phosphor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Keel can now run fully offline. Everything stays on your computer.',
            style: TextStyle(color: KColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: KColors.phosDim,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.computer_outlined,
                    size: 13, color: KColors.phosphor),
                const SizedBox(width: 6),
                Text(
                  model,
                  style: const TextStyle(
                    color: KColors.phosphor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Local models are faster and private but may produce shorter '
            'or less nuanced responses than cloud models.',
            style: TextStyle(
                color: KColors.textMuted, fontSize: 11, height: 1.5),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _switchToOllama,
                icon: const Icon(Icons.check, size: 14),
                label: const Text('Switch to Local'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KColors.phosDim,
                  foregroundColor: KColors.phosphor,
                  side: const BorderSide(
                      color: KColors.phosphor, width: 0.5),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Keep current provider'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Model option tile
// ---------------------------------------------------------------------------

class _ModelOption extends StatelessWidget {
  final _OllamaModel model;
  final bool isSelected;
  final bool isInstalled;
  final VoidCallback onTap;

  const _ModelOption({
    required this.model,
    required this.isSelected,
    required this.isInstalled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? KColors.amberDim : Colors.transparent,
            border: Border.all(
              color: isSelected
                  ? KColors.amber.withValues(alpha: 0.4)
                  : KColors.border,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 14,
                color: isSelected ? KColors.amber : KColors.textDim,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          model.label,
                          style: TextStyle(
                            color: isSelected
                                ? KColors.amber
                                : KColors.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (model.recommended) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: KColors.amberDim,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: const Text(
                              'RECOMMENDED',
                              style: TextStyle(
                                color: KColors.amber,
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.05,
                              ),
                            ),
                          ),
                        ],
                        if (isInstalled) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: KColors.phosDim,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: const Text(
                              'INSTALLED',
                              style: TextStyle(
                                color: KColors.phosphor,
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.05,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      model.description,
                      style: const TextStyle(
                          color: KColors.textDim, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                model.size,
                style: const TextStyle(
                    color: KColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Standalone model pull button (used in LLM settings view)
// ---------------------------------------------------------------------------

/// Resolves the ollama binary path: system PATH first, then Keel's local install.
Future<String> resolveOllamaExe() async {
  try {
    final r = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      ['ollama'],
    );
    if (r.exitCode == 0) return 'ollama';
  } catch (_) {}

  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ?? '';
  final local = Platform.isWindows
      ? '${Platform.environment['LOCALAPPDATA']}\\Keel\\bin\\ollama.exe'
      : '$home/.local/share/keel/bin/ollama';

  if (await File(local).exists()) return local;
  return 'ollama'; // fallback — will fail gracefully if not found
}

class OllamaModelPullButton extends StatefulWidget {
  final String modelId;
  final String baseUrl;
  final VoidCallback? onComplete;

  const OllamaModelPullButton({
    super.key,
    required this.modelId,
    required this.baseUrl,
    this.onComplete,
  });

  @override
  State<OllamaModelPullButton> createState() => _OllamaModelPullButtonState();
}

class _OllamaModelPullButtonState extends State<OllamaModelPullButton> {
  bool _pulling = false;
  bool _done = false;
  bool _failed = false;
  double _progress = 0;
  Process? _process;

  @override
  void dispose() {
    _process?.kill();
    super.dispose();
  }

  Future<void> _pull() async {
    setState(() {
      _pulling = true;
      _done = false;
      _failed = false;
      _progress = 0;
    });

    try {
      final exe = await resolveOllamaExe();

      // Ensure service is running
      final running = await OllamaClient.isRunning(widget.baseUrl);
      if (!running) {
        await Process.start(exe, ['serve'], mode: ProcessStartMode.detached);
        await Future.delayed(const Duration(seconds: 2));
      }

      _process = await Process.start(exe, ['pull', widget.modelId]);

      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (!mounted) return;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final total = (json['total'] as num?)?.toDouble() ?? 0;
          final completed = (json['completed'] as num?)?.toDouble() ?? 0;
          if (total > 0 && mounted) {
            setState(() => _progress = (completed / total).clamp(0.0, 1.0));
          }
        } catch (_) {}
      });

      final exitCode = await _process!.exitCode;
      if (!mounted) return;

      if (exitCode == 0) {
        setState(() {
          _done = true;
          _pulling = false;
          _progress = 1.0;
        });
        widget.onComplete?.call();
      } else {
        setState(() {
          _failed = true;
          _pulling = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() {
        _failed = true;
        _pulling = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return const Icon(Icons.check_circle, size: 16, color: KColors.phosphor);
    }

    if (_pulling) {
      return SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: KColors.surface2,
                color: KColors.amber,
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _progress > 0
                  ? '${(_progress * 100).toStringAsFixed(0)}%'
                  : 'Pulling...',
              style: const TextStyle(color: KColors.textDim, fontSize: 9),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: _pull,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _failed ? KColors.redDim : KColors.amberDim,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: _failed
                ? KColors.red.withValues(alpha: 0.3)
                : KColors.amber.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          _failed ? 'Retry' : 'Pull',
          style: TextStyle(
            color: _failed ? KColors.red : KColors.amber,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
