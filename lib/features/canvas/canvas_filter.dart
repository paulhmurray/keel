import '../../core/database/database.dart';
import 'canvas_tags.dart';

/// Pure filter / search helper for Canvas. Lifted out of canvas_view so it
/// can be unit-tested without spinning up the widget tree.
///
/// Filter semantics:
///   - [band]: card.band must match (null = all bands)
///   - [colour]: 'none' matches cards with no colour set; any other value
///     must equal card.colour exactly. null disables the filter.
///   - [linked]: 'linked' keeps only cards with linkedItemType set; 'free'
///     keeps only those without. null disables the filter.
///   - [promoted]: 'promoted' keeps only promoted cards; 'not_promoted'
///     keeps only un-promoted cards. null disables the filter.
///   - [tag]: keeps only cards whose tags list contains this tag
///     (lowercased comparison). null disables the filter.
///   - [search]: case-insensitive substring match against title or body.
///     Empty or whitespace-only string disables the filter.
class CanvasFilter {
  final String? band;
  final String? colour;
  final String? linked;
  final String? promoted;
  final String? tag;
  final String search;

  const CanvasFilter({
    this.band,
    this.colour,
    this.linked,
    this.promoted,
    this.tag,
    this.search = '',
  });

  static const empty = CanvasFilter();

  /// Number of filters currently restricting the result (excluding search).
  /// Used by the toolbar to render an "N active" badge.
  int get activeCount =>
      (band != null ? 1 : 0) +
      (colour != null ? 1 : 0) +
      (linked != null ? 1 : 0) +
      (promoted != null ? 1 : 0) +
      (tag != null ? 1 : 0);

  bool _matches(CanvasCard c) {
    if (band != null && c.band != band) return false;
    if (colour != null) {
      if (colour == 'none') {
        if (c.colour != null) return false;
      } else if (c.colour != colour) {
        return false;
      }
    }
    if (linked == 'linked' && c.linkedItemType == null) return false;
    if (linked == 'free' && c.linkedItemType != null) return false;
    if (promoted == 'promoted' && c.promotedAt == null) return false;
    if (promoted == 'not_promoted' && c.promotedAt != null) return false;
    if (tag != null) {
      final tags = CanvasTags.decode(c.tags);
      if (!tags.contains(tag!.toLowerCase())) return false;
    }
    final q = search.trim().toLowerCase();
    if (q.isNotEmpty) {
      final inTitle = c.title.toLowerCase().contains(q);
      final inBody = c.body?.toLowerCase().contains(q) ?? false;
      if (!inTitle && !inBody) return false;
    }
    return true;
  }

  List<CanvasCard> apply(Iterable<CanvasCard> cards) {
    return cards.where(_matches).toList();
  }

  CanvasFilter copyWith({
    Object? band = _sentinel,
    Object? colour = _sentinel,
    Object? linked = _sentinel,
    Object? promoted = _sentinel,
    Object? tag = _sentinel,
    String? search,
  }) {
    return CanvasFilter(
      band: band == _sentinel ? this.band : band as String?,
      colour: colour == _sentinel ? this.colour : colour as String?,
      linked: linked == _sentinel ? this.linked : linked as String?,
      promoted:
          promoted == _sentinel ? this.promoted : promoted as String?,
      tag: tag == _sentinel ? this.tag : tag as String?,
      search: search ?? this.search,
    );
  }
}

const _sentinel = Object();
