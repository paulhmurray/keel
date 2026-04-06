import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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

enum _WizardStep { detecting, notInstalled, installing, selectModel, downloading, ready }

class OllamaWizardDialog extends StatefulWidget {
  const OllamaWizardDialog({super.key});

  @override
  State<OllamaWizardDialog> createState() => _OllamaWizardDialogState();
}

class _OllamaWizardDialogState extends State<OllamaWizardDialog> {
  _WizardStep _step = _WizardStep.detecting;

  // Detection
  bool _ollamaInPath = false;
  bool _ollamaRunning = false;
  List<String> _installedModels = [];

  // Install
  final List<String> _installLog = [];
  bool _installFailed = false;

  // Model selection
  String _selectedModelId = 'llama3.2:3b';
  final _customCtrl = TextEditingController();
  bool _useCustom = false;

  // Download
  final List<String> _pullLog = [];
  double _pullProgress = 0; // 0–1
  String _pullStatus = '';
  bool _pullFailed = false;
  bool _pullComplete = false;
  Process? _pullProcess;

  static const _baseUrl = 'http://localhost:11434';

  @override
  void initState() {
    super.initState();
    _detect();
  }

  @override
  void dispose() {
    _pullProcess?.kill();
    _customCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Step 1: Detection
  // ---------------------------------------------------------------------------

  Future<void> _detect() async {
    setState(() => _step = _WizardStep.detecting);

    // Check if ollama binary is in PATH
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        ['ollama'],
      );
      _ollamaInPath = result.exitCode == 0;
    } catch (_) {
      _ollamaInPath = false;
    }

    if (!_ollamaInPath) {
      setState(() => _step = _WizardStep.notInstalled);
      return;
    }

    // Check if service is running and get installed models
    _ollamaRunning = await OllamaClient.isRunning(_baseUrl);
    if (_ollamaRunning) {
      _installedModels = await OllamaClient.getAvailableModels(_baseUrl);
    }

