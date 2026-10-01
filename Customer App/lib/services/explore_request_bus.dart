import 'package:flutter/foundation.dart';

/// A request to show the Explore tab filtered down to one category.
class ExploreRequest {
  /// Sent as `category_id` to the directory. May be [SalonController]'s combo
  /// sentinel rather than a catalogue uuid.
  final String? categoryId;

  /// What to call the filter on screen.
  final String? categoryLabel;

  const ExploreRequest({this.categoryId, this.categoryLabel});

  bool get isCategory => categoryId != null && categoryId!.isNotEmpty;
}

/// One-shot hand-off between the home tab and the Explore tab.
///
/// Both of them live inside the bottom-nav shell, so neither can reach the
/// other: the home tab has no handle on the shell's tab index, and the shell is
/// the only thing that knows the index exists. Dropping the request here and
/// letting both listen keeps that knowledge in one place — the shell owns the
/// tab index, the Explore tab owns the filter.
///
/// The request is consumed by [take], so exactly one caller acts on it.
class ExploreRequestBus extends ChangeNotifier {
  static final instance = ExploreRequestBus._();

  ExploreRequestBus._();

  ExploreRequest? _pending;

  /// The request waiting to be picked up, without consuming it.
  ExploreRequest? get pending => _pending;

  /// The waiting request, cleared so it is not acted on twice.
  ExploreRequest? take() {
    final request = _pending;
    _pending = null;
    return request;
  }

  /// Show the Explore tab with no filter — the whole directory. Used by
  /// empty states elsewhere ("no bookings yet") whose next step is to look
  /// for a salon.
  void showAll() {
    _pending = const ExploreRequest();
    notifyListeners();
  }

  /// Show the Explore tab, filtered to one category.
  void showCategory({
    required String categoryId,
    required String categoryLabel,
  }) {
    _pending = ExploreRequest(
      categoryId: categoryId,
      categoryLabel: categoryLabel,
    );
    notifyListeners();
  }
}
