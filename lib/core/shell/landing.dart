/// Where Keel opens for an entity. A project lands on Helm — the
/// operational hub that answers "what do I do about this today?" — while
/// a programme lands on its overview, because a portfolio genuinely needs
/// one. Nav indices are the shell's: 0 = Overview, 16 = Helm.
library;

const int kNavOverview = 0;
const int kNavHelm = 16;

int landingIndexFor({required bool isProgramme}) =>
    isProgramme ? kNavOverview : kNavHelm;

/// Kind-aware twin: programmes AND portfolios land on their overview;
/// only a plain project lands on Helm.
int landingIndexForKind(String kind) =>
    landingIndexFor(isProgramme: kind == 'programme' || kind == 'portfolio');

/// True when the user is sitting on one of the two home pages, so a
/// project switch may move them to the new entity's home. Anywhere else
/// (RAID, Plan…) stays put — they came here on purpose.
bool isHomePage(int index) => index == kNavOverview || index == kNavHelm;
