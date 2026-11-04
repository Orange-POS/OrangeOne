import 'package:orange_one/features/help_support/domain/entities/tutorial_catalog.dart';

abstract interface class TutorialRepository {
  /// Published tutorials, updated whenever they change remotely.
  Stream<TutorialCatalog> watchPublished();
}
