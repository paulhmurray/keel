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

  ProjectProvider(this._db) {
    _loadProjects();
  }

  Project? get currentProject => _currentProject;
  List<Project> get projects => _projects;
  String? get currentProjectId => _currentProject?.id;

  Future<void> _loadProjects() async {
    _projects = await _db.projectDao.getAllProjects();
    if (_projects.isNotEmpty && _currentProject == null) {
      _currentProject = _projects.first;
    }
    notifyListeners();

    // Watch for project list changes
    _db.projectDao.watchAllProjects().listen((list) {
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

  Future<void> createProject(String name, {String? description, String? startDate}) async {
    final id = const Uuid().v4();
    await _db.projectDao.insertProject(
      ProjectsCompanion.insert(
        id: id,
        name: name,
        description: Value(description),
        startDate: Value(startDate),
      ),
    );
    await _seedScaffold(id);
    // Projects list will update via the stream listener
  }

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
