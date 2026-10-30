/// Portfolio demo: one PMO portfolio, three programmes with deliberately
/// different health profiles, seven linked projects, and a local cascade
/// pass so every tier is populated the moment the seed finishes.
///
/// The three programmes are written to make the portfolio page argue
/// its own case:
///   • Core Banking Modernisation — honest amber: data and report agree.
///   • Customer Channels — the watermelon: reported GREEN, data says red,
///     decisions past need-by, forecast breaching tolerance.
///   • Regulatory & Risk Uplift — green and complete: every input filled.
/// People are shared across projects by name so the load metric fires.
///
/// Dates are relative to today so the demo never goes stale.
library;

import 'package:drift/drift.dart';

import '../cascade/cascade_service.dart';
import '../cascade/cascade_sync.dart';
import '../cascade/local_cascade_gateway.dart';
import '../database/database.dart';
import '../portfolio/programme_pulse.dart' show isoDate;

class PortfolioSeedService {
  static const portfolioId = 'seed-port-001';

  /// Seeds the whole tree. Returns false (and does nothing) when the demo
  /// portfolio already exists.
  static Future<bool> seed(AppDatabase db) async {
    if (await db.projectDao.getProjectById(portfolioId) != null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Plan axis shared by every entity: 24 months from the January of
    // this year, so cascaded bars line up on the programme Gantt.
    final month0 = DateTime(today.year, 1, 5);
    final labels = List.generate(24, (i) {
      final d = DateTime(month0.year, month0.month + i, 1);
      return '"${_mon[d.month - 1]} ${d.year}"';
    });
    final monthLabelsJson = '[${labels.join(',')}]';
    int monthOf(DateTime d) => (d.year - month0.year) * 12 + d.month - month0.month;
    String day(int offset) => isoDate(today.add(Duration(days: offset)));

    await db.projectDao.insertProject(ProjectsCompanion.insert(
      id: portfolioId,
      name: 'FinCo Enterprise Portfolio',
      kind: const Value('portfolio'),
      description: const Value(
          'Group PMO view across the 2026 change portfolio: core banking, '
          'customer channels and the regulatory uplift.'),
      startDate: Value(isoDate(month0)),
    ));

    final programmes = <_Programme>[
      _Programme(
        id: 'seed-prog-cb',
        name: 'Core Banking Modernisation',
        reportedRag: 'amber',
        reportSummary:
            'Temenos migration tracking to the re-baselined plan. Wave 2 '
            'data reconciliation is the watch item; vendor capacity is '
            'the constraint.',
        projects: [
          _Project(
            id: 'seed-prj-cb-mig',
            name: 'Account Migration Waves',
            lead: 'Dana Whitfield',
            wps: [
              _WP('mig-w1', 'Wave 1 — pilot accounts', 'wp1', 'green'),
              _WP('mig-w2', 'Wave 2 — retail 1.2M', 'wp2', 'amber'),
              _WP('mig-rec', 'Reconciliation & cut-over', 'wp3', 'amber'),
            ],
            milestones: [
              _MS('mig-w1', 'Wave 1 cut-over complete', -40, 'complete'),
              _MS('mig-w2', 'Wave 2 dress rehearsal', 18, 'on_track', type: 'gate'),
              _MS('mig-w2', 'Wave 2 go-live', 46, 'not_started'),
              _MS('mig-rec', 'Legacy read-only', 120, 'not_started', type: 'hard_deadline'),
            ],
            risks: [
              _Risk('Reconciliation tooling cannot handle Wave 2 volumes in the '
                  'overnight window', 'likely', 'major', escalated: true),
              _Risk('Temenos SI rotates two senior engineers off in Q2',
                  'possible', 'major'),
              _Risk('Customer comms land after cut-over notice period',
                  'unlikely', 'moderate'),
            ],
            issues: [
              _Issue('Wave 1 defect backlog (14 open) delaying Wave 2 entry',
                  'high', escalated: true),
            ],
            dependency: _Dep('Data platform CDC feeds must be live before Wave 2',
                'Real-time Data Platform', 'inbound'),
            decisions: [
              _Dec('Approve Wave 2 scope split (retail then SME)', 'decided',
                  raisedDays: -30, decidedDays: -12),
              _Dec('Extend parallel-run from 2 to 4 weeks', 'pending',
                  dueDays: 10, impact: 'Delays Wave 2 go-live by a fortnight'),
              _Dec('Accept reconciliation tolerance of 0.01%', 'pending',
                  dueDays: 25),
            ],
            actions: [
              _Act('Load-test reconciliation tool at 2× Wave 2 volume',
                  'Marcus Webb', -5),
              _Act('Confirm SI staffing plan for Q2', 'Dana Whitfield', 12),
              _Act('Draft customer cut-over notice', 'Priya Sharma', 20),
            ],
            people: ['Dana Whitfield', 'Marcus Webb', 'Priya Sharma', 'Tom Adeyemi'],
            budgetPounds: 9800000,
            forecastFactorBp: 10300, // +3%: inside tolerance
          ),
          _Project(
            id: 'seed-prj-cb-data',
            name: 'Real-time Data Platform',
            lead: 'Sophie Chen',
            wps: [
              _WP('dp-cdc', 'Change-data-capture feeds', 'wp1', 'green'),
              _WP('dp-lake', 'Lakehouse & reporting', 'wp2', 'green'),
            ],
            milestones: [
              _MS('dp-cdc', 'CDC live for current accounts', -20, 'complete'),
              _MS('dp-cdc', 'CDC live for lending', 14, 'on_track'),
              _MS('dp-lake', 'Finance reporting on lakehouse', 75, 'not_started'),
            ],
            risks: [
              _Risk('Kafka cluster sizing underestimates lending event volume',
                  'possible', 'moderate'),
              _Risk('Lakehouse vendor pricing changes at renewal', 'unlikely', 'minor'),
            ],
            issues: const [],
            dependency: _Dep('Downstream of Account Migration for schema freeze',
                'Account Migration Waves', 'outbound'),
            decisions: [
              _Dec('Standardise on Iceberg table format', 'decided',
                  raisedDays: -50, decidedDays: -41),
              _Dec('Retire nightly batch extracts once CDC is live', 'pending',
                  dueDays: 40),
            ],
            actions: [
              _Act('Publish CDC schema catalogue', 'Sophie Chen', 7),
              _Act('Agree lending event volumes with Temenos', 'Marcus Webb', 15),
            ],
            people: ['Sophie Chen', 'Marcus Webb', 'Tom Adeyemi'],
            budgetPounds: 4200000,
            forecastFactorBp: 9900,
          ),
          _Project(
            id: 'seed-prj-cb-decom',
            name: 'Mainframe Decommission',
            lead: 'Tom Adeyemi',
            wps: [
              _WP('dc-inv', 'Application inventory & retirement', 'wp1', 'green'),
              _WP('dc-exit', 'Hosting contract exit', 'wp2', 'amber'),
            ],
            milestones: [
              _MS('dc-inv', 'Retirement list approved', -10, 'complete', type: 'gate'),
              _MS('dc-exit', 'Hosting exit notice served', 60, 'not_started'),
              _MS('dc-exit', 'Mainframe powered down', 330, 'not_started', type: 'hard_deadline'),
            ],
            risks: [
              _Risk('Two regulatory reports still only run on the mainframe',
                  'likely', 'moderate'),
            ],
            issues: const [],
            dependency: _Dep('Cannot exit hosting until Wave 2 migration completes',
                'Account Migration Waves', 'inbound'),
            decisions: [
              _Dec('Serve hosting exit notice in Q3 or Q4', 'pending', dueDays: 55),
            ],
            actions: [
              _Act('Re-platform remaining regulatory reports', 'Tom Adeyemi', 30),
            ],
            people: ['Tom Adeyemi', 'Marcus Webb'],
            budgetPounds: 1600000,
            forecastFactorBp: 10000,
          ),
        ],
      ),
      _Programme(
        id: 'seed-prog-ch',
        name: 'Customer Channels',
        reportedRag: 'green',
        reportSummary:
            'Mobile app adoption ahead of plan; open banking integrations '
            'progressing. No issues to raise to the Board this period.',
        projects: [
          _Project(
            id: 'seed-prj-ch-mobile',
            name: 'Mobile App 2.0',
            lead: 'Priya Sharma',
            wps: [
              _WP('mb-core', 'Core app rebuild', 'wp1', 'red'),
              _WP('mb-ob', 'Open banking integrations', 'wp2', 'amber'),
              _WP('mb-launch', 'Launch & adoption', 'wp3', 'amber'),
            ],
            milestones: [
              _MS('mb-core', 'Beta to 5k staff', -25, 'at_risk'),
              _MS('mb-core', 'App store submission', -3, 'at_risk', type: 'gate'),
              _MS('mb-ob', 'Three aggregators live', 35, 'not_started'),
              _MS('mb-launch', 'Public launch', 70, 'not_started', type: 'hard_deadline'),
            ],
            risks: [
              _Risk('Biometric login fails accessibility audit', 'likely', 'severe',
                  escalated: true),
              _Risk('Apple review rejects background payments flow', 'possible', 'major',
                  escalated: true),
              _Risk('Aggregator certification queue is 8 weeks', 'likely', 'moderate'),
              _Risk('Marketing launch date fixed before build date', 'almost certain',
                  'major'),
            ],
            issues: [
              _Issue('Beta crash rate 4.1% against 1% exit criterion', 'high',
                  escalated: true),
              _Issue('Two squads without a tech lead since March', 'medium'),
            ],
            dependency: _Dep('Needs identity platform tokens from Regulatory uplift',
                'Identity & Access Uplift', 'inbound'),
            decisions: [
              _Dec('Go / no-go on app store submission', 'pending', dueDays: -9,
                  impact: 'Every week of slip moves public launch; marketing spend committed'),
              _Dec('Descope background payments from launch', 'pending', dueDays: -2,
                  impact: 'Blocks the Apple review resubmission'),
              _Dec('Hire interim tech leads via agency', 'pending', dueDays: 5),
              _Dec('Adopt React Native over Flutter', 'decided',
                  raisedDays: -140, decidedDays: -75),
            ],
            actions: [
              _Act('Remediate accessibility findings (12)', 'Priya Sharma', -14),
              _Act('Fix top 5 crash signatures', 'Leo Marsh', -6),
              _Act('Resubmit to Apple review', 'Leo Marsh', 8),
              _Act('Brief marketing on launch risk', 'Priya Sharma', -1),
            ],
            people: ['Priya Sharma', 'Leo Marsh', 'Marcus Webb', 'Sophie Chen'],
            budgetPounds: 6400000,
            forecastFactorBp: 10900, // +9%: breaches the 5% tolerance
          ),
          _Project(
            id: 'seed-prj-ch-contact',
            name: 'Contact Centre Platform',
            lead: 'Leo Marsh',
            wps: [
              _WP('cc-tel', 'Telephony migration', 'wp1', 'amber'),
              _WP('cc-crm', 'Agent desktop & CRM', 'wp2', 'red'),
            ],
            milestones: [
              _MS('cc-tel', 'Pilot site live', -12, 'at_risk'),
              _MS('cc-crm', 'Agent desktop MVP', 28, 'not_started'),
              _MS('cc-tel', 'All sites migrated', 110, 'not_started'),
            ],
            risks: [
              _Risk('CRM vendor roadmap drops the on-prem connector', 'likely', 'major'),
              _Risk('Agent union consultation not yet started', 'possible', 'major'),
            ],
            issues: [
              _Issue('Pilot site call quality below SLA', 'high'),
            ],
            dependency: _Dep('Shares the identity platform with Mobile App 2.0',
                'Identity & Access Uplift', 'inbound'),
            decisions: [
              _Dec('Pause pilot until call quality fixed', 'pending', dueDays: -4),
              _Dec('Select CRM integration pattern', 'decided',
                  raisedDays: -60, decidedDays: -20),
            ],
            actions: [
              _Act('Root-cause pilot call quality', 'Leo Marsh', -3),
              _Act('Open union consultation', 'Priya Sharma', 14),
            ],
            people: ['Leo Marsh', 'Priya Sharma', 'Marcus Webb'],
            budgetPounds: 3100000,
            forecastFactorBp: 10400,
          ),
        ],
      ),
      _Programme(
        id: 'seed-prog-reg',
        name: 'Regulatory & Risk Uplift',
        reportedRag: 'green',
        reportSummary:
            'Consumer Duty evidence pack on schedule; identity platform '
            'delivered tokens to channels two weeks early. ISO 27001 '
            'surveillance audit passed.',
        projects: [
          _Project(
            id: 'seed-prj-reg-iam',
            name: 'Identity & Access Uplift',
            lead: 'Marcus Webb',
            wps: [
              _WP('iam-core', 'Identity platform', 'wp1', 'green'),
              _WP('iam-pam', 'Privileged access', 'wp2', 'green'),
            ],
            milestones: [
              _MS('iam-core', 'Tokens available to channels', -15, 'complete'),
              _MS('iam-pam', 'PAM live for production', 22, 'on_track'),
              _MS('iam-core', 'Legacy SSO switched off', 95, 'not_started'),
            ],
            risks: [
              _Risk('Legacy SSO dependants not fully inventoried', 'possible', 'moderate'),
            ],
            issues: const [],
            dependency: _Dep('Mobile App 2.0 and Contact Centre consume our tokens',
                'Customer Channels', 'outbound'),
            decisions: [
              _Dec('Enforce MFA for all privileged roles', 'decided',
                  raisedDays: -40, decidedDays: -33),
              _Dec('Set legacy SSO switch-off date', 'pending', dueDays: 30),
            ],
            actions: [
              _Act('Complete SSO dependant inventory', 'Marcus Webb', 9),
              _Act('PAM runbook sign-off', 'Aisha Rahman', 16),
            ],
            people: ['Marcus Webb', 'Aisha Rahman', 'Tom Adeyemi'],
            budgetPounds: 2700000,
            forecastFactorBp: 9800,
          ),
          _Project(
            id: 'seed-prj-reg-duty',
            name: 'Consumer Duty Evidence',
            lead: 'Aisha Rahman',
            wps: [
              _WP('cd-out', 'Outcome monitoring', 'wp1', 'green'),
              _WP('cd-pack', 'Board evidence pack', 'wp2', 'green'),
            ],
            milestones: [
              _MS('cd-out', 'Outcome metrics baselined', -30, 'complete'),
              _MS('cd-pack', 'H1 Board pack submitted', 12, 'on_track', type: 'gate'),
              _MS('cd-pack', 'Annual attestation', 150, 'not_started', type: 'hard_deadline'),
            ],
            risks: [
              _Risk('Vulnerable-customer flag data quality below threshold',
                  'possible', 'moderate'),
            ],
            issues: const [],
            dependency: _Dep('Outcome data sourced from the Real-time Data Platform',
                'Real-time Data Platform', 'inbound'),
            decisions: [
              _Dec('Adopt FCA outcome taxonomy as-is', 'decided',
                  raisedDays: -25, decidedDays: -22),
            ],
            actions: [
              _Act('Data quality fix for vulnerability flags', 'Sophie Chen', 11),
            ],
            people: ['Aisha Rahman', 'Sophie Chen'],
            budgetPounds: 900000,
            forecastFactorBp: 10000,
          ),
        ],
      ),
    ];

    final cascade = CascadeService(db, gateway: LocalCascadeGateway(db));

    for (final prog in programmes) {
      await db.projectDao.insertProject(ProjectsCompanion.insert(
        id: prog.id,
        name: prog.name,
        kind: const Value('programme'),
        startDate: Value(isoDate(month0)),
      ));
      await db.programmeGanttDao.upsertHeader(ProgrammeHeadersCompanion(
        id: Value('${prog.id}-header'),
        projectId: Value(prog.id),
        title: Value(prog.name),
        monthLabels: Value(monthLabelsJson),
        month0Date: Value(isoDate(month0)),
        updatedAt: Value(now),
      ));
      // The programme's OWN report: this is the self-reported RAG the
      // pulse puts beside the computed one.
      await db.reportsDao.upsertReport(StatusReportsCompanion(
        id: Value('${prog.id}-report'),
        projectId: Value(prog.id),
        title: Value('${prog.name} — Board status'),
        period: Value('Week of ${day(-6)}'),
        overallRag: Value(prog.reportedRag),
        summary: Value(prog.reportSummary),
        reportDate: Value(today.subtract(const Duration(days: 6))),
      ));

      for (final prj in prog.projects) {
        await _seedProject(db, prj, prog,
            month0: month0,
            monthLabelsJson: monthLabelsJson,
            monthOf: monthOf,
            day: day,
            today: today,
            now: now);
        // Link project → programme (same machine: activates at full detail).
        final code = await db.programmeLinksDao.generateCodeForEntity(
            ownerEntityId: prog.id, ownerKind: 'programme');
        await db.programmeLinksDao.redeemCode(
            code: code, ownerEntityId: prj.id, ownerKind: 'project');
      }
      // Link programme → portfolio.
      final code = await db.programmeLinksDao.generateCodeForEntity(
          ownerEntityId: portfolioId, ownerKind: 'portfolio');
      await db.programmeLinksDao.redeemCode(
          code: code, ownerEntityId: prog.id, ownerKind: 'programme');
    }

    // Cascade pass, tier by tier: projects push, programmes pull then push
    // their pulse, the portfolio pulls.
    for (final prog in programmes) {
      for (final prj in prog.projects) {
        await reconcileCascade(db: db, cascade: cascade, projectId: prj.id);
      }
    }
    for (final prog in programmes) {
      await reconcileCascade(db: db, cascade: cascade, projectId: prog.id);
    }
    await reconcileCascade(db: db, cascade: cascade, projectId: portfolioId);
    return true;
  }

  static Future<void> _seedProject(
    AppDatabase db,
    _Project p,
    _Programme prog, {
    required DateTime month0,
    required String monthLabelsJson,
    required int Function(DateTime) monthOf,
    required String Function(int) day,
    required DateTime today,
    required DateTime now,
  }) async {
    await db.projectDao.insertProject(ProjectsCompanion.insert(
      id: p.id,
      name: p.name,
      startDate: Value(isoDate(month0.add(Duration(days: 20 * p.id.length % 60)))),
      description: Value('${p.name} — part of ${prog.name}. Lead: ${p.lead}.'),
    ));
    await db.programmeGanttDao.upsertHeader(ProgrammeHeadersCompanion(
      id: Value('${p.id}-header'),
      projectId: Value(p.id),
      title: Value(p.name),
      monthLabels: Value(monthLabelsJson),
      month0Date: Value(isoDate(month0)),
      updatedAt: Value(now),
    ));

    // Work packages + a build activity each, then the dated milestones.
    var sort = 0;
    for (final wp in p.wps) {
      final wpId = '${p.id}-wp-${wp.key}';
      await db.programmeGanttDao.upsertWorkPackage(TimelineWorkPackagesCompanion(
        id: Value(wpId),
        projectId: Value(p.id),
        name: Value(wp.name),
        shortCode: Value(wp.key.toUpperCase()),
        colourTheme: Value(wp.colour),
        ragStatus: Value(wp.rag),
        sortOrder: Value(sort++),
        updatedAt: Value(now),
      ));
      final start = month0.add(Duration(days: 30 * (sort - 1) * 2));
      final end = start.add(const Duration(days: 150));
      await db.programmeGanttDao.upsertActivity(TimelineActivitiesCompanion(
        id: Value('$wpId-build'),
        workPackageId: Value(wpId),
        projectId: Value(p.id),
        name: Value('${wp.name} — delivery'),
        owner: Value(p.lead),
        activityType: const Value('activity'),
        startMonth: Value(monthOf(start).clamp(0, 23)),
        endMonth: Value(monthOf(end).clamp(0, 23)),
        startDate: Value(isoDate(start)),
        endDate: Value(isoDate(end)),
        status: Value(wp.rag == 'red' ? 'at_risk' : 'on_track'),
        isCritical: Value(wp.rag != 'green'),
        sortOrder: Value(sort),
        updatedAt: Value(now),
      ));
    }
    var m = 0;
    for (final ms in p.milestones) {
      final d = today.add(Duration(days: ms.dayOffset));
      await db.programmeGanttDao.upsertActivity(TimelineActivitiesCompanion(
        id: Value('${p.id}-ms-${++m}'),
        workPackageId: Value('${p.id}-wp-${ms.wpKey}'),
        projectId: Value(p.id),
        name: Value(ms.name),
        owner: Value(p.lead),
        activityType: Value(ms.type),
        startMonth: Value(monthOf(d).clamp(0, 23)),
        endMonth: Value(monthOf(d).clamp(0, 23)),
        startDate: Value(isoDate(d)),
        endDate: Value(isoDate(d)),
        status: Value(ms.status),
        isCritical: Value(ms.type != 'milestone'),
        sortOrder: Value(100 + m),
        // Completed milestones count towards throughput when recent.
        updatedAt: Value(ms.status == 'complete' ? d : now),
      ));
    }

    // RAID.
    var r = 0;
    for (final risk in p.risks) {
      r++;
      await db.raidDao.upsertRisk(RisksCompanion(
        id: Value('${p.id}-r$r'),
        projectId: Value(p.id),
        ref: Value('R$r'),
        title: Value(risk.title),
        description: Value(risk.title),
        likelihood: Value(risk.likelihood),
        impact: Value(risk.impact),
        status: const Value('open'),
        owner: Value(p.lead),
        mitigation: const Value('Mitigation plan agreed at the last review.'),
        nextReviewAt: Value(day(risk.escalated ? -3 : 11)),
        escalatedAt: Value(risk.escalated ? today.subtract(const Duration(days: 4)) : null),
        source: const Value('manual'),
      ));
    }
    var i = 0;
    for (final issue in p.issues) {
      i++;
      await db.raidDao.upsertIssue(IssuesCompanion(
        id: Value('${p.id}-i$i'),
        projectId: Value(p.id),
        ref: Value('I$i'),
        description: Value(issue.title),
        priority: Value(issue.priority),
        status: const Value('open'),
        owner: Value(p.lead),
        dueDate: Value(day(7)),
        escalatedAt: Value(issue.escalated ? today.subtract(const Duration(days: 2)) : null),
        source: const Value('manual'),
      ));
    }
    await db.raidDao.upsertDependency(ProgramDependenciesCompanion(
      id: Value('${p.id}-dep1'),
      projectId: Value(p.id),
      ref: const Value('D1'),
      description: Value(p.dependency.title),
      dependencyType: Value(p.dependency.type),
      counterparty: Value(p.dependency.counterparty),
      status: const Value('open'),
      owner: Value(p.lead),
      dueDate: Value(day(45)),
      source: const Value('manual'),
    ));

    // Decisions: open ones carry a need-by date; made ones carry raised →
    // decided dates so latency is real.
    var dn = 0;
    for (final d in p.decisions) {
      dn++;
      final raised = today.add(Duration(days: d.raisedDays));
      final decided = d.decidedDays == null ? null : today.add(Duration(days: d.decidedDays!));
      await db.decisionsDao.upsertDecision(DecisionsCompanion(
        id: Value('${p.id}-d$dn'),
        projectId: Value(p.id),
        ref: Value('DC$dn'),
        description: Value(d.title),
        status: Value(d.status),
        decisionMaker: Value(d.status == 'pending' ? 'Programme Board' : p.lead),
        dueDate: Value(d.dueDays == null ? null : day(d.dueDays!)),
        decidedAt: Value(decided == null ? null : isoDate(decided)),
        impactStatement: Value(d.impact),
        escalatedAt: Value((d.dueDays ?? 1) < 0 ? today.subtract(const Duration(days: 1)) : null),
        source: const Value('manual'),
        createdAt: Value(raised),
        updatedAt: Value(decided ?? raised),
      ));
    }

    var an = 0;
    for (final a in p.actions) {
      an++;
      await db.actionsDao.upsertAction(ProjectActionsCompanion(
        id: Value('${p.id}-a$an'),
        projectId: Value(p.id),
        ref: Value('A$an'),
        description: Value(a.title),
        owner: Value(a.owner),
        dueDate: Value(day(a.dueDays)),
        status: const Value('open'),
        priority: Value(a.dueDays < 0 ? 'high' : 'medium'),
        source: const Value('manual'),
      ));
    }

    // The project's own status report (cascades to the programme).
    await db.reportsDao.upsertReport(StatusReportsCompanion(
      id: Value('${p.id}-report'),
      projectId: Value(p.id),
      title: Value('${p.name} — weekly status'),
      period: Value('Week of ${day(-4)}'),
      overallRag: Value(p.wps.any((w) => w.rag == 'red')
          ? 'red'
          : p.wps.any((w) => w.rag == 'amber')
              ? 'amber'
              : 'green'),
      summary: Value('${p.name}: ${p.wps.length} workstreams, '
          '${p.risks.length} open risks, ${p.decisions.where((d) => d.status == 'pending').length} decisions pending.'),
      reportDate: Value(today.subtract(const Duration(days: 4))),
    ));

    // People + team roles. Names repeat across projects on purpose: the
    // portfolio's load metric groups cascaded copies by name.
    var pn = 0;
    for (final name in p.people) {
      pn++;
      final pid = '${p.id}-p$pn';
      await db.peopleDao.upsertPerson(PersonsCompanion(
        id: Value(pid),
        projectId: Value(p.id),
        name: Value(name),
        role: Value(pn == 1 ? 'Project lead' : _roleFor(name)),
        organisation: const Value('FinCo Ltd'),
        personType: const Value('colleague'),
        isStakeholder: const Value(false),
      ));
      await db.teamRoleDao.upsert(TeamRolesCompanion(
        id: Value('${p.id}-tr$pn'),
        projectId: Value(p.id),
        roleName: Value(pn == 1 ? 'Project Manager' : _roleFor(name)),
        teamGroup: Value(pn == 1 ? 'programme_leadership' : 'delivery'),
        personId: Value(pid),
        isScaffold: const Value(false),
        isApplicable: const Value(true),
        sortOrder: Value(pn),
      ));
    }

    // Finance: approved budget, one SUBMITTED forecast, two months of
    // actuals. Forecast = budget × factor so variance is deliberate.
    const actor = 'Seed';
    await db.financeDao.seedDefaultCategories(p.id, changedBy: actor);
    final cats = await db.financeDao.getCategories(p.id);
    final catId = {for (final c in cats) c.name: c.id};
    final fyA = 'FY${(today.year % 100)}';
    final fyB = 'FY${(today.year % 100) + 1}';
    // Split the budget 60/40 across the two FYs and across four categories.
    final split = <(String, double)>[
      ('People', 0.45),
      ('Vendor', 0.30),
      ('Technology', 0.20),
      ('Other', 0.05),
    ];
    final budgetId = await db.financeDao.createBudget(
      projectId: p.id,
      name: '${p.name} — approved budget',
      currency: 'GBP',
      fundingSource: '${prog.name} envelope',
      changedBy: actor,
    );
    var ln = 0;
    for (final (cat, share) in split) {
      if (!catId.containsKey(cat)) continue;
      for (final (fy, fyShare) in [(fyA, 0.6), (fyB, 0.4)]) {
        ln++;
        await db.financeDao.upsertLine(
          id: '${p.id}-bl$ln',
          projectId: p.id,
          budgetId: budgetId,
          costCategoryId: catId[cat]!,
          financialYear: fy,
          amountMinor: (p.budgetPounds * share * fyShare).round() * 100,
          changedBy: actor,
        );
      }
    }
    await db.financeDao.approveBudget(budgetId,
        approvedBy: 'Richard Okafor', changedBy: actor);

    final period = '${today.year}-${today.month.toString().padLeft(2, '0')}';
    final snapId = await db.financeDao.createSnapshot(
        projectId: p.id, period: period, changedBy: actor);
    ln = 0;
    for (final (cat, share) in split) {
      if (!catId.containsKey(cat)) continue;
      for (final (fy, fyShare) in [(fyA, 0.6), (fyB, 0.4)]) {
        ln++;
        await db.financeDao.upsertForecastLine(
          id: '${p.id}-fl$ln',
          projectId: p.id,
          snapshotId: snapId,
          costCategoryId: catId[cat]!,
          financialYear: fy,
          amountMinor:
              (p.budgetPounds * share * fyShare * p.forecastFactorBp / 10000).round() * 100,
          changedBy: actor,
        );
      }
    }
    await db.financeDao.submitSnapshot(snapId, changedBy: actor);

    for (var back = 1; back <= 2; back++) {
      final d = DateTime(today.year, today.month - back, 1);
      final per = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      var k = 0;
      for (final (cat, share) in split) {
        if (!catId.containsKey(cat)) continue;
        k++;
        await db.financeDao.upsertActualLine(
          id: '${p.id}-al$back-$k',
          projectId: p.id,
          period: per,
          costCategoryId: catId[cat]!,
          amountMinor: (p.budgetPounds * share / 24).round() * 100,
          changedBy: actor,
        );
      }
    }
  }

  static String _roleFor(String name) => switch (name) {
        'Marcus Webb' => 'Security architect',
        'Priya Sharma' => 'Change lead',
        'Sophie Chen' => 'Data engineering lead',
        'Tom Adeyemi' => 'Infrastructure lead',
        'Leo Marsh' => 'Engineering manager',
        'Aisha Rahman' => 'Compliance lead',
        _ => 'Delivery lead',
      };

  static const _mon = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

class _Programme {
  final String id;
  final String name;
  final String reportedRag;
  final String reportSummary;
  final List<_Project> projects;
  const _Programme({
    required this.id,
    required this.name,
    required this.reportedRag,
    required this.reportSummary,
    required this.projects,
  });
}

class _Project {
  final String id;
  final String name;
  final String lead;
  final List<_WP> wps;
  final List<_MS> milestones;
  final List<_Risk> risks;
  final List<_Issue> issues;
  final _Dep dependency;
  final List<_Dec> decisions;
  final List<_Act> actions;
  final List<String> people;
  final int budgetPounds;
  /// Forecast as basis points of budget (10000 = on budget).
  final int forecastFactorBp;
  const _Project({
    required this.id,
    required this.name,
    required this.lead,
    required this.wps,
    required this.milestones,
    required this.risks,
    required this.issues,
    required this.dependency,
    required this.decisions,
    required this.actions,
    required this.people,
    required this.budgetPounds,
    required this.forecastFactorBp,
  });
}

class _WP {
  final String key, name, colour, rag;
  const _WP(this.key, this.name, this.colour, this.rag);
}

class _MS {
  final String wpKey, name, status, type;
  final int dayOffset;
  const _MS(this.wpKey, this.name, this.dayOffset, this.status,
      {this.type = 'milestone'});
}

class _Risk {
  final String title, likelihood, impact;
  final bool escalated;
  const _Risk(this.title, this.likelihood, this.impact, {this.escalated = false});
}

class _Issue {
  final String title, priority;
  final bool escalated;
  const _Issue(this.title, this.priority, {this.escalated = false});
}

class _Dep {
  final String title, counterparty, type;
  const _Dep(this.title, this.counterparty, this.type);
}

class _Dec {
  final String title, status;
  final int raisedDays;
  final int? decidedDays;
  final int? dueDays;
  final String? impact;
  const _Dec(this.title, this.status,
      {this.raisedDays = -20, this.decidedDays, this.dueDays, this.impact});
}

class _Act {
  final String title, owner;
  final int dueDays;
  const _Act(this.title, this.owner, this.dueDays);
}
