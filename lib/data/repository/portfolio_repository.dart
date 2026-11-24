import '../local/dao/portfolio_dao.dart';
import '../local/entity/portfolio_entity.dart';

export '../local/dao/portfolio_dao.dart' show DuplicatePortfolioNameException;

class PortfolioRepository {
  const PortfolioRepository(this._dao);

  final PortfolioDao _dao;

  Stream<List<PortfolioEntity>> observeAll() => _dao.observeAll();

  Stream<PortfolioEntity?> observeById(int id) => _dao.observeById(id);

  Future<PortfolioEntity?> getById(int id) => _dao.getById(id);

  Future<PortfolioEntity?> getDefault() => _dao.getDefault();

  Future<List<PortfolioEntity>> getAll() => _dao.getAll();

  /// Creates a portfolio. The first portfolio ever created becomes the default.
  Future<int> create(String name, {bool makeDefault = false}) async {
    final bool isFirst = await _dao.count() == 0;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int id = await _dao.insert(
      PortfolioEntity(
        name: name.trim(),
        isDefault: false,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (isFirst || makeDefault) await _dao.setDefault(id);
    return id;
  }

  Future<void> rename(int id, String name) =>
      _dao.rename(id, name.trim(), DateTime.now().millisecondsSinceEpoch);

  Future<void> setDefault(int id) => _dao.setDefault(id);

  /// Deletes a portfolio (cascading its assets/liabilities). Refuses to remove
  /// the final portfolio. If the default is removed, the next one is promoted.
  Future<bool> delete(int id) async {
    if (await _dao.count() <= 1) return false;
    final PortfolioEntity? target = await _dao.getById(id);
    if (target == null) return false;
    await _dao.deleteById(id);
    if (target.isDefault) {
      final List<PortfolioEntity> remaining = await _dao.getAll();
      if (remaining.isNotEmpty) await _dao.setDefault(remaining.first.id);
    }
    return true;
  }

  /// Ensures at least one (default) portfolio exists; returns its id.
  Future<int> ensureDefaultPortfolio([
    String defaultName = 'My Portfolio',
  ]) async {
    final PortfolioEntity? existingDefault = await _dao.getDefault();
    if (existingDefault != null) return existingDefault.id;
    final List<PortfolioEntity> all = await _dao.getAll();
    if (all.isNotEmpty) {
      await _dao.setDefault(all.first.id);
      return all.first.id;
    }
    return create(defaultName, makeDefault: true);
  }
}
