import 'package:drift/drift.dart' show Value;

import '../database/database.dart';

/// Inserts a fully-populated demo project on first launch.
/// Safe to call repeatedly — checks for existing projects first.
class SeedService {

  static Future<void> maybeSeed(AppDatabase db) async {
    final existing = await db.projectDao.getAllProjects();
    if (existing.isNotEmpty) return;

    await seedDemoProject(db);
  }

  /// Always creates the Horizon Programme demo project, regardless of whether
  /// other projects already exist.
  static Future<void> seedDemoProject(AppDatabase db) async {
    // -------------------------------------------------------------------------
    // Project
    // -------------------------------------------------------------------------
    const projectId = 'seed-horizon-001';
    await db.projectDao.insertProject(
      ProjectsCompanion.insert(
        id: projectId,
        name: 'Horizon Programme',
        description: const Value(
            'Enterprise-wide digital transformation at FinCo Ltd. '
            'Modernising core banking infrastructure, replacing legacy batch '
            'processing with real-time data pipelines, and delivering a new '
            'customer-facing mobile platform.'),
        startDate: const Value('2025-01-06'),
      ),
    );

    // -------------------------------------------------------------------------
    // Programme overview
    // -------------------------------------------------------------------------
    await db.programmeDao.upsertOverview(
      ProgrammeOverviewsCompanion(
        id: const Value('seed-overview-001'),
        projectId: const Value(projectId),
        vision: const Value(
            'A fully cloud-native, real-time banking platform that enables '
            'FinCo to launch new products in days, not quarters.'),
        objectives: const Value(
            '1. Decommission legacy mainframe by Q4 2026\n'
            '2. Migrate 4M customer accounts to new core banking system\n'
            '3. Launch mobile app to 500k active users by Q3 2025\n'
            '4. Reduce batch processing windows from 6 hours to under 5 minutes\n'
            '5. Achieve ISO 27001 certification for the new platform'),
        scope: const Value(
            'Core banking replacement, mobile channel, data platform, '
            'API gateway, identity & access management, and operational '
            'tooling. Covers Retail Banking and SME divisions.'),
        outOfScope: const Value(
            'Investment banking systems, FX trading platform, '
            'international subsidiaries (covered by separate programmes).'),
        keyMilestones: const Value(
            'M1 – Jan 2025: Programme kick-off & governance established\n'
            'M2 – Mar 2025: Architecture design authority approved\n'
            'M3 – Jun 2025: Core banking pilot (10k accounts) go-live\n'
            'M4 – Sep 2025: Mobile app public launch\n'
            'M5 – Dec 2025: 1M accounts migrated\n'
            'M6 – Q4 2026: Full mainframe decommission'),
        budget: const Value('£42M over 24 months'),
        sponsor: const Value('Helena Cross (CTO, FinCo Ltd)'),
        programmeManager: const Value('You'),
      ),
    );

    // -------------------------------------------------------------------------
    // Charter
    // -------------------------------------------------------------------------
    await db.projectCharterDao.upsert(
      ProjectChartersCompanion(
        id:        const Value('seed-charter-001'),
        projectId: Value(projectId),
        vision: const Value(
            'A fully cloud-native, real-time banking platform that enables '
            'FinCo to launch new products in days, not quarters, while '
            'meeting the highest standards of resilience and regulatory '
            'compliance.'),
        objectives: const Value(
            '• Decommission the legacy IBM zOS mainframe by Q4 2026\n'
            '• Migrate 4M customer accounts to Temenos T24 with zero '
            'unplanned outage\n'
            '• Launch a mobile app reaching 500k MAU within 12 months '
            'of public release\n'
            '• Reduce end-of-day batch processing from 6 hours to under '
            '5 minutes by enabling real-time event streaming\n'
            '• Achieve ISO 27001 certification and complete SOC 2 Type II '
            'audit on the new platform'),
        scopeIn: const Value(
            'Core banking replacement, mobile and digital channels, real-time '
            'data platform, API gateway, identity & access management, '
            'observability tooling, and the operating-model changes needed '
            'to run them. Covers Retail Banking and SME divisions across '
            'all UK branches and digital channels.'),
        scopeOut: const Value(
            'Investment Banking, FX trading platform, and the international '
            'subsidiaries are out of scope — they will be addressed by '
            'separate programmes already chartered for 2027. Branch network '
            'real-estate decisions are also out of scope.'),
        deliveryApproach: const Value(
            'Hybrid delivery: discovery and design phases run waterfall '
            'with stage gates at the Architecture Design Authority. Build, '
            'test and deploy run as quarterly increments using a scaled '
            'agile cadence (5 squads across the workstreams). Migrations '
            'are sequenced — pilot (10k accounts), Phase 2 (1M), then full '
            '(4M) — with go/no-go gates at each cutover.'),
        successCriteria: const Value(
            '• Mainframe fully decommissioned (zero workloads remain) by '
            'end of M21\n'
            '• 100% of customer accounts running on Temenos T24 with '
            'reconciliation evidence\n'
            '• Mobile app at 500k MAU and 4.5+ App Store rating\n'
            '• ISO 27001 certified, SOC 2 Type II clean opinion\n'
            '• Batch window <5 minutes sustained over 30 consecutive days\n'
            '• Programme delivered within £42M envelope (±10%)'),
        keyConstraints: const Value(
            '• Hard regulatory deadline: PRA submission of decommission '
            'plan by end of FY26\n'
            '• Capacity: only 3 of 6 contracted Temenos developers '
            'currently available — vendor escalation in flight\n'
            '• Budget: £42M cap; quarterly re-forecast required by CFO\n'
            '• Branch staff cannot be taken off the floor for more than '
            '2 days during peak periods (Apr/Dec)'),
        assumptions: const Value(
            '• Temenos resourcing recovers to contracted levels by end '
            'of Q1 2025\n'
            '• AWS Frankfurt region remains the primary hosting location\n'
            '• Branch training plan is approved at the next Steerco\n'
            '• No major regulatory rule changes during the migration '
            'window\n'
            '• Existing data residency policy holds for EU customer '
            'records (subject to Legal review — DC2 dependency)'),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // -------------------------------------------------------------------------
    // Workstreams
    // -------------------------------------------------------------------------
    final workstreams = [
      ('seed-ws-001', 'Core Banking Replacement', 'Amara Osei', 'amber',
          'On track for pilot. Vendor (Temenos) resource constraints causing minor delays.'),
      ('seed-ws-002', 'Data Platform & Analytics', 'Raj Patel', 'green',
          'Kafka cluster live in dev. Flink jobs in progress.'),
      ('seed-ws-003', 'Mobile & Digital Channels', 'Sophie Chen', 'green',
          'iOS and Android builds passing CI. UX sign-off scheduled for next sprint.'),
      ('seed-ws-004', 'Security & Compliance', 'Marcus Webb', 'amber',
          'ISO 27001 gap analysis in progress. Pen test booked for April.'),
      ('seed-ws-005', 'Change Management & Training', 'Priya Sharma', 'red',
          'Branch training plan not yet approved. Sponsor escalation raised.'),
    ];

    for (int i = 0; i < workstreams.length; i++) {
      final (id, name, lead, status, notes) = workstreams[i];
      await db.programmeDao.insertWorkstream(
        WorkstreamsCompanion.insert(
          id: id,
          projectId: projectId,
          name: name,
          lead: Value(lead),
          status: Value(status),
          notes: Value(notes),
          sortOrder: Value(i),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Governance cadences
    // -------------------------------------------------------------------------
    final cadences = [
      ('seed-gov-001', 'Programme Board', 'Monthly', 'Helena Cross (CTO)',
          'Observer', 'Formal governance. RAG report required 48hrs prior.'),
      ('seed-gov-002', 'Architecture Design Authority', 'Bi-weekly',
          'James Farrow (Chief Architect)', 'Presenting',
          'All design decisions above complexity threshold require ADA sign-off.'),
      ('seed-gov-003', 'Delivery Stand-up', 'Daily', 'You', 'Chair',
          '15 minutes. Focus on blockers. Jira board reviewed.'),
      ('seed-gov-004', 'Steering Committee', 'Quarterly', 'CFO & CTO',
          'Presenting', 'Budget and strategic direction. Board pack required.'),
    ];

    for (final (id, name, freq, chair, role, notes) in cadences) {
      await db.programmeDao.insertGovernance(
        GovernanceCadencesCompanion.insert(
          id: id,
          projectId: projectId,
          meetingName: name,
          frequency: Value(freq),
          chair: Value(chair),
          myRole: Value(role),
          notes: Value(notes),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // RAID — Risks
    // -------------------------------------------------------------------------
    final risks = [
      (
        'seed-r-001', 'R1',
        'Temenos delivery team under-resourced — only 3 of 6 contracted '
            'developers currently onboarded. Pilot milestone at risk.',
        'high', 'high', 'open',
        'Escalated to Temenos account manager. Requesting replacement resource '
            'by 14 March. Contingency: extend pilot by 4 weeks.',
        'Amara Osei',
      ),
      (
        'seed-r-002', 'R2',
        'Data migration tooling (Attunity) has not been validated against '
            'FinCo\'s mainframe EBCDIC encoding. Silent data corruption possible.',
        'medium', 'high', 'open',
        'Data quality team running encoding validation sprint. '
            'Results expected 21 March.',
        'Raj Patel',
      ),
      (
        'seed-r-003', 'R3',
        'Key person dependency: Raj Patel is sole architect for the data '
            'platform. No documented backup.',
        'medium', 'high', 'open',
        'Succession plan in progress. Junior architect shadowing from next sprint.',
        null,
      ),
      (
        'seed-r-004', 'R4',
        'Regulatory approval from PRA for new core banking system may take '
            'longer than the 8 weeks budgeted.',
        'low', 'high', 'open',
        'Pre-submission meeting with PRA scheduled for 28 March. '
            'Legal counsel reviewing submission pack.',
        'Marcus Webb',
      ),
      (
        'seed-r-005', 'R5',
        'Branch staff resistance to new system — early pulse survey shows '
            '34% of branch managers "not confident" with the migration plan.',
        'high', 'medium', 'open',
        'Training programme fast-tracked. Executive road-show planned for April.',
        'Priya Sharma',
      ),
    ];

    for (final (id, ref, desc, likelihood, impact, status, mitigation, owner)
        in risks) {
      await db.raidDao.upsertRisk(
        RisksCompanion(
          id: Value(id),
          projectId: Value(projectId),
          ref: Value(ref),
          description: Value(desc),
          likelihood: Value(likelihood),
          impact: Value(impact),
          status: Value(status),
          mitigation: Value(mitigation),
          owner: Value(owner),
          source: const Value('manual'),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // RAID — Assumptions
    // -------------------------------------------------------------------------
    final assumptions = [
      (
        'seed-a-001', 'A1',
        'Temenos T24 licence covers unlimited user seats for Retail Banking '
            'during the migration period.',
        'open', 'Legal', null,
      ),
      (
        'seed-a-002', 'A2',
        'The PRA will not require a parallel-run period longer than 3 months '
            'for the core banking switchover.',
        'open', 'Compliance', null,
      ),
      (
        'seed-a-003', 'A3',
        'FinCo\'s existing AWS Enterprise Agreement covers compute costs '
            'for the new data platform without additional procurement.',
        'validated', 'Raj Patel', '2025-02-14',
      ),
    ];

    for (final (id, ref, desc, status, validatedBy, validatedDate)
        in assumptions) {
      await db.raidDao.upsertAssumption(
        AssumptionsCompanion(
          id: Value(id),
          projectId: Value(projectId),
          ref: Value(ref),
          description: Value(desc),
          status: Value(status),
          validatedBy: Value(validatedBy),
          validatedAt: validatedDate != null
              ? Value(DateTime.parse(validatedDate))
              : const Value(null),
          source: const Value('manual'),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // RAID — Issues
    // -------------------------------------------------------------------------
    final issues = [
      (
        'seed-i-001', 'I1',
        'Vendor test environment has been unavailable for 6 business days. '
            'Core banking integration testing blocked.',
        'high', 'open', 'Amara Osei', '2025-03-21',
        'Temenos have acknowledged the outage. SLA breach logged. '
            'Compensating: running unit tests against mock only.',
      ),
      (
        'seed-i-002', 'I2',
        'Branch training budget overspent by £180k due to additional '
            'travel costs not included in original estimate.',
        'medium', 'in progress', 'Priya Sharma', null,
        'Finance reviewing. Request for budget reforecast submitted to Steering Committee.',
      ),
    ];

    for (final (id, ref, desc, priority, status, owner, due, resolution)
        in issues) {
      await db.raidDao.upsertIssue(
        IssuesCompanion(
          id: Value(id),
          projectId: Value(projectId),
          ref: Value(ref),
          description: Value(desc),
          priority: Value(priority),
          status: Value(status),
          owner: Value(owner),
          dueDate: Value(due),
          resolution: Value(resolution),
          source: const Value('manual'),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // RAID — Dependencies
    // -------------------------------------------------------------------------
    final dependencies = [
      (
        'seed-d-001', 'D1',
        'SWIFT integration certification — required before core banking '
            'can process live payments. Owned by SWIFT, not FinCo.',
        'inbound', 'SWIFT team', 'open', '2025-05-30',
      ),
      (
        'seed-d-002', 'D2',
        'Identity platform (Azure AD B2C) must complete DR failover '
            'configuration before mobile app goes to production.',
        'inbound', 'Marcus Webb', 'open', '2025-07-01',
      ),
      (
        'seed-d-003', 'D3',
        'Data platform must provide customer 360 API before mobile '
            'personalisation features can be built.',
        'outbound', 'Raj Patel', 'in progress', '2025-04-15',
      ),
    ];

    for (final (id, ref, desc, type, owner, status, due) in dependencies) {
      await db.raidDao.upsertDependency(
        ProgramDependenciesCompanion(
          id: Value(id),
          projectId: Value(projectId),
          ref: Value(ref),
          description: Value(desc),
          dependencyType: Value(type),
          owner: Value(owner),
          status: Value(status),
          dueDate: Value(due),
          source: const Value('manual'),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Decisions
    // -------------------------------------------------------------------------
    final decisions = [
      (
        'seed-dc-001', 'DC1',
        'Core banking vendor selection: Temenos T24 vs Thought Machine Vault',
        'decided', 'Helena Cross', '2024-12-01',
        'Temenos selected based on existing relationship, lower integration risk, '
            'and 18-month faster delivery estimate. Vault scored higher on '
            'technical modernity but the replatforming risk was unacceptable.',
        'Proceed with Temenos T24. Contract signed Jan 2025.',
      ),
      (
        'seed-dc-002', 'DC2',
        'Cloud provider for data platform: AWS vs Azure',
        'decided', 'Raj Patel', '2025-01-20',
        'AWS selected due to existing Enterprise Agreement and data '
            'engineering team expertise. Azure evaluated but switching cost too high.',
        'AWS. Confirmed by ADA on 20 Jan 2025.',
      ),
      (
        'seed-dc-003', 'DC3',
        'Whether to run core banking and mainframe in parallel for 3 or 6 months',
        'pending', 'Helena Cross', '2025-04-30',
        'PRA guidance expected by end of March. Risk of 3-month window is '
            'customer impact if issues emerge post-cutover.',
        null,
      ),
      (
        'seed-dc-004', 'DC4',
        'Mobile app: native iOS/Android vs React Native cross-platform',
        'decided', 'Sophie Chen', '2025-02-05',
        'React Native selected for cost and speed. Performance benchmarks '
            'showed <5% degradation vs native, acceptable for v1 scope.',
        'React Native. ADA approved 5 Feb 2025.',
      ),
    ];

    for (final (id, ref, desc, status, maker, due, rationale, outcome)
        in decisions) {
      await db.decisionsDao.upsertDecision(
        DecisionsCompanion(
          id: Value(id),
          projectId: Value(projectId),
          ref: Value(ref),
          description: Value(desc),
          status: Value(status),
          decisionMaker: Value(maker),
          dueDate: Value(due),
          rationale: Value(rationale),
          outcome: Value(outcome),
          source: const Value('manual'),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // People
    // -------------------------------------------------------------------------
    // Each tuple: (id, name, role, org, email, phone, teams, category, isStakeholder).
    // Category is one of: colleague | exec | vendor. isStakeholder is orthogonal.
    final persons = [
      (
        'seed-p-001', 'Helena Cross', 'CTO', 'FinCo Ltd',
        'helena.cross@finco.com', '+44 7700 900123', '@helena.cross',
        'exec', true,
      ),
      (
        'seed-p-002', 'Richard Okafor', 'CFO', 'FinCo Ltd',
        'r.okafor@finco.com', '+44 7700 900456', '@richard.okafor',
        'exec', true,
      ),
      (
        'seed-p-003', 'Amara Osei', 'Core Banking Lead', 'FinCo Ltd',
        'a.osei@finco.com', null, '@amara.osei',
        'colleague', false,
      ),
      (
        'seed-p-004', 'Raj Patel', 'Data Platform Architect', 'FinCo Ltd',
        'raj.patel@finco.com', null, '@raj.patel',
        'colleague', false,
      ),
      (
        'seed-p-005', 'Sophie Chen', 'Mobile Engineering Lead', 'FinCo Ltd',
        's.chen@finco.com', null, '@sophie.chen',
        'colleague', false,
      ),
      (
        'seed-p-006', 'Marcus Webb', 'Head of Security', 'FinCo Ltd',
        'm.webb@finco.com', '+44 7700 900789', '@marcus.webb',
        'colleague', false,
      ),
      (
        'seed-p-007', 'Priya Sharma', 'Change Manager', 'FinCo Ltd',
        'p.sharma@finco.com', null, '@priya.sharma',
        'colleague', false,
      ),
      (
        'seed-p-008', 'James Farrow', 'Chief Architect', 'FinCo Ltd',
        'j.farrow@finco.com', null, '@james.farrow',
        'colleague', true,
      ),
      // Executives
      (
        'seed-p-009', 'Diana Holt', 'CEO', 'FinCo Ltd',
        'diana.holt@finco.com', null, '@diana.holt',
        'exec', true,
      ),
      (
        'seed-p-010', 'Olivia Pierce', 'COO', 'FinCo Ltd',
        'o.pierce@finco.com', null, '@olivia.pierce',
        'exec', false,
      ),
      (
        'seed-p-011', 'Kwame Mensah', 'Chair, Audit Committee',
        'FinCo Ltd Board', 'k.mensah@finco-board.com', null, null,
        'exec', true,
      ),
      // Vendors
      (
        'seed-p-012', 'Stefan Blau', 'Engagement Director', 'Temenos',
        'stefan.blau@temenos.com', '+41 22 555 0140', null,
        'vendor', true,
      ),
      (
        'seed-p-013', 'Elena Vasquez', 'Senior Solutions Architect',
        'AWS', 'evasquez@amazon.com', null, null,
        'vendor', false,
      ),
      (
        'seed-p-014', 'Hugo Reinhardt', 'Audit Partner', 'BDO LLP',
        'h.reinhardt@bdo.co.uk', null, null,
        'vendor', false,
      ),
      (
        'seed-p-015', 'Naomi Kim', 'Senior Manager', 'Accenture',
        'naomi.kim@accenture.com', null, null,
        'vendor', false,
      ),
    ];

    for (final (id, name, role, org, email, phone, teams, type, stakeholder)
        in persons) {
      await db.peopleDao.upsertPerson(
        PersonsCompanion(
          id: Value(id),
          projectId: Value(projectId),
          name: Value(name),
          role: Value(role),
          organisation: Value(org),
          email: Value(email),
          phone: Value(phone),
          teamsHandle: Value(teams),
          personType: Value(type),
          isStakeholder: Value(stakeholder),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    // Stakeholder profiles
    await db.peopleDao.upsertStakeholder(
      StakeholderProfilesCompanion(
        id: const Value('seed-sp-001'),
        projectId: const Value(projectId),
        personId: const Value('seed-p-001'),
        influence: const Value('high'),
        stance: const Value('sponsor'),
        engagementStrategy: const Value(
            'Monthly 1:1 ahead of Programme Board. Helena is highly engaged '
            'but time-constrained. Keep updates crisp — one-pager max. '
            'She responds well to visual dashboards.'),
        notes: const Value(
            'Promoted to CTO 18 months ago. Under board pressure to show '
            'digital credentials. The Horizon Programme is her flagship bet.'),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await db.peopleDao.upsertStakeholder(
      StakeholderProfilesCompanion(
        id: const Value('seed-sp-002'),
        projectId: const Value(projectId),
        personId: const Value('seed-p-002'),
        influence: const Value('high'),
        stance: const Value('neutral'),
        engagementStrategy: const Value(
            'Focus on ROI and cost trajectory. Richard approved the business '
            'case but will pull funding if quarterly burn rate exceeds forecast. '
            'Always lead with financials.'),
        notes: const Value(
            'Not a technology person. Sceptical of large IT programmes '
            'after a failed CRM project in 2022. Needs to see tangible '
            'milestones to maintain confidence.'),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await db.peopleDao.upsertStakeholder(
      StakeholderProfilesCompanion(
        id: const Value('seed-sp-003'),
        projectId: const Value(projectId),
        personId: const Value('seed-p-008'),
        influence: const Value('medium'),
        stance: const Value('supporter'),
        engagementStrategy: const Value(
            'Bring James into design decisions early — he dislikes being '
            'presented with faits accomplis. He is a good ally at ADA.'),
        notes: const Value(
            'Strong opinions on event-driven architecture. Has been '
            'pushing for Kafka since 2023.'),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // Colleague profiles
    await db.peopleDao.upsertColleague(
      ColleagueProfilesCompanion(
        id: const Value('seed-cp-001'),
        projectId: const Value(projectId),
        personId: const Value('seed-p-003'),
        team: const Value('Core Banking'),
        directReport: const Value(false),
        workingStyle: const Value(
            'Very detail-oriented. Prefers written briefs over verbal. '
            'Will escalate quickly if she feels under-resourced.'),
        notes: const Value(
            'Key person risk. Currently doing the work of 1.5 people. '
            'Watch for burnout signals.'),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await db.peopleDao.upsertColleague(
      ColleagueProfilesCompanion(
        id: const Value('seed-cp-002'),
        projectId: const Value(projectId),
        personId: const Value('seed-p-004'),
        team: const Value('Data Platform'),
        directReport: const Value(false),
        workingStyle: const Value(
            'Works best with clear problem statements and autonomy. '
            'Dislikes micromanagement. Very reliable once committed.'),
        notes: const Value('Single point of failure for data architecture. '
            'Succession planning urgent.'),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // -------------------------------------------------------------------------
    // Actions
    // -------------------------------------------------------------------------
    final today = DateTime.now();
    final actions = [
      (
        'seed-ac-001', 'AC1',
        'Escalate Temenos resourcing to account director — request written '
            'commitment to 6 FTE by 14 March',
        'Amara Osei', _dateOffset(today, -2), 'open', 'high',
      ),
      (
        'seed-ac-002', 'AC2',
        'Commission data encoding validation sprint for EBCDIC → UTF-8 migration',
        'Raj Patel', _dateOffset(today, 5), 'open', 'high',
      ),
      (
        'seed-ac-003', 'AC3',
        'Book pre-submission meeting with PRA for core banking approval',
        'Marcus Webb', _dateOffset(today, 10), 'open', 'medium',
      ),
      (
        'seed-ac-004', 'AC4',
        'Prepare Steering Committee budget reforecast pack for branch training overspend',
        'Priya Sharma', _dateOffset(today, 3), 'open', 'high',
      ),
      (
        'seed-ac-005', 'AC5',
        'Document Raj Patel succession plan and assign shadow architect',
        null, _dateOffset(today, 14), 'open', 'medium',
      ),
      (
        'seed-ac-006', 'AC6',
        'Complete ADA sign-off for API gateway architecture',
        'James Farrow', _dateOffset(today, -5), 'closed', 'medium',
      ),
      (
        'seed-ac-007', 'AC7',
        'Circulate mobile app UX prototype to Helena for executive sign-off',
        'Sophie Chen', _dateOffset(today, 7), 'open', 'low',
      ),
    ];

    for (int i = 0; i < actions.length; i++) {
      final (id, ref, desc, owner, due, status, priority) = actions[i];
      await db.actionsDao.upsertAction(
        ProjectActionsCompanion(
          id: Value(id),
          projectId: Value(projectId),
          ref: Value(ref),
          description: Value(desc),
          owner: Value(owner),
          dueDate: Value(due),
          status: Value(status),
          priority: Value(priority),
          source: const Value('manual'),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Context entries
    // -------------------------------------------------------------------------
    final contextEntries = [
      (
        'seed-ctx-001',
        'Change Advisory Board process',
        'observation',
        'CAB meets every Thursday at 14:00. All production changes require '
            'CAB approval minimum 5 business days prior. Emergency changes '
            'need CISO sign-off within 2 hours. Helena has final veto. '
            'The CAB secretary is Janet Liu — keep her informed to avoid surprises.',
        'process',
      ),
      (
        'seed-ctx-002',
        'How decisions really get made at FinCo',
        'insight',
        'Formal governance (Programme Board, ADA) ratifies decisions, but '
            'the real conversations happen in Helena\'s weekly "coffee round" '
            'on Monday mornings — informal 30-min with her direct reports. '
            'If you need Helena to support something at the Board, get it '
            'into the Monday conversation first.',
        'relationship',
      ),
      (
        'seed-ctx-003',
        'Richard Okafor\'s red lines on the programme',
        'note',
        'Following a 1:1 in February, Richard was explicit: he will not '
            'tolerate a budget overrun above 15% without a formal re-baseline. '
            'He also wants a monthly one-page financial dashboard separate '
            'from the main programme report. Currently we are at 8% variance.',
        'rule',
      ),
      (
        'seed-ctx-004',
        'Temenos vendor relationship history',
        'observation',
        'FinCo has been a Temenos customer since 2009. The relationship is '
            'strong at executive level but the delivery team has turned over '
            'significantly. The current project manager (Dan Holt) is new '
            'and still learning the account. Previous PM (Yuki Tanaka) was '
            'excellent — departed to Accenture in Dec 2024.',
        'structure',
      ),
      (
        'seed-ctx-005',
        'Branch network political context',
        'insight',
        'Branch managers report to the Retail Banking MD (Tony Bridges), '
            'not to the programme. Tony is supportive in Steering Committee '
            'but his branch managers are resistant — they feel the '
            'transformation is being done "to" them. Priya\'s change '
            'management plan needs to address this directly.',
        'relationship',
      ),
    ];

    for (final (id, title, type, content, tags) in contextEntries) {
      await db.contextDao.insertEntry(
        ContextEntriesCompanion.insert(
          id: id,
          projectId: projectId,
          title: title,
          content: content,
          entryType: Value(type),
          tags: Value(tags),
          source: const Value('manual'),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Inbox items
    // -------------------------------------------------------------------------
    await db.inboxDao.insertInboxItem(
      InboxItemsCompanion.insert(
        id: 'seed-inbox-001',
        projectId: projectId,
        content:
            'RISK: SWIFT certification timeline has slipped — new estimate '
            'is 10 weeks not 8. This puts the payments go-live at risk.',
        tags: const Value('risk'),
        source: const Value('manual'),
        status: const Value('unprocessed'),
      ),
    );

    await db.inboxDao.insertInboxItem(
      InboxItemsCompanion.insert(
        id: 'seed-inbox-002',
        projectId: projectId,
        content:
            'ACTION: Follow up with Tony Bridges re branch manager concerns — '
            'suggest a dedicated session before the April road-show @priya.sharma',
        tags: const Value('action'),
        source: const Value('manual'),
        status: const Value('unprocessed'),
      ),
    );

    await db.inboxDao.insertInboxItem(
      InboxItemsCompanion.insert(
        id: 'seed-inbox-003',
        projectId: projectId,
        content:
            'DECISION: Do we need a formal data residency policy for '
            'EU customer records before the AWS migration proceeds? '
            'Legal flagged this in the contract review.',
        tags: const Value('decision'),
        source: const Value('manual'),
        status: const Value('unprocessed'),
      ),
    );

    // -------------------------------------------------------------------------
    // Status report
    // -------------------------------------------------------------------------
    await db.reportsDao.upsertReport(
      StatusReportsCompanion(
        id: const Value('seed-report-001'),
        projectId: const Value(projectId),
        title: const Value('Horizon Programme — Week 10 Status'),
        period: const Value('Week 10 (Mar 2025)'),
        overallRag: const Value('amber'),
        summary: const Value(
            'The programme is progressing broadly to plan but two items '
            'have moved the overall RAG to Amber this week. Temenos '
            'resourcing remains the primary concern, with only 3 of 6 '
            'contracted developers active. The branch training budget '
            'overspend has been escalated to Steering Committee.'),
        accomplishments: const Value(
            'AWS infrastructure baseline completed and signed off by ADA.\n'
            'Mobile app React Native architecture approved.\n'
            'Data encoding validation sprint kicked off.\n'
            'PRA pre-submission meeting booked for 28 March.'),
        nextSteps: const Value(
            'Resolve Temenos resourcing — written commitment expected by 14 March.\n'
            'Complete branch training budget reforecast for Steering Committee.\n'
            'Progress SWIFT certification timeline — engage SWIFT account manager.\n'
            'Run executive road-show with branch managers in April.'),
        risksHighlighted: const Value(
            'R1 (Temenos resourcing) — HIGH. Escalated to vendor account director.\n'
            'R5 (Branch resistance) — HIGH likelihood. Priya\'s change plan being accelerated.\n'
            'I1 (Test environment outage) — 6 days of integration testing lost.'),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // -------------------------------------------------------------------------
    // Glossary — systems and terms
    // -------------------------------------------------------------------------
    final glossarySystems = <(String, String, String?, String, String, String, String)>[
      // (id, name, acronym, description, owner, environment, status)
      ('seed-gl-sys-001', 'Temenos T24', 'T24',
          'Target core banking platform replacing the legacy mainframe.',
          'Amara Osei', 'AWS Frankfurt', 'live'),
      ('seed-gl-sys-002', 'Mainframe', 'IBM zOS',
          'Legacy core banking platform — to be decommissioned by Q4 2026.',
          'Amara Osei', 'On-premise (Slough DC)', 'sunsetting'),
      ('seed-gl-sys-003', 'Apache Kafka', 'Kafka',
          'Event-streaming backbone for real-time data flow between services.',
          'Raj Patel', 'AWS MSK', 'live'),
      ('seed-gl-sys-004', 'Apache Flink', 'Flink',
          'Streaming compute engine for real-time analytics and aggregations.',
          'Raj Patel', 'AWS EMR', 'live'),
      ('seed-gl-sys-005', 'Snowflake', null,
          'Data warehouse for batch analytics, BI dashboards, and reporting.',
          'Raj Patel', 'AWS', 'live'),
      ('seed-gl-sys-006', 'Auth0', null,
          'Identity provider for the new mobile and web channels.',
          'Marcus Webb', 'Auth0 EU', 'live'),
      ('seed-gl-sys-007', 'Datadog', null,
          'Observability platform — metrics, logs and traces.',
          'Marcus Webb', 'SaaS', 'live'),
      ('seed-gl-sys-008', 'Mobile App (FinCo Connect)', 'FCx',
          'iOS / Android customer-facing app. React Native.',
          'Sophie Chen', 'App Store / Play Store', 'live'),
      ('seed-gl-sys-009', 'API Gateway', null,
          'Kong-based API gateway fronting Temenos and downstream services.',
          'James Farrow', 'AWS', 'live'),
      ('seed-gl-sys-010', 'Jira / Confluence', null,
          'Issue tracking and documentation. Atlassian Cloud.',
          'Programme Office', 'SaaS', 'live'),
    ];
    for (final s in glossarySystems) {
      final (id, name, acronym, desc, owner, env, status) = s;
      await db.glossaryDao.upsert(
        GlossaryEntriesCompanion(
          id:          Value(id),
          projectId:   Value(projectId),
          type:        const Value('system'),
          name:        Value(name),
          acronym:     Value(acronym),
          description: Value(desc),
          owner:       Value(owner),
          environment: Value(env),
          status:      Value(status),
          updatedAt:   Value(DateTime.now()),
        ),
      );
    }

    final glossaryTerms = <(String, String, String?, String)>[
      // (id, name, acronym, description)
      ('seed-gl-tm-001', 'Architecture Design Authority', 'ADA',
          'Cross-workstream forum that approves architecture decisions. '
          'Chaired by James Farrow (Chief Architect). Meets fortnightly.'),
      ('seed-gl-tm-002', 'Steering Committee', 'Steerco',
          'Programme governance forum — Helena (CTO), Richard (CFO), '
          'Diana (CEO), and the workstream leads. Monthly.'),
      ('seed-gl-tm-003', 'Know Your Customer', 'KYC',
          'Regulatory checks on customer identity at onboarding.'),
      ('seed-gl-tm-004', 'Anti-Money Laundering', 'AML',
          'Detection of suspicious transaction patterns.'),
      ('seed-gl-tm-005', 'RAG Status', 'RAG',
          'Red / Amber / Green health rating used across workstreams.'),
      ('seed-gl-tm-006', 'Monthly Active Users', 'MAU',
          'Distinct users who have opened the mobile app at least once '
          'in the last 30 days.'),
      ('seed-gl-tm-007', 'Business as Usual', 'BAU',
          'Steady-state operation post programme close.'),
      ('seed-gl-tm-008', 'Recovery Point / Time Objective', 'RPO / RTO',
          'Disaster recovery targets. Horizon target: RPO 5 min, RTO 30 min.'),
      ('seed-gl-tm-009', 'Prudential Regulation Authority', 'PRA',
          'UK regulator for banks. Owns approval of the decommission plan.'),
      ('seed-gl-tm-010', 'ISO 27001', null,
          'International standard for information security management. '
          'Horizon scope certified at M15.'),
      ('seed-gl-tm-011', 'SOC 2 Type II', 'SOC 2',
          'Audit report on control effectiveness over a sustained period. '
          'In flight — final report at M18.'),
      ('seed-gl-tm-012', 'Open Banking', null,
          'Regulatory regime requiring banks to expose customer-permissioned '
          'APIs to authorised third parties.'),
    ];
    for (final t in glossaryTerms) {
      final (id, name, acronym, desc) = t;
      await db.glossaryDao.upsert(
        GlossaryEntriesCompanion(
          id:          Value(id),
          projectId:   Value(projectId),
          type:        const Value('term'),
          name:        Value(name),
          acronym:     Value(acronym),
          description: Value(desc),
          updatedAt:   Value(DateTime.now()),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Documents — sample uploaded documents (metadata + extracted text)
    // -------------------------------------------------------------------------
    final documents = <(String, String, String, String, String)>[
      // (id, title, documentType, tags, content)
      (
        'seed-doc-001',
        'Programme Charter v1.2',
        'pdf',
        'charter,governance',
        'HORIZON PROGRAMME — CHARTER v1.2\n\n'
            'Vision: A fully cloud-native, real-time banking platform.\n\n'
            'Sponsor: Helena Cross (CTO)\n'
            'Programme Manager: You\n'
            'Budget: £42M / 24 months\n\n'
            'See Charter section in Keel for full content. This document '
            'is the v1.2 baseline approved at the kick-off Steerco '
            '(Jan 2025).',
      ),
      (
        'seed-doc-002',
        'ADA Decision Record — Core Banking Vendor Selection',
        'pdf',
        'decision,architecture',
        'ARCHITECTURE DESIGN AUTHORITY — DECISION RECORD\n'
            'Date: 21 January 2025\n'
            'Decision: Adopt Temenos T24 as the target core banking '
            'platform. Reject the build-in-house and Thought Machine '
            'options.\n\n'
            'Rationale: Total cost of ownership over 5 years is 35% lower '
            'than build-in-house. Time-to-pilot is 4 months shorter than '
            'Thought Machine. The Temenos accelerator pack covers ~70% '
            'of the FinCo retail product set out of the box.\n\n'
            'Risks acknowledged: Vendor lock-in, hosting concentration. '
            'Mitigations: Multi-region deployment, exit clauses in MSA.',
      ),
      (
        'seed-doc-003',
        'Q1 2025 Steering Committee Pack',
        'pdf',
        'steerco,reporting',
        'HORIZON STEERCO — Q1 2025 PACK\n\n'
            'Programme RAG: Amber\n\n'
            'Highlights:\n'
            '- Pilot Go-Live (10k accounts) successful, zero incidents.\n'
            '- Mobile MVP feature-complete; closed beta scheduled for '
            'Apr 2025.\n'
            '- ISO 27001 gap analysis complete; remediation in progress.\n\n'
            'Concerns:\n'
            '- Temenos resourcing — only 3 of 6 contracted developers '
            'active. Escalated to vendor account director.\n'
            '- Branch training plan over budget by 18%. Reforecast '
            'requested by CFO.\n\n'
            'Decisions sought: Approval to proceed with Phase 2 migration '
            '(1M accounts) starting M9.',
      ),
      (
        'seed-doc-004',
        'Mobile App Architecture Specification',
        'docx',
        'architecture,mobile',
        'FINCO CONNECT — MOBILE APP ARCHITECTURE\n\n'
            'Platform: React Native (iOS + Android shared codebase).\n'
            'Auth: Auth0 + biometric (FaceID / fingerprint).\n'
            'Backend: REST APIs via Kong gateway → Temenos T24 / data '
            'platform.\n'
            'State management: Redux Toolkit + RTK Query.\n'
            'Offline: Read-only cache of last balance + 30 days of '
            'transactions.\n'
            'Crash reporting: Datadog RUM.\n\n'
            'Performance targets: Cold start <2s, p95 API latency <300ms.',
      ),
      (
        'seed-doc-005',
        'ISO 27001 Gap Analysis Report',
        'pdf',
        'security,compliance',
        'ISO 27001:2022 — GAP ANALYSIS\n'
            'Prepared by: BDO LLP (Hugo Reinhardt, Audit Partner)\n'
            'Date: February 2025\n\n'
            'Annex A controls assessed: 93 / 93\n'
            'Compliant: 71\n'
            'Partial: 18 (remediation tracked)\n'
            'Non-compliant: 4 (remediation in flight)\n\n'
            'Critical gaps:\n'
            '- A.5.23 Cloud services (no formal cloud security policy)\n'
            '- A.8.16 Monitoring activities (Datadog rollout pending)\n'
            '- A.5.7 Threat intelligence (no formal feed subscribed)\n'
            '- A.8.28 Secure coding (training programme not mandatory)\n\n'
            'Recommendation: 6-month remediation plan, certification '
            'achievable by M15.',
      ),
    ];
    for (final d in documents) {
      final (id, title, docType, tags, content) = d;
      await db.contextDao.insertDocument(
        DocumentsCompanion(
          id:           Value(id),
          projectId:    Value(projectId),
          title:        Value(title),
          documentType: Value(docType),
          tags:         Value(tags),
          content:      Value(content),
          updatedAt:    Value(DateTime.now()),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Journal entries — meeting notes and PM thoughts across the timeline
    // -------------------------------------------------------------------------
    final journalEntries = <(String, String, String, String, String)>[
      // (id, title, entryDate, meetingContext, body)
      (
        'seed-jrn-001',
        'Steerco prep notes — March 2025',
        '2025-03-12',
        'Pre-Steerco prep',
        'Helena wants a tighter narrative on the Temenos resourcing risk. '
            'Need to walk her through the escalation path before Friday.\n\n'
            '/risk Temenos resourcing — only 3 of 6 contracted developers '
            'active. Likely impact: 2-week slippage to Phase 2 start.\n\n'
            '/action Draft a one-page brief for Helena by EOD Wed '
            '(owner: me, due 2025-03-13).\n\n'
            'Richard will press on burn rate — Q1 actuals are 7% under '
            'plan but his focus is the trajectory not the spot value.',
      ),
      (
        'seed-jrn-002',
        'Vendor escalation call — Temenos',
        '2025-03-19',
        'Call with Stefan Blau (Temenos Engagement Director)',
        'Stefan acknowledged the resourcing gap. Two senior devs joining '
            'the programme by 1 April, fully ramped by mid-April.\n\n'
            '/decision Temenos to provide written commitment on resourcing '
            '(decision-maker: Stefan Blau, due 2025-03-21).\n\n'
            '/action Track resourcing weekly via the vendor scorecard '
            '(owner: Amara Osei, recurring).\n\n'
            'Stefan also flagged that the Q3 release branch will need '
            'a second pen test — book BDO accordingly.',
      ),
      (
        'seed-jrn-003',
        'Pilot Go-Live retrospective',
        '2025-08-29',
        'Cross-workstream retro',
        'Pilot went smoothly — 10k accounts migrated, zero unplanned '
            'outage, customer NPS unchanged.\n\n'
            'What worked:\n'
            '- The dual-write pattern allowed instant rollback if needed.\n'
            '- Branch staff briefing pack was clear and well-received.\n\n'
            'What to fix for Phase 2:\n'
            '- Reconciliation reports were too verbose — simplify the '
            'morning-after dashboard.\n'
            '- Customer comms went out 2 hours late due to a manual '
            'sign-off bottleneck.\n\n'
            '/action Streamline reconciliation dashboard before Phase 2 '
            '(owner: Amara Osei, due 2025-09-15).',
      ),
      (
        'seed-jrn-004',
        'Branch training plan review — Priya',
        '2025-12-04',
        '1:1 with Priya Sharma',
        'The training plan is in trouble. Sponsor (regional ops) hasn\'t '
            'signed off because the modular structure conflicts with '
            'existing branch training delivery. Priya needs help.\n\n'
            '/risk Branch training plan unsigned — risk to mainframe '
            'decommission readiness. Likely high, impact high.\n\n'
            '/action Set up a working session with Priya, regional ops '
            'lead, and the L&D function (owner: me, due 2025-12-10).\n\n'
            'Helena needs to be in the loop. This will probably end up '
            'at the next Steerco.',
      ),
      (
        'seed-jrn-005',
        'Quarterly programme review — Q1 2026',
        '2026-03-20',
        'Quarterly review with Helena',
        'Phase 2 migration completed on schedule. ISO 27001 cert '
            'achieved on time. Mobile crossed 250k MAU — halfway to the '
            '500k target. SOC 2 Type II evidence collection underway.\n\n'
            'Watch items:\n'
            '- Full migration sprints starting next month — biggest '
            'technical risk on the programme.\n'
            '- Branch training still unresolved (see Dec note).\n'
            '- Open banking integrations slipping — three external partners '
            'have moved their dates right.\n\n'
            '/decision Defer the open banking partner C integration to '
            'Phase 4 (decision-maker: Helena Cross, status: pending).',
      ),
      (
        'seed-jrn-006',
        'Training plan slip — Steerco escalation',
        '2026-04-28',
        'Post-Steerco debrief',
        'Steerco escalated the training plan. Helena and Diana asked '
            'Priya to come back with a re-baselined plan in two weeks. '
            'They\'ve allocated an additional £180k of contingency to '
            'unblock external trainers.\n\n'
            '/risk Branch training slip — RAG moved to RED at programme '
            'level. Watching closely.\n\n'
            '/action Priya to deliver re-baselined plan (owner: Priya '
            'Sharma, due 2026-05-12).\n\n'
            '/decision Approve £180k contingency draw-down for external '
            'trainers (decision-maker: Richard Okafor, status: approved, '
            'date: 2026-04-28).',
      ),
    ];
    for (final j in journalEntries) {
      final (id, title, date, meeting, body) = j;
      await db.journalDao.insertEntry(
        JournalEntriesCompanion(
          id:             Value(id),
          projectId:      Value(projectId),
          title:          Value(title),
          body:           Value(body),
          entryDate:      Value(date),
          meetingContext: Value(meeting),
          // Pre-mark as parsed so the demo doesn't re-extract on first load
          // and create duplicate actions/risks (which would conflict with
          // the seeded RAID/Decisions/Actions IDs).
          parsed:         const Value(true),
          confirmedAt:    Value(DateTime.now()),
          updatedAt:      Value(DateTime.now()),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Playbook — full 10-stage Project Delivery
    // -------------------------------------------------------------------------
    await _seedHorizonPlaybook(db, projectId);

    // -------------------------------------------------------------------------
    // Plan — Programme Gantt: header, work packages, activities
    // -------------------------------------------------------------------------
    await _seedHorizonPlan(db, projectId);
  }

  // ---------------------------------------------------------------------------
  // Playbook seeder — Project Delivery (10 stages, attached to Horizon)
  // ---------------------------------------------------------------------------

  static Future<void> _seedHorizonPlaybook(
      AppDatabase db, String projectId) async {
    const orgId = 'seed-org-001';
    const playbookId = 'seed-pb-001';

    // Organisation that owns the playbook.
    await db.playbookDao.upsertOrganisation(OrganisationsCompanion(
      id:        const Value(orgId),
      name:      const Value('FinCo Ltd'),
      shortName: const Value('FinCo'),
      notes:     const Value('Default organisation for the demo playbook.'),
      updatedAt: Value(DateTime.now()),
    ));

    // The playbook itself.
    await db.playbookDao.upsertPlaybook(PlaybooksCompanion(
      id:             const Value(playbookId),
      organisationId: const Value(orgId),
      name:           const Value('Project Delivery'),
      description:    const Value(
          'End-to-end project lifecycle from idea to benefits realisation. '
          'Used across FinCo for any project with a budget over £500k.'),
      version:        const Value('2.0'),
      updatedAt:      Value(DateTime.now()),
    ));

    // Stages.
    final stages = <_Stage>[
      _Stage('seed-pb-st-01', 'Initiation',
          'Capture the idea, identify a sponsor, define the high-level '
              'problem and outcome.',
          'Sponsor', 'Sponsor signs off the brief'),
      _Stage('seed-pb-st-02', 'Discovery',
          'Validate feasibility. Confirm stakeholders, success criteria, '
              'high-level scope, and constraints.',
          'Programme Manager', 'Discovery output reviewed at Steerco'),
      _Stage('seed-pb-st-03', 'Business Case',
          'Quantified ROI, options analysis, recommended option, funding '
              'request. Approved at Investment Committee.',
          'CFO', 'Investment Committee approval recorded'),
      _Stage('seed-pb-st-04', 'Planning',
          'Detailed scope, schedule, budget, resource plan, risk register, '
              'communications plan, and governance model.',
          'Programme Manager', 'Plan approved at Steerco'),
      _Stage('seed-pb-st-05', 'Design',
          'Solution architecture, security architecture, integration design, '
              'data model. Approved at the Architecture Design Authority.',
          'Chief Architect', 'ADA approval recorded'),
      _Stage('seed-pb-st-06', 'Build',
          'Iterative development. Sprint cadence, daily stand-ups, '
              'continuous integration, code reviews, unit tests.',
          'Workstream Leads', 'Feature complete sign-off per workstream'),
      _Stage('seed-pb-st-07', 'Test',
          'System integration test, user acceptance test, performance '
              'test, security test, regression. Defect triage to zero P1/P2.',
          'QA Lead', 'UAT pass + zero open P1/P2 defects'),
      _Stage('seed-pb-st-08', 'Deploy',
          'Cutover plan, dress rehearsal, go/no-go review, deployment, '
              'release verification, customer comms.',
          'Programme Manager', 'Go-Live confirmed by ops + zero rollback'),
      _Stage('seed-pb-st-09', 'Hypercare',
          'Heightened post-go-live support. War-room, incident response, '
              'rapid fixes. Typically 4–8 weeks.',
          'Operations Lead', 'Hypercare exit criteria met'),
      _Stage('seed-pb-st-10', 'Close',
          'Handover to BAU, lessons learned workshop, benefits tracking '
              'plan, programme financial close, retrospective.',
          'Programme Manager', 'Lessons-learned doc + benefits plan signed'),
    ];

    for (var i = 0; i < stages.length; i++) {
      final s = stages[i];
      await db.playbookDao.upsertStage(PlaybookStagesCompanion(
        id:            Value(s.id),
        playbookId:    const Value(playbookId),
        name:          Value(s.name),
        description:   Value(s.description),
        sortOrder:     Value(i),
        approverRole:  Value(s.approver),
        gateCondition: Value(s.gate),
        updatedAt:     Value(DateTime.now()),
      ));
    }

    // Attach to Horizon and create progress records.
    await db.playbookDao.attachPlaybookToProject(
      projectId: projectId,
      playbookId: playbookId,
    );

    // Mark progress to reflect "we're in mid-Build, parallel-Test" today.
    final pp = await db.playbookDao.getProjectPlaybook(projectId);
    if (pp == null) return;
    final progresses = await db.playbookDao.getProgressForProjectPlaybook(pp.id);
    const stageStatusByOrder = <int, String>{
      0: 'complete',     // Initiation
      1: 'complete',     // Discovery
      2: 'complete',     // Business Case
      3: 'complete',     // Planning
      4: 'complete',     // Design
      5: 'in_progress',  // Build
      6: 'in_progress',  // Test
      7: 'not_started',  // Deploy
      8: 'not_started',  // Hypercare
      9: 'not_started',  // Close
    };
    final now = DateTime.now();
    for (final progress in progresses) {
      final stage = await db.playbookDao.getStageById(progress.stageId);
      if (stage == null) continue;
      final status = stageStatusByOrder[stage.sortOrder] ?? 'not_started';
      final isDone = status == 'complete';
      await db.playbookDao.upsertProgress(ProjectStageProgressesCompanion(
        id:                Value(progress.id),
        projectPlaybookId: Value(progress.projectPlaybookId),
        stageId:           Value(progress.stageId),
        status:            Value(status),
        gateMet:           Value(isDone),
        approvedBy:        Value(isDone ? 'You' : null),
        approvedAt:        Value(isDone ? now : null),
        updatedAt:         Value(now),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Plan / Programme Gantt seeder
  //
  // The Plan view is a 24-month Gantt over Jan 2025 → Dec 2026.
  // Activities use month indices 0..23. Today (≈ M16) splits the plan into
  // "complete" (M0..M15) and "in-flight or future" (M16+).
  // ---------------------------------------------------------------------------

  static Future<void> _seedHorizonPlan(
      AppDatabase db, String projectId) async {
    // ── Programme header (24 months, Jan 2025 – Dec 2026) ───────────────────
    await db.programmeGanttDao.upsertHeader(
      ProgrammeHeadersCompanion(
        id:           const Value('seed-pg-header-001'),
        projectId:    Value(projectId),
        title:        const Value('Horizon Programme'),
        subtitle:     const Value('FinCo Digital Transformation 2025–2026'),
        hardDeadline: const Value('Q4 2026 — Mainframe decommission'),
        inScope:      const Value(
            'Core banking replacement, mobile channel, data platform, '
            'API gateway, identity & access management, operational tooling.'),
        outOfScope:   const Value(
            'Investment banking, FX trading, international subsidiaries.'),
        monthLabels:  const Value(_horizonMonthLabelsJson),
        month0Date:   const Value('2025-01-06'),
        updatedAt:    Value(DateTime.now()),
      ),
    );

    // ── Work packages ───────────────────────────────────────────────────────
    final wps = <_WP>[
      _WP('seed-wp-gov',    'Programme Governance',    'governance', 'green', 0,
          'Steering, design authority, and overall coordination.'),
      _WP('seed-wp-cb',     'Core Banking Replacement','wp1',        'amber', 1,
          'Temenos rollout. Pilot complete; full migration in progress.'),
      _WP('seed-wp-data',   'Data Platform & Analytics','wp2',       'green', 2,
          'Kafka + Flink + data lake. Real-time analytics live.'),
      _WP('seed-wp-mobile', 'Mobile & Digital Channels','wp3',       'green', 3,
          'iOS/Android live. Open banking integrations underway.'),
      _WP('seed-wp-sec',    'Security & Compliance',   'wp4',        'amber', 4,
          'ISO 27001 certified. SOC 2 Type II in flight.'),
      _WP('seed-wp-change', 'Change Mgmt & Training',  'mpower',     'red',   5,
          'Branch training plan slipped — sponsor escalation raised.'),
    ];

    for (final wp in wps) {
      await db.programmeGanttDao.upsertWorkPackage(
        TimelineWorkPackagesCompanion(
          id:           Value(wp.id),
          projectId:    Value(projectId),
          name:         Value(wp.name),
          shortCode:    Value(wp.shortCode),
          description:  Value(wp.description),
          colourTheme:  Value(wp.colour),
          ragStatus:    Value(wp.rag),
          sortOrder:    Value(wp.sortOrder),
          updatedAt:    Value(DateTime.now()),
        ),
      );
    }

    // ── Activities ──────────────────────────────────────────────────────────
    // Each entry: workpackage, name, type, startMonth, endMonth, status,
    // owner, isCritical, optional notes.
    final activities = <_Act>[
      // Programme Governance ------------------------------------------------
      _Act('seed-wp-gov', 'Programme kick-off',
          'milestone', 0, 0, 'complete', 'You', true,
          'Steerco established, charter signed.'),
      _Act('seed-wp-gov', 'Architecture Design Authority approved',
          'gate', 3, 3, 'complete', 'You', true, null),
      _Act('seed-wp-gov', 'Monthly Steering Committee',
          'ongoing', 0, 23, 'on_track', 'You', false, null),
      _Act('seed-wp-gov', 'Mid-programme review',
          'milestone', 12, 12, 'complete', 'You', false, null),
      _Act('seed-wp-gov', 'PRA pre-submission',
          'hard_deadline', 14, 14, 'complete', 'You', false, null),
      _Act('seed-wp-gov', 'Programme close & lessons learned',
          'activity', 22, 23, 'not_started', 'You', false, null),

      // Core Banking Replacement -------------------------------------------
      _Act('seed-wp-cb', 'Vendor selection finalised',
          'gate', 1, 1, 'complete', 'Amara Osei', true, null),
      _Act('seed-wp-cb', 'Core banking architecture design',
          'activity', 1, 3, 'complete', 'Amara Osei', false, null),
      _Act('seed-wp-cb', 'Dev environment build',
          'activity', 3, 6, 'complete', 'Amara Osei', false, null),
      _Act('seed-wp-cb', 'Pilot data migration (10k accounts)',
          'activity', 5, 8, 'complete', 'Amara Osei', true, null),
      _Act('seed-wp-cb', 'Pilot Go-Live',
          'milestone', 8, 8, 'complete', 'Amara Osei', true,
          'First 10k customers on new core.'),
      _Act('seed-wp-cb', 'Phase 2 migration (1M accounts)',
          'activity', 9, 14, 'complete', 'Amara Osei', true, null),
      _Act('seed-wp-cb', 'Full migration sprints (4M accounts)',
          'activity', 14, 20, 'on_track', 'Amara Osei', true,
          'Temenos resourcing recovered after Q1 escalation.'),
      _Act('seed-wp-cb', 'Mainframe decommission',
          'hard_deadline', 21, 21, 'not_started', 'Amara Osei', true, null),

      // Data Platform & Analytics ------------------------------------------
      _Act('seed-wp-data', 'Kafka cluster build (dev)',
          'activity', 1, 3, 'complete', 'Raj Patel', false, null),
      _Act('seed-wp-data', 'Flink streaming jobs',
          'activity', 3, 5, 'complete', 'Raj Patel', false, null),
      _Act('seed-wp-data', 'Real-time analytics MVP',
          'milestone', 7, 7, 'complete', 'Raj Patel', false, null),
      _Act('seed-wp-data', 'Data lake migration',
          'activity', 7, 10, 'complete', 'Raj Patel', false, null),
      _Act('seed-wp-data', 'BI dashboard rollout',
          'activity', 10, 12, 'complete', 'Raj Patel', false, null),
      _Act('seed-wp-data', 'ML model deployment (fraud, churn)',
          'activity', 12, 16, 'complete', 'Raj Patel', false, null),
      _Act('seed-wp-data', 'Customer 360 view live',
          'milestone', 19, 19, 'on_track', 'Raj Patel', false, null),

      // Mobile & Digital Channels ------------------------------------------
      _Act('seed-wp-mobile', 'UX design & sign-off',
          'gate', 2, 2, 'complete', 'Sophie Chen', true, null),
      _Act('seed-wp-mobile', 'iOS / Android MVP build',
          'activity', 2, 5, 'complete', 'Sophie Chen', false, null),
      _Act('seed-wp-mobile', 'Closed beta (5k users)',
          'milestone', 8, 8, 'complete', 'Sophie Chen', false, null),
      _Act('seed-wp-mobile', 'Public launch',
          'milestone', 10, 10, 'complete', 'Sophie Chen', true,
          '500k downloads target tracked from this point.'),
      _Act('seed-wp-mobile', 'Feature parity with web',
          'activity', 10, 14, 'complete', 'Sophie Chen', false, null),
      _Act('seed-wp-mobile', 'Open banking integrations',
          'activity', 14, 18, 'on_track', 'Sophie Chen', false, null),
      _Act('seed-wp-mobile', '500k MAU milestone',
          'milestone', 22, 22, 'not_started', 'Sophie Chen', false, null),

      // Security & Compliance ----------------------------------------------
      _Act('seed-wp-sec', 'ISO 27001 gap analysis',
          'activity', 0, 2, 'complete', 'Marcus Webb', false, null),
      _Act('seed-wp-sec', 'Penetration test (Q2 2025)',
          'activity', 2, 4, 'complete', 'Marcus Webb', false, null),
      _Act('seed-wp-sec', 'Remediation sprint',
          'activity', 4, 6, 'complete', 'Marcus Webb', false, null),
      _Act('seed-wp-sec', 'Identity & Access Management rollout',
          'activity', 6, 9, 'complete', 'Marcus Webb', false, null),
      _Act('seed-wp-sec', 'SOC 2 Type II preparation',
          'activity', 9, 12, 'complete', 'Marcus Webb', false, null),
      _Act('seed-wp-sec', 'ISO 27001 certification',
          'milestone', 15, 15, 'complete', 'Marcus Webb', true, null),
      _Act('seed-wp-sec', 'Continuous compliance monitoring',
          'ongoing', 15, 23, 'on_track', 'Marcus Webb', false, null),
      _Act('seed-wp-sec', 'SOC 2 Type II report',
          'milestone', 18, 18, 'on_track', 'Marcus Webb', false, null),

      // Change Mgmt & Training (currently red) -----------------------------
      _Act('seed-wp-change', 'Change impact assessment',
          'activity', 0, 3, 'complete', 'Priya Sharma', false, null),
      _Act('seed-wp-change', 'Initial training plan draft',
          'activity', 3, 5, 'complete', 'Priya Sharma', false, null),
      _Act('seed-wp-change', 'Training plan approval (REVISED)',
          'gate', 16, 16, 'at_risk', 'Priya Sharma', true,
          'Slipped from M5. Sponsor escalation raised — at risk for M16.'),
      _Act('seed-wp-change', 'Branch staff training — cohort 1',
          'activity', 16, 19, 'not_started', 'Priya Sharma', false, null),
      _Act('seed-wp-change', 'Branch staff training — cohort 2',
          'activity', 19, 21, 'not_started', 'Priya Sharma', false, null),
      _Act('seed-wp-change', 'Customer comms rollout',
          'activity', 16, 18, 'on_track', 'Priya Sharma', false, null),
      _Act('seed-wp-change', 'Adoption metric tracking',
          'ongoing', 18, 23, 'not_started', 'Priya Sharma', false, null),
      _Act('seed-wp-change', 'Training programme complete',
          'milestone', 21, 21, 'not_started', 'Priya Sharma', false, null),
    ];

    var sortOrder = 0;
    for (final a in activities) {
      sortOrder++;
      await db.programmeGanttDao.upsertActivity(
        TimelineActivitiesCompanion(
          id:            Value('seed-act-${sortOrder.toString().padLeft(3, "0")}'),
          workPackageId: Value(a.wpId),
          projectId:     Value(projectId),
          name:          Value(a.name),
          owner:         Value(a.owner),
          activityType:  Value(a.type),
          startMonth:    Value(a.start),
          endMonth:      Value(a.end),
          status:        Value(a.status),
          isCritical:    Value(a.critical),
          notes:         Value(a.notes),
          sortOrder:     Value(sortOrder),
          updatedAt:     Value(DateTime.now()),
        ),
      );
    }
  }

  static String _dateOffset(DateTime base, int days) {
    final dt = base.add(Duration(days: days));
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

// JSON array of month labels covering the 24-month Horizon timeline.
const _horizonMonthLabelsJson =
    '["Jan 2025","Feb 2025","Mar 2025","Apr 2025","May 2025","Jun 2025",'
    '"Jul 2025","Aug 2025","Sep 2025","Oct 2025","Nov 2025","Dec 2025",'
    '"Jan 2026","Feb 2026","Mar 2026","Apr 2026","May 2026","Jun 2026",'
    '"Jul 2026","Aug 2026","Sep 2026","Oct 2026","Nov 2026","Dec 2026"]';

// ─── Internal value types kept here so the Plan seeder reads top-down ──────

class _WP {
  final String id;
  final String name;
  final String colour;
  final String rag;
  final int sortOrder;
  final String description;
  final String shortCode;
  _WP(this.id, this.name, this.colour, this.rag, this.sortOrder,
      this.description)
      : shortCode = id.split('-').last.toUpperCase();
}

class _Act {
  final String wpId;
  final String name;
  final String type;
  final int start;
  final int end;
  final String status;
  final String owner;
  final bool critical;
  final String? notes;
  _Act(this.wpId, this.name, this.type, this.start, this.end, this.status,
      this.owner, this.critical, this.notes);
}

class _Stage {
  final String id;
  final String name;
  final String description;
  final String approver;
  final String gate;
  _Stage(this.id, this.name, this.description, this.approver, this.gate);
}
