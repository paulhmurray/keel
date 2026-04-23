/// Scaffold role definitions — pre-populated when a new project is created.
/// These are suggestions, not requirements.

class StakeholderScaffoldRole {
  final String roleName;
  final String roleType; // accountable | active | affected
  final String hint; // shown to the user beneath the role name
  final bool isCritical; // triggers warning if unfilled
  final int sortOrder;

  const StakeholderScaffoldRole({
    required this.roleName,
    required this.roleType,
    required this.hint,
    this.isCritical = false,
    required this.sortOrder,
  });
}

class TeamScaffoldRole {
  final String roleName;
  final String teamGroup;
  final String hint;
  final int sortOrder;

  const TeamScaffoldRole({
    required this.roleName,
    required this.teamGroup,
    required this.hint,
    required this.sortOrder,
  });
}

// ---------------------------------------------------------------------------
// Stakeholder scaffold
// ---------------------------------------------------------------------------

const stakeholderScaffold = <StakeholderScaffoldRole>[
  // Accountable
  StakeholderScaffoldRole(
    roleName: 'Programme Sponsor',
    roleType: 'accountable',
    hint: 'Ultimate accountability, budget sign-off, escalation endpoint. Every programme must have one.',
    isCritical: true,
    sortOrder: 0,
  ),
  StakeholderScaffoldRole(
    roleName: 'Business Owner',
    roleType: 'accountable',
    hint: 'Owns the business outcomes. May be the same as Sponsor.',
    isCritical: true,
    sortOrder: 1,
  ),
  StakeholderScaffoldRole(
    roleName: 'Executive Champion',
    roleType: 'accountable',
    hint: 'Senior visible advocate. Particularly important in change-heavy programmes.',
    sortOrder: 2,
  ),

  // Active
  StakeholderScaffoldRole(
    roleName: 'Steering Committee',
    roleType: 'active',
    hint: 'Governance participants. Add individual members.',
    sortOrder: 10,
  ),
  StakeholderScaffoldRole(
    roleName: 'Change Authority',
    roleType: 'active',
    hint: 'Approves changes to scope, budget, or timeline.',
    sortOrder: 11,
  ),
  StakeholderScaffoldRole(
    roleName: 'Regulator / Compliance Representative',
    roleType: 'active',
    hint: 'In regulated environments (government, insurance, healthcare) this person is critical. Often overlooked until something goes wrong.',
    sortOrder: 12,
  ),
  StakeholderScaffoldRole(
    roleName: 'Vendor / Partner Lead',
    roleType: 'active',
    hint: 'External parties with delivery accountability. Mark N/A if no vendors.',
    sortOrder: 13,
  ),
  StakeholderScaffoldRole(
    roleName: 'Key Subject Matter Expert',
    roleType: 'active',
    hint: 'Domain expert whose sign-off is required. Add one per domain as needed.',
    sortOrder: 14,
  ),

  // Affected
  StakeholderScaffoldRole(
    roleName: 'End User Representative',
    roleType: 'affected',
    hint: 'Represents the people who will use or be impacted by the outcome.',
    sortOrder: 20,
  ),
  StakeholderScaffoldRole(
    roleName: 'Impacted Business Units',
    roleType: 'affected',
    hint: "Operational teams whose ways of working change.",
    sortOrder: 21,
  ),
  StakeholderScaffoldRole(
    roleName: 'Customer Representative',
    roleType: 'affected',
    hint: 'External customers if relevant. Mark N/A if not applicable.',
    sortOrder: 22,
  ),
];

// ---------------------------------------------------------------------------
// Team scaffold
// ---------------------------------------------------------------------------

const teamScaffold = <TeamScaffoldRole>[
  // Programme Leadership
  TeamScaffoldRole(
    roleName: 'Programme Manager',
    teamGroup: 'programme_leadership',
    hint: 'You. Pre-filled from project setup.',
    sortOrder: 0,
  ),
  TeamScaffoldRole(
    roleName: 'Change Manager',
    teamGroup: 'programme_leadership',
    hint: 'Owns the people side of change — communications, training, adoption. Critical and often under-resourced.',
    sortOrder: 1,
  ),
  TeamScaffoldRole(
    roleName: 'Deputy PM / Delivery Lead',
    teamGroup: 'programme_leadership',
    hint: 'Second in command. Mark N/A for smaller programmes.',
    sortOrder: 2,
  ),
  TeamScaffoldRole(
    roleName: 'PMO Lead',
    teamGroup: 'programme_leadership',
    hint: 'Programme Management Office representative. Mark N/A if no PMO.',
    sortOrder: 3,
  ),

  // Business & Analysis
  TeamScaffoldRole(
    roleName: 'Business Analyst',
    teamGroup: 'business_analysis',
    hint: 'Requirements, process mapping, acceptance criteria.',
    sortOrder: 10,
  ),
  TeamScaffoldRole(
    roleName: 'Business Architect',
    teamGroup: 'business_analysis',
    hint: 'Future state business design.',
    sortOrder: 11,
  ),
  TeamScaffoldRole(
    roleName: 'Process Owner',
    teamGroup: 'business_analysis',
    hint: 'Owns the process being changed.',
    sortOrder: 12,
  ),

  // Technology
  TeamScaffoldRole(
    roleName: 'Solution Architect',
    teamGroup: 'technology',
    hint: 'Overall technical design and integrity.',
    sortOrder: 20,
  ),
  TeamScaffoldRole(
    roleName: 'Enterprise Architect',
    teamGroup: 'technology',
    hint: 'Fits the solution into the broader technology landscape.',
    sortOrder: 21,
  ),
  TeamScaffoldRole(
    roleName: 'Technical Lead',
    teamGroup: 'technology',
    hint: 'Owns the build. Day-to-day technical decision-making.',
    sortOrder: 22,
  ),
  TeamScaffoldRole(
    roleName: 'Integration Lead',
    teamGroup: 'technology',
    hint: 'Specifically for integration programmes. Mark N/A if not applicable.',
    sortOrder: 23,
  ),
  TeamScaffoldRole(
    roleName: 'Security Architect',
    teamGroup: 'technology',
    hint: 'Particularly important in regulated and government environments.',
    sortOrder: 24,
  ),
  TeamScaffoldRole(
    roleName: 'Infrastructure Lead',
    teamGroup: 'technology',
    hint: 'Environments, deployment, operations.',
    sortOrder: 25,
  ),

  // Specialist
  TeamScaffoldRole(
    roleName: 'Data Lead',
    teamGroup: 'specialist',
    hint: 'Data migration, data quality, data governance.',
    sortOrder: 30,
  ),
  TeamScaffoldRole(
    roleName: 'Testing Lead / QA Lead',
    teamGroup: 'specialist',
    hint: 'Test strategy, test management, sign-off.',
    sortOrder: 31,
  ),
  TeamScaffoldRole(
    roleName: 'DevOps / Release Manager',
    teamGroup: 'specialist',
    hint: 'Deployment pipeline and release management.',
    sortOrder: 32,
  ),

  // Governance & Assurance
  TeamScaffoldRole(
    roleName: 'Risk Manager',
    teamGroup: 'governance',
    hint: 'Owns the risk framework. Often the PM in smaller programmes.',
    sortOrder: 40,
  ),
  TeamScaffoldRole(
    roleName: 'Benefits Realisation Lead',
    teamGroup: 'governance',
    hint: 'Tracks whether the programme delivered value post go-live. Frequently forgotten until too late.',
    sortOrder: 41,
  ),
];