    setState(() => _step = _WizardStep.selectModel);
  }

  // ---------------------------------------------------------------------------
  // Step 2: Install (optional)
  // ---------------------------------------------------------------------------

  Future<void> _runInstall() async {
    setState(() {
      _step = _WizardStep.installing;
      _installLog.clear();
      _installFailed = false;
    });

    try {
      Process process;
      if (Platform.isLinux || Platform.isMacOS) {
        process = await Process.start(
          'bash',
          ['-c', 'curl -fsSL https://ollama.ai/install.sh | sh'],
        );
      } else {
        // Windows: open browser to download page — no silent install
        await Process.run('cmd', ['/c', 'start', 'https://ollama.com/download']);
        setState(() {
          _installLog.add('Opening ollama.com/download in your browser.');
          _installLog.add('Install Ollama, then click "I installed it manually".');
        });
        return;
      }

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (mounted) setState(() => _installLog.add(line));
      });
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (mounted) setState(() => _installLog.add(line));
      });

      final exitCode = await process.exitCode;
      if (!mounted) return;

      if (exitCode == 0) {
        _ollamaInPath = true;
        // Give the service a moment to start
        await Future.delayed(const Duration(seconds: 2));
        _ollamaRunning = await OllamaClient.isRunning(_baseUrl);
        if (_ollamaRunning) {
          _installedModels = await OllamaClient.getAvailableModels(_baseUrl);
        }
        setState(() => _step = _WizardStep.selectModel);
      } else {
        setState(() => _installFailed = true);
      }
    } catch (e) {
      if (mounted) setState(() => _installFailed = true);
    }
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
      // First ensure Ollama service is running; start it if not
      if (!_ollamaRunning) {
        await Process.start('ollama', ['serve'],
            mode: ProcessStartMode.detached);
        await Future.delayed(const Duration(seconds: 2));
        _ollamaRunning = await OllamaClient.isRunning(_baseUrl);
      }

      _pullProcess = await Process.start('ollama', ['pull', model]);

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
        // Save model in settings and mark as ready
        _finalise();
      } else {
        setState(() {
          _pullFailed = true;
          _pullStatus = 'Download failed (exit code $exitCode).';
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _pullFailed = true;
        _pullStatus = 'Error: $e';
      });
    }
  }

  void _onPullLine(String line) {
    if (!mounted) return;
    try {
      // Ollama streams newline-delimited JSON
      final json = jsonDecode(line) as Map<String, dynamic>;
      final status = json['status'] as String? ?? '';
      final total = (json['total'] as num?)?.toDouble() ?? 0;
      final completed = (json['completed'] as num?)?.toDouble() ?? 0;

      setState(() {
        _pullStatus = status;
        if (total > 0) {
          _pullProgress = (completed / total).clamp(0.0, 1.0);
        }
        // Keep last 8 lines in log
        _pullLog.add(_formatPullStatus(status, total, completed));
        if (_pullLog.length > 8) _pullLog.removeAt(0);
      });
    } catch (_) {
      // Not JSON — plain text line
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
    // Refresh installed models
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.computer_outlined, size: 18, color: KColors.amber),
          const SizedBox(width: 10),
          const Text(
            'OLLAMA SETUP WIZARD',
            style: TextStyle(
              color: KColors.amber,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08,
            ),
          ),
          const Spacer(),
          if (_step != _WizardStep.downloading && _step != _WizardStep.installing)
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
    const steps = ['Detect', 'Select', 'Download', 'Ready'];
    int currentStep;
    switch (_step) {
      case _WizardStep.detecting:
      case _WizardStep.notInstalled:
      case _WizardStep.installing:
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
                              ? const Icon(Icons.check, size: 12, color: KColors.phosphor)
                              : Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    color: isActive ? KColors.amber : KColors.textMuted,
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
                          color: isActive ? KColors.amber : KColors.textMuted,
                          fontSize: 9,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
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
      case _WizardStep.notInstalled:
        return _buildNotInstalled();
      case _WizardStep.installing:
        return _buildInstalling();
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
            'Checking for Ollama...',
            style: TextStyle(color: KColors.textDim, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildNotInstalled() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: KColors.amber),
              SizedBox(width: 8),
              Text(
                'Ollama not found',
                style: TextStyle(
                  color: KColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Ollama is not installed on this machine. Keel can download and '
            'run the installer for you, or you can install it manually.',
            style: TextStyle(color: KColors.textDim, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _runInstall,
                icon: const Icon(Icons.download_outlined, size: 14),
                label: const Text('Download & Install Ollama'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () async {
                  // User says they'll install manually — re-detect after a moment
                  await Future.delayed(const Duration(seconds: 1));
                  _detect();
                },
                child: const Text("I'll install it myself"),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Ollama is free and open source. It runs entirely on your machine — '
            'no data leaves your computer.',
            style: TextStyle(color: KColors.textMuted, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildInstalling() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!_installFailed)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: KColors.amber),
                )
              else
                const Icon(Icons.error_outline, size: 14, color: KColors.red),
              const SizedBox(width: 8),
              Text(
                _installFailed ? 'Installation failed' : 'Installing Ollama...',
                style: TextStyle(
                  color: _installFailed ? KColors.red : KColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KColors.bg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: KColors.border),
            ),
            child: SingleChildScrollView(
              reverse: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _installLog
                    .map((l) => Text(
                          l,
                          style: const TextStyle(
                            color: KColors.textDim,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
          if (_installFailed) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _runInstall,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Retry'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => setState(() => _step = _WizardStep.notInstalled),
                  child: const Text('Back'),
                ),
              ],
            ),
          ] else if (Platform.isWindows) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _detect,
              child: const Text('I installed it — check again'),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _ollamaRunning ? KColors.phosDim : KColors.amberDim,
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
                  color: _ollamaRunning ? KColors.phosphor : KColors.amber,
                ),
                const SizedBox(width: 6),
                Text(
                  _ollamaRunning
                      ? 'Ollama is running · ${_installedModels.length} model${_installedModels.length == 1 ? '' : 's'} installed'
                      : 'Ollama installed but not running — will start on pull',
                  style: TextStyle(
                    color: _ollamaRunning ? KColors.phosphor : KColors.amber,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _useCustom ? KColors.amberDim : Colors.transparent,
                border: Border.all(
                  color: _useCustom ? KColors.amber.withValues(alpha: 0.4) : KColors.border,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    _useCustom ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 14,
                    color: _useCustom ? KColors.amber : KColors.textDim,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _useCustom
                        ? TextField(
                            controller: _customCtrl,
                            autofocus: true,
                            style: const TextStyle(color: KColors.text, fontSize: 12),
                            decoration: const InputDecoration(
                              hintText: 'e.g. codellama:7b',
                              hintStyle: TextStyle(color: KColors.textMuted, fontSize: 12),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          )
                        : const Text(
                            'Custom model',
                            style: TextStyle(color: KColors.textDim, fontSize: 12),
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
                onPressed: _targetModel.isNotEmpty ? _pullModel : null,
                icon: const Icon(Icons.download_outlined, size: 14),
                label: Text('Download ${_useCustom ? (_customCtrl.text.trim().isEmpty ? "model" : _customCtrl.text.trim()) : _selectedModelId}'),
              ),
              if (_installedModels.isNotEmpty) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {
                    // Already have models — skip to ready
                    setState(() {
                      if (_installedModels.isNotEmpty &&
                          !_installedModels.contains(_selectedModelId)) {
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
                const Icon(Icons.check_circle, size: 14, color: KColors.phosphor)
              else
                const Icon(Icons.error_outline, size: 14, color: KColors.red),
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

          // Progress bar
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

          // Log
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
                  onPressed: () => setState(() => _step = _WizardStep.selectModel),
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
                'Ollama is ready',
                style: TextStyle(
                  color: KColors.phosphor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Local LLM ready. Keel can now run fully offline.',
            style: const TextStyle(color: KColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: KColors.phosDim,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.computer_outlined, size: 13, color: KColors.phosphor),
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
            style: TextStyle(color: KColors.textMuted, fontSize: 11, height: 1.5),
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
                  side: const BorderSide(color: KColors.phosphor, width: 0.5),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              model.label,
                              style: TextStyle(
                                color: isSelected ? KColors.amber : KColors.text,
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
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          model.description,
                          style: const TextStyle(
                              color: KColors.textDim, fontSize: 11),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      model.size,
                      style: const TextStyle(
                          color: KColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inline model pull widget (used in settings card)
// ---------------------------------------------------------------------------

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
  String _status = '';
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
      _status = 'Starting...';
    });

    try {
      _process = await Process.start('ollama', ['pull', widget.modelId]);

      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine);

      final exitCode = await _process!.exitCode;
      if (!mounted) return;
      if (exitCode == 0) {
        setState(() {
          _done = true;
          _pulling = false;
          _progress = 1.0;
          _status = 'Done';
        });
        widget.onComplete?.call();
      } else {
        setState(() {
          _failed = true;
          _pulling = false;
          _status = 'Failed';
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _failed = true;
        _pulling = false;
        _status = 'Error: $e';
      });
    }
  }

  void _onLine(String line) {
    if (!mounted) return;
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final status = json['status'] as String? ?? '';
      final total = (json['total'] as num?)?.toDouble() ?? 0;
      final completed = (json['completed'] as num?)?.toDouble() ?? 0;
      setState(() {
        _status = status;
        if (total > 0) _progress = (completed / total).clamp(0.0, 1.0);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return const Icon(Icons.check_circle, size: 14, color: KColors.phosphor);
    }
    if (_pulling) {
      return SizedBox(
        width: 80,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              backgroundColor: KColors.surface2,
              color: KColors.amber,
              minHeight: 3,
            ),
            const SizedBox(height: 2),
            Text(
              _status,
              style: const TextStyle(color: KColors.textMuted, fontSize: 9),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }
    return InkWell(
      onTap: _pull,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: KColors.border2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download_outlined, size: 11, color: KColors.textDim),
            const SizedBox(width: 3),
            Text(
              _failed ? 'Retry' : 'Pull',
              style: TextStyle(
                color: _failed ? KColors.red : KColors.textDim,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
