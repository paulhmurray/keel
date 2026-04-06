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
    final persons = [
      (
        'seed-p-001', 'Helena Cross', 'CTO', 'FinCo Ltd',
        'helena.cross@finco.com', '+44 7700 900123', '@helena.cross',
        'stakeholder',
      ),
      (
        'seed-p-002', 'Richard Okafor', 'CFO', 'FinCo Ltd',
        'r.okafor@finco.com', '+44 7700 900456', '@richard.okafor',
        'stakeholder',
      ),
      (
        'seed-p-003', 'Amara Osei', 'Core Banking Lead', 'FinCo Ltd',
        'a.osei@finco.com', null, '@amara.osei',
        'colleague',
      ),
      (
        'seed-p-004', 'Raj Patel', 'Data Platform Architect', 'FinCo Ltd',
        'raj.patel@finco.com', null, '@raj.patel',
        'colleague',
      ),
      (
        'seed-p-005', 'Sophie Chen', 'Mobile Engineering Lead', 'FinCo Ltd',
        's.chen@finco.com', null, '@sophie.chen',
        'colleague',
      ),
      (
        'seed-p-006', 'Marcus Webb', 'Head of Security', 'FinCo Ltd',
        'm.webb@finco.com', '+44 7700 900789', '@marcus.webb',
        'colleague',
      ),
      (
        'seed-p-007', 'Priya Sharma', 'Change Manager', 'FinCo Ltd',
        'p.sharma@finco.com', null, '@priya.sharma',
        'colleague',
      ),
      (
        'seed-p-008', 'James Farrow', 'Chief Architect', 'FinCo Ltd',
        'j.farrow@finco.com', null, '@james.farrow',
        'stakeholder',
      ),
    ];

    for (final (id, name, role, org, email, phone, teams, type) in persons) {
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
  }

  static String _dateOffset(DateTime base, int days) {
    final dt = base.add(Duration(days: days));
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
