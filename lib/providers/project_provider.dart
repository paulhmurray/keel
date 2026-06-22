import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';
import '../core/database/database.dart';
import '../core/programme/scaffold_definitions.dart';
import '../core/seed/seed_service.dart';

class ProjectProvider extends ChangeNotifier {
  final AppDatabase _db;

  Project? _currentProject;
  List<Project> _projects = [];
  StreamSubscription<List<Project>>? _projectsSub;

  ProjectProvider(this._db) {
    _loadProjects();
  }

  @override
  void dispose() {
    _projectsSub?.cancel();
    super.dispose();
  }

  Project? get currentProject => _currentProject;
  List<Project> get projects => _projects;
  String? get currentProjectId => _currentProject?.id;

  /// Whether the active project is actually a programme (a portfolio
  /// container that receives cascaded items from linked projects). Used
  /// by views that diverge on kind — charter, status report, overview,
  /// etc. Defaults to false for legacy rows or when no project is
  /// active.
  bool get isProgramme => _currentProject?.kind == 'programme';

  /// Convenience lists for the project picker — separates the two
  /// kinds so the picker can group them.
  List<Project> get projectsOnly =>
      _projects.where((p) => p.kind != 'programme').toList();
  List<Project> get programmesOnly =>
      _projects.where((p) => p.kind == 'programme').toList();

  Future<void> _loadProjects() async {
    _projects = await _db.projectDao.getAllProjects();
    if (_projects.isNotEmpty && _currentProject == null) {
      _currentProject = _projects.first;
    }
    notifyListeners();

    // Watch for project list changes
    _projectsSub = _db.projectDao.watchAllProjects().listen((list) {
      _projects = list;
      // If current project was deleted, clear or pick next
      if (_currentProject != null) {
        final still = list.where((p) => p.id == _currentProject!.id);
        if (still.isEmpty) {
          _currentProject = list.isNotEmpty ? list.first : null;
        }
      } else if (list.isNotEmpty) {
        _currentProject = list.first;
      }
      notifyListeners();
    });
  }

  void selectProject(Project project) {
    _currentProject = project;
    notifyListeners();
  }

  void selectProjectById(String id) {
    final match = _projects.where((p) => p.id == id);
    if (match.isNotEmpty) {
      _currentProject = match.first;
      notifyListeners();
    }
  }

  Future<void> createProject(
    String name, {
    String? description,
    String? startDate,
    String? copyPeopleFromProjectId,
    String kind = 'project',
  }) async {
    final id = const Uuid().v4();
    await _db.projectDao.insertProject(
      ProjectsCompanion.insert(
        id: id,
        name: name,
        description: Value(description),
        startDate: Value(startDate),
        kind: Value(kind),
      ),
    );
    if (copyPeopleFromProjectId != null) {
      // Copy people (and their roles/profiles) from a sibling project
      // or programme. Skip the scaffold seed so we don't duplicate the
      // role list.
      await _db.copyPeopleToProject(
        sourceProjectId: copyPeopleFromProjectId,
        targetProjectId: id,
      );
    } else {
      await _seedScaffold(id);
    }
    // Projects list will update via the stream listener
  }

  /// Convenience wrapper for programme creation — same plumbing as
  /// [createProject] but stamps `kind='programme'` so call sites can be
  /// explicit about intent.
  Future<void> createProgramme(
    String name, {
    String? description,
    String? startDate,
    String? copyPeopleFromProjectId,
  }) =>
      createProject(
        name,
        description: description,
        startDate: startDate,
        copyPeopleFromProjectId: copyPeopleFromProjectId,
        kind: 'programme',
      );

  Future<void> _seedScaffold(String projectId) async {
    final uuid = const Uuid();
    final now = DateTime.now();
    for (final role in stakeholderScaffold) {
      await _db.stakeholderRoleDao.upsert(StakeholderRolesCompanion.insert(
        id: uuid.v4(),
        projectId: projectId,
        roleName: role.roleName,
        roleType: role.roleType,
        isScaffold: const Value(true),
        isApplicable: const Value(true),
        sortOrder: Value(role.sortOrder),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
    }
    for (final role in teamScaffold) {
      await _db.teamRoleDao.upsert(TeamRolesCompanion.insert(
        id: uuid.v4(),
        projectId: projectId,
        roleName: role.roleName,
        teamGroup: role.teamGroup,
        isScaffold: const Value(true),
        isApplicable: const Value(true),
        sortOrder: Value(role.sortOrder),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
    }
  }

  Future<void> deleteProject(String id) async {
    await _db.deleteProjectCascade(id);
    // Stream listener in _loadProjects() handles the list + currentProject update
  }

  Future<void> loadDemoProject() async {
    await SeedService.seedDemoProject(_db);
    // Stream listener will pick up the new project and switch to it if needed
  }

  Future<void> refreshProjects() async {
    _projects = await _db.projectDao.getAllProjects();
    notifyListeners();
  }
}
