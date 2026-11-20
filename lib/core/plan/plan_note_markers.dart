/// Prefixes Keel stamps on the plan-activity notes it writes itself. The
/// Microsoft Project export's "public notes" mode drops lines that start
/// with these, so the writers and the filter must share them.

/// Re-plan history: "Re-planned 2026-11-02: was …, now …. AI view (…): …"
const kReplanNotePrefix = 'Re-planned ';

/// The AI's commentary on a move (also embedded in a re-plan line).
const kAiViewNotePrefix = 'AI view (';

/// Rows and arrows added by the plan review.
const kPlanReviewNotePrefix = 'Added on plan review';

/// True for a note line Keel generated (history or commentary), as
/// opposed to text a person wrote.
bool isKeelGeneratedNoteLine(String line) {
  final l = line.trimLeft();
  return l.startsWith(kReplanNotePrefix) ||
      l.startsWith(kAiViewNotePrefix) ||
      l.startsWith(kPlanReviewNotePrefix);
}
