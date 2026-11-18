import '../data/local/entity/portfolio_entity.dart';
import 'collections.dart';

/// Orders the present [types] using the saved [order] (a list of enum names).
///
/// Types missing from the saved order are appended in natural (enum) order, so
/// newly added categories show up at the bottom. Names that don't parse resolve
/// to the enum's fallback value, matching the Android implementation.
List<T> orderTypes<T extends Enum>(
  Iterable<T> types,
  List<String> order,
  T Function(String) parse,
) {
  final Set<T> present = types.toSet();
  final List<T> result = <T>[];
  for (final String name in order) {
    final T type = parse(name);
    if (present.remove(type)) result.add(type);
  }
  result.addAll(sortedByDescending<T>(present, (T type) => -type.index));
  return result;
}

/// Returns the id of the default portfolio in [portfolios], if any.
int? defaultPortfolioId(List<PortfolioEntity> portfolios) {
  for (final PortfolioEntity portfolio in portfolios) {
    if (portfolio.isDefault) return portfolio.id;
  }
  return null;
}

/// Picks the portfolio to show: the explicitly selected one, else the default,
/// else the first available.
PortfolioEntity? resolveActivePortfolio(
  List<PortfolioEntity> portfolios,
  int? selectedId,
) {
  if (portfolios.isEmpty) return null;
  if (selectedId != null) {
    for (final PortfolioEntity portfolio in portfolios) {
      if (portfolio.id == selectedId) return portfolio;
    }
  }
  for (final PortfolioEntity portfolio in portfolios) {
    if (portfolio.isDefault) return portfolio;
  }
  return portfolios.first;
}
